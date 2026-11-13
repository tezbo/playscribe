import assert from 'node:assert/strict'
import { test } from 'node:test'
import { openDb } from '../src/db.ts'
import { seedAutoGames, type AutoGame } from '../src/ingest/autoRegistry.ts'
import { runIngest, seedGames } from '../src/ingest/pipeline.ts'
import * as store from '../src/store.ts'
import { fakeFetch, steamNews } from './helpers.ts'

// feed-log-lines-to-step (B1, 0.5.5): the ingest counts reach the Actions job log every run, zeros included, so Quinn can
// check dropped against kept and #466's held rows show.

const day = (n: number) => new Date(Date.now() + n * 86400e3)
const ago = (h: number) => new Date(Date.now() - h * 3600e3).toISOString()
const monthDay = (d: Date) => `${d.toLocaleString('en-US', { month: 'long', timeZone: 'UTC' })} ${d.getUTCDate()}`
const DAWN = 'https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=3751260'

const auto = (id: string, app: number): AutoGame => ({
  id, steamAppId: app, name: id, igdbId: app, ps5TitleIds: [], ps5Release: '2023-01-01',
  sources: [{ id: `auto-${app}-steam`, kind: 'steamNews', url: `https://store.steampowered.com/feeds/news/app/${app}/`, platforms: ['pc'], trust: 'official', fetch: 'auto', ps5Signal: 'explicit' }],
})

const summaryLines = (lines: string[]) => lines.filter((l) => /^ingest: (claims withheld|held rows|backfill|derived games|promoted|polled)/.test(l))

test('every poll prints the count lines: claims withheld, held rows, backfill dropped and kept, derived games read, promotions', async () => {
  const db = openDb(':memory:')
  const lines: string[] = []
  const deps = {
    db,
    log: (m: string) => void lines.push(m),
    igdb: null,
    fetchFn: fakeFetch({
      [DAWN]: steamNews([
        { gid: '1', title: '10.3.0 | Terrifier PTB Patch Notes', date: ago(30), contents: 'Public test build. Fixed a crash.', tags: ['patchnotes'] },
        { gid: '2', title: 'Patch 1.3', date: ago(20), contents: `At 02:00 UTC+0 on ${monthDay(day(2))}, the updates for Xbox Series X|S and PlayStation 5 will be available.`, tags: ['patchnotes'] },
        { gid: '3', title: 'Patch 1.4', date: ago(9 * 24), contents: 'Patch 1.4 is live on PC. Console versions will follow after certification.', tags: ['patchnotes'] },
      ]),
      'https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=900010': steamNews([{ gid: 'a', title: 'Patch 2.0', date: ago(5), contents: 'Patch 2.0 is live.[list][*]Fixed a crash[/list]', tags: ['patchnotes'] }]),
    }),
  }
  await seedGames(deps)
  seedAutoGames(db, [auto('alpha-900010', 900010)])
  await runIngest(deps, { autoSlice: 1 })
  assert.deepEqual(summaryLines(lines), [
    'ingest: claims withheld: 1 held to a stated time, 1 test builds, 0 PC-scoped, 0 announcements',
    'ingest: held rows: 1 PS5 rows announced until a stated time',
    'ingest: backfill: dropped 0, kept 0',
    'ingest: derived games read: 1',
    'ingest: promoted 1 console-later Steam updates to live',
    lines.find((l) => l.startsWith('ingest: polled'))!,
  ])
})

test('a backfill prints how many releases it dropped and kept', async () => {
  const db = openDb(':memory:')
  const lines: string[] = []
  const date = new Date(Math.floor((Date.now() - 100 * 3600e3) / 1000) * 1000).toISOString()
  const deps = {
    db,
    log: (m: string) => void lines.push(m),
    igdb: null,
    fetchFn: fakeFetch({ [DAWN]: steamNews([{ gid: '1', title: 'Title Update coming this week!', date, contents: 'Fixes and new content, now on PC and PS5.', tags: ['patchnotes'] }]) }),
  }
  await seedGames(deps)
  await runIngest(deps)
  // The old rules: an announcement made a release with an assumed live PS5 row.
  const id = store.upsertRelease(db, { gameId: 'dawnwalker', versionKey: 'major-announce', displayName: 'Title Update coming this week!', kind: 'major', kindBasis: 'inferred', announcedAt: date, notes: [], sourceId: 'dawnwalker-steam' }).id
  store.upsertPlatform(db, id, 'ps5', { status: 'live', verification: 'assumed', liveAt: store.field(date, 'assumed', 'dawnwalker-steam') })
  db.prepare("UPDATE seen_posts SET release_id = ? WHERE post_id = '1'").run(id)
  lines.length = 0
  await runIngest(deps, { force: true, until: new Date(Date.now() - 90 * 86400e3).toISOString() })
  assert.ok(lines.includes('ingest: backfill: dropped 1, kept 0'), summaryLines(lines).join('\n'))
})
