import assert from 'node:assert/strict'
import { test } from 'node:test'
import { openDb } from '../src/db.ts'
import { isAnnouncementTitle, isTestBuildPost, pcScopedPost, statedLiveTime } from '../src/ingest/claims.ts'
import { nameRelease } from '../src/ingest/classify.ts'
import { runIngest, seedGames } from '../src/ingest/pipeline.ts'
import * as store from '../src/store.ts'
import { seedAutoGames } from '../src/ingest/autoRegistry.ts'
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

test('a headline announcing a not-yet-shipped update is not a release (Palworld Feybreak)', () => {
  assert.ok(isAnnouncementTitle("Palworld's next major update, Feybreak, releases on Dec. 23"))
  assert.ok(isAnnouncementTitle('Update 1.2 Coming Tomorrow'))
  assert.ok(!isAnnouncementTitle('Update 1.2 Patch Notes'))
  assert.ok(!isAnnouncementTitle('Hotfix 1.0.5 is now live'))
  assert.ok(!isAnnouncementTitle('10.2.2a Backend Bugfix Patch'))
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
  assert.equal(statedLiveTime('The free update arrives on November 20, 2026 on all platforms.', pub), '2026-11-20T23:59:00.000Z')
  assert.equal(statedLiveTime('The update will be live at 14:00 UTC-5 on November 10.', pub), '2026-11-10T19:00:00.000Z')
  assert.equal(statedLiveTime('The update released on November 1 fixed a lot.', pub), null)
  assert.equal(statedLiveTime('The sale ends on November 12. Patch notes below.', pub), null)
  assert.equal(statedLiveTime('Fixed a crash.', pub), null)
})

test('the time that counts is the one in the sentence naming PlayStation (Delta Force); a maintenance notice titled as an update lands when the maintenance ends (Crystal of Atlan)', () => {
  const delta = `Major Update: Season Aurora Is Coming!
Dear Operators,

We plan to launch a non-stop update for PC, mobile, and console versions on November 10, opening the new season "Aurora"!
The expected update cadence for the PC version is as follows:
At 00:30 UTC+0 on November 10, Operations and Warfare ranked matches will be off-season and temporarily closed.
At 02:00 UTC+0 on November 10, the PC update will be available.

The expected update cadence for the console version is as follows:
At 00:30 UTC+0 on November 10, Operations and Warfare ranked matches will be off-season and temporarily closed.
At 01:59 UTC+0 on November 10, the Operations entrance and matchmaking mode will be closed.
At 02:00 UTC+0 on November 10, the updates for Xbox Series X|S and PlayStation 5 will be available.`
  assert.equal(statedLiveTime(delta, '2026-11-07T12:00:03.000Z'), '2026-11-10T02:00:00.000Z')
  const crystal = `November 12 Version Update Notice
Dear Adventurer,
To provide adventurers with a better experience, the Guild will be issuing a temporary restraining order on all adventurer activities in Atlan starting on November 12, 2026 at 06:00 (UTC+0). This order is expected to remain in effect for approximately 4 hours (maintenance may end earlier or be extended depending on actual conditions).`
  assert.equal(statedLiveTime(crystal, '2026-11-11T07:29:28.000Z'), '2026-11-12T10:00:00.000Z')
  // Without an update title the same maintenance wording is not a release time.
  assert.equal(statedLiveTime(crystal.replace('Version Update Notice', 'Server Notice'), '2026-11-11T07:29:28.000Z'), null)
})

test('live patches that mention another date are not held (Quinn scan of 2,664 real posts, 12 Nov)', () => {
  const pub = '2026-11-05T10:00:00.000Z'
  // wording modelled on the false firings: CoH3 3.0.0 (a DLC date), DbD 10.0.3 and 10.0.1 (an event start, a survivor),
  // Helldivers 6.0.1 (a store item), Apex (a matchmaking test tomorrow)
  for (const t of [
    '3.0.0 Update Patch Notes\nThe new DLC will be released on November 25, 2026.',
    '10.0.3 Bugfix Patch\nThe Summer Screams event will start on November 12 with new rewards.',
    '10.0.1 Patch Notes\nA new survivor will be available on November 7.',
    '6.0.1 Patch Notes\nThe warbond store item will return on November 10.',
    'Latest Update 10/6/2026\nA matchmaking test will begin tomorrow, November 6.',
    'November 5 Update\nWe will roll out the update on November 5 with no downtime.',
  ]) assert.equal(statedLiveTime(t, pub), null, t)
  assert.equal(statedLiveTime('Patch notes\nThe 3.0 update will arrive on November 30.', pub), null, 'beyond 14 days')
})

