import assert from 'node:assert/strict'
import { test } from 'node:test'
import { digestOf } from '../src/digest.ts'
import { extractNotes, tagNotes } from '../src/ingest/notes.ts'

const digest = (body: string) => digestOf(tagNotes(extractNotes(body)))

test('digest (roadmap 6): counts by kind, PC-only lines left out, PS5-named lines counted', () => {
  const d = digest('[h3]New Features[/h3][list][*]Added photo mode[*]Added a new boss[/list][h3]Bug Fixes[/h3][list][*]Fixed a crash on PS5[*]Fixed HDR[*]Fixed Steam Deck suspend[/list][h3]Balance[/h3][list][*]Reduced boss health[/list]')
  assert.deepEqual([d.new, d.fixed, d.balance, d.other], [2, 2, 1, 0])
  assert.equal(d.ps5, 1)
})

test('digest: top new lines only when headings are clean', () => {
  const clean = digest('[h3]New Features[/h3][list][*]Added photo mode[*]Added a new boss[*]Added co-op[*]Added a map[/list]')
  assert.deepEqual(clean.topNew, ['Added photo mode', 'Added a new boss', 'Added co-op'])
  // Generic heading: the lines are guessed from their first word, so counts only.
  const generic = digest('[list][*]Added photo mode[*]Fixed a crash[/list]')
  assert.equal(generic.new, 1)
  assert.equal(generic.topNew, undefined)
  // Long lines are not shown.
  assert.equal(digest(`[h3]New[/h3][list][*]${'Added a very long description '.repeat(6)}[/list]`).topNew, undefined)
})

test('digest: empty notes are all zero', () => {
  assert.deepEqual(digestOf([]), { new: 0, fixed: 0, balance: 0, other: 0, ps5: 0 })
})
