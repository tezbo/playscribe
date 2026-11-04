// Fills the PS Plus monthly lineup automatically from Push Square's "PS Plus Essential games for <month>" article.
// Allowed because its robots.txt permits article pages and its terms (read 2026-11-04) carry no bot clause; see
// docs/ps5-patch-data.md. Facts only: month, claim window and game names are kept, article text never is. The
// hand-curated plus.json overrides a month when both exist.
import type { DB } from './db.ts'
import { getText, type FetchFn } from './http.ts'
import { plusProblems, type PlusMonth } from './plus.ts'

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
  const lead = text(/<p>(.*?)<\/p>/is.exec(body)?.[1] ?? '')
  const start = /from (?:\w+day,? )?(\d{1,2})(?:st|nd|rd|th)? (\w+) (\d{4})/i.exec(lead)
  if (!start || !monthNo(start[2]!)) return null
  const from = `${start[3]}-${pad(monthNo(start[2]!))}-${pad(Number(start[1]))}`
  const list = /<\/p>\s*<ul>(.*?)<\/ul>/is.exec(body)?.[1] ?? ''
  const games = [...list.matchAll(/<li>\s*<a [^>]*>(.*?)<\/a>/gis)].map((m) => ({ name: text(m[1]!) })).filter((g) => g.name)
  // The window ends the day before the next lineup ("rotated out ... on 1st December"), or at the end of the month.
  const next = /rotated out[^.]*?\bon (\d{1,2})(?:st|nd|rd|th)? (\w+)/i.exec(text(body))
  let until: string
  if (next && monthNo(next[2]!)) {
    const nm = monthNo(next[2]!)
    const year = Number(start[3]) + (nm < monthNo(start[2]!) ? 1 : 0)
    until = new Date(Date.UTC(year, nm - 1, Number(next[1]) - 1)).toISOString().slice(0, 10)
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
