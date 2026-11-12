import assert from 'node:assert/strict'
import { test } from 'node:test'
import { openDb } from '../src/db.ts'
import { isTestBuildPost, pcScopedPost, statedLiveTime } from '../src/ingest/claims.ts'
import { nameRelease } from '../src/ingest/classify.ts'
import { runIngest, seedGames } from '../src/ingest/pipeline.ts'
import * as store from '../src/store.ts'
import { fakeFetch, steamNews } from './helpers.ts'

// r050-feed-ps5-claim-fixes: wording taken from the posts Quinn's spot-check found wrong.

test('a PTB, public test, test build, beta or preview post is not a release', () => {
  assert.ok(isTestBuildPost('10.3.0 | Terrifier PTB Patch Notes'))
  assert.ok(isTestBuildPost('Public Test Build 0.9 Patch Notes'))
  assert.ok(isTestBuildPost('Open Beta Update 1.2'))
  assert.ok(isTestBuildPost('Patch 2.0 Preview Notes'))
  assert.ok(!isTestBuildPost('10.2.2a Backend Bugfix Patch'))
  assert.ok(!isTestBuildPost('AC Black Flag Resynced Title Update 1.0.8 – Patch Notes'))
})

test('a post listing platform builds without PlayStation, or rolling out to other platforms later, is PC-scoped', () => {
  assert.ok(pcScopedPost('Hotfix\nWindows: v1.0.6.2132\nMac: v1.0.6.776\n- Fixed a crash'))
  assert.ok(pcScopedPost('We added a new option on PC and are rolling it out soon to other platforms.'))
  assert.ok(!pcScopedPost('Windows: v1.0.6.2132\nMac: v1.0.6.776\nPS5: 1.0.6'))
  assert.ok(!pcScopedPost('Fixed a crash on startup.'))
})

test('a stated later time is read; past, vague and non-release dates are not', () => {
  const pub = '2026-11-08T10:00:00.000Z'
  assert.equal(statedLiveTime('At 02:00 UTC+0 on November 10, the updates for Xbox Series X|S and PlayStation 5 will be available.', pub), '2026-11-10T02:00:00.000Z')
  assert.equal(statedLiveTime('Update 1.2 is starting on November 12, 2026 at 06:00 (UTC+0) and rolling out to all platforms.', pub), '2026-11-12T06:00:00.000Z')
  assert.equal(statedLiveTime('The free update arrives on November 23, 2026 on all platforms.', pub), '2026-11-23T23:59:00.000Z')
  assert.equal(statedLiveTime('Update live at 14:00 UTC-5 on November 10', pub), '2026-11-10T19:00:00.000Z')
  assert.equal(statedLiveTime('The update released on November 1 fixed a lot.', pub), null)
  assert.equal(statedLiveTime('The sale ends on November 12. Patch notes below.', pub), null)
  assert.equal(statedLiveTime('Fixed a crash.', pub), null)
})

test('a letter after the version stays in its name (10.2.2a)', () => {
  const n = nameRelease('10.2.2a Backend Bugfix Patch', '2026-11-02T10:00:00.000Z')
  assert.deepEqual([n.displayName, n.versionKey], ['Patch 10.2.2a', '10.2.2a'])
})

const day = (n: number) => new Date(Date.now() + n * 86400e3)
const ago = (h: number) => new Date(Date.now() - h * 3600e3).toISOString()
const monthDay = (d: Date) => `${d.toLocaleString('en-US', { month: 'long', timeZone: 'UTC' })} ${d.getUTCDate()}`

const setup = async (items: Parameters<typeof steamNews>[0]) => {
  const db = openDb(':memory:')
  const deps = { db, fetchFn: fakeFetch({ 'https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=3751260': steamNews(items) }), igdb: null }
  await seedGames(deps)
  await runIngest(deps)
  return { db, deps }
}
const ps5Of = (db: ReturnType<typeof openDb>, id: string) => store.getRelease(db, id)?.platforms.find((p) => p.platform === 'ps5')

