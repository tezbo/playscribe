// "Since you last looked" (roadmap item 6, catch-up): a short summary of one release, derived from its notes at read time,
// so the app can tell a returning player what they missed without opening every update. Counts cover lines a PS5 player
// can use (PC-only lines are left out). `topNew` (at most 3 lines) appears only when the headings are clean: the lines
// sit under a heading that names new content, so they are really new, and each is short enough to read at a glance.
// No download size: too few releases carry one.
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
