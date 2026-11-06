// PS Plus monthly games card (r050-plus-card). Hand-curated: sources/plus.json is typed in once a month from Sony's public
// announcement (names and dates only, no copied text). Nothing is fetched automatically, because playstation.com's
// terms bar automated access (docs/ps5-patch-data.md, open check). Exported as v1/plus.json.
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

export interface PlusGame {
  name: string
  /** Id of a game the app tracks, when it is one. */
  gameId?: string
  /** IGDB image id of the game's cover, for titles the app's bundled PS5 index lacks. The app shows the name plate without it. */
  coverId?: string
}
export interface PlusMonth {
  /** YYYY-MM */
  month: string
  /** First day the lineup can be claimed, YYYY-MM-DD */
  from: string
  /** Last day it can be claimed (inclusive), YYYY-MM-DD */
  until: string
  games: PlusGame[]
}
export interface Plus {
  version: 1
  months: PlusMonth[]
}

const DAY = /^\d{4}-\d{2}-\d{2}$/
const MONTH = /^\d{4}-\d{2}$/

export const plusProblems = (raw: unknown, knownGameIds?: Set<string>): string[] => {
  const out: string[] = []
  const p = raw as Partial<Plus> | null
  if (!p || typeof p !== 'object' || !Array.isArray(p.months)) return ['plus.json needs a months array']
  const seen = new Set<string>()
  for (const [i, m] of p.months.entries()) {
    const at = `months[${i}]`
    if (!MONTH.test(m.month ?? '')) out.push(`${at}.month must be YYYY-MM`)
    if (seen.has(m.month)) out.push(`${at}.month ${m.month} repeats`)
    seen.add(m.month)
    if (!DAY.test(m.from ?? '') || !DAY.test(m.until ?? '') || Number.isNaN(Date.parse(m.from)) || Number.isNaN(Date.parse(m.until))) out.push(`${at}.from and until must be real YYYY-MM-DD dates`)
    else if (m.until < m.from) out.push(`${at}.until is before from`)
    if (!Array.isArray(m.games) || m.games.length === 0) out.push(`${at}.games must not be empty`)
    for (const [j, g] of (m.games ?? []).entries()) {
      if (!g.name?.trim() || g.name.length > 80) out.push(`${at}.games[${j}].name must be 1 to 80 characters`)
      if (g.gameId && knownGameIds && !knownGameIds.has(g.gameId)) out.push(`${at}.games[${j}].gameId ${g.gameId} is not a tracked game`)
      if (g.coverId !== undefined && !/^[a-z0-9]{4,40}$/.test(g.coverId)) out.push(`${at}.games[${j}].coverId must be an IGDB image id`)
      if (/https?:\/\//i.test(g.name ?? '')) out.push(`${at}.games[${j}].name must not be a link`)
    }
  }
  return out
}

/** The curated file, newest month first, or empty when nothing is typed in yet (the app then hides the card). */
export const loadPlus = (path = fileURLToPath(new URL('./sources/plus.json', import.meta.url)), knownGameIds?: Set<string>): Plus => {
  const raw = JSON.parse(readFileSync(path, 'utf8'))
  const problems = plusProblems(raw, knownGameIds)
  if (problems.length) throw new Error(`plus.json: ${problems.join('; ')}`)
  return { version: 1, months: [...raw.months].sort((a: PlusMonth, b: PlusMonth) => (a.month < b.month ? 1 : -1)) }
}
