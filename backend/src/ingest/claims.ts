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
  // "(PC first, other platforms coming soon)" about one item in a full cross-platform patch is not the whole post's scope.
  const outsideParens = (re: RegExp) => {
    const m = re.exec(text)
    return !!m && !(text.lastIndexOf('(', m.index) > text.lastIndexOf(')', m.index))
  }
  return (
    outsideParens(/\b(?:on|for)\s+(?:pc|steam|windows)\b[^.!?\n]{0,120}\b(?:other|more|additional)\s+platforms?\b[^.!?\n]{0,40}\b(?:soon|later|in the future|at a later date)/i) ||
    outsideParens(/\b(?:other|more|additional)\s+platforms?\b[^.!?\n]{0,30}\b(?:soon|later|in the future)\b/i) ||
    outsideParens(/\b(?:soon|later|in the future)\b[^.!?\n]{0,30}\b(?:to\s+)?(?:other|more|additional)\s+platforms?\b/i)
  )
}

const MONTHS = ['january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october', 'november', 'december']
const MONTH = '(january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)\\.?'
const DATE = new RegExp(`\\b${MONTH}\\s+(\\d{1,2})(?:st|nd|rd|th)?(?:,?\\s+(\\d{4}))?\\b|\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+(?:of\\s+)?${MONTH}(?:,?\\s+(\\d{4}))?\\b`, 'gi')
const TIME = /(\d{1,2}):(\d{2})\s*(?:\(?\s*(?:UTC|GMT)\s*([+-]\d{1,2})?(?::?(\d{2}))?\s*\)?)?/i
// A date counts only when its sentence is about this update arriving later (a future marker and the update's own words)
// and about nothing else (an event, a DLC, a store item, a test, a stream). Failing toward "live" is deliberate: a live
// patch held back for days costs more than an alert 90 minutes early (Quinn's scan of 2,664 real posts, 12 Nov).
const FUTURE = /\b(will|tomorrow|starting|starts?|scheduled|coming|expected|arrives?|arriving|rolling out|launch(?:es|ing)?|releas(?:e|es|ing)|go(?:es|ing)? live)\b/i
const NEXT_RELEASE = /\bnext\s+(?:weekly\s+|major\s+|minor\s+)?(?:patch|update|hotfix|release|version|season)\b/i
const RELEASE_WORDS = /\b(releas\w*|live|available|update|patch|season)\b/i
const OWN = /\b(updates?|patch(?:es)?|hotfix(?:es)?|version|season)\b/i
const NOT_A_RELEASE = /\b(ends?|ending|until|through|expires?|deadline|sale|events?|dlc|store|warbond|tests?|testing|ama|streams?|livestream|showcase|giveaway|pre-?orders?|wish-?lists?|before|by|bundle|skin|pass|trailer|reveal|beta|playtest)\b/i
// Maintenance is the release when the post is titled as an update: the update lands when the maintenance ends.
const MAINTENANCE = /\b(maintenance|downtime|restraining order|servers? (?:will )?(?:be )?(?:down|offline|unavailable))\b/i
const RELEASEY_TITLE = /\b(update|version|patch|hotfix)\b/i

const monthIndex = (m: string) => MONTHS.findIndex((x) => x.startsWith(m.toLowerCase().slice(0, 3)))

/**
 * A later time the post states for the update ("At 02:00 UTC+0 on November 10, the updates ... will be available",
 * "starting on November 12, 2026 at 06:00 (UTC+0)"): an ISO time after the post's own, or null. A date with no
 * clock time or zone is held until the end of that UTC day, so the row is never early. Dates in the past and
 * dates more than 14 days out are ignored (they are history or a roadmap, not this update's release time).
 */
