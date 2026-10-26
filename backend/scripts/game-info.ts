// Writes the basics every game page starts from, so no game opens to a blank page (Terry,
// 2026-10-26): IGDB's description and storyline, genres, first release, and its videos with the
// launch trailer first. One file per shard, v1/info/<igdbId % 100>.json on the feed branch, covering
// every game in the bundled PS5 catalogue (same selection as scripts/ps5-index.ts).
//
//   TWITCH_CLIENT_ID=… TWITCH_CLIENT_SECRET=… npm run game-info -- <outDir>
import { mkdirSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { Igdb } from '../src/ingest/igdb.ts'

const { TWITCH_CLIENT_ID, TWITCH_CLIENT_SECRET } = process.env
const outDir = process.argv[2]
if (!TWITCH_CLIENT_ID || !TWITCH_CLIENT_SECRET || !outDir) {
  console.error('Usage: TWITCH_CLIENT_ID=… TWITCH_CLIENT_SECRET=… npm run game-info -- <outDir>. Nothing written.')
  process.exit(1)
}
const igdb = new Igdb(TWITCH_CLIENT_ID, TWITCH_CLIENT_SECRET)
const SHARDS = 100

export interface GameInfo {
  summary?: string
  storyline?: string
  genres?: string[]
  firstRelease?: string
  /** YouTube videos, launch trailer first, then other trailers, then the rest. */
  videos?: { youtubeId: string; name: string }[]
}

const videoRank = (name: string) => (/launch/i.test(name) ? 0 : /trailer/i.test(name) ? 1 : 2)

const [ps5] = await igdb.query<{ id: number }>('platforms', 'fields id; where slug = "ps5"; limit 1;')
const types = await igdb.query<{ id: number; type: string }>('game_types', 'fields id,type; limit 50;')
const typeIds = types.filter((t) => ['Main Game', 'Remake', 'Remaster', 'Expanded Game', 'Port'].includes(t.type)).map((t) => t.id)
if (!ps5 || !typeIds.length) throw new Error('PS5 platform or game types not found')

const shards: Record<string, GameInfo>[] = Array.from({ length: SHARDS }, () => ({}))
let n = 0
for (let offset = 0; ; offset += 500) {
  const page = await igdb.query<any>(
    'games',
    'fields summary,storyline,genres.name,first_release_date,videos.video_id,videos.name;' +
      `where platforms = (${ps5.id}) & game_type = (${typeIds.join(',')}) & version_parent = null; sort id asc; limit 500; offset ${offset};`,
  )
  for (const g of page) {
    const videos = (g.videos ?? [])
      .filter((v: any) => v.video_id)
      .map((v: any, i: number) => ({ youtubeId: v.video_id as string, name: (v.name as string) ?? 'Trailer', i }))
      .sort((a: any, b: any) => videoRank(a.name) - videoRank(b.name) || a.i - b.i)
      .slice(0, 6)
      .map(({ youtubeId, name }: any) => ({ youtubeId, name }))
    const info: GameInfo = {
      summary: g.summary || undefined,
      storyline: g.storyline || undefined,
      genres: g.genres?.map((x: any) => x.name),
      firstRelease: g.first_release_date ? new Date(g.first_release_date * 1000).toISOString().slice(0, 10) : undefined,
      videos: videos.length ? videos : undefined,
    }
    shards[g.id % SHARDS]![g.id] = JSON.parse(JSON.stringify(info))
    n++
  }
  if (page.length < 500) break
}

const dir = join(outDir, 'v1', 'info')
mkdirSync(dir, { recursive: true })
shards.forEach((games, i) => writeFileSync(join(dir, `${i}.json`), JSON.stringify({ games }) + '\n'))
console.log(`wrote ${SHARDS} info shards for ${n} games`)
