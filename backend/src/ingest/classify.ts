import type { KindBasis, NoteSection, PlatformStatus, ReleaseKind } from '../types.ts'

// Release naming and kinds, per docs/ps5-patch-data.md. The studio's own label always wins;
// anything else is inferred and marked so it can be audited.

// A number followed by a slash or AM/PM is a date or time ("Latest Update 5/14", "Update 5PM PT"), not a version.
const VERSION = /\b(?:update|patch|hotfix|version|ver\.?|v)\s*#?\s*(\d+(?:\.\d+){0,3}[a-z]?)\b(?!\s*\/|\s*[ap]\.?m\b)/i
const BARE_VERSION = /\b(\d+\.\d+(?:\.\d+){0,2})\b/

export interface Naming {
  displayName: string
  /** Groups posts about the same release: the studio's version, else the label plus the day. */
  versionKey: string
  studioKind: ReleaseKind | null
}

export const studioKindOf = (title: string): ReleaseKind | null => {
  const t = title.replace(/\bpatch\s*notes?\b/gi, ' ').replace(/\brelease\s*notes?\b/gi, ' ')
  if (/\bday[\s-]*(one|1|zero|0)\b/i.test(t)) return 'dayOne'
  if (/\bhot\s*-?fix(es)?\b/i.test(t)) return 'hotfix'
  if (/\b(update|expansion|dlc|season)\b/i.test(t)) return 'major'
  if (/\bpatch\b/i.test(t)) return 'patch'
  // "Wukong 1.0.8.14860 Patch Notes": the studio publishes it as patch notes for a numbered build.
  if (/\bpatch\s*notes?\b/i.test(title) && BARE_VERSION.test(title)) return 'patch'
  return null
}

const LABEL: Record<ReleaseKind, string> = { dayOne: 'Day one patch', hotfix: 'Hotfix', patch: 'Patch', major: 'Update', silent: 'Update' }

export const nameRelease = (title: string, publishedAt: string): Naming => {
  const studioKind = studioKindOf(title)
  const m = title.match(VERSION) ?? title.match(BARE_VERSION)
  const version = m?.[1]
  // "Update 1.1", "Patch 1.04", "Hotfix 1.1.2": keep the studio's word for it when it gave one.
  const word = title.match(/\b(day[\s-]*one patch|hot\s*-?fix|update|patch|expansion)\b/i)?.[1]
  const label = word ? word.replace(/\s+/g, ' ').replace(/^./, (c) => c.toUpperCase()).replace(/^Hot ?-?fix$/i, 'Hotfix') : LABEL[studioKind ?? 'major']
  const displayName = version ? `${label} ${version}` : studioKind === 'dayOne' ? 'Day one patch' : title.trim().slice(0, 80)
  const versionKey = version ? version.toLowerCase() : `${(studioKind ?? 'post').toLowerCase()}-${publishedAt.slice(0, 10)}`
  return { displayName, versionKey, studioKind }
}

const ADDS = /^(add|added|adds|new|introduc|now (you|players) can|you can now)/i
const NEW_SECTION = /new (features|content)|what'?s new|features/i

export const isFixOnly = (notes: NoteSection[]) =>
  !notes.some((s) => NEW_SECTION.test(s.title) || s.items.some((i) => ADDS.test(i.text)))

const DAY = 24 * 3600 * 1000

export const classify = (opts: {
  title: string
  notes: NoteSection[]
  announcedAt: string
  previousAnnouncedAt?: string | null
  platformReleaseDate?: string | null
}): { kind: ReleaseKind; kindBasis: KindBasis } => {
  const studio = studioKindOf(opts.title)
  if (studio) return { kind: studio, kindBasis: 'studio' }
  const at = Date.parse(opts.announcedAt)
  if (opts.platformReleaseDate && Math.abs(at - Date.parse(opts.platformReleaseDate)) <= DAY) return { kind: 'dayOne', kindBasis: 'inferred' }
  if (isFixOnly(opts.notes)) {
    const sincePrev = opts.previousAnnouncedAt ? at - Date.parse(opts.previousAnnouncedAt) : Infinity
    return { kind: sincePrev <= 7 * DAY ? 'hotfix' : 'patch', kindBasis: 'inferred' }
  }
  return { kind: 'major', kindBasis: 'inferred' }
}

/**
 * The version string the PS5 shows, e.g. "01.004.000". Studios often drop the leading zero
 * ("Ver. 1.005.000"); the console always shows two digits, so it is padded. In a multi-platform
 * post only a version next to "PS5" counts, so a PC build number is never taken for the PS5 one;
 * `ps5Only` is for posts that are only about PS5.
 */
export const consoleVersionOf = (text: string, opts: { ps5Only?: boolean } = {}) => {
  const V = '(\\d{1,2})\\.(\\d{3})\\.(\\d{3})(?!\\d|\\.\\d)'
  const near = new RegExp(`(?:PS5|PlayStation\\s*®?\\s*5)[^\\n]{0,40}?\\b${V}|\\b${V}\\s*\\(\\s*(?:PS5|PlayStation\\s*®?\\s*5)`, 'i')
  const m = text.match(near) ?? (opts.ps5Only ? text.match(new RegExp(`\\b${V}`)) : null)
  if (!m) return null
  const [major, minor, patch] = (m[1] ? m.slice(1, 4) : m.slice(4, 7)) as [string, string, string]
  return `${major.padStart(2, '0')}.${minor}.${patch}`
}

/** A download size near the word size/download/GB, in bytes. */
export const sizeBytesOf = (text: string) => {
  const m = text.match(/(\d+(?:[.,]\d+)?)\s*(GB|MB|GiB|MiB)\b/i)
  if (!m) return null
  const n = Number(m[1]!.replace(',', '.'))
  const unit = m[2]!.toUpperCase()
  return Math.round(n * (unit.startsWith('G') ? 1e9 : 1e6))
}

/** For a post that names PS5: is the update out there, coming later, or not coming at all? */
export const ps5StatusOf = (text: string): PlatformStatus => {
  const near = (re: string) => new RegExp(`(PS5|PlayStation\\s*®?\\s*5|consoles?)[^.!?\\n]{0,80}${re}|${re}[^.!?\\n]{0,80}(PS5|PlayStation\\s*®?\\s*5|consoles?)`, 'i')
  if (near('(not planned|no plans|will not|won\'t)').test(text)) return 'notPlanned'
  if (near('(coming soon|later|next week|in the coming|certification|cert\\b|as soon as|follow shortly|following week)').test(text)) return 'announced'
  return 'live'
}
