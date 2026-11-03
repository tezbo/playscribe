// Roadmap 11: faster alerts for a small hot set. Follows live on devices, so the server cannot know which games
// are followed; the hot set is the games that just had a patch (a follow-up hotfix is most likely there) plus a pinned list.
import { readFileSync } from 'node:fs'
import type { DB } from './db.ts'

export const HOT_WINDOW_DAYS = 14
export const HOT_MAX = 12
/** A hot source may be polled again after this long; every other source keeps the hourly rule. */
export const HOT_POLL_MS = 25 * 60_000

const pinned = JSON.parse(readFileSync(new URL('./sources/hot-pinned.json', import.meta.url), 'utf8')) as { games: string[] }

/** Pinned games first, then the games with the newest patches in the last 14 days, up to HOT_MAX. */
export const hotGameIds = (db: DB, at = new Date(), pin: string[] = pinned.games): Set<string> => {
  const since = new Date(at.getTime() - HOT_WINDOW_DAYS * 86400e3).toISOString()
  const recent = (db.prepare('SELECT game_id FROM releases WHERE announced_at >= ? GROUP BY game_id ORDER BY MAX(announced_at) DESC').all(since) as { game_id: string }[]).map((r) => r.game_id)
  return new Set([...pin, ...recent].slice(0, HOT_MAX))
}