export const statedLiveTime = (raw: string, publishedAt: string): string | null => {
  // Steam's BBCode tags ([p], [list], [*]) end a sentence as a line break does.
  const text = raw.replace(/\[\/?[a-z0-9*]+(?:=[^\]]*)?\]/gi, '\n')
  const published = Date.parse(publishedAt)
  if (Number.isNaN(published)) return null
  let best: number | null = null
  let bestNamesPs5 = false
  const titleReleasey = RELEASEY_TITLE.test(text.split('\n')[0] ?? '')
  for (const m of text.matchAll(DATE)) {
    const monthName = m[1] ?? m[5]
    const day = Number(m[2] ?? m[4])
    const yearText = m[3] ?? m[6]
    if (!monthName || !(day >= 1 && day <= 31)) continue
    const mi = monthIndex(monthName)
    if (mi < 0) continue
    const at = m.index ?? 0
    // The sentence (or line) around the date, plus the next one when the date's own ends before saying what happens.
    const from = Math.max(0, text.lastIndexOf('\n', at), text.lastIndexOf('. ', at) + 1)
    const rest = text.slice(at + m[0].length)
    const end = rest.search(/\n|[.!?](?:\s|$)/)
    const sentence = text.slice(from, at + m[0].length + (end < 0 ? 160 : Math.min(end + 1, 240)))
    const head = sentence
    const maintenance = titleReleasey && MAINTENANCE.test(sentence)
    // "The next patch will be on January 3" is a different release from the one this post is about.
    if (NEXT_RELEASE.test(sentence)) continue
    const ownDay = !(TIME.test(sentence) && /utc|gmt/i.test(sentence)) && new Date(Date.UTC(yearText ? Number(yearText) : new Date(published).getUTCFullYear(), mi, day)).toISOString().slice(0, 10) === publishedAt.slice(0, 10)
    // A sentence that puts the release on the post's own day says the post is the release: nothing else in it is a hold.
    if (ownDay && RELEASE_WORDS.test(sentence) && !NOT_A_RELEASE.test(sentence)) return null
    if (!FUTURE.test(sentence) || !(OWN.test(sentence) || maintenance) || NOT_A_RELEASE.test(head)) continue
    // The sentence that names PlayStation or consoles gives the time that matters for this feed.
    const namesPs5 = /\b(ps5|playstation|consoles?)\b/i.test(sentence)
    let year = yearText ? Number(yearText) : new Date(published).getUTCFullYear()
    let day0 = Date.UTC(year, mi, day)
    if (!yearText && day0 < published - 86400e3) day0 = Date.UTC(year + 1, mi, day)
    // The clock time sits within a short window either side of the date.
    // The clock time must sit in the same sentence or line as the date.
    const t = sentence.match(TIME)
    let when = day0 + 86400e3 - 60e3 // no time: the end of that UTC day
    if (t && /utc|gmt/i.test(t[0])) {
      const offset = t[3] ? Number(t[3]) * 3600e3 + Math.sign(Number(t[3])) * Number(t[4] ?? 0) * 60e3 : 0
      when = day0 + Number(t[1]) * 3600e3 + Number(t[2]) * 60e3 - offset
    }
    if (maintenance) {
      // "expected to remain in effect for approximately 4 hours": the update is there when the maintenance is over.
      const d = text.slice(at, at + m[0].length + 400).match(/\b(?:approximately|about|around|roughly|~)\s*(\d{1,2})\s*hours?\b/i)
      if (d) when += Number(d[1]) * 3600e3
    }
    // A date with no clock time that is the post's own day says nothing about holding it: the post is that day's news.
    const dateOnly = !(t && /utc|gmt/i.test(t[0]))
    if (dateOnly && new Date(day0).toISOString().slice(0, 10) === publishedAt.slice(0, 10)) continue
    if (when <= published + 3600e3 || when - published > 14 * 86400e3) continue
    if (best === null || (namesPs5 && !bestNamesPs5) || (namesPs5 === bestNamesPs5 && when < best)) {
      best = when
      bestNamesPs5 = namesPs5
    }
  }
  return best === null ? null : new Date(best).toISOString()
}
