// Roadmap 14: the upcoming-games shard for the watchlist. Pure rules; scripts/upcoming.ts feeds them from IGDB.
// No invented dates: a vague IGDB date stays vague (month, quarter, year, tbd) and is never turned into a day.
import type { Precision } from './ps5-dates.ts'

export type UpcomingStatus = 'announced' | 'dated' | 'released'
export type DatePrecision = 'day' | Precision

export interface UpcomingGame {
  igdbId: number
  name: string
  /** YYYY-MM-DD. For month/quarter/year this is the last day of the period, as in the PS5 index; absent for tbd. */
  date?: string
  datePrecision: DatePrecision
  status: UpcomingStatus
  coverId?: string
}

export const SHARDS = 10
export const shardOf = (igdbId: number) => igdbId % SHARDS

/** Released: an exact day that has come. Dated: an exact day ahead. Announced: only a vague date, or none (tbd). */
export const statusOf = (date: string | undefined, precision: DatePrecision, today: string): UpcomingStatus =>
  precision !== 'day' || !date ? 'announced' : date <= today ? 'released' : 'dated'

export const upcomingOf = (
  g: { igdbId: number; name: string; d?: string; q?: Precision; coverId?: string },
  today: string,
): UpcomingGame | null => {
  const datePrecision: DatePrecision = g.q ?? 'day'
  if (!g.d && datePrecision !== 'tbd') return null
  // A vague date that has already passed (e.g. Q1 of this year) is no longer upcoming; so is an old exact release.
  if (g.d && g.d < today && !(datePrecision === 'day' && daysBetween(g.d, today) <= RECENT_DAYS)) return null
  return { igdbId: g.igdbId, name: g.name, ...(g.d ? { date: g.d } : {}), datePrecision, status: statusOf(g.d, datePrecision, today), ...(g.coverId ? { coverId: g.coverId } : {}) }
}

/** A game released in the last few days stays in the shard, so a follower who was offline still gets its release-day alert. */
export const RECENT_DAYS = 3
const daysBetween = (a: string, b: string) => Math.round((Date.parse(b) - Date.parse(a)) / 86400e3)

/** The release-day event: exact-day releases that came in the last 72 h. The app alerts once per game for a followed one. */
export const releaseDayEvents = (games: UpcomingGame[], today: string) =>
  games.filter((g) => g.status === 'released' && g.date && daysBetween(g.date, today) <= RECENT_DAYS).map((g) => ({ igdbId: g.igdbId, name: g.name, date: g.date! }))

export const shardsOf = (games: UpcomingGame[]) => {
  const shards: Record<string, UpcomingGame>[] = Array.from({ length: SHARDS }, () => ({}))
  for (const g of games) shards[shardOf(g.igdbId)]![g.igdbId] = g
  return shards
}
