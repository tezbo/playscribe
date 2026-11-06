// Fills the PS Plus monthly lineup automatically from Push Square's "PS Plus Essential games for <month>" article.
// Allowed because its robots.txt permits article pages and its terms (read 2026-11-04) carry no bot clause; see
// docs/ps5-patch-data.md. Facts only: month, claim window and game names are kept, article text never is. The
// hand-curated plus.json overrides a month when both exist.
import type { DB } from './db.ts'
import { getText, type FetchFn } from './http.ts'
import { plusProblems, type PlusMonth } from './plus.ts'
import type { Igdb } from './ingest/igdb.ts'

const LIST_URL = 'https://www.pushsquare.com/tags/ps-plus'
const SITE = 'https://www.pushsquare.com/'
const MONTHS = ['january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october', 'november', 'december']
const pad = (n: number) => String(n).padStart(2, '0')
const monthNo = (name: string) => MONTHS.indexOf(name.toLowerCase()) + 1

/** Announcement links on the tag page, e.g. news/2026/10/ps-plus-essential-games-for-november-2026-announced. */
export const announcementLinks = (listHtml: string): string[] => {
  const hrefs = [...listHtml.matchAll(/href="([^"#]*news\/\d{4}\/\d{2}\/ps-plus-essential-games-for-[a-z]+-\d{4}-announced)"/g)].map((m) => new URL(m[1]!, SITE).toString())
  return [...new Set(hrefs)]
}

const text = (html: string) => html.replace(/<[^>]*>/g, ' ').replace(/&amp;/g, '&').replace(/&#0?39;|&rsquo;/g, "'").replace(/&nbsp;/g, ' ').replace(/\s+/g, ' ').trim()

/** The month's lineup from one announcement article, or null when it does not look like one. */
export const parsePlusEssential = (html: string): PlusMonth | null => {
  const head = /<h1[^>]*>(.*?)<\/h1>/is.exec(html)?.[1]
  const title = /PS Plus Essential Games for (\w+) (\d{4})/i.exec(text(head ?? ''))
  if (!title || !monthNo(title[1]!)) return null
  const month = `${title[2]}-${pad(monthNo(title[1]!))}`
  const body = /<div class="body body-text[^>]*>(.*?)<\/article>/is.exec(html)?.[1] ?? ''
  const prose = text(body.split(/<ul>/i)[0] + ' ' + (body.split(/<\/ul>/i)[1] ?? ''))
  // Wording varies month to month: "from Tuesday, 3rd November 2026", "starting Tuesday 6th October". The year may be missing.
  const lineupYear = Number(title[2])
  const start = /(?:from|starting)\s+(?:\w+day,?\s+)?(\d{1,2})(?:st|nd|rd|th)?\s+(\w+)(?:\s+(\d{4}))?/i.exec(prose)
  if (!start || !monthNo(start[2]!)) return null
  const startYear = Number(start[3] ?? lineupYear)
  const from = `${startYear}-${pad(monthNo(start[2]!))}-${pad(Number(start[1]))}`
  const list = /<\/p>\s*<ul>(.*?)<\/ul>/is.exec(body)?.[1] ?? ''
  const games = [...list.matchAll(/<li>\s*<a [^>]*>(.*?)<\/a>/gis)].map((m) => ({ name: text(m[1]!) })).filter((g) => g.name)
  // The window ends the day before the next lineup ("rotated out ... on 1st December"), on the stated last day ("running until
  // 2nd November"), or at the end of the month.
  const rotated = /rotated out[^.]*?\bon (\d{1,2})(?:st|nd|rd|th)? (\w+)/i.exec(prose)
  const until_ = /(?:running )?until (\d{1,2})(?:st|nd|rd|th)? (\w+)/i.exec(prose)
  const yearFor = (nm: number) => startYear + (nm < monthNo(start[2]!) ? 1 : 0)
  let until: string
  if (rotated && monthNo(rotated[2]!)) {
    const nm = monthNo(rotated[2]!)
    until = new Date(Date.UTC(yearFor(nm), nm - 1, Number(rotated[1]) - 1)).toISOString().slice(0, 10)
  } else if (until_ && monthNo(until_[2]!)) {
    const nm = monthNo(until_[2]!)
    until = `${yearFor(nm)}-${pad(nm)}-${pad(Number(until_[1]))}`
  } else {
    const [y, m] = month.split('-').map(Number) as [number, number]
    until = new Date(Date.UTC(y, m, 0)).toISOString().slice(0, 10)
  }
  const out: PlusMonth = { month, from, until, games }
  return plusProblems({ months: [out] }).length ? null : out
}

export const storedPlusMonths = (db: DB): PlusMonth[] =>
  (db.prepare('SELECT data FROM plus_months ORDER BY month DESC').all() as { data: string }[]).map((r) => JSON.parse(r.data) as PlusMonth)

/** Reads the newest announcements not stored yet. A failure is logged and leaves what is stored (and plus.json) in place. */
export const fetchPlus = async (db: DB, fetchFn: FetchFn, log: (m: string) => void = () => {}, max = 2): Promise<number> => {
  let added = 0
  try {
    const links = announcementLinks(await getText(fetchFn, LIST_URL, { accept: 'text/html' })).slice(0, max)
    for (const url of links) {
      const slug = /for-([a-z]+)-(\d{4})-announced/.exec(url)
      if (slug && db.prepare('SELECT 1 FROM plus_months WHERE month = ?').get(`${slug[2]}-${pad(monthNo(slug[1]!))}`)) continue
      const m = parsePlusEssential(await getText(fetchFn, url, { accept: 'text/html' }))
      if (!m) {
        log(`plus: ${url} did not parse as a lineup`)
        continue
      }
      db.prepare('INSERT OR REPLACE INTO plus_months (month, data, fetched_at) VALUES (?, ?, ?)').run(m.month, JSON.stringify(m), new Date().toISOString())
      added++
    }
  } catch (e) {
    log(`plus: ${(e as Error).message}`)
  }
  return added
}

const ROMAN: Record<string, string> = { i: '1', ii: '2', iii: '3', iv: '4', v: '5', vi: '6', vii: '7', viii: '8', ix: '9', x: '10' }
/** A title for comparing: lower case, no punctuation, roman numerals as digits ("IV-VI" and "4-6" match). */
export const plusTitleKey = (name: string) =>
  name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
    .split(' ')
    .map((t) => ROMAN[t] ?? t)
    .join(' ')

const COVER_RETRY_MS = 7 * 86400e3

/**
 * Looks up the IGDB cover of every lineup title that has none (coverId in plus.json wins), by name, PS5 games only, and
 * remembers the answer in plus_covers. Exact title match only, so a wrong cover never shows; no match leaves the name plate.
 */
export const resolvePlusCovers = async (db: DB, igdb: Pick<Igdb, 'query'> | null, log: (m: string) => void = () => {}, manual: PlusMonth[] = []): Promise<number> => {
  if (!igdb) return 0
  const names = new Set<string>()
  for (const m of [...storedPlusMonths(db), ...manual]) for (const g of m.games) if (!g.coverId) names.add(g.name)
  let found = 0
  for (const name of names) {
    const row = db.prepare('SELECT cover_id, checked_at FROM plus_covers WHERE name = ?').get(name) as { cover_id: string | null; checked_at: string } | undefined
    if (row && (row.cover_id || Date.now() - Date.parse(row.checked_at) < COVER_RETRY_MS)) continue
    try {
      const [ps5] = await igdb.query<{ id: number }>('platforms', 'fields id; where slug = "ps5"; limit 1;')
      const safe = name.replace(/["\\]/g, ' ').slice(0, 80)
      const rows = await igdb.query<{ name: string; cover?: { image_id: string } }>('games', `fields name,cover.image_id; search "${safe}"; where platforms = (${ps5!.id}) & cover != null; limit 10;`)
      const hit = rows.find((r) => plusTitleKey(r.name) === plusTitleKey(name))?.cover?.image_id
      db.prepare('INSERT OR REPLACE INTO plus_covers (name, cover_id, checked_at) VALUES (?, ?, ?)').run(name, hit ?? null, new Date().toISOString())
      if (hit) found++
      else log(`plus: no IGDB cover found for "${name}"`)
    } catch (e) {
      log(`plus: cover lookup for "${name}" failed: ${(e as Error).message}`)
    }
  }
  return found
}

/** Adds the resolved cover to lineup games that have none. */
export const withPlusCovers = (db: DB, months: PlusMonth[]): PlusMonth[] => {
  const covers = new Map((db.prepare('SELECT name, cover_id FROM plus_covers WHERE cover_id IS NOT NULL').all() as { name: string; cover_id: string }[]).map((r) => [r.name, r.cover_id]))
  return months.map((m) => ({ ...m, games: m.games.map((g) => (g.coverId || !covers.has(g.name) ? g : { ...g, coverId: covers.get(g.name)! })) }))
}
