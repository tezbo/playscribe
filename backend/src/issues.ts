// Roadmap 16: known issues. A "Known issues" section (or a "Known issue:" line) in a release's notes becomes an
// issue with a stable id, so the app can follow it. A later release whose fixes mention the same thing marks it addressed.
// Derived from stored notes at export time, so a rule change reaches old releases and nothing needs a new table.
import { createHash } from 'node:crypto'
import type { NoteSection } from './types.ts'

export interface KnownIssue {
  /** Stable hash of the game and the normalised text, the same across releases that repeat the line. */
  id: string
  text: string
  status: 'open' | 'addressed'
  /** The release that first listed it. */
  firstReleaseId: string
  addressedBy?: string
  addressedAt?: string
}

const SECTION = /\bknown\s+(issues?|bugs?|problems?)\b/i
const LINE = /^\s*known\s+(issue|bug|problem)s?\s*[:\-–]\s*/i
const STOP = new Set(['the', 'a', 'an', 'to', 'of', 'in', 'on', 'for', 'and', 'or', 'is', 'are', 'that', 'with', 'when', 'where', 'fixed', 'fix', 'fixes', 'issue', 'issues', 'bug', 'an', 'be', 'it', 'its', 'not', 'no', 'some', 'players', 'player'])

export const normalise = (text: string) =>
  text
    .toLowerCase()
    .replace(LINE, '')
    .replace(/[^a-z0-9 ]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()

const tokens = (text: string) => new Set(normalise(text).split(' ').filter((t) => t.length > 2 && !STOP.has(t)))

/** Same thing, said again: one contains the other, or most of the shorter one's words are in the other. */
export const sameIssue = (a: string, b: string) => {
  const ta = tokens(a)
  const tb = tokens(b)
  if (ta.size < 2 || tb.size < 2) return normalise(a) === normalise(b)
  const shared = [...ta].filter((t) => tb.has(t)).length
  return shared / Math.min(ta.size, tb.size) >= 0.7
}

export const issueId = (gameId: string, text: string) => createHash('sha1').update(`${gameId}\n${normalise(text)}`).digest('hex').slice(0, 12)

/** Known-issue lines in notes, and the other (non known-issue) lines that can fix them. PC-only lines are ignored. */
export const splitNotes = (notes: NoteSection[]) => {
  const issues: string[] = []
  const rest: string[] = []
  for (const s of notes) {
    const inSection = SECTION.test(s.title)
    for (const i of s.items) {
      if (i.pcOnly) continue
      if (inSection) issues.push(i.text.replace(LINE, '').trim())
      else if (LINE.test(i.text)) issues.push(i.text.replace(LINE, '').trim())
      else rest.push(i.text)
    }
  }
  return { issues, rest }
}

/** Oldest release first. An issue still listed as known in a later release stays open. */
export const issuesOf = (gameId: string, releases: { id: string; announcedAt: string; notes: NoteSection[] }[]): KnownIssue[] => {
  const ordered = [...releases].sort((a, b) => a.announcedAt.localeCompare(b.announcedAt) || a.id.localeCompare(b.id))
  const split = ordered.map((r) => ({ r, ...splitNotes(r.notes) }))
  const out = new Map<string, KnownIssue>()
  for (const [i, { r, issues }] of split.entries()) {
    for (const text of issues) {
      const id = issueId(gameId, text)
      if (out.has(id)) continue
      const issue: KnownIssue = { id, text, status: 'open', firstReleaseId: r.id }
      // Fixed by the first later release that mentions it among its fixes, unless that release lists it as known again.
      for (const later of split.slice(i + 1)) {
        if (later.issues.some((t) => sameIssue(t, text))) break
        if (later.rest.some((t) => sameIssue(t, text))) {
          issue.status = 'addressed'
          issue.addressedBy = later.r.id
          issue.addressedAt = later.r.announcedAt
          break
        }
      }
      out.set(id, issue)
    }
  }
  return [...out.values()]
}