test('a post that is itself the release, or talks about the next one, is not held (Rematch S3.0, Slay the Spire)', () => {
  assert.equal(statedLiveTime('S3.0 Patch Notes - 1.203.000\nS3.0 Release Date: March 25th\n1v1 will be back during season 3! April 3rd', '2026-03-25T09:00:00.000Z'), null)
  assert.equal(statedLiveTime('Weekly Patch 53\nThe next patch will be on January 3, 2019.', '2018-12-21T18:00:00.000Z'), null)
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
  const summary = await runIngest(deps)
  return { db, deps, summary }
}
const ps5Of = (db: ReturnType<typeof openDb>, id: string) => store.getRelease(db, id)?.platforms.find((p) => p.platform === 'ps5')

test('ingest: test builds and PC-scoped posts make no PS5 row; a stated later time holds the row announced until then', async () => {
  const when = day(2)
  const { db, summary } = await setup([
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
  assert.deepEqual(summary.held, { stated: 1, testBuild: 1, pcScoped: 1, announcement: 0 })
  // Nothing happens early; once the time has passed the row is live and earns its one alert from now.
  assert.equal(store.promoteStated(db, day(1)), 0)
  assert.equal(store.promoteStated(db, day(3)), 1)
  const live = ps5Of(db, 'dawnwalker@1.3')!
  assert.deepEqual([live.status, live.verification], ['live', 'official'])
  assert.ok(live.alert)
  // A stated time long past (a backfill reading an old post) goes live without a fresh alert window.
  db.prepare("UPDATE platform_releases SET status = 'announced', pushed_at = NULL, alert_from = NULL WHERE release_id = 'dawnwalker@1.3' AND platform = 'ps5'").run()
  assert.equal(store.promoteStated(db, day(30)), 1)
  assert.equal(ps5Of(db, 'dawnwalker@1.3')!.alert?.from, held.liveAt?.value) // the old time, so the 72 h guard keeps it quiet
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

test('backfill drops the mislabelled release the same post made before (10.2 -> 10.2.2a)', async () => {
  const { db, deps } = await setup([{ gid: '1', title: '10.2.2a Backend Bugfix Patch', date: ago(10), contents: 'Fixed a backend bug. Live on PC.', tags: ['patchnotes'] }])
  const pc = store.getRelease(db, 'dawnwalker@10.2.2a')!
  // The old rules stored it as 10.2 and remembered that on the post: a copy of the release under the old key.
  const row = db.prepare("SELECT * FROM releases WHERE id = 'dawnwalker@10.2.2a'").get() as Record<string, any>
  db.prepare('INSERT INTO releases (' + Object.keys(row).join(',') + ') VALUES (' + Object.keys(row).map(() => '?').join(',') + ')').run(...Object.values({ ...row, id: 'dawnwalker@10.2', version_key: '10.2', display_name: 'Patch 10.2' }))
  db.prepare("UPDATE seen_posts SET release_id = 'dawnwalker@10.2'").run()
  assert.ok(pc)
  await runIngest(deps, { force: true, until: new Date(Date.now() - 90 * 86400e3).toISOString() })
  assert.ok(!store.getRelease(db, 'dawnwalker@10.2'))
  assert.equal(store.getRelease(db, 'dawnwalker@10.2.2a')?.displayName, 'Patch 10.2.2a')
})

test('backfill also repairs derived (auto-onboarded) games, which the slice never re-reads', async () => {
  const db = openDb(':memory:')
  const when = day(2)
  const fetchFn = fakeFetch({
    'https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=111': steamNews([
      { gid: 'a1', title: 'Patch 1.3', date: ago(20), contents: `At 02:00 UTC+0 on ${monthDay(when)}, the updates for Xbox Series X|S and PlayStation 5 will be available.`, tags: ['patchnotes'] },
      { gid: 'a2', title: 'Developer diary', date: ago(19), contents: 'No patch here.' },
    ]),
  })
  const deps = { db, fetchFn, igdb: null }
  await seedGames(deps)
  seedAutoGames(db, [{ id: 'alpha-1', steamAppId: 111, name: 'alpha-1', igdbId: 1, ps5TitleIds: [], ps5Release: '2024-01-01', sources: [{ id: 'auto-111-steam', kind: 'steamNews', url: 'https://store.steampowered.com/feeds/news/app/111/', platforms: ['pc'], trust: 'official', fetch: 'auto', ps5Signal: 'explicit' }] }])
  await runIngest(deps, { autoSlice: 1 })
  const at = store.getRelease(db, 'alpha-1@1.3')!.platforms.find((p) => p.platform === 'pc')!.liveAt!
  // The old rules: live on PS5 at the post's own time.
  db.prepare("DELETE FROM platform_releases WHERE release_id = 'alpha-1@1.3' AND platform = 'ps5'").run()
  store.upsertPlatform(db, 'alpha-1@1.3', 'ps5', { status: 'live', verification: 'official', liveAt: store.field(at.value, 'official', at.sourceId) })
  assert.equal(ps5Of(db, 'alpha-1@1.3')!.status, 'live')
  const s = await runIngest(deps, { force: true, until: new Date(Date.now() - 90 * 86400e3).toISOString() })
  assert.deepEqual([ps5Of(db, 'alpha-1@1.3')!.status, ps5Of(db, 'alpha-1@1.3')!.verification], ['announced', 'official'])
  assert.ok(s.polled.includes('steam-111'))
  assert.equal(store.newsOf(db, 'alpha-1').length, 0)
})

test('backfill removes the release an announcement headline made before, and a stated live row survives later runs', async () => {
  const date = new Date(Math.floor((Date.now() - 100 * 3600e3) / 1000) * 1000).toISOString()
  const { db, deps } = await setup([
    { gid: '1', title: 'Title Update coming this week!', date, contents: 'Fixes and new content, now on PC and PS5.', tags: ['patchnotes'] },
    { gid: '2', title: 'Patch 1.3', date: ago(20), contents: `At 02:00 UTC+0 on ${monthDay(day(2))}, the updates for Xbox Series X|S and PlayStation 5 will be available.`, tags: ['patchnotes'] },
  ])
  const at = date
  // The old rules: an announcement made a release with an assumed live PS5 row.
  const id = store.upsertRelease(db, { gameId: 'dawnwalker', versionKey: 'major-announce', displayName: 'Title Update coming this week!', kind: 'major', kindBasis: 'inferred', announcedAt: at, notes: [], sourceId: 'dawnwalker-steam' }).id
  store.upsertPlatform(db, id, 'ps5', { status: 'live', verification: 'assumed', liveAt: store.field(at, 'assumed', 'dawnwalker-steam') })
  db.prepare("UPDATE seen_posts SET release_id = ? WHERE post_id = '1'").run(id)
  await runIngest(deps, { force: true, until: new Date(Date.now() - 90 * 86400e3).toISOString() })
  assert.ok(!store.getRelease(db, id))
  // A stated time that passed keeps its own time: no pass moves it back to the post.
  const held = ps5Of(db, 'dawnwalker@1.3')!.liveAt!.value
  assert.equal(store.promoteStated(db, day(3)), 1)
  await runIngest(deps, { force: true })
  assert.equal(ps5Of(db, 'dawnwalker@1.3')!.liveAt!.value, held)
})

test('alert age: a promoted row whose own live date is old keeps no fresh alert window (feed and push)', async () => {
  const { alertFromOf } = await import('../src/alerts.ts')
  const now = Date.parse('2026-11-12T17:05:00.000Z')
  const live = (v: string) => JSON.stringify({ value: v })
  // Years-old patch promoted today: the alert counts from its own date, so the 72 h guard stops it.
  assert.equal(alertFromOf({ alert_from: '2026-11-12T17:05:01.005Z', live_at: live('2025-06-11T22:50:42.000Z') }, now), '2025-06-11T22:50:42.000Z')
  // A console-later update a few days after its Steam post still counts from the moment it went live on PS5.
  assert.equal(alertFromOf({ alert_from: '2026-11-12T17:05:01.005Z', live_at: live('2026-11-02T10:00:00.000Z') }, now), '2026-11-12T17:05:01.005Z')
  assert.equal(alertFromOf({ alert_from: null, live_at: live('2026-11-12T10:00:00.000Z') }, now), '2026-11-12T10:00:00.000Z')
})

test('backfill applies a post\'s stated time even when a second post of the same day wrote the assumed row (DDV Season of Scares)', async () => {
  const when = day(2)
  const first = ago(30), second = new Date(Math.floor(Date.parse(first) / 1000) * 1000 + 36e3).toISOString()
  const { db, deps } = await setup([
    { gid: '1', title: 'Season of Scares Update Patch Notes', date: first, contents: `Our Season of Scares free update arrives on ${monthDay(when)}, 2026. Details below.`, tags: ['patchnotes'] },
    { gid: '2', title: 'Season of Scares Update Patch Notes', date: second, contents: 'Hotfix notes. More details soon.', tags: ['patchnotes'] },
  ])
  const id = [...(db.prepare('SELECT DISTINCT release_id AS id FROM seen_posts WHERE release_id IS NOT NULL').all() as { id: string }[])][0]!.id
  // Read forward, the later plain post does not release the row the first one held.
  assert.equal(ps5Of(db, id)!.status, 'announced')
  // The old rules: the second post wrote the assumed live row, at its own time.
  db.prepare("DELETE FROM platform_releases WHERE release_id = ? AND platform = 'ps5'").run(id)
  store.upsertPlatform(db, id, 'ps5', { status: 'live', verification: 'assumed', liveAt: store.field(second, 'assumed', 'dawnwalker-steam') })
  await runIngest(deps, { force: true, until: new Date(Date.now() - 90 * 86400e3).toISOString() })
  const row = ps5Of(db, id)!
  assert.deepEqual([row.status, row.liveAt?.value.slice(0, 10)], ['announced', when.toISOString().slice(0, 10)])
})
