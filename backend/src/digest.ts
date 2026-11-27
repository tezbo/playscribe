// "Since you last looked" (roadmap item 6, catch-up): a short summary of one release, derived from its notes at read time,
// so the app can tell a returning player what they missed without opening every update. Counts cover lines a PS5 player
// can use (PC-only lines are left out). `topNew` (at most 3 lines) appears only when the headings are clean: the lines
// sit under a heading that names new content, so they are really new, and each is short enough to read at a glance.
// No download size: too few releases carry one.
import { readFileSync } from 'node:fs'
import { categoryOf } from './ingest/notes.ts'
import type { NoteCategory, NoteSection } from './types.ts'

export interface Digest {
  new: number
  fixed: number
  balance: number
  other: number
  /** Lines that name PS5 (or PS5 Pro) specifically. */
  ps5: number
  /** Up to 3 new lines, present only when the headings are clean. */
  topNew?: string[]
}

const MAX_LINE = 120
const TOP = 3

export const digestOf = (notes: NoteSection[]): Digest => {
  const d: Digest = { new: 0, fixed: 0, balance: 0, other: 0, ps5: 0 }
  const headed: string[] = []
  for (const s of notes) {
    const byHeading = categoryOf(s.title) === 'new'
    for (const i of s.items) {
      if (i.pcOnly) continue
      const c: NoteCategory = i.category ?? 'other'
      d[c]++
      if (i.platforms?.includes('ps5') || i.ps5ProOnly) d.ps5++
      if (byHeading && c === 'new' && i.text.length <= MAX_LINE && !/^(this|these|the following|below)\b/i.test(i.text)) headed.push(i.text)
    }
  }
  // Clean means the new lines came from named headings and most "new" lines did: otherwise the picks could be fixes in disguise.
  if (headed.length >= 1 && headed.length >= d.new * 0.6) d.topNew = headed.slice(0, TOP)
  return d
}

// A release's headline and key changes, quoted from its own official notes (the Feed has sent neither until now, so the app fell back to
// "Fixes and tuning" for every update with notes). Order of preference for the headline: (1) the post's own subtitle when its title has one
// ("Update 7.2: The Decimation"), (2) words quoted from the most significant official item, (3) none, and the app shows no subtitle.
// Nothing is written by us: a line is cut at a word boundary, with an ellipsis only when cut.
const HEADLINE_MAX = 100
const KEY_MAX = 3
const LEAD = /^(this|these|the following|below|please|we |we'|today|the game has been|hi\b|hello|hey\b|greetings|welcome|thank|thanks|dear|note\b|notes?:|patch notes?\b|known issues?\b|read more|see |click|for more|full (patch )?notes|\[?update\b|version\b|v?\d+(\.\d+)+\b)/i
const noteWords = (t: string) => t.split(/\s+/).filter((w) => /[a-z]/i.test(w)).length

/** A line fit to lead a page: a real sentence of a few words, not a greeting, a pointer to other text or a bare version. */
const usable = (t: string) => t.length >= 12 && noteWords(t) >= 4 && !LEAD.test(t) && !/^https?:/i.test(t) && !/[|]{2}|…$/.test(t)

export const cutAtWord = (text: string, max = HEADLINE_MAX) => {
  const t = text.replace(/\s+/g, ' ').trim().replace(/[.:;,\s]+$/, '')
  if (t.length <= max) return t
  const cut = t.slice(0, max).replace(/\s+\S*$/, '').replace(/[.:;,\s]+$/, '')
  return `${cut}…`
}

/** The subtitle of a post title: what follows a version label and a separator ("Update 1.4 - Deep Dive" gives "Deep Dive"). */
export const titleSubtitle = (displayName: string) => {
  const m = displayName.match(/^(?:.*?\b(?:update|patch|hotfix|version|v)\s*v?\d[\w.]*|v?\d[\w.]*)\s*(?:[:\u2013\u2014|]|\s-\s)\s*(.{4,})$/i)
  const sub = m?.[1]?.trim()
  return sub && noteWords(sub) >= 1 && !/^(update|patch|notes?|hotfix|release)\b/i.test(sub) ? sub : null
}

export const headlinesOf = (notes: NoteSection[], displayName = ''): { headline?: string; keyChanges?: string[] } => {
  const rank: Record<string, number> = { new: 0, balance: 1, fixed: 2, other: 3 }
  const picks: { text: string; r: number; order: number }[] = []
  let order = 0
  for (const s of notes) {
    const heading = categoryOf(s.title)
    for (const i of s.items) {
      order++
      if (i.pcOnly) continue
      const t = i.text.replace(/\s+/g, ' ').trim()
      if (t.length > 220 || !usable(t)) continue
      const c: NoteCategory = i.category ?? 'other'
      // A "new" line under a heading that says new content is the strongest; fixes lead only when nothing else is usable.
      // A line that fits whole beats one that would be cut mid-sentence.
      const r = (c === 'other' && heading === 'new' ? 0 : rank[c] ?? 3) + (t.length > HEADLINE_MAX ? 0.5 : 0)
      picks.push({ text: t, r, order })
    }
  }
  picks.sort((a, b) => a.r - b.r || a.order - b.order)
  const seen = new Set<string>()
  const keys: string[] = []
  for (const p of picks) {
    const k = p.text.toLowerCase().slice(0, 40)
    if (seen.has(k)) continue
    seen.add(k)
    keys.push(cutAtWord(p.text, 140))
    if (keys.length === KEY_MAX) break
  }
  const subtitle = titleSubtitle(displayName)
  const headline = subtitle ? cutAtWord(subtitle) : keys[0] ? cutAtWord(keys[0]) : undefined
  return { ...(headline ? { headline } : {}), ...(keys.length ? { keyChanges: keys } : {}) }
}

// Releases the app bundles with a hand-written headline (the demo games): the feed leaves them alone, because the app lets the feed's value win.
let handWritten: Set<string> | undefined
export const handWrittenHeadlines = (): Set<string> => {
  if (handWritten) return handWritten
  try {
    const rows = JSON.parse(readFileSync(new URL('../../ios/Playscribe/Resources/Data/releases.json', import.meta.url), 'utf8')) as { id: string; headline?: string }[]
    handWritten = new Set(rows.filter((r) => r.headline).map((r) => r.id))
  } catch {
    handWritten = new Set()
  }
  return handWritten
}
