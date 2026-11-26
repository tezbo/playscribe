import assert from 'node:assert/strict'
import { copyFileSync, mkdtempSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { test } from 'node:test'
import { confirmPlatform } from '../src/confirm.ts'
import { openDb } from '../src/db.ts'
import { runIngest, seedGames } from '../src/ingest/pipeline.ts'
import { deliverPush, pushNewPs5, queueNewPs5 } from '../src/push/notify.ts'
import type { Apns } from '../src/push/apns.ts'
import { syncDevices } from '../src/push/relay.ts'
import { fakeFetch, rss } from './helpers.ts'

// 12 Nov 2026: the Feed job sent pushes during the poll and then failed at Publish (state over 100 MB). The pushed flag died with the run,
// the release never reached the feed, and the same alert went out again and again; a tap opened "no longer available".
// The poll now only claims and queues; the alerts are sent after Publish, from the queue.
test('push after publish: a run that fails before Publish sends nothing and the release is queued again next run', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'push-after-publish-'))
  const path = join(dir, 'state.db')
  const published = join(dir, 'published.db')
  const db = openDb(path)
  const fetchFn = fakeFetch({
    'https://blog.playstation.com/feed/': rss([{ title: 'Black Myth: Wukong Update 1.2 detailed for PS5', link: 'https://blog.playstation.com/wukong', date: new Date().toISOString(), body: '<ul><li>Added new boss</li></ul>' }]),
  })
  await seedGames({ db, fetchFn, igdb: null })
  await runIngest({ db, fetchFn, igdb: null })
  const id = (db.prepare("SELECT id FROM releases WHERE game_id = 'wukong'").get() as { id: string }).id
  confirmPlatform(db, id, 'ps5', { sourceId: 'playstation-blog', version: '01.006.000' })
  db.exec('PRAGMA wal_checkpoint(TRUNCATE)')
  db.close()
  copyFileSync(path, published) // what the feed branch holds: the release live, not yet claimed

  const sent: string[] = []
  const apns = { send: async (t: string) => (sent.push(t), { status: 200 }) } as unknown as Apns
  const load = (p: string) => {
    const d = openDb(p)
    syncDevices(d, [{ id: 'a', token: 'a'.repeat(64), environment: 'production', locale: null, quiet: null, follows: [{ gameId: 'wukong', notify: 'all' }], updated: '2026-11-05T00:00:00.000Z' }])
    return d
  }

  // Run 1: claim and queue. Nothing is sent, and the claim is in the database.
  const run1 = load(path)
  const q1 = queueNewPs5(run1, { maxAgeHours: 72, hasApns: true })
  assert.equal(q1.jobs.length, 1)
  assert.equal(sent.length, 0, 'the poll sends nothing')
  assert.ok((run1.prepare("SELECT pushed_at FROM platform_releases WHERE release_id = ? AND platform = 'ps5'").get(id) as { pushed_at: string | null }).pushed_at)
  assert.equal(queueNewPs5(run1, { maxAgeHours: 72, hasApns: true }).jobs.length, 0, 'claimed once within the run')
  run1.close()

  // Publish failed: the run's database is discarded, the feed still holds the unclaimed copy. The next run offers the release again,
  // and still nothing has been sent, so no device was told about a release the feed does not hold.
  const run2 = load(published)
  const q2 = queueNewPs5(run2, { maxAgeHours: 72, hasApns: true })
  assert.deepEqual(q2.jobs.map((j) => j.job.releaseId), [id])
  assert.equal(sent.length, 0)

  // Publish succeeded: now the queue is sent, once, and the claim is what the feed holds, so the next run offers nothing.
  const d = await deliverPush(apns, q2.jobs[0]!.job, q2.jobs[0]!.outcome)
  assert.deepEqual([d.outcome.sent, d.outcome.failed], [1, 0])
  assert.equal(sent.length, 1)
  assert.equal(queueNewPs5(run2, { maxAgeHours: 72, hasApns: true }).jobs.length, 0)
  assert.equal((await pushNewPs5(run2, apns, { maxAgeHours: 72 })).length, 0, 'the one-shot path agrees: already claimed')
  assert.equal(sent.length, 1)
  run2.close()
})

test('push after publish: dead tokens come back from the delivery as hashes, not tokens', async () => {
  const job = { releaseId: 'r', payload: { aps: { alert: { title: 't', body: 'b' }, sound: 'default' } }, targets: [{ id: 'gone', token: 'a1'.repeat(32), environment: 'production' as const, quiet: null }, { id: 'ok', token: 'd4'.repeat(32), environment: 'production' as const, quiet: null }] }
  const apns = { send: async (t: string) => (t.startsWith('a1') ? { status: 410, reason: 'Unregistered' } : { status: 200 }) } as unknown as Apns
  const d = await deliverPush(apns, job, { releaseId: 'r', sent: 0, failed: 0 })
  assert.deepEqual([d.outcome.sent, d.outcome.failed, d.dead.map((x) => x.id)], [1, 1, ['gone']])
  assert.ok(!JSON.stringify(d.dead).includes('a1'.repeat(32)))
})
