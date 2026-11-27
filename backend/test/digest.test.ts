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

// data-notes-coverage-all-games: the Feed sent no headline, so the app showed "Fixes and tuning" for every update with notes.
test('headlinesOf: quotes the most significant official item, never a greeting; the title subtitle comes first; nothing fits means none', async () => {
  const { headlinesOf, titleSubtitle } = await import('../src/digest.ts')
  const item = (text: string, category: 'new' | 'fixed' | 'balance' | 'other', pcOnly = false) => ({ text, category, pcOnly, ps5ProOnly: false })
  const out = headlinesOf([
    { title: 'Changes', items: [item('Hello everyone, thanks for playing this update!', 'other'), item('Fixed a crash when opening the map', 'fixed'), item('Added Idus Knight and Heavy Knight as new starting classes', 'new'), item('Added a PC-only DLSS toggle for the menu', 'new', true)] },
  ])
  assert.equal(out.headline, 'Added Idus Knight and Heavy Knight as new starting classes')
  assert.deepEqual(out.keyChanges, ['Added Idus Knight and Heavy Knight as new starting classes', 'Fixed a crash when opening the map'])
  assert.equal(titleSubtitle('Update 7.2: The Decimation'), 'The Decimation')
  assert.equal(titleSubtitle('Update 1.4'), null)
  assert.equal(headlinesOf([{ title: 'Changes', items: [item('Hi all', 'other')] }], 'Patch 2').headline, undefined)
  assert.equal(headlinesOf([{ title: 'Changes', items: [item('Fixed a crash when opening the map during the second chapter and the long chase that follows it in the old town', 'fixed')] }]).headline?.endsWith('…'), true)
})
