// Roadmap 11: faster alerts for a small hot set. Follows live on devices, so the server cannot know which games
// are followed; the hot set is the games that just had a patch (a follow-up hotfix is most likely there) plus a pinned list.
import { readFileSync } from 'node:fs'
import type { DB } from './db.ts'

export const HOT_WINDOW_DAYS = 14
export const HOT_MAX = 12
/** r060-dayone-patch-watch: a game whose exact PS5 day is from 2 days before to 7 days after `at` is launching, so its
 *  day-one patch (ps5-patch-data.md: published within a day of the platform release) is caught at the hot cadence. */
export const LAUNCH_BEFORE_DAYS = 2
export const LAUNCH_AFTER_DAYS = 7
/** A hot source may be polled again after this long; every other source keeps the hourly rule. */
export const HOT_POLL_MS = 25 * 60_000

const pinned = JSON.parse(readFileSync(new URL('./sources/hot-pinned.json', import.meta.url), 'utf8')) as { games: string[] }

const day = (at: Date, offsetDays: number) => new Date(at.getTime() + offsetDays * 86400e3).toISOString().slice(0, 10)

/** Games in their launch window (exact PS5 day only; a month, quarter, year or tbd date is not a launch), soonest first.
 *  Only games with a source to poll count: registry games, and derived games with a Steam app. */
export const launchingGameIds = (db: DB, at = new Date()): string[] =>
  (db.prepare(`SELECT id FROM games WHERE ps5_release BETWEEN ? AND ? AND ps5_release_precision IS NULL AND auto <> 2
      AND (auto = 0 OR steam_app_id IS NOT NULL) ORDER BY ps5_release, id`).all(day(at, -LAUNCH_AFTER_DAYS), day(at, LAUNCH_BEFORE_DAYS)) as { id: string }[]).map((r) => r.id)

/** Pinned games first, then launching games, then the games with the newest patches in the last 14 days, up to HOT_MAX. */
export const hotGameIds = (db: DB, at = new Date(), pin: string[] = pinned.games): Set<string> => {
  const since = new Date(at.getTime() - HOT_WINDOW_DAYS * 86400e3).toISOString()
  const recent = (db.prepare('SELECT game_id FROM releases WHERE announced_at >= ? GROUP BY game_id ORDER BY MAX(announced_at) DESC').all(since) as { game_id: string }[]).map((r) => r.game_id)
  return new Set([...pin, ...launchingGameIds(db, at), ...recent].slice(0, HOT_MAX))
}
