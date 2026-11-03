// Writes the basics every game page starts from, so no game opens to a blank page (Terry,
// 2026-10-26): IGDB's description and storyline, genres, first release, and its videos with the
// launch trailer first. One file per shard, v1/info/<igdbId % 100>.json on the feed branch, covering
// every game in the bundled PS5 catalogue (same selection as scripts/ps5-index.ts).
//
//   TWITCH_CLIENT_ID=… TWITCH_CLIENT_SECRET=… npm run game-info -- <outDir>
import { mkdirSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { Igdb } from '../src/ingest/igdb.ts'
import { similarOf, type SimilarGame } from '../src/similar.ts'
import { registry, steamAppIdOf } from '../src/registry.ts'

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
  /** The game's official website, and the page its patch notes are posted on. Opened in the browser. */
  links?: { official?: string; patchNotes?: string }
  /** IGDB similar_games, at most 8, for the "Similar games" row. */
  similar?: SimilarGame[]
}

// Patch notes page: the registry's official PS5 news page (a web page, not a feed), else the game's Steam news.
const steamNews = (id: number) => `https://store.steampowered.com/news/app/${id}`
const registryNotes = new Map<number, string | null>()
for (const g of Object.values(registry.games)) {
  if (!g.igdbId) continue
  const page = g.sources.find((s) => s.trust === 'official' && s.kind === 'html' && s.platforms.includes('ps5'))
  const steam = g.sources.map(steamAppIdOf).find((x) => x)
  const url = page?.url ?? (steam && !g.steamIsPcPort ? steamNews(steam) : undefined)
  // A PC port's Steam news says nothing about PS5, so it gets no Steam fallback.
  if (url || g.steamIsPcPort) registryNotes.set(g.igdbId, url ?? null)
}
const linksOf = (g: any): GameInfo['links'] => {
  const sites: { url: string; type?: number; category?: number }[] = g.websites ?? []
  const official = sites.find((w) => (w.type ?? w.category) === 1)?.url
  const steamId = sites.map((w) => w.url?.match(/store\.steampowered\.com\/app\/(\d+)/)?.[1]).find((x) => x)
  const patchNotes = registryNotes.has(g.id) ? registryNotes.get(g.id) ?? undefined : steamId ? steamNews(Number(steamId)) : undefined
  return official || patchNotes ? { official, patchNotes } : undefined
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
    'fields summary,storyline,genres.name,first_release_date,videos.video_id,videos.name,websites.url,websites.type,similar_games.name,similar_games.cover.image_id;' +
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
      links: linksOf(g),
      similar: similarOf(g.similar_games, g.id),
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
