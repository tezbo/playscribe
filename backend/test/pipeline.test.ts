import assert from 'node:assert/strict'
import { test } from 'node:test'
import { confirmPlatform } from '../src/confirm.ts'
import { openDb } from '../src/db.ts'
import { runIngest, seedGames } from '../src/ingest/pipeline.ts'
import { pushPs5Release, pushNewPs5 } from '../src/push/notify.ts'
import type { Apns } from '../src/push/apns.ts'
import * as store from '../src/store.ts'
import { getRelease, newsOf, promoteAnnounced } from '../src/store.ts'
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
  assert.match(sent[0]!.payload.aps.alert.body, /Update 1\.6 is out on PS5 \(version 01\.006\.000\)/)
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
  assert.match(p.aps.alert.body, /Update 1\.1 is out on PS5/)
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
  assert.ok(newsOf(db, 'dawnwalker').every((n) => Object.keys(n).sort().join() === 'date,gameId,title,url' && n.gameId === 'dawnwalker'))
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