test('ingest: test builds and PC-scoped posts make no PS5 row; a stated later time holds the row announced until then', async () => {
  const when = day(2)
  const { db } = await setup([
    { gid: '1', title: '10.3.0 | Terrifier PTB Patch Notes', date: ago(30), contents: 'Public test build. Fixed a crash.', tags: ['patchnotes'] },
    { gid: '2', title: 'Hotfix 1.0.6', date: ago(25), contents: 'Windows: v1.0.6.2132\nMac: v1.0.6.776\n- Fixed a crash', tags: ['patchnotes'] },
    { gid: '3', title: 'Patch 1.3', date: ago(20), contents: `At 02:00 UTC+0 on ${monthDay(when)}, the updates for Xbox Series X|S and PlayStation 5 will be available.`, tags: ['patchnotes'] },
    { gid: '4', title: '10.2.2a Backend Bugfix Patch', date: ago(10), contents: 'Fixed a backend bug. Live on PC.', tags: ['patchnotes'] },
  ])
  assert.ok(store.getRelease(db, 'dawnwalker@10.3.0'))
  assert.equal(ps5Of(db, 'dawnwalker@10.3.0'), undefined)
  assert.equal(ps5Of(db, 'dawnwalker@1.0.6'), undefined)
  const held = ps5Of(db, 'dawnwalker@1.3')!
  assert.deepEqual([held.status, held.verification, held.liveAt?.value], ['announced', 'official', `${when.toISOString().slice(0, 10)}T02:00:00.000Z`])
  assert.equal(held.alert, undefined)
  assert.ok(store.getRelease(db, 'dawnwalker@10.2.2a'))
  // Nothing happens early; once the time has passed the row is live and earns its one alert from now.
  assert.equal(store.promoteStated(db, day(1)), 0)
  assert.equal(store.promoteStated(db, day(3)), 1)
  const live = ps5Of(db, 'dawnwalker@1.3')!
  assert.deepEqual([live.status, live.verification], ['live', 'official'])
  assert.ok(live.alert)
})

test('backfill repairs rows the old rules made from the same post, and leaves other sources alone', async () => {
  const when = day(2)
  const items = [
    { gid: '1', title: 'Patch 1.3', date: ago(20), contents: `At 02:00 UTC+0 on ${monthDay(when)}, the updates for Xbox Series X|S and PlayStation 5 will be available.`, tags: ['patchnotes'] },
    { gid: '2', title: '10.3.0 | Terrifier PTB Patch Notes', date: ago(30), contents: 'Public test build.', tags: ['patchnotes'] },
  ]
  const { db, deps } = await setup(items)
  // The old rules: live on PS5 at the post's own time.
  for (const [id, verification] of [['dawnwalker@1.3', 'official'], ['dawnwalker@10.3.0', 'assumed']] as const) {
    const pc = ps5Of(db, id) ?? store.getRelease(db, id)!.platforms.find((p) => p.platform === 'pc')!
    const at = store.getRelease(db, id)!.platforms.find((p) => p.platform === 'pc')!.liveAt!
    db.prepare("DELETE FROM platform_releases WHERE release_id = ? AND platform = 'ps5'").run(id)
    store.upsertPlatform(db, id, 'ps5', { status: 'live', verification, liveAt: store.field(at.value, verification, at.sourceId) })
    void pc
  }
  assert.equal(ps5Of(db, 'dawnwalker@1.3')!.status, 'live')
  await runIngest(deps, { force: true, until: new Date(Date.now() - 90 * 86400e3).toISOString() })
  const fixed = ps5Of(db, 'dawnwalker@1.3')!
  assert.deepEqual([fixed.status, fixed.verification], ['announced', 'official'])
  assert.equal(ps5Of(db, 'dawnwalker@10.3.0'), undefined)
})
