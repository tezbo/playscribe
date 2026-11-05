import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { allowedByRobots, getJson, getText, type FetchFn } from './http.ts'
import { parseFeed, looksLikePatch } from './ingest/adapters.ts'
import { toLines } from './ingest/notes.ts'
import { matchesGame } from './ingest/pipeline.ts'
import { registry, steamAppIdOf } from './registry.ts'

// News, as opposed to patch notes: what a studio or the press says about a game that is not an update.
//   v1/news.json           the newest items across every game, plus wider PS5 news that names none of ours (gameId null)
//   v1/news/<gameId>.json  one registry game's newest items
// Studio posts (Steam announcements that are not patches) carry a short excerpt and are `official`.
// Press items are headline, link and date only, never article text, and are `reported`.
// A source that fails keeps its previous items (read back from the files already in the output folder).
export interface NewsItem {
  id: string
  gameId: string | null
  title: string
  publishedAt: string
  /** Studio posts only: the opening of the post as plain text. */
  excerpt?: string
  url: string
  kind: 'official' | 'reported'
}

const PRESS_FEED = 'https://www.pushsquare.com/feeds/latest'
const PER_GAME = 20
const GLOBAL = 200

interface SteamNews {
  appnews: { newsitems: { gid: string; title: string; url: string; date: number; contents: string; tags?: string[]; is_external_url?: boolean; feed_type?: number }[] }
}

export const excerptOf = (body: string, max = 220) => {
  const lines = toLines(body).filter((l) => !l.startsWith('§') && !/^https?:\/\//.test(l) && !/^\{STEAM_CLAN_IMAGE\}/.test(l))
  const text = lines.map((l) => l.replace(/^(## |- )/, '')).join(' ').replace(/\s+/g, ' ').trim()
  if (text.length <= max) return text
  const cut = text.slice(0, max)
  return cut.slice(0, Math.max(cut.lastIndexOf(' '), 60)).replace(/[\s,;:.\-–]+$/, '') + '…'
}

const steamItems = async (fetchFn: FetchFn, gameId: string): Promise<NewsItem[]> => {
  const src = registry.games[gameId]!.sources.find((s) => s.kind === 'steamNews')
  const appid = src && steamAppIdOf(src)
  if (!appid) return []
  const d = await getJson<SteamNews>(fetchFn, `https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=${appid}&count=40&maxlength=0&feeds=steam_community_announcements`)
  return d.appnews.newsitems
    .filter((n) => !n.is_external_url && !n.tags?.includes('patchnotes') && !looksLikePatch(n.title))
    .map((n) => ({
      id: `${gameId}:${n.gid}`,
      gameId,
      title: n.title.trim(),
      publishedAt: new Date(n.date * 1000).toISOString(),
      excerpt: excerptOf(n.contents) || undefined,
      url: `https://store.steampowered.com/news/app/${appid}/view/${n.gid}`,
      kind: 'official' as const,
    }))
}

const pressItems = async (fetchFn: FetchFn): Promise<NewsItem[]> => {
  if (!(await allowedByRobots(fetchFn, PRESS_FEED))) throw new Error('press feed disallowed by robots.txt')
  const posts = parseFeed('press', await getText(fetchFn, PRESS_FEED)).filter((p) => p.title && /^https:\/\//.test(p.url))
  return posts.map((p) => {
    const owner = Object.entries(registry.games).find(([, g]) => matchesGame(g.name, p.title, { aliases: g.aliases, exclude: g.exclude }))?.[0]
    return { id: `press:${p.postId}`, gameId: owner ?? null, title: p.title.trim(), publishedAt: p.publishedAt, url: p.url, kind: 'reported' as const }
  })
}

const readItems = (path: string): NewsItem[] => {
  try {
    return existsSync(path) ? ((JSON.parse(readFileSync(path, 'utf8')) as { items: NewsItem[] }).items ?? []) : []
  } catch {
    return []
  }
}

const newest = (items: NewsItem[], n: number) => {
  const seen = new Set<string>()
  return items
    .filter((i) => !seen.has(i.id) && !!seen.add(i.id))
    .sort((a, b) => (a.publishedAt < b.publishedAt ? 1 : a.publishedAt > b.publishedAt ? -1 : a.id < b.id ? -1 : 1))
    .slice(0, n)
}

/** Fetches news for every registry game and writes the files; returns what it wrote and what failed. */
export const exportNews = async (fetchFn: FetchFn, outDir: string, log: (m: string) => void = () => {}) => {
  const root = join(outDir, 'v1')
  const dir = join(root, 'news')
  const previous = new Map<string, NewsItem[]>()
  const ids = Object.keys(registry.games)
  for (const id of ids) previous.set(id, readItems(join(dir, `${id}.json`)))
  const prevGlobal = readItems(join(root, 'news.json'))

  const errors: string[] = []
  const perGame = new Map<string, NewsItem[]>()
  for (const id of ids) {
    try {
      perGame.set(id, await steamItems(fetchFn, id))
    } catch (e) {
      errors.push(`${id}: ${(e as Error).message}`)
      perGame.set(id, previous.get(id) ?? [])
    }
  }
  let press: NewsItem[]
  try {
    press = await pressItems(fetchFn)
  } catch (e) {
    errors.push(`press: ${(e as Error).message}`)
    press = prevGlobal.filter((i) => i.kind === 'reported')
  }
  for (const i of press) if (i.gameId) perGame.set(i.gameId, [...(perGame.get(i.gameId) ?? []), i])

  rmSync(dir, { recursive: true, force: true })
  mkdirSync(dir, { recursive: true })
  const all: NewsItem[] = []
  for (const id of ids) {
    // Keep what was already published for the game, so an item that scrolled off a source's page stays until newer ones push it out.
    const items = newest([...(perGame.get(id) ?? []), ...(previous.get(id) ?? [])], PER_GAME)
    all.push(...items)
    writeFileSync(join(dir, `${id}.json`), JSON.stringify({ items }, null, 1) + '\n')
  }
  all.push(...press.filter((i) => !i.gameId), ...prevGlobal.filter((i) => i.kind === 'reported' && !i.gameId))
  const global = newest(all, GLOBAL)
  // updatedAt is the newest item, not the run time, so quiet runs leave the file untouched.
  writeFileSync(join(root, 'news.json'), JSON.stringify({ updatedAt: global[0]?.publishedAt ?? null, items: global }, null, 1) + '\n')
  for (const e of errors) log(`::warning::news ${e}`)
  return { items: global.length, errors }
}
