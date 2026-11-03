import assert from 'node:assert/strict'
import { test } from 'node:test'
import { extractNotes } from '../src/ingest/notes.ts'
import { issueId, issuesOf, sameIssue } from '../src/issues.ts'

const rel = (id: string, at: string, body: string) => ({ id, announcedAt: at, notes: extractNotes(body) })

test('roadmap 16: known-issue sections and lines become issues with a stable id', () => {
  const r1 = rel('g@1.0', '2026-10-01T00:00:00Z', '[h2]Fixes[/h2][list][*]Fixed a door[/list][h2]Known issues[/h2][list][*]Saves may fail to load after fast travel[*]Known issue: HDR looks washed out on PS5 Pro[/list]')
  const out = issuesOf('g', [r1])
  assert.deepEqual(out.map((i) => i.text), ['Saves may fail to load after fast travel', 'HDR looks washed out on PS5 Pro'])
  assert.equal(out[0]!.id, issueId('g', 'saves may fail to load after fast travel!'))
  assert.ok(out.every((i) => i.status === 'open' && i.firstReleaseId === 'g@1.0'))
})

test('roadmap 16: a later patch that fixes the same thing marks it addressed, with the event release; relisting keeps it open', () => {
  const r1 = rel('g@1.0', '2026-10-01T00:00:00Z', '[h2]Known issues[/h2][list][*]Saves may fail to load after fast travel[*]HDR looks washed out on PS5 Pro[/list]')
  const r2 = rel('g@1.1', '2026-10-10T00:00:00Z', '[h2]Fixes[/h2][list][*]Fixed saves failing to load after fast travel[/list][h2]Known issues[/h2][list][*]HDR looks washed out on PS5 Pro[/list]')
  const out = issuesOf('g', [r2, r1])
  const [saves, hdr] = out
  assert.deepEqual([saves!.status, saves!.addressedBy, saves!.addressedAt], ['addressed', 'g@1.1', '2026-10-10T00:00:00Z'])
  assert.equal(hdr!.status, 'open')
  assert.equal(out.length, 2)
})

test('roadmap 16: PC-only lines are not issues, and unrelated lines do not address one', () => {
  const r1 = rel('g@1.0', '2026-10-01T00:00:00Z', '[h2]Known issues[/h2][list][*]Steam Deck: stutter in the market[*]Quest marker missing in chapter two[/list]')
  const r2 = rel('g@1.1', '2026-10-10T00:00:00Z', '[h2]Fixes[/h2][list][*]Fixed a crash in the cave[/list]')
  const out = issuesOf('g', [r1, r2])
  assert.deepEqual(out.map((i) => i.text), ['Quest marker missing in chapter two'])
  assert.equal(out[0]!.status, 'open')
  assert.equal(sameIssue('Fixed a crash in the cave', 'Quest marker missing in chapter two'), false)
})
