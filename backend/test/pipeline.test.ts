import assert from 'node:assert/strict'
import { test } from 'node:test'
import { confirmPlatform } from '../src/confirm.ts'
import { openDb } from '../src/db.ts'
import { runIngest, seedGames } from '../src/ingest/pipeline.ts'
import { pushPs5Release, pushReportedPs5 } from '../src/push/notify.ts'
import type { Apns } from '../src/push/apns.ts'
import { getRelease } from '../src/store.ts'
import { fakeFetch, pressArticle, pressIndexPage, rss, steamNews } from './helpers.ts'

const recent = (h: number) => new Date(Date.now() - h * 3600_000).toISOString()

const setup = async () => {
  const db = openDb(':memory:')
  const fetchFn = fakeFetch({
    'https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=3751260': steamNews([
      { gid: '1', title: 'The Blood of Dawnwalker - Update 1.1', date: recent(30), contents: 'Update 1.1 is out now on PC, PlayStation 5, and Xbox Series X|S![h2]Highlights[/h2][list][*]Added photo mode[*]Fixed a crash[/list]', tags: ['patchnotes'] },
      { gid: '2', title: 'Community Update: art contest', date: recent(20), contents: 'Not a patch' },
    ]),
    'https://www.pushsquare.com/news/dw-1-1': pressArticle('Dawnwalker PS5 Patch 1.1 Out Now, 13GB Update', 'The patch is 12.882GB on PS5 and brings it to version 01.004.000.'),
    'https://www.pushsquare.com/news/kcd2-1-7': pressArticle('Kingdom Come Deliverance 2 Patch 1.7 Coming Next Week on PS5', 'Warhorse says patch 1.7 is in certification.'),
    'https://www.pushsquare.com/tags/updates': pressIndexPage([
      { title: 'Dawnwalker PS5 Patch 1.1 Out Now, 13GB Update', path: 'news/dw-1-1', date: recent(10), tags: ['Bandai Namco', 'PS5', 'Dawnwalker', 'Updates'] },
      { title: 'Kingdom Come Deliverance 2 Patch 1.7 Coming Next Week on PS5', path: 'news/kcd2-1-7', date: recent(9) },
      { title: 'Unrelated game gets Patch 2.0', path: 'news/other', date: recent(9) },
      { title: 'Minecraft Dungeons Update 1.2 is out now', path: 'news/mcd', date: recent(8) },
      { title: 'Huge 30GB Update Prepares Ghost of Yotei for DLC', path: 'news/yotei', date: recent(7) },
      { title: 'Elden Ring: All Patch 1.05 Notes', path: 'guides/elden-ring-patches', date: recent(6) },
    ]),
    'https://blog.playstation.com/feed/': rss([
      { title: 'Kingdom Come: Deliverance II Update 1.6 arrives on PS5 today', link: 'https://blog.playstation.com/kcd2-1-6', date: recent(2), body: '<h2>New</h2><ul><li>Added a new quest line</li></ul>' },
    ]),
  })
  const deps = { db, fetchFn, igdb: null }
  await seedGames(deps)
  return { db, deps, summary: await runIngest(deps) }
}

test('Steam sets PC only; a PS5 mention goes to review, never to a PS5 row', async () => {
  const { db, summary } = await setup()
  const r = getRelease(db, 'dawnwalker@1.1')!
  assert.equal(r.kind, 'major')
  assert.equal(r.kindBasis, 'studio')
  const pc = r.platforms.find((p) => p.platform === 'pc')!
  assert.equal(pc.verification, 'official')
  assert.ok(!summary.created.some((id) => id.includes('community')))
  const review = db.prepare("SELECT reason FROM review_items WHERE release_id = 'dawnwalker@1.1' ORDER BY reason").all().map((x: any) => x.reason)
  assert.ok(review.includes('steamMentionsPs5'))
})

test('press fills PS5 facts as reported, matched by name and version', async () => {
  const { db } = await setup()
  const ps5 = getRelease(db, 'dawnwalker@1.1')!.platforms.find((p) => p.platform === 'ps5')!
  assert.equal(ps5.status, 'live')
  assert.equal(ps5.verification, 'reported')
  assert.equal(ps5.version?.value, '01.004.000')
  assert.equal(ps5.version?.verification, 'reported')
  assert.equal(ps5.sizeBytes?.value, 12.882e9)
  // A headline about next week's patch is announced, not live, and has no live date.
  const next = getRelease(db, 'kcd2@1.7')!.platforms.find((p) => p.platform === 'ps5')!
  assert.equal(next.status, 'announced')
  assert.equal(next.liveAt, null)
  // A headline without a version is not a release name.
  const yotei = db.prepare("SELECT display_name, kind FROM releases WHERE game_id = 'yotei'").all() as { display_name: string; kind: string }[]
  assert.deepEqual(yotei.map((r) => [r.display_name, r.kind]), [['PS5 update', 'silent']])
  // "Minecraft Dungeons" is not Minecraft, a guide is not news, and an unknown game is not tracked.
  assert.equal(db.prepare("SELECT COUNT(*) AS n FROM releases WHERE game_id NOT IN ('dawnwalker','kcd2','yotei')").get()!.n, 0)
})

