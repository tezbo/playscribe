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
  /** So the game page is never blank: IGDB's description (cut to 300 characters at a word), genres and a trailer (YouTube id). */
  summary?: string
  genres?: string[]
  trailerId?: string
  /** IGDB's hype count: how many people are waiting for it. A sort key for "Coming to PS5", not shown. */
  hypes?: number
  /** Present for 14 days after the date moved: what it was, when we saw it move, and which way. */
  move?: DateMove
}

export interface DateMove {
  kind: 'delayed' | 'earlier' | 'dated'
  previousDate?: string
  previousPrecision: DatePrecision
  movedAt: string
}

export const SHARDS = 10
export const shardOf = (igdbId: number) => igdbId % SHARDS

/** Released: an exact day that has come. Dated: an exact day ahead. Announced: only a vague date, or none (tbd). */
export const statusOf = (date: string | undefined, precision: DatePrecision, today: string): UpcomingStatus =>
  precision !== 'day' || !date ? 'announced' : date <= today ? 'released' : 'dated'

export interface Extras {
  summary?: string
  genres?: string[]
  videos?: { video_id: string; name?: string }[]
  hypes?: number
}

const SUMMARY_MAX = 300
/** First 300 characters, ending on a whole word with an ellipsis. */
export const shorten = (text: string) => {
  const t = text.replace(/\s+/g, ' ').trim()
  if (t.length <= SUMMARY_MAX) return t
  const cut = t.slice(0, SUMMARY_MAX)
  return `${cut.slice(0, Math.max(cut.lastIndexOf(' '), 0)).replace(/[,;:.\s]+$/, '')}…`
}

/** The trailer: a video named like a trailer, else the first one. */
export const trailerOf = (videos: Extras['videos']): string | undefined =>
  (videos?.find((v) => /\btrailer\b/i.test(v.name ?? '')) ?? videos?.[0])?.video_id

export const upcomingOf = (
  g: { igdbId: number; name: string; d?: string; q?: Precision; coverId?: string } & Extras,
  today: string,
): UpcomingGame | null => {
  const datePrecision: DatePrecision = g.q ?? 'day'
  if (!g.d && datePrecision !== 'tbd') return null
  // A vague date that has already passed (e.g. Q1 of this year) is no longer upcoming; so is an old exact release.
  if (g.d && g.d < today && !(datePrecision === 'day' && daysBetween(g.d, today) <= RECENT_DAYS)) return null
  return { igdbId: g.igdbId, name: g.name, ...(g.d ? { date: g.d } : {}), datePrecision, status: statusOf(g.d, datePrecision, today), ...(g.coverId ? { coverId: g.coverId } : {}),
    ...(g.summary ? { summary: shorten(g.summary) } : {}),
    ...(g.genres?.length ? { genres: g.genres.slice(0, 3) } : {}),
    ...(trailerOf(g.videos) ? { trailerId: trailerOf(g.videos)! } : {}),
    ...(g.hypes ? { hypes: g.hypes } : {}),
  }
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

/** How long a "date moved" note stays on a game. */
export const MOVE_DAYS = 14

/**
 * Compares today's date for a game with the last run's and names a real move, or null. Precision-only changes that keep
 * the same period, or that narrow a vague date, are not moves ("Q4" to "December"). Exact to later, or exact to vague, is delayed; exact to earlier is
 * earlier; a vague or tbd date that becomes an exact day is "dated". A move found earlier stays for 14 days.
 */
export const moveOf = (cur: UpcomingGame, prev: UpcomingGame | undefined, today: string): DateMove | undefined => {
  if (prev?.move && daysBetween(prev.move.movedAt, today) < MOVE_DAYS && !prevDiffers(cur, prev)) return prev.move
  if (!prev || !prevDiffers(cur, prev)) return undefined
  const was = prev.datePrecision
  const now = cur.datePrecision
  let kind: DateMove['kind'] | null = null
  if (was === 'day' && now === 'day') kind = cur.date! > prev.date! ? 'delayed' : 'earlier'
  else if (was === 'day') kind = 'delayed'
  else if (now === 'day') kind = 'dated'
  else if (was === 'tbd' && now !== 'tbd') kind = 'dated'
  else if (now === 'tbd') kind = 'delayed'
  // Vague to vague: only a later period is a move. A narrower one ("Q4" to "November") is the date firming up, not news.
  else if (cur.date && prev.date && cur.date > prev.date) kind = 'delayed'
  return kind ? { kind, ...(prev.date ? { previousDate: prev.date } : {}), previousPrecision: was, movedAt: today } : undefined
}

const prevDiffers = (cur: UpcomingGame, prev: UpcomingGame) => cur.date !== prev.date || cur.datePrecision !== prev.datePrecision

/** Adds `move` to each game that moved since the previous run. */
export const withMoves = (games: UpcomingGame[], previous: UpcomingGame[], today: string): UpcomingGame[] => {
  const before = new Map(previous.map((g) => [g.igdbId, g]))
  return games.map((g) => {
    const move = moveOf(g, before.get(g.igdbId), today)
    return move ? { ...g, move } : g
  })
}
