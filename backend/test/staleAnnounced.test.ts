import assert from 'node:assert/strict'
import { test } from 'node:test'
import { openDb } from '../src/db.ts'
import { ALERT_MAX_AGE_HOURS } from '../src/alerts.ts'
import { seedAutoGames, type AutoGame } from '../src/ingest/autoRegistry.ts'
import { runIngest, seedGames } from '../src/ingest/pipeline.ts'
import { pushPs5Release } from '../src/push/notify.ts'
import type { Apns } from '../src/push/apns.ts'
import * as store from '../src/store.ts'
import { fakeFetch, steamNews } from './helpers.ts'

// feed-stale-announced-rows (B1, 0.5.5). Feed run 43257955413 (12 Nov 2026, 16:49 to 17:06 UTC) polled 600 newly
// auto-onboarded games for the first time. Their whole Steam history was read; posts saying consoles get the patch later
// made announced PS5 rows, and promoteAnnounced at the end of the same run took them live with alert_from = the run time,
// so updates from 2023 to October 2026 were published as if they had just reached PS5. These are those 11 rows, with each
// Steam date kept at the same age it had at 17:05:01 that day.
const RUN = Date.parse('2026-11-12T17:05:01.005Z')
const ROWS: [game: string, app: number, steamDate: string][] = [
  ['tt-isle-of-man-ride-on-the-edge-3', 228729, '2023-06-09T13:39:34.000Z'],
  ['underdungeon', 219525, '2024-03-08T13:53:02.000Z'],
  ['towers-of-aghasba', 250636, '2025-06-11T22:50:42.000Z'],
  ['void-crew', 243017, '2025-09-11T09:09:26.000Z'],
  ['vampire-the-masquerade-bloodlines-2', 116530, '2025-10-30T16:32:45.000Z'],
  ['wizordum', 216197, '2025-12-18T18:00:30.000Z'],
  ['trail-out', 188913, '2026-03-17T03:03:59.000Z'],
  ['unbeatable', 144859, '2026-04-01T16:06:40.000Z'],
  ['unbeatable', 144859, '2026-06-25T22:06:14.000Z'],
  ['unrailed-2-back-on-track', 278600, '2026-07-10T15:19:04.000Z'],
  ['transport-fever-3', 344466, '2026-10-08T13:05:35.000Z'],
]
// The same path for a patch inside the 30-day window #481 left open: 10 days after Steam is 3 days past the day it counts as
// live on PS5 (Steam + 7 days), so it is past the 72 h alert window too.
const TEN_DAYS: [string, number, string] = ['fresh-onboard', 900001, new Date(RUN - 10 * 86400e3).toISOString()]

const auto = (id: string, app: number): AutoGame => ({
  id, steamAppId: app, name: id, igdbId: app, ps5TitleIds: [], ps5Release: '2023-01-01',
  sources: [{ id: `auto-${app}-steam`, kind: 'steamNews', url: `https://store.steampowered.com/feeds/news/app/${app}/`, platforms: ['pc'], trust: 'official', fetch: 'auto', ps5Signal: 'explicit' }],
})

const DAY = 86400e3
const PS5_LIVE_AFTER = 7 * DAY

test('first poll of an auto-onboarded game: old console-later Steam patches go live on PS5 without a fresh alert (the 11 rows)', async () => {
  const db = openDb(':memory:')
  const shift = Date.now() - RUN
  const rows = [...ROWS, TEN_DAYS].map(([game, app, date], i) => ({ game: `${game}-${app}`, app, date: new Date(Date.parse(date) + shift).toISOString(), gid: `p${i}`, version: `9.${i}` }))
  const routes: Record<string, string> = {}
  for (const app of new Set(rows.map((r) => r.app))) {
    routes[`https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=${app}`] = steamNews(
      rows.filter((r) => r.app === app).map((r) => ({ gid: r.gid, title: `Patch ${r.version}`, date: r.date, contents: `Patch ${r.version} is live on PC. Console versions will follow after certification.[list][*]Fixed a crash[/list]`, tags: ['patchnotes'] })),
    )
  }
  const deps = { db, fetchFn: fakeFetch(routes), igdb: null }
  await seedGames(deps)
  const games = [...new Map(rows.map((r) => [r.game, auto(r.game, r.app)])).values()]
  seedAutoGames(db, games)

  // The 12 Nov run: one regular poll whose auto slice reads each game's history for the first time.
  await runIngest(deps, { autoSlice: games.length })

  const t = new Date().toISOString()
  db.prepare("INSERT INTO devices (id, key_hash, apns_token, environment, created_at, updated_at) VALUES ('d', 'hd', ?, 'production', ?, ?)").run('d'.repeat(64), t, t)
  for (const g of games) db.prepare("INSERT INTO follows (device_id, game_id, notify) VALUES ('d', ?, 'all')").run(g.id)
  const sent: unknown[] = []
  const apns = { send: async (_t: string, _e: string, p: object) => (sent.push(p), { status: 200 }) } as unknown as Apns

  for (const r of rows) {
    const id = `${r.game}@${r.version}`
    const release = store.getRelease(db, id)
    assert.ok(release, `${id} was created`)
    const ps5 = release.platforms.find((p) => p.platform === 'ps5')!
    // Check 3: a week past Steam it is live on PS5, dated from Steam; it never stays announced.
    assert.deepEqual([ps5.status, ps5.verification, ps5.liveAt?.value], ['live', 'assumed', r.date], id)
    // The stored alert moment is when it counted as live on PS5 (Steam + 7 days), never the run that first read it.
    const row = db.prepare("SELECT alert_from FROM platform_releases WHERE release_id = ? AND platform = 'ps5'").get(id) as { alert_from: string | null }
    assert.ok(row.alert_from && Date.parse(row.alert_from) <= Date.parse(r.date) + PS5_LIVE_AFTER, `${id}: alert_from ${row.alert_from} is the run time, not the day it went live on PS5`)
    // Check 4: no alert window in the feed the app reads, and the push job skips it as too old.
    const from = ps5.alert?.from
    assert.ok(from && Date.now() - Date.parse(from) > ALERT_MAX_AGE_HOURS * 3600e3, `${id}: feed alert window opens at ${from}`)
    assert.equal((await pushPs5Release(db, apns, id, { maxAgeHours: ALERT_MAX_AGE_HOURS })).skipped, 'tooOld', id)
  }
  assert.equal(sent.length, 0)
})

