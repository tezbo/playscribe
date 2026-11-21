// Auto-onboarding (0.5.4, docs: design/auto-onboarding-0.5.4.md): derive a Steam news source for every PS5
// index game whose IGDB entry links a Steam store page. The hand registry always wins; nothing here is "official".
import { readdirSync, readFileSync } from 'node:fs'
import type { DB } from '../db.ts'
import { registry, steamAppIdOf, type RegistryGame, type SourceDef } from '../registry.ts'
import * as store from '../store.ts'

export interface IndexGame { i: number; n: string; d?: string | null; p?: string | null; v?: string | null; c?: string | null; a?: string | null }
export interface InfoEntry { links?: { official?: string; patchNotes?: string } }

export const steamAppIdFromUrl = (url: string | undefined) => url?.match(/store\.steampowered\.com\/(?:news\/)?app\/(\d+)/)?.[1]

/** Sony first-party games are separate PC ports on Steam: a Steam patch says nothing about PS5. */
export const looksLikeSonyPort = (g: IndexGame) => /\b(sony|playstation)\b/i.test(`${g.p ?? ''} ${g.v ?? ''}`)

/** Loose name key: case, punctuation and spacing folded, so "Astro Bot" and "ASTRO BOT™" are one game. */
export const nameKey = (n: string) => n.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/\b(the|a|an)\b/g, '').replace(/[^a-z0-9]+/g, '')

export const slugOf = (g: IndexGame) => `${g.n.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '')}-${g.i}`

export interface AutoGame extends RegistryGame { id: string; steamAppId: number; coverImageId?: string | null; artworkImageId?: string | null; ps5Release?: string | null }

export interface AutoResult {
  games: AutoGame[]
  skipped: { handRegistered: number; notReleased: number; noSteam: number; duplicateApp: number }
}

/** Pure: index + info shards + the hand registry's igdb ids -> the auto entries. `today` is an ISO date. */
export const buildAutoRegistry = (index: IndexGame[], info: Map<number, InfoEntry>, handIgdbIds: Set<number>, handAppIds: Set<number>, today: string, handNames: Set<string> = new Set()): AutoResult => {
  const skipped = { handRegistered: 0, notReleased: 0, noSteam: 0, duplicateApp: 0 }
  const seen = new Set<number>()
  const games: AutoGame[] = []
  for (const g of index) {
    // A hand game with no IGDB id and no Steam source (a link-only console exclusive) can only be matched by name.
    if (handIgdbIds.has(g.i) || handNames.has(nameKey(g.n))) { skipped.handRegistered++; continue }
    if (!g.d || g.d > today) { skipped.notReleased++; continue }
    const app = steamAppIdFromUrl(info.get(g.i)?.links?.patchNotes)
    if (!app) { skipped.noSteam++; continue }
    const appId = Number(app)
    if (handAppIds.has(appId) || seen.has(appId)) { skipped.duplicateApp++; continue }
    seen.add(appId)
    const source: SourceDef = { id: `auto-${appId}-steam`, kind: 'steamNews', url: `https://store.steampowered.com/feeds/news/app/${appId}/`, platforms: ['pc'], trust: 'official', fetch: 'auto', ps5Signal: 'explicit' }
    games.push({ id: slugOf(g), steamAppId: appId, name: g.n, igdbId: g.i, ps5TitleIds: [], coverImageId: g.c ?? null, artworkImageId: g.a ?? null, ps5Release: g.d ?? null, ...(looksLikeSonyPort(g) ? { steamIsPcPort: true } : {}), sources: [source] })
  }
  return { games, skipped }
}

export const INDEX_URL = new URL('../../../ios/Playscribe/Resources/Data/ps5-index.json', import.meta.url)

/** The index and the published info shards (out/v1/info) -> the auto entries, with the hand registry's ids and Steam apps excluded. */
export const deriveAutoRegistry = (infoDir: string, indexUrl: URL = INDEX_URL, today = new Date().toISOString().slice(0, 10)): AutoResult => {
  const index = (JSON.parse(readFileSync(indexUrl, 'utf8')) as { games: IndexGame[] }).games
  const info = new Map<number, InfoEntry>()
  let shards: string[] = []
  try { shards = readdirSync(infoDir).filter((f) => f.endsWith('.json')) } catch { shards = [] }
  for (const f of shards) for (const [id, e] of Object.entries(JSON.parse(readFileSync(`${infoDir}/${f}`, 'utf8')).games as Record<string, InfoEntry>)) info.set(Number(id), e)
  const hand = Object.values(registry.games)
  const handIgdb = new Set(hand.map((g) => g.igdbId).filter((x): x is number => !!x))
  const handApps = new Set(hand.flatMap((g) => g.sources.map(steamAppIdOf)).filter((x): x is number => !!x))
  const handNames = new Set(hand.flatMap((g) => [g.name, ...(g.aliases ?? [])]).map(nameKey))
  return buildAutoRegistry(index, info, handIgdb, handApps, today, handNames)
}

/** Writes the auto entries as game rows (auto = 1), from the index's own cover, key art and PS5 date: no IGDB call. */
export const seedAutoGames = (db: DB, games: AutoGame[]) => {
  let written = 0
  for (const g of games) {
    if (store.upsertAutoGame(db, { id: g.id, name: g.name, igdbId: g.igdbId, steamAppId: g.steamAppId, coverImageId: g.coverImageId, artworkImageId: g.artworkImageId, ps5Release: g.ps5Release, ps5ReleasePrecision: g.ps5Release ? 'day' : null, steamIsPcPort: g.steamIsPcPort })) written++
  }
  const retired = store.retireAutoGames(db, new Set(games.map((g) => g.id)))
  return { written, retired }
}
