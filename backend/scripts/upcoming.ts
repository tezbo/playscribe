// Upcoming PS5 games for the watchlist (roadmap 14): v1/upcoming/<igdbId % 10>.json plus v1/upcoming/events.json
// (release-day events), on the feed branch. Dates come from IGDB's PS5 release_dates only; see src/upcoming.ts.
//
//   TWITCH_CLIENT_ID=… TWITCH_CLIENT_SECRET=… npm run upcoming -- <outDir>
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { Igdb } from '../src/ingest/igdb.ts'
import { ps5DatesOf, type Override, type ReleaseDate } from '../src/ps5-dates.ts'
import { releaseDayEvents, shardsOf, upcomingOf, withMoves, SHARDS, type UpcomingGame } from '../src/upcoming.ts'

const { TWITCH_CLIENT_ID, TWITCH_CLIENT_SECRET } = process.env
const outDir = process.argv[2]
if (!TWITCH_CLIENT_ID || !TWITCH_CLIENT_SECRET || !outDir) {
  console.error('Usage: TWITCH_CLIENT_ID=… TWITCH_CLIENT_SECRET=… npm run upcoming -- <outDir>. Nothing written.')
  process.exit(1)
}
const igdb = new Igdb(TWITCH_CLIENT_ID, TWITCH_CLIENT_SECRET)
const today = new Date().toISOString().slice(0, 10)
const since = Math.floor(Date.now() / 1000) - 5 * 86400

const [ps5] = await igdb.query<{ id: number }>('platforms', 'fields id; where slug = "ps5"; limit 1;')
const [ps4] = await igdb.query<{ id: number }>('platforms', 'fields id; where slug = "ps4--1"; limit 1;')
const statuses = await igdb.query<{ id: number; name: string }>('release_date_statuses', 'fields id,name; limit 50;')
const formats = await igdb.query<{ id: number; format: string }>('date_formats', 'fields id,format; limit 50;')
const types = await igdb.query<{ id: number; type: string }>('game_types', 'fields id,type; limit 50;')
const typeIds = types.filter((t) => ['Main Game', 'Remake', 'Remaster', 'Expanded Game', 'Port'].includes(t.type)).map((t) => t.id)
if (!ps5 || !ps4 || !typeIds.length) throw new Error('PS5 platform or game types not found')
const statusName = new Map(statuses.map((s) => [s.id, s.name]))
const formatName = new Map(formats.map((f) => [f.id, f.format]))
const overrides = JSON.parse(readFileSync(new URL('./ps5-date-overrides.json', import.meta.url), 'utf8')) as Record<string, Override>

// A PS5 release row dated from a few days ago onwards, or a PS5 row with no date yet (tbd).
const games: UpcomingGame[] = []
for (const where of [`release_dates.platform = ${ps5.id} & release_dates.date > ${since}`, `release_dates.platform = ${ps5.id} & release_dates.date = null`]) {
  for (let offset = 0; ; offset += 500) {
    const page = await igdb.query<any>(
      'games',
      'fields name,cover.image_id,summary,genres.name,videos.video_id,videos.name,hypes,release_dates.date,release_dates.platform,release_dates.status,release_dates.date_format;' +
        `where ${where} & game_type = (${typeIds.join(',')}) & version_parent = null; sort id asc; limit 500; offset ${offset};`,
    )
    for (const g of page) {
      const dates = ps5DatesOf(g.release_dates as ReleaseDate[], { ps5: ps5.id, ps4: ps4.id }, (i) => statusName.get(i!), overrides[String(g.id)], (i) => formatName.get(i!))
      const u = upcomingOf({ igdbId: g.id, name: g.name, d: dates.d, q: dates.q, coverId: g.cover?.image_id }, today)
      if (u && !games.some((x) => x.igdbId === u.igdbId)) games.push(u)
    }
    if (page.length < 500) break
  }
}

const dir = join(outDir, 'v1', 'upcoming')
mkdirSync(dir, { recursive: true })
// The feed branch still holds the last run's shards: compare with them to find dates that moved.
const previous: UpcomingGame[] = []
for (let i = 0; i < SHARDS; i++) {
  try {
    previous.push(...Object.values(JSON.parse(readFileSync(join(dir, `${i}.json`), 'utf8')).games as Record<string, UpcomingGame>))
  } catch {}
}
games.splice(0, games.length, ...withMoves(games, previous, today))
shardsOf(games).forEach((g, i) => writeFileSync(join(dir, `${i}.json`), JSON.stringify({ games: g }) + '\n'))
writeFileSync(join(dir, 'events.json'), JSON.stringify({ today, releaseDay: releaseDayEvents(games, today) }) + '\n')
console.log(`wrote ${SHARDS} upcoming shards for ${games.length} games`)
