import assert from 'node:assert/strict'
import { test } from 'node:test'
import { confirmPlatform } from '../src/confirm.ts'
import { openDb } from '../src/db.ts'
import { runIngest, seedGames, ps4SinceFromIndex } from '../src/ingest/pipeline.ts'
import { alertCopy, headlineOf, pushPs5Release, pushNewPs5 } from '../src/push/notify.ts'
import type { Apns } from '../src/push/apns.ts'
import * as store from '../src/store.ts'
import { getRelease, newsOf, promoteAnnounced } from '../src/store.ts'
import { clearRobotsCache } from '../src/http.ts'
import { hotGameIds } from '../src/hot.ts'
import { fakeFetch, pressArticle, pressIndexPage, rss, steamNews } from './helpers.ts'

const recent = (h: number) => new Date(Date.now() - h * 3600_000).toISOString()

const setup = async (beforeIngest?: (db: ReturnType<typeof openDb>) => void) => {
  const db = openDb(':memory:')
  const fetchFn = fakeFetch({
    'https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=3751260': steamNews([
      { gid: '1', title: 'The Blood of Dawnwalker - Update 1.1', date: recent(30), contents: 'Update 1.1 is out now on PC! Notes for PlayStation 5 follow on our site.[h2]Highlights[/h2][list][*]Added photo mode[*]Fixed a crash[/list]', tags: ['patchnotes'] },
      { gid: '2', title: 'Community Update: art contest', date: recent(20), contents: 'Not a patch' },
      { gid: '3', title: 'Hotfix 1.0.5', date: recent(40), contents: 'Hotfix 1.0.5 is now live on PC, PS5 and Xbox Series X|S. It fixes a crash when using a PS5 controller on PC.', tags: ['patchnotes'] },
      { gid: '4', title: 'Patch 1.2', date: recent(3), contents: 'Patch 1.2 is live on PC. Console versions will follow after certification.', tags: ['patchnotes'] },
      { gid: '5', title: 'Hotfix 1.1.1', date: recent(5), contents: 'Small fixes. [url=https://store.steampowered.com/app/3751260]PS5 wishlist[/url] [url="https://dawnwalkergame.com/news/hotfix-1-1-1"]Read the PlayStation notes[/url]', tags: ['patchnotes'] },
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
  beforeIngest?.(db)
  return { db, deps, summary: await runIngest(deps) }
}

test('a Steam patch is taken as out on PS5 too, unless it says consoles get it later; it keeps its links', async () => {
  const { db } = await setup()
  const hotfix = getRelease(db, 'dawnwalker@1.1.1')!
  const ps5 = hotfix.platforms.find((p) => p.platform === 'ps5')!
  assert.deepEqual([ps5.status, ps5.verification, ps5.liveAt?.verification, ps5.version, ps5.alert?.style], ['live', 'assumed', 'assumed', null, 'standard'])
  assert.deepEqual(hotfix.links, { steamNotes: 'https://store.steampowered.com/news/app/3751260/view/5', ps5Page: 'https://dawnwalkergame.com/news/hotfix-1-1-1' })
  const later = getRelease(db, 'dawnwalker@1.2')!
  assert.deepEqual(later.platforms.find((p) => p.platform === 'ps5')!.status, 'announced')
  assert.equal(later.platforms.find((p) => p.platform === 'ps5')!.alert, undefined)
  assert.deepEqual(later.links, { steamNotes: 'https://store.steampowered.com/news/app/3751260/view/4' })
  // A week after Steam, a console-later update counts as live on PS5, dated from Steam, without an alert once stale.
  assert.equal(promoteAnnounced(db, new Date(Date.now() + 6 * 86400e3)), 0)
  assert.equal(promoteAnnounced(db, new Date(Date.now() + 8 * 86400e3)), 1)
  const promoted = getRelease(db, 'dawnwalker@1.2')!.platforms.find((p) => p.platform === 'ps5')!
  assert.deepEqual([promoted.status, promoted.verification, promoted.liveAt?.value], ['live', 'assumed', getRelease(db, 'dawnwalker@1.2')!.platforms.find((p) => p.platform === 'pc')!.liveAt?.value])
  // Roadmap 11: it earns its one alert now, counted from the moment it went live, not Steam's week-old date.
  const row = db.prepare("SELECT pushed_at, alert_from FROM platform_releases WHERE release_id = 'dawnwalker@1.2' AND platform = 'ps5'").get()!
  assert.equal(row.pushed_at, null)
  assert.ok(row.alert_from)
  assert.equal(promoted.alert?.style, 'standard')
  assert.equal(promoted.alert?.from, row.alert_from)
  assert.equal(promoteAnnounced(db, new Date(Date.now() + 9 * 86400e3)), 0)
  const sent: unknown[] = []
  const apns = { send: async (_t: string, _e: string, payload: object) => (sent.push(payload), { status: 200 }) } as unknown as Apns
  const t = new Date().toISOString()
  db.prepare("INSERT INTO devices (id, key_hash, apns_token, environment, created_at, updated_at) VALUES ('c', 'hc', ?, 'production', ?, ?)").run('c'.repeat(64), t, t)
  db.prepare("INSERT INTO follows (device_id, game_id, notify) VALUES ('c', 'dawnwalker', 'all')").run()
  // The push job runs against the real clock, so the promotion time must be fresh for it; here it was set 8 days ahead.
  db.prepare("UPDATE platform_releases SET alert_from = ? WHERE release_id = 'dawnwalker@1.2' AND platform = 'ps5'").run(t)
  assert.equal((await pushPs5Release(db, apns, 'dawnwalker@1.2', { maxAgeHours: 72 })).sent, 1)
  assert.equal((await pushPs5Release(db, apns, 'dawnwalker@1.2', { maxAgeHours: 72 })).skipped, 'alreadyPushed')
  assert.equal(sent.length, 1)
  // A studio post that names PS5 is that update's PS5 page.
  assert.equal(getRelease(db, 'kcd2@1.6')!.links.ps5Page, 'https://blog.playstation.com/kcd2-1-6')
})

test('Steam sets PC as official; a PS5 mention also goes to review', async () => {
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

test('a studio post that says the update is live on PS5 makes the PS5 row official, with no person', async () => {
  const { db } = await setup()
  const ps5 = getRelease(db, 'dawnwalker@1.0.5')!.platforms.find((p) => p.platform === 'ps5')!
  assert.deepEqual([ps5.status, ps5.verification, ps5.liveAt?.verification, ps5.alert?.style], ['live', 'official', 'official', 'standard'])
  assert.equal(db.prepare("SELECT COUNT(*) AS n FROM review_items WHERE release_id = 'dawnwalker@1.0.5' AND resolved_at IS NULL").get()!.n, 0)
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

  confirmPlatform(db, id, 'ps5', { sourceId: 'playstation-blog', version: '01.006.000' })
  const ps5 = getRelease(db, id)!.platforms.find((p) => p.platform === 'ps5')!
  assert.equal(ps5.verification, 'official')
  assert.equal(ps5.status, 'live')
  assert.equal(ps5.version?.verification, 'official')

  const first = await pushPs5Release(db, apns, id, { maxAgeHours: 72 })
  assert.equal(first.sent, 2)
  assert.deepEqual(sent.map((s) => s.token).sort(), ['a'.repeat(64), 'b'.repeat(64)])
  assert.equal(sent[0]!.payload.releaseId, id)
  assert.match(sent[0]!.payload.aps.alert.body, /^Update 1\.6/)
  assert.equal(sent[0]!.payload.aps['interruption-level'], 'active')
  assert.equal(getRelease(db, id)!.platforms.find((p) => p.platform === 'ps5')!.alert?.style, 'standard')
  assert.equal((await pushPs5Release(db, apns, id, { maxAgeHours: 72 })).skipped, 'alreadyPushed')
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM review_items WHERE release_id = ? AND resolved_at IS NULL').get(id)!.n, 0)
})

test('every update live on PS5 earns one standard alert; a press-only report earns none; confirming does not alert again', async () => {
  const { db } = await setup()
  const id = 'dawnwalker@1.1'
  const t = new Date().toISOString()
  db.prepare("INSERT INTO devices (id, key_hash, apns_token, environment, created_at, updated_at) VALUES ('a', 'ha', ?, 'production', ?, ?)").run('a'.repeat(64), t, t)
  db.prepare("INSERT INTO follows (device_id, game_id, notify) VALUES ('a', 'dawnwalker', 'all')").run()
  const sent: any[] = []
  const apns = { send: async (_t: string, _e: string, payload: object) => (sent.push(payload), { status: 200 }) } as unknown as Apns
  assert.equal(getRelease(db, id)!.platforms.find((p) => p.platform === 'ps5')!.alert?.style, 'standard')

  const out = await pushNewPs5(db, apns, { maxAgeHours: 1e6 })
  // Yōtei is press-only (no Steam post, no studio post): no alert, no tag, and its push is not claimed.
  assert.equal(out.filter((o) => o.releaseId.startsWith('yotei@')).length, 0)
  assert.equal(getRelease(db, (db.prepare("SELECT release_id FROM platform_releases WHERE release_id LIKE 'yotei@%' AND platform = 'ps5'").get() as { release_id: string }).release_id)!.platforms.find((p) => p.platform === 'ps5')!.alert, undefined)
  assert.ok(out.filter((o) => !o.releaseId.startsWith('yotei@')).every((o) => o.style === 'standard'))
  const p = sent.find((x) => x.releaseId === id)
  assert.match(p.aps.alert.body, /^Update /)
  assert.ok(p.digest && typeof p.digest.new === 'number', 'payload carries digest counts')
  assert.equal(p.aps['interruption-level'], 'active')
  assert.equal((await pushNewPs5(db, apns, { maxAgeHours: 1e6 })).length, 0)

  const before = sent.length
  confirmPlatform(db, id, 'ps5', { sourceId: 'dawnwalker-news', version: '01.004.001' })
  assert.equal((await pushPs5Release(db, apns, id, { maxAgeHours: 1e6 })).skipped, 'alreadyPushed')
  assert.equal(sent.length, before)
  // Announced rows earn no alert.
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

test('roadmap 11: a stale report is stored as pushed with no alert; a patch dated before the PS5 launch is not live on PS5', async () => {
  const { db } = await setup()
  const t = new Date().toISOString()
  db.prepare("INSERT INTO devices (id, key_hash, apns_token, environment, created_at, updated_at) VALUES ('b', 'hb', ?, 'production', ?, ?)").run('b'.repeat(64), t, t)
  db.prepare("INSERT INTO follows (device_id, game_id, notify) VALUES ('b', 'dawnwalker', 'all')").run()
  const sent: unknown[] = []
  const apns = { send: async (_t: string, _e: string, payload: object) => (sent.push(payload), { status: 200 }) } as unknown as Apns
  const yotei = 'dawnwalker@1.1'
  db.prepare("UPDATE platform_releases SET live_at = ? WHERE release_id = ? AND platform = 'ps5'").run(JSON.stringify({ value: recent(100), verification: 'reported', sourceId: 'x' }), yotei)
  const out = await pushPs5Release(db, apns, yotei, { maxAgeHours: 72 })
  assert.equal(out.skipped, 'tooOld')
  assert.equal(sent.length, 0)
  assert.ok(db.prepare("SELECT pushed_at FROM platform_releases WHERE release_id = ? AND platform = 'ps5'").get(yotei)!.pushed_at)
  assert.equal((await pushPs5Release(db, apns, yotei, { maxAgeHours: 72 })).skipped, 'alreadyPushed')
})

test('roadmap 11: a Steam patch dated before the game\'s PS5 launch is not live on PS5', async () => {
  const { db } = await setup((d) => d.prepare("UPDATE games SET ps5_release = '2099-01-01' WHERE id = 'dawnwalker'").run())
  const r = getRelease(db, 'dawnwalker@1.1.1')!
  assert.equal(r.platforms.find((p) => p.platform === 'pc')!.status, 'live')
  assert.equal(r.platforms.find((p) => p.platform === 'ps5'), undefined)
})

test('roadmap 9: checkedAt follows the latest fetch, and a PC number never reaches the PS5 row', async () => {
  const { db, deps } = await setup()
  const ps5 = () => getRelease(db, 'dawnwalker@1.1.1')!.platforms.find((p) => p.platform === 'ps5')!
  assert.equal(ps5().version, null)
  const t0 = ps5().liveAt!.checkedAt
  await new Promise((r) => setTimeout(r, 5))
  db.prepare('UPDATE source_state SET last_fetched_at = NULL').run()
  db.prepare('DELETE FROM seen_posts').run()
  await runIngest(deps)
  assert.ok(ps5().liveAt!.checkedAt > t0)
  assert.equal(ps5().version, null)
})

test('roadmap 11: the hot set is the games with a patch in the last 14 days plus the pinned list; a hot run skips the rest', async () => {
  const { db, deps } = await setup()
  const hot = hotGameIds(db, new Date(), ['yotei'])
  assert.ok(hot.has('yotei') && hot.has('dawnwalker'))
  assert.ok(hotGameIds(db, new Date(Date.now() + 40 * 86400e3), []).size === 0)
  assert.equal(hotGameIds(db, new Date(), ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm']).size, 12)
  // 30 minutes later a hot game's sources are due again; a cold game's and the shared press sources are not.
  db.prepare("UPDATE source_state SET last_fetched_at = ?").run(new Date(Date.now() - 30 * 60_000).toISOString())
  const r = await runIngest(deps, { hot: true })
  assert.ok(r.polled.some((id: string) => id.startsWith('dawnwalker')))
  assert.ok(!r.polled.some((id: string) => id === 'pushsquare-updates'))
})

test('roadmap 17: official non-patch posts become news headlines (title, date, url only); a patch post does not', async () => {
  const { db } = await setup()
  const rows = db.prepare("SELECT * FROM news WHERE game_id = 'dawnwalker'").all() as Record<string, any>[]
  const art = rows.find((r) => r.title === 'Community Update: art contest')!
  assert.ok(art)
  assert.deepEqual(Object.keys(art).sort(), ['game_id', 'published_at', 'source_id', 'title', 'url'])
  assert.ok(!rows.some((r) => /Hotfix|Update 1\.1$/.test(r.title)))
  assert.ok(newsOf(db, 'dawnwalker').every((n) => Object.keys(n).sort().join() === 'date,gameId,title,url,verification' && n.gameId === 'dawnwalker'))
})

test('coverage audit: a Steam-assumed PS5 row dated before the PS5 launch is dropped; official rows stay', async () => {
  const { db } = await setup()
  const row = (id: string) => db.prepare("SELECT 1 FROM platform_releases WHERE release_id = ? AND platform = 'ps5'").get(id)
  assert.ok(row('dawnwalker@1.1.1'))
  db.prepare("UPDATE games SET ps5_release = '2099-01-01' WHERE id = 'dawnwalker'").run()
  const n = store.dropPreLaunchPs5(db)
  assert.ok(n >= 1)
  assert.equal(row('dawnwalker@1.1.1'), undefined)
  assert.ok(row('dawnwalker@1.1'), 'a press or official PS5 row is kept')
  assert.equal(store.dropPreLaunchPs5(db), 0)
})

test('prelaunch gate (r051): Steam-only official PS5 rows announced before launch are dropped; launch-day and day-before (timezone) patches and press rows stay', async () => {
  const { db } = await setup()
  const t = new Date().toISOString()
  db.prepare("UPDATE games SET ps5_release = '2023-09-06' WHERE id = 'dawnwalker'").run()
  const add = (id: string, at: string, src: string) => {
    db.prepare(`INSERT INTO releases (id, game_id, version_key, display_name, kind, kind_basis, announced_at, notes, source_ids, content_hash, created_at, updated_at) VALUES (?, 'dawnwalker', ?, ?, 'patch', 'studio', ?, '[]', ?, 'x', ?, ?)`).run(id, id, id, at, JSON.stringify([src]), t, t)
    db.prepare(`INSERT INTO platform_releases (release_id, platform, status, verification, live_at, updated_at) VALUES (?, 'ps5', 'live', 'official', NULL, ?)`).run(id, t)
  }
  add('dawnwalker@old', '2021-08-31T10:00:00.000Z', 'dawnwalker-steam')
  add('dawnwalker@launch', '2023-09-06T08:00:00.000Z', 'dawnwalker-steam')
  add('dawnwalker@eve', '2023-09-05T23:00:00.000Z', 'dawnwalker-steam')
  add('dawnwalker@press', '2021-08-31T10:00:00.000Z', 'pushsquare')
  add('dawnwalker@nosrc', '2021-08-31T10:00:00.000Z', 'x')
  db.prepare("UPDATE releases SET source_ids = '[]' WHERE id = 'dawnwalker@nosrc'").run()
  store.dropPreLaunchPs5(db)
  const has = (id: string) => !!db.prepare("SELECT 1 FROM platform_releases WHERE release_id = ? AND platform = 'ps5'").get(id)
  assert.equal(has('dawnwalker@old'), false)
  assert.ok(has('dawnwalker@launch') && has('dawnwalker@eve') && has('dawnwalker@press'))
  assert.ok(has('dawnwalker@nosrc'), 'a release with no recorded source is not Steam-only')
})

test('trust audit (r050): with no PS5 date, Steam-assumed rows before the PS5 launch go; press-reported ones become PS4 updates without a PS5 version', async () => {
  const { db } = await setup()
  const t = new Date().toISOString()
  db.prepare("UPDATE games SET ps5_release = NULL WHERE id = 'dawnwalker'").run()
  const add = (id: string, at: string, sources: string[], verification: string, version: string | null) => {
    db.prepare(`INSERT INTO releases (id, game_id, version_key, display_name, kind, kind_basis, announced_at, notes, source_ids, content_hash, created_at, updated_at) VALUES (?, 'dawnwalker', ?, ?, 'patch', 'studio', ?, '[]', ?, 'x', ?, ?)`).run(id, id, id, at, JSON.stringify(sources), t, t)
    db.prepare(`INSERT INTO platform_releases (release_id, platform, status, verification, version, live_at, updated_at) VALUES (?, 'ps5', 'live', ?, ?, NULL, ?)`).run(id, verification, version && JSON.stringify({ value: version, verification, sourceId: sources[0], checkedAt: t }), t)
  }
  add('dawnwalker@steam-old', '2019-12-13T19:24:32.000Z', ['dawnwalker-steam'], 'assumed', null)
  add('dawnwalker@press-old', '2020-09-23T16:56:00.000Z', ['dawnwalker-steam', 'pushsquare'], 'reported', '01.004.000')
  add('dawnwalker@press-new', '2021-03-01T10:00:00.000Z', ['pushsquare'], 'reported', '01.005.000')
  assert.equal(store.dropPreLaunchPs5(db) >= 1, true)
  const since = new Map([[db.prepare("SELECT igdb_id FROM games WHERE id = 'dawnwalker'").get()!.igdb_id as number, '2015-05-19']])
  assert.equal(store.labelPreLaunchPs4(db, since), 1)
  const ps5 = (id: string) => db.prepare("SELECT version FROM platform_releases WHERE release_id = ? AND platform = 'ps5'").get(id) as { version: string | null } | undefined
  const ps4 = (id: string) => (db.prepare('SELECT ps4 FROM releases WHERE id = ?').get(id) as { ps4: number }).ps4
  assert.equal(ps5('dawnwalker@steam-old'), undefined)
  assert.equal(ps4('dawnwalker@press-old'), 1)
  assert.equal(ps5('dawnwalker@press-old')!.version, null)
  assert.equal(ps4('dawnwalker@press-new'), 0)
  assert.ok(ps5('dawnwalker@press-new')!.version)
  assert.equal(store.labelPreLaunchPs4(db, since), 0, 'safe to run every ingest')
})

test('trust audit (r050): an unreadable or empty PS5 index fails closed, never reads as "no game had a PS4 release"', async () => {
  const { writeFileSync, mkdtempSync } = await import('node:fs')
  const { tmpdir } = await import('node:os')
  const { join } = await import('node:path')
  const dir = mkdtempSync(join(tmpdir(), 'idx-'))
  assert.equal(ps4SinceFromIndex(new URL('file:///nonexistent/ps5-index.json')), undefined)
  writeFileSync(join(dir, 'empty.json'), JSON.stringify({ games: [{ i: 1, n: 'A' }] }))
  assert.equal(ps4SinceFromIndex(new URL(`file://${join(dir, 'empty.json')}`)), undefined)
  writeFileSync(join(dir, 'ok.json'), JSON.stringify({ games: [{ i: 7, n: 'B', b: '2019-01-01' }] }))
  assert.equal(ps4SinceFromIndex(new URL(`file://${join(dir, 'ok.json')}`))?.get(7), '2019-01-01')
  assert.ok(ps4SinceFromIndex()?.size, 'the real bundled index is readable')
})

test('trust audit (r050): a PS5 row over 90 days before the PS5 release with no PS4 version is dropped; a day-one patch and a PS4 game are kept', async () => {
  const { db } = await setup()
  const t = new Date().toISOString()
  db.prepare("UPDATE games SET ps5_release = '2026-07-10' WHERE id = 'dawnwalker'").run()
  const add = (id: string, at: string) => {
    db.prepare(`INSERT INTO releases (id, game_id, version_key, display_name, kind, kind_basis, announced_at, notes, source_ids, content_hash, created_at, updated_at) VALUES (?, 'dawnwalker', ?, ?, 'patch', 'studio', ?, '[]', '["pushsquare"]', 'x', ?, ?)`).run(id, id, id, at, t, t)
    db.prepare(`INSERT INTO platform_releases (release_id, platform, status, verification, live_at, updated_at) VALUES (?, 'ps5', 'live', 'reported', NULL, ?)`).run(id, t)
  }
  add('dawnwalker@pc-patch', '2024-12-23T15:00:00.000Z')
  add('dawnwalker@dayone', '2026-07-05T10:00:00.000Z')
  const has = (id: string) => !!db.prepare("SELECT 1 FROM platform_releases WHERE release_id = ? AND platform = 'ps5'").get(id)
  const igdb = db.prepare("SELECT igdb_id FROM games WHERE id = 'dawnwalker'").get()!.igdb_id as number
  assert.equal(store.labelPreLaunchPs4(db, new Map()), 0, 'a game with a PS5 date and no PS4 release is never relabelled')
  assert.equal(store.dropEarlyPs5(db, new Map([[igdb, '2020-01-01']])), 0, 'a game with a PS4 release keeps its rows')
  assert.equal(store.dropEarlyPs5(db, new Map()), 1)
  assert.equal(has('dawnwalker@pc-patch'), false)
  assert.ok(has('dawnwalker@dayone'))
})

// Roadmap duplicate audit: the same patch seen as "1.4" by the press and "1.4.0" by Steam is one release.
const spelling = async (steamTitle: string, pressTitle: string, steamHoursAgo = 30, pressHoursAgo = 28) => {
  const db = openDb(':memory:')
  const fetchFn = fakeFetch({
    'https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=3751260': steamNews([{ gid: '1', title: steamTitle, date: recent(steamHoursAgo), contents: 'Notes.[list][*]Fixed a crash[/list]', tags: ['patchnotes'] }]),
    'https://www.pushsquare.com/news/dw': pressArticle(pressTitle, 'The patch is 3.5GB on PS5 and brings it to version 01.004.000.'),
    'https://www.pushsquare.com/tags/updates': pressIndexPage([{ title: pressTitle, path: 'news/dw', date: recent(pressHoursAgo), tags: ['PS5', 'Dawnwalker', 'Updates'] }]),
  })
  const deps = { db, fetchFn, igdb: null }
  await seedGames(deps)
  await runIngest(deps)
  return db
}
const dawnwalkerIds = (db: ReturnType<typeof openDb>) => (db.prepare("SELECT id FROM releases WHERE game_id = 'dawnwalker' ORDER BY id").all() as { id: string }[]).map((r) => r.id)

test('a press announcement older than 30 days reads as live only when a later release is live; a delayed one stays announced; a fresh one stays announced', async () => {
  const ps5 = (db: ReturnType<typeof openDb>, id: string) => store.getPlatformRow(db, id, 'ps5')?.status
  // Steam patch 1.5 is the earlier release, so nothing came after the announced 1.9: it stays announced.
  const delayed = await spelling('The Blood of Dawnwalker - Update 1.5', 'Dawnwalker PS5 Update 1.9 Will Arrive Next Week', 100 * 24, 90 * 24)
  assert.equal(ps5(delayed, 'dawnwalker@1.9'), 'announced')
  // Steam patch 1.5 landed after the announcement and is live: the old announcement has happened.
  const settled = await spelling('The Blood of Dawnwalker - Update 1.5', 'Dawnwalker PS5 Update 1.9 Will Arrive Next Week', 80 * 24, 90 * 24)
  assert.equal(ps5(settled, 'dawnwalker@1.9'), 'live')
  assert.equal(store.settleOldAnnouncements(settled), 0, 'idempotent')
  const fresh = await spelling('The Blood of Dawnwalker - Update 1.5', 'Dawnwalker PS5 Update 1.8 Will Arrive Next Week', 20, 28)
  assert.equal(ps5(fresh, 'dawnwalker@1.8'), 'announced')
})

test('a blocked source is retried once a day and the block clears on success; robots.txt is still honoured on the retry', async () => {
  const blockedAt = (db: ReturnType<typeof openDb>, hoursAgo: number) =>
    db.prepare("INSERT OR REPLACE INTO source_state (source_id, last_fetched_at, last_status, last_error, blocked, fail_streak) VALUES ('pushsquare', ?, 403, 'x', 1, 0)").run(new Date(Date.now() - hoursAgo * 3600e3).toISOString())
  const state = (db: ReturnType<typeof openDb>) => db.prepare("SELECT blocked, last_status FROM source_state WHERE source_id = 'pushsquare'").get() as { blocked: number; last_status: number }
  const run = async (db: ReturnType<typeof openDb>, routes: Record<string, string | { status: number; body?: string }> = {}) => {
    const deps = { db, fetchFn: fakeFetch({ 'https://www.pushsquare.com/tags/updates': pressIndexPage([]), ...routes }), igdb: null }
    await seedGames(deps)
    return runIngest(deps, { force: true })
  }
  const recent1 = openDb(':memory:')
  await seedGames({ db: recent1, fetchFn: fakeFetch({}), igdb: null })
  blockedAt(recent1, 1)
  assert.ok((await run(recent1)).skipped.includes('pushsquare'), 'blocked an hour ago: not asked again')
  assert.equal(state(recent1).blocked, 1)
  const old = openDb(':memory:')
  await seedGames({ db: old, fetchFn: fakeFetch({}), igdb: null })
  blockedAt(old, 25)
  assert.ok((await run(old)).polled.includes('pushsquare'), 'blocked over a day ago: one retry')
  assert.deepEqual({ ...state(old) }, { blocked: 0, last_status: 200 })
  const robots = openDb(':memory:')
  await seedGames({ db: robots, fetchFn: fakeFetch({}), igdb: null })
  blockedAt(robots, 25)
  clearRobotsCache()
  const r = await run(robots, { 'https://www.pushsquare.com/robots.txt': 'User-agent: *\nDisallow: /' })
  clearRobotsCache()
  assert.ok(!r.polled.includes('pushsquare'))
  assert.equal(state(robots).blocked, 1, 'a robots.txt disallow keeps it blocked')
})

test('the same version number far apart is two patches: a press report keeps its own release (PS5 1.4 in the past, the later 1.4.0 from Steam)', async () => {
  const db = await spelling('The Blood of Dawnwalker - Update 1.4', 'Dawnwalker PS5 Update 1.4 Out Now', 100 * 24, 300 * 24)
  const ids = dawnwalkerIds(db)
  assert.equal(ids.length, 2, ids.join())
  const press = ids.find((i) => i !== 'dawnwalker@1.4')!
  assert.match(press, /^dawnwalker@1\.4-\d{4}-\d{2}-\d{2}$/)
  assert.equal(getRelease(db, press)!.displayName, 'Update 1.4')
  assert.equal(store.getPlatformRow(db, 'dawnwalker@1.4', 'ps5')?.verification, 'assumed', 'the later Steam patch is untouched by the old press report')
  assert.equal(store.getPlatformRow(db, press, 'ps5')?.verification, 'reported')
})

test('one patch under two spellings of its version is one release; its PS5 facts and sources fold in', async () => {
  const db = await spelling('The Blood of Dawnwalker - Update 1.4.0', 'Dawnwalker PS5 Update 1.4 Out Now')
  assert.deepEqual(dawnwalkerIds(db), ['dawnwalker@1.4.0'])
  const r = getRelease(db, 'dawnwalker@1.4.0')!
  assert.deepEqual(r.sourceIds.sort(), ['dawnwalker-steam', 'pushsquare'])
  const ps5 = r.platforms.find((p) => p.platform === 'ps5')!
  assert.equal(ps5.version?.value, '01.004.000')
  assert.equal(ps5.verification, 'reported')
})

test('the same spelling difference with the press first, and a studio post later, still gives one release', async () => {
  const db = await spelling('The Blood of Dawnwalker - Update 1.4.0', 'Dawnwalker PS5 Update 1.4 Out Now', 20, 30)
  assert.equal(dawnwalkerIds(db).length, 1)
})

test('a press-only duplicate stored before this rule is folded into the real release', async () => {
  const db = await spelling('The Blood of Dawnwalker - Update 1.4.0', 'Dawnwalker PS5 Update 1.4 Out Now')
  const real = getRelease(db, 'dawnwalker@1.4.0')!
  const t = new Date().toISOString()
  db.prepare(`INSERT INTO releases (id, game_id, version_key, display_name, kind, kind_basis, announced_at, notes, source_ids, content_hash, created_at, updated_at) VALUES ('dawnwalker@1.4', 'dawnwalker', '1.4', 'Update 1.4', 'silent', 'inferred', ?, '[]', '["pushsquare"]', 'x', ?, ?)`).run(real.announcedAt, t, t)
  db.prepare(`INSERT INTO platform_releases (release_id, platform, status, version, size_bytes, live_at, bundles, verification, updated_at) VALUES ('dawnwalker@1.4', 'ps5', 'live', NULL, NULL, NULL, '[]', 'reported', ?)`).run(t)
  assert.equal(store.mergeSilentDuplicates(db), 1)
  assert.deepEqual(dawnwalkerIds(db), ['dawnwalker@1.4.0'])
  assert.equal(store.mergeSilentDuplicates(db), 0)
})

test('"Patch 10.2" and "Patch 10.2.0" months apart are different patches; "2.0" is not "2"', async () => {
  const { versionIdentity, equivalentRelease } = store
  assert.equal(versionIdentity('1.4.0'), versionIdentity('1.4'))
  assert.equal(versionIdentity('1.4.0.0'), '1.4')
  assert.equal(versionIdentity('2.0'), '2.0')
  assert.notEqual(versionIdentity('1.4.1'), versionIdentity('1.4'))
  const db = openDb(':memory:')
  await seedGames({ db, fetchFn: fakeFetch({}), igdb: null })
  const t = new Date().toISOString()
  db.prepare(`INSERT INTO releases (id, game_id, version_key, display_name, kind, kind_basis, announced_at, notes, source_ids, content_hash, created_at, updated_at) VALUES ('dawnwalker@10.2.0', 'dawnwalker', '10.2.0', 'Patch 10.2.0', 'patch', 'studio', '2026-09-15T15:07:00.000Z', '[]', '[]', 'x', ?, ?)`).run(t, t)
  assert.equal(equivalentRelease(db, 'dawnwalker', '10.2', '2026-10-29T15:06:00.000Z'), undefined)
  assert.equal(equivalentRelease(db, 'dawnwalker', '10.2', '2026-09-16T15:06:00.000Z')?.id, 'dawnwalker@10.2.0')
})

test('richer alerts (r050): counts in the title, headline body, counts fallback', () => {
  const d = { new: 3, fixed: 12, balance: 0, other: 1, ps5: 2 }
  assert.deepEqual(alertCopy('Dawnwalker', 'Update 1.1', { ...d, topNew: ['New skill tree'] }), { title: 'Dawnwalker: 3 new, 12 fixed, 2 PS5-only', body: 'Update 1.1: New skill tree' })
  assert.equal(alertCopy('Dawnwalker', 'Update 1.1', d).body, '3 new, 12 fixed, 2 PS5-only.')
  assert.deepEqual(alertCopy('Dawnwalker', 'Update 1.1', { new: 1, fixed: 0, balance: 0, other: 4, ps5: 0 }), { title: 'Dawnwalker: 1 new', body: '1 new.' })
  assert.deepEqual(alertCopy('Dawnwalker', 'Update 1.1', { new: 0, fixed: 0, balance: 0, other: 4, ps5: 0 }), { title: 'Dawnwalker', body: 'A new update is out' })
})

test('headline: text before a colon, 60 characters at a word boundary, ellipsis only when cut', () => {
  assert.equal(headlineOf('Added photo mode'), 'Added photo mode')
  assert.equal(headlineOf('Photo mode: capture every fight in the dark forest'), 'Photo mode')
  const long = 'Added a brand new endless survival mode with daily challenges and leaderboards for every player'
  const h = headlineOf(long)!
  assert.ok(h.length <= 60 && h.endsWith('…') && !h.slice(0, -1).endsWith(' '))
  assert.ok(long.startsWith(h.slice(0, -1)))
  assert.equal(headlineOf('x'.repeat(59)), 'x'.repeat(59))
  assert.equal(headlineOf(undefined), null)
  assert.equal(headlineOf(': nothing before'), null)
})

test('data audit: a later post for the same release never moves a Steam-assumed PS5 date later; repair fixes stored rows', async () => {
  const { db } = await setup()
  const ps5 = () => store.getPlatformRow(db, 'dawnwalker@1.1.1', 'ps5')!
  const live = () => JSON.parse(ps5().live_at as string).value as string
  const first = live()
  // A second Steam-assumed write with a later date keeps the first.
  store.upsertPlatform(db, 'dawnwalker@1.1.1', 'ps5', { status: 'live', verification: 'assumed', liveAt: store.field(new Date(Date.parse(first) + 3 * 86400e3).toISOString(), 'assumed', 'dawnwalker-steam') })
  assert.equal(live(), first)
  // Stored rows already moved later are repaired to the PC row's Steam date.
  const pc = JSON.parse(store.getPlatformRow(db, 'dawnwalker@1.1.1', 'pc')!.live_at as string).value as string
  db.prepare("UPDATE platform_releases SET live_at = ? WHERE release_id = 'dawnwalker@1.1.1' AND platform = 'ps5'").run(JSON.stringify({ ...JSON.parse(ps5().live_at as string), value: new Date(Date.parse(pc) + 86400e3).toISOString() }))
  assert.ok(store.repairAssumedLiveAt(db) >= 1)
  assert.equal(live(), pc)
  assert.equal(store.repairAssumedLiveAt(db), 0)
})

test('news: Push Square headlines that name a tracked game are Reported news (title, date, link); its patch and unrelated items are not', async () => {
  const db = openDb(':memory:')
  const fetchFn = fakeFetch({
    'https://www.pushsquare.com/feeds/latest': rss([
      { title: 'The Blood of Dawnwalker gets a free photo mode next week', link: 'https://www.pushsquare.com/news/2026/11/dawnwalker-photo-mode', date: recent(3), body: '<p>Long article text that must never be stored.</p>' },
      { title: 'Dawnwalker Update 1.2 patch notes', link: 'https://www.pushsquare.com/news/2026/11/dawnwalker-1-2', date: recent(2), body: '<p>x</p>' },
      { title: 'Some other game announced', link: 'https://www.pushsquare.com/news/2026/11/other', date: recent(1), body: '<p>y</p>' },
    ]),
  })
  const deps = { db, fetchFn, igdb: null }
  await seedGames(deps)
  await runIngest(deps, { force: true })
  const items = newsOf(db, 'dawnwalker').filter((n) => n.url.includes('pushsquare'))
  assert.equal(items.length, 2) // photo mode headline and the patch-titled headline are both news here
  assert.ok(items.every((n) => n.verification === 'reported'))
  assert.deepEqual(Object.keys(items[0]!).sort(), ['date', 'gameId', 'title', 'url', 'verification'])
  assert.ok(!JSON.stringify(items).includes('Long article text'))
  assert.equal(db.prepare("SELECT COUNT(*) AS n FROM news WHERE url LIKE '%other%'").get()!.n, 0)
  assert.ok(!db.prepare("SELECT 1 FROM releases WHERE game_id = 'dawnwalker' AND source_ids LIKE '%pushsquare-news%'").get(), 'the news feed never makes a release')
})

// Terry 2026-11-06: PS4 games play on PS5, so a PS4 patch for a game with no native PS5 version counts, labelled ps4.
test('a PS4 patch post for a backward-compatible game is a labelled PS4 update; a native PS5 game ignores PS4 posts after its launch', async () => {
  const title = 'Dawnwalker PS4 Patch 1.9 Out Now'
  const build = async (ps5Release: string | null) => {
    const db = openDb(':memory:')
    const fetchFn = fakeFetch({
      'https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=3751260': steamNews([]),
      'https://www.pushsquare.com/news/dw4': pressArticle(title, 'The patch is 1.2GB on PS4.'),
      'https://www.pushsquare.com/tags/updates': pressIndexPage([{ title, path: 'news/dw4', date: recent(50), tags: ['PS4', 'Dawnwalker', 'Updates'] }]),
    })
    const deps = { db, fetchFn, igdb: null }
    await seedGames(deps)
    db.prepare('UPDATE games SET ps5_release = ? WHERE id = ?').run(ps5Release, 'dawnwalker')
    await runIngest(deps)
    return db
  }
  const compat = await build(null)
  const r = getRelease(compat, 'dawnwalker@1.9')!
  assert.equal(r.ps4, true)
  assert.equal(r.displayName.includes('PS5'), false)
  assert.equal(r.platforms.find((p) => p.platform === 'ps5')!.verification, 'reported')
  assert.equal(store.dropPreLaunchPs5(compat), 0)
  const native = await build('2020-01-01')
  assert.equal(getRelease(native, 'dawnwalker@1.9'), null)
})

// Quinn's review of the PS4 history rule (#280).
const ps4World = async (posts: { title: string; body?: string; hoursAgo: number; tags?: string[] }[], ps5Release: string | null) => {
  const db = openDb(':memory:')
  const pages: Record<string, unknown> = {
    'https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=3751260': steamNews([]),
  }
  posts.forEach((p, i) => (pages[`https://www.pushsquare.com/news/p${i}`] = pressArticle(p.title, p.body ?? 'The patch is 1.2GB.')))
  pages['https://www.pushsquare.com/tags/updates'] = pressIndexPage(posts.map((p, i) => ({ title: p.title, path: `news/p${i}`, date: recent(p.hoursAgo), tags: p.tags ?? ['PS4', 'Dawnwalker', 'Updates'] })))
  const deps = { db, fetchFn: fakeFetch(pages as never), igdb: null }
  await seedGames(deps)
  db.prepare('UPDATE games SET ps5_release = ? WHERE id = ?').run(ps5Release, 'dawnwalker')
  await runIngest(deps)
  return db
}

test('a PS4 build number is never the PS5 version', async () => {
  const db = await ps4World([{ title: 'Dawnwalker PS4 Patch 1.9 Out Now', body: 'Brings the game to Ver. 1.005.000 on PS4.', hoursAgo: 50 }], null)
  const r = getRelease(db, 'dawnwalker@1.9')!
  assert.equal(r.ps4, true)
  assert.equal(r.platforms.find((p) => p.platform === 'ps5')!.version, null)
})

test('a PS4 post is kept when it predates the native PS5 release and ignored after it', async () => {
  const launch = new Date(Date.now() - 20 * 86400e3).toISOString().slice(0, 10)
  const db = await ps4World([
    { title: 'Dawnwalker PS4 Patch 1.8 Out Now', hoursAgo: 24 * 40 },
    { title: 'Dawnwalker PS4 Patch 1.9 Out Now', hoursAgo: 24 * 5 },
  ], launch)
  assert.equal(getRelease(db, 'dawnwalker@1.8')?.ps4, true)
  assert.equal(getRelease(db, 'dawnwalker@1.9'), null)
})

test('a title naming PS4 and PS5 is a PS5 post, not labelled ps4; a PS5 report joining a ps4 release clears the label', async () => {
  const db = await ps4World([{ title: 'Dawnwalker PS5, PS4 Patch 1.9 Out Now', hoursAgo: 50, tags: ['PS5', 'PS4', 'Dawnwalker', 'Updates'] }], null)
  assert.equal(getRelease(db, 'dawnwalker@1.9')?.ps4, undefined)
  const labelled = await ps4World([{ title: 'Dawnwalker PS4 Patch 1.9 Out Now', hoursAgo: 50 }], null)
  assert.equal(getRelease(labelled, 'dawnwalker@1.9')?.ps4, true)
  labelled.prepare("UPDATE releases SET ps4 = 1 WHERE id = 'dawnwalker@1.9'").run()
  const deps = { db: labelled, fetchFn: fakeFetch({
    'https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=3751260': steamNews([]),
    'https://www.pushsquare.com/news/n': pressArticle('Dawnwalker PS5 Patch 1.9 Out Now', 'The patch is 3GB on PS5.'),
    'https://www.pushsquare.com/tags/updates': pressIndexPage([{ title: 'Dawnwalker PS5 Patch 1.9 Out Now', path: 'news/n', date: recent(40), tags: ['PS5', 'Dawnwalker', 'Updates'] }]),
  } as never), igdb: null }
  labelled.prepare("DELETE FROM source_state").run()
  await runIngest(deps, { force: true })
  assert.equal(getRelease(labelled, 'dawnwalker@1.9')?.ps4, undefined)
})

test('a PS4-only post from an RSS feed is labelled ps4, not stored as a PS5 update', async () => {
  const db = openDb(':memory:')
  const fetchFn = fakeFetch({
    'https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=3751260': steamNews([]),
    'https://www.playstationlifestyle.net/feed': rss([{ title: 'Dawnwalker PS4 Patch 1.9 Is Out Now', link: 'https://www.playstationlifestyle.net/dw19', date: recent(50), body: '<p>Patch 1.9 is 1GB.</p>' }]),
  } as never)
  const deps = { db, fetchFn, igdb: null }
  await seedGames(deps)
  await runIngest(deps)
  assert.equal(getRelease(db, 'dawnwalker@1.9')?.ps4, true)
})
