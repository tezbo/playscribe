// What a post does and does not say about PS5 (r050-feed-ps5-claim-fixes, from Quinn's spot-check of 25 rows).
// Each rule is conservative: when it fires, the feed claims less ("announced", or no PS5 row), never more.

/** A test build is not a release: PTB, public test, test build, beta, preview, playtest. Read from the title only. */
export const isTestBuildPost = (title: string) =>
  /\b(ptb|public\s+test(?:ing)?(?:\s+(?:realm|build|server|branch))?|test\s+(?:build|server|realm|branch)|(?:open\s+|closed\s+)?beta|preview(?:\s+build)?|playtest|experimental\s+branch)\b/i.test(title)

const PLAYSTATION = /\b(ps5|ps4|playstation)\b/i

/**
 * True when a post says the update is for PC only or lists the builds of other platforms with no PlayStation
 * among them ("Windows: v1.0.6.2132 / Mac: v1.0.6.776"; "added on PC, rolling out soon to other platforms").
 * A post that names PlayStation is never PC-scoped by this rule.
 */
export const pcScopedPost = (text: string) => {
  if (PLAYSTATION.test(text)) return false
  const builds = new Set<string>()
  for (const m of text.matchAll(/\b(windows|mac(?:os)?|linux|steam\s*deck|xbox|switch)\b\s*[:\-–]\s*v?\d+\.\d+/gi)) builds.add(m[1]!.toLowerCase().replace(/\s+/g, ''))
  if (builds.size >= 2) return true
  return /\b(?:on|for)\s+(?:pc|steam|windows)\b[^.!?\n]{0,120}\b(?:other|more|additional)\s+platforms?\b[^.!?\n]{0,40}\b(?:soon|later|in the future|at a later date)/i.test(text)
    || /\b(?:other|more|additional)\s+platforms?\b[^.!?\n]{0,30}\b(?:soon|later|in the future)\b/i.test(text)
    || /\b(?:soon|later|in the future)\b[^.!?\n]{0,30}\b(?:to\s+)?(?:other|more|additional)\s+platforms?\b/i.test(text)
}

const MONTHS = ['january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october', 'november', 'december']
const MONTH = '(january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)\\.?'
const DATE = new RegExp(`\\b${MONTH}\\s+(\\d{1,2})(?:st|nd|rd|th)?(?:,?\\s+(\\d{4}))?\\b|\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+(?:of\\s+)?${MONTH}(?:,?\\s+(\\d{4}))?\\b`, 'gi')
const TIME = /(\d{1,2}):(\d{2})\s*(?:\(?\s*(?:UTC|GMT)\s*([+-]\d{1,2})?(?::?(\d{2}))?\s*\)?)?/i
const AVAILABLE = /\b(available|live|release[ds]?|releasing|arrive[sd]?|arriving|rolling out|roll out|go(?:es|ing)? live|launch(?:es|ing)?|deploy(?:ed|ing)?|updates? (?:will|is|are)|patch (?:will|is))\b/i
const NOT_A_RELEASE = /\b(ends?|ending|until|through|expires?|deadline|sale|event|stream|livestream|showcase|giveaway|maintenance|downtime|servers? (?:will )?(?:be )?(?:down|offline))\b/i

const monthIndex = (m: string) => MONTHS.findIndex((x) => x.startsWith(m.toLowerCase().slice(0, 3)))

/**
 * A later time the post states for the update ("At 02:00 UTC+0 on November 10, the updates ... will be available",
 * "starting on November 12, 2026 at 06:00 (UTC+0)"): an ISO time after the post's own, or null. A date with no
 * clock time or zone is held until the end of that UTC day, so the row is never early. Dates in the past and
 * dates more than 60 days out are ignored (they are history or a roadmap, not this update's release time).
 */
export const statedLiveTime = (text: string, publishedAt: string): string | null => {
  const published = Date.parse(publishedAt)
  if (Number.isNaN(published)) return null
  let best: number | null = null
  for (const m of text.matchAll(DATE)) {
    const monthName = m[1] ?? m[5]
    const day = Number(m[2] ?? m[4])
    const yearText = m[3] ?? m[6]
    if (!monthName || !(day >= 1 && day <= 31)) continue
    const mi = monthIndex(monthName)
    if (mi < 0) continue
    const at = m.index ?? 0
    const sentence = text.slice(Math.max(0, text.lastIndexOf('\n', at), text.lastIndexOf('. ', at) + 1), at + m[0].length + 160)
    if (!AVAILABLE.test(sentence) || NOT_A_RELEASE.test(sentence.slice(0, sentence.length - 80))) continue
    let year = yearText ? Number(yearText) : new Date(published).getUTCFullYear()
    let day0 = Date.UTC(year, mi, day)
    if (!yearText && day0 < published - 86400e3) day0 = Date.UTC(year + 1, mi, day)
    // The clock time sits within a short window either side of the date.
    const near = text.slice(Math.max(0, at - 60), at + m[0].length + 160)
    const t = near.match(TIME)
    let when = day0 + 86400e3 - 60e3 // no time: the end of that UTC day
    if (t && /utc|gmt/i.test(t[0])) {
      const offset = t[3] ? Number(t[3]) * 3600e3 + Math.sign(Number(t[3])) * Number(t[4] ?? 0) * 60e3 : 0
      when = day0 + Number(t[1]) * 3600e3 + Number(t[2]) * 60e3 - offset
    }
    if (when <= published + 3600e3 || when - published > 60 * 86400e3) continue
    if (best === null || when < best) best = when
  }
  return best === null ? null : new Date(best).toISOString()
}