test('a console-later patch announced before its week is up still earns its alert when it goes live on PS5', async () => {
  const db = openDb(':memory:')
  const date = new Date(Date.now() - 3 * DAY).toISOString()
  const deps = {
    db,
    fetchFn: fakeFetch({
      'https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=900002': steamNews([{ gid: 'q1', title: 'Patch 2.0', date, contents: 'Patch 2.0 is live on PC. Console versions will follow after certification.[list][*]Fixed a crash[/list]', tags: ['patchnotes'] }]),
    }),
    igdb: null,
  }
  await seedGames(deps)
  seedAutoGames(db, [auto('on-time-900002', 900002)])
  await runIngest(deps, { autoSlice: 1 })
  assert.equal(store.getRelease(db, 'on-time-900002@2.0')!.platforms.find((p) => p.platform === 'ps5')!.status, 'announced')
  // The hourly run that sees the week pass (an hour late here) takes it live and opens its 72 h alert window.
  const at = new Date(Date.parse(date) + PS5_LIVE_AFTER + 3600e3)
  assert.equal(store.promoteAnnounced(db, at), 1)
  const alertFrom = (db.prepare("SELECT alert_from FROM platform_releases WHERE release_id = 'on-time-900002@2.0' AND platform = 'ps5'").get() as { alert_from: string }).alert_from
  assert.ok(at.getTime() - Date.parse(alertFrom) < ALERT_MAX_AGE_HOURS * 3600e3, `alert_from ${alertFrom}`)
  assert.ok(Date.parse(alertFrom) >= Date.parse(date) + PS5_LIVE_AFTER)
})

test('a console-later patch that reaches PS5 on day 2 alerts in the day-2 run, not on day 7', async () => {
  const db = openDb(':memory:')
  const day0 = new Date(Date.now() - 2 * DAY).toISOString()
  const day2 = new Date(Date.now() - 3600e3).toISOString()
  const day0Post = { gid: 'd0', title: 'Patch 3.0', date: day0, contents: 'Patch 3.0 is live on PC. Console versions will follow after certification.[list][*]Fixed a crash[/list]', tags: ['patchnotes'] }
  const day2Post = { gid: 'd2', title: 'Patch 3.0 is now live on PS5', date: day2, contents: 'Patch 3.0 is now live on PlayStation 5 and Xbox Series X|S.', tags: ['patchnotes'] }
  const url = 'https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=900003'
  let posts = [day0Post]
  const deps = { db, fetchFn: ((u: string, i?: RequestInit) => fakeFetch({ [url]: steamNews(posts) })(u, i)) as typeof fetch, igdb: null }
  await seedGames(deps)
  seedAutoGames(db, [auto('day-two-900003', 900003)])
  await runIngest(deps, { autoSlice: 1 })
  const ps5 = () => store.getRelease(db, 'day-two-900003@3.0')!.platforms.find((p) => p.platform === 'ps5')!
  assert.equal(ps5().status, 'announced')
  // Day 2: the studio says it is out on PS5. That run takes it live and opens the alert window now, five days before the week is up.
  posts = [day0Post, day2Post]
  // Two days pass: the game's Steam feed is due again.
  db.prepare('UPDATE source_state SET last_fetched_at = ?').run(day0)
  await runIngest(deps, { autoSlice: 1, force: true })
  assert.equal(ps5().status, 'live')
  const from = ps5().alert?.from
  assert.ok(from && Date.now() - Date.parse(from) < ALERT_MAX_AGE_HOURS * 3600e3, `alert window opens at ${from}`)
  const t = new Date().toISOString()
  db.prepare("INSERT INTO devices (id, key_hash, apns_token, environment, created_at, updated_at) VALUES ('e', 'he', ?, 'production', ?, ?)").run('e'.repeat(64), t, t)
  db.prepare("INSERT INTO follows (device_id, game_id, notify) VALUES ('e', 'day-two-900003', 'all')").run()
  const sent: unknown[] = []
  const apns = { send: async (_t: string, _e: string, p: object) => (sent.push(p), { status: 200 }) } as unknown as Apns
  assert.equal((await pushPs5Release(db, apns, 'day-two-900003@3.0', { maxAgeHours: ALERT_MAX_AGE_HOURS })).sent, 1)
})