test('an official PS5 post is pending until a person confirms; push fires once', async () => {
  const { db } = await setup()
  const id = 'kcd2@1.6'
  assert.equal(getRelease(db, id)!.platforms.find((p) => p.platform === 'ps5')!.verification, 'pending')
  assert.ok(db.prepare("SELECT 1 FROM review_items WHERE release_id = ? AND reason = 'officialPost'").get(id))

  // Two followers: one wants everything, one only major updates, one opted out.
  const t = new Date().toISOString()
  for (const [dev, notify] of [['a', 'all'], ['b', 'major'], ['c', 'off']] as const) {
    db.prepare("INSERT INTO devices (id, key_hash, apns_token, environment, created_at, updated_at) VALUES (?, ?, ?, 'production', ?, ?)").run(dev, `h${dev}`, dev.repeat(64), t, t)
    db.prepare('INSERT INTO follows (device_id, game_id, notify) VALUES (?, ?, ?)').run(dev, 'kcd2', notify)
  }
  const sent: { token: string; payload: any }[] = []
  const apns = { send: async (token: string, _env: string, payload: object) => (sent.push({ token, payload }), { status: 200 }) } as unknown as Apns

  const before = await pushPs5Release(db, apns, id, { maxAgeHours: 72 })
  assert.equal(before.skipped, 'notLive')
  confirmPlatform(db, id, 'ps5', { sourceId: 'playstation-blog', version: '01.006.000' })
  const ps5 = getRelease(db, id)!.platforms.find((p) => p.platform === 'ps5')!
  assert.equal(ps5.verification, 'official')
  assert.equal(ps5.status, 'live')
  assert.equal(ps5.version?.verification, 'official')

  const first = await pushPs5Release(db, apns, id, { maxAgeHours: 72 })
  assert.equal(first.sent, 2)
  assert.deepEqual(sent.map((s) => s.token).sort(), ['a'.repeat(64), 'b'.repeat(64)])
  assert.equal(sent[0]!.payload.releaseId, id)
  assert.match(sent[0]!.payload.aps.alert.body, /Update 1\.6 is out on PS5 \(version 01\.006\.000\)/)
  assert.equal(sent[0]!.payload.aps['interruption-level'], 'active')
  assert.equal(getRelease(db, id)!.platforms.find((p) => p.platform === 'ps5')!.alert?.style, 'standard')
  assert.equal((await pushPs5Release(db, apns, id, { maxAgeHours: 72 })).skipped, 'alreadyPushed')
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM review_items WHERE release_id = ? AND resolved_at IS NULL').get(id)!.n, 0)
})

test('a press report that an update is live earns one quiet "Unconfirmed" alert, and confirming it does not alert again', async () => {
  const { db } = await setup()
  const id = 'dawnwalker@1.1'
  const t = new Date().toISOString()
  db.prepare("INSERT INTO devices (id, key_hash, apns_token, environment, created_at, updated_at) VALUES ('a', 'ha', ?, 'production', ?, ?)").run('a'.repeat(64), t, t)
  db.prepare("INSERT INTO follows (device_id, game_id, notify) VALUES ('a', 'dawnwalker', 'all')").run()
  const sent: any[] = []
  const apns = { send: async (_t: string, _e: string, payload: object) => (sent.push(payload), { status: 200 }) } as unknown as Apns
  assert.deepEqual(getRelease(db, id)!.platforms.find((p) => p.platform === 'ps5')!.alert, { style: 'quiet', tag: 'Unconfirmed' })

  const out = await pushReportedPs5(db, apns, { maxAgeHours: 1e6 })
  // Yōtei's press report is live too, but nobody follows it.
  assert.deepEqual(out.map((o) => [o.releaseId.replace(/@.*/, ''), o.style, o.sent]).sort(), [['dawnwalker', 'quiet', 1], ['yotei', 'quiet', 0]])
  const p = sent[0]
  assert.deepEqual(p.aps.alert, {
    title: 'Unconfirmed: The Blood of Dawnwalker',
    subtitle: 'Update 1.1 reported on PS5',
    body: "From press reports. This will update when it's official.",
  })
  assert.equal(p.aps['interruption-level'], 'passive')
  assert.equal(p.aps.sound, undefined)
  assert.equal(p.aps['thread-id'], 'dawnwalker.unconfirmed')
  assert.deepEqual([p.verification, p.tag], ['reported', 'Unconfirmed'])
  assert.equal((await pushReportedPs5(db, apns, { maxAgeHours: 1e6 })).length, 0)

  confirmPlatform(db, id, 'ps5', { sourceId: 'dawnwalker-news', version: '01.004.001' })
  assert.deepEqual(getRelease(db, id)!.platforms.find((p) => p.platform === 'ps5')!.alert, { style: 'standard' })
  assert.equal((await pushPs5Release(db, apns, id, { maxAgeHours: 1e6 })).skipped, 'alreadyPushed')
  assert.equal(sent.length, 1)
  // Announced or pending rows earn no alert.
  assert.equal(getRelease(db, 'kcd2@1.7')!.platforms.find((p) => p.platform === 'ps5')!.alert, undefined)
})

test('press never downgrades an official fact, and a second ingest reads nothing twice', async () => {
  const { db, deps } = await setup()
  confirmPlatform(db, 'dawnwalker@1.1', 'ps5', { sourceId: 'dawnwalker-news', version: '01.004.001' })
  const again = await runIngest(deps, { force: true })
  assert.equal(again.created.length, 0)
  const ps5 = getRelease(db, 'dawnwalker@1.1')!.platforms.find((p) => p.platform === 'ps5')!
  assert.equal(ps5.version?.value, '01.004.001')
  assert.equal(ps5.verification, 'official')
})

test('sources are polled at most hourly, and a 403 switches a source off', async () => {
  const db = openDb(':memory:')
  const deps = { db, fetchFn: fakeFetch({ 'https://www.remedygames.com/news': { status: 403 } }), igdb: null }
  await seedGames(deps)
  const first = await runIngest(deps)
  assert.ok(first.errors.some((e) => e.sourceId === 'remedy-news' && /manual/.test(e.error)))
  const second = await runIngest(deps)
  assert.equal(second.polled.length, 0)
  const forced = await runIngest(deps, { force: true })
  assert.ok(!forced.polled.includes('remedy-news'))
})
