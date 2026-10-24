import assert from 'node:assert/strict'
import { test } from 'node:test'
import { classify, consoleVersionOf, nameRelease, ps5StatusOf, sizeBytesOf, studioKindOf } from '../src/ingest/classify.ts'
import { extractNotes } from '../src/ingest/notes.ts'

test('studio labels win and name the release', () => {
  assert.deepEqual(nameRelease('The Blood of Dawnwalker - Update 1.1 Patch Notes', '2026-10-22T09:00:00Z'), { displayName: 'Update 1.1', versionKey: '1.1', studioKind: 'major' })
  assert.equal(nameRelease('Hotfix #28 Now Live!', '2024-10-16T00:00:00Z').displayName, 'Hotfix 28')
  assert.equal(nameRelease('Patch 1.04 is out', '2026-01-01T00:00:00Z').versionKey, '1.04')
  assert.equal(studioKindOf('Day One Patch notes'), 'dayOne')
  assert.equal(studioKindOf('Black Myth: Wukong 1.0.8.14860 Patch Notes'), 'patch')
  assert.equal(studioKindOf('Dev diary: combat'), null)
})

test('kinds are inferred when the studio gives no label', () => {
  const fixes = extractNotes('[list][*]Fixed a crash on load[*]Improved stability[/list]')
  const adds = extractNotes('[list][*]Added photo mode[*]Fixed a crash[/list]')
  assert.deepEqual(classify({ title: 'Notes', notes: fixes, announcedAt: '2026-10-05T00:00:00Z', previousAnnouncedAt: '2026-10-01T00:00:00Z' }), { kind: 'hotfix', kindBasis: 'inferred' })
  assert.deepEqual(classify({ title: 'Notes', notes: fixes, announcedAt: '2026-11-05T00:00:00Z', previousAnnouncedAt: '2026-10-01T00:00:00Z' }), { kind: 'patch', kindBasis: 'inferred' })
  assert.deepEqual(classify({ title: 'Notes', notes: adds, announcedAt: '2026-11-05T00:00:00Z' }), { kind: 'major', kindBasis: 'inferred' })
  assert.deepEqual(classify({ title: 'Notes', notes: adds, announcedAt: '2026-09-03T10:00:00Z', platformReleaseDate: '2026-09-03' }), { kind: 'dayOne', kindBasis: 'inferred' })
})

test('console facts are read from text', () => {
  assert.equal(consoleVersionOf('PS5 version 01.004.000 is live'), '01.004.000')
  assert.equal(consoleVersionOf('Update 1.1'), null)
  assert.equal(sizeBytesOf('a 13GB download on PS5'), 13e9)
  assert.equal(sizeBytesOf('weighs 850 MB'), 850e6)
  assert.equal(ps5StatusOf('Update 1.1 is out now on PC, PlayStation 5, and Xbox Series X|S!'), 'live')
  assert.equal(ps5StatusOf('The PS5 patch is in certification and will follow shortly.'), 'announced')
  assert.equal(ps5StatusOf('There are no plans for a PS5 version.'), 'notPlanned')
})

test('notes keep sections, sub-headed items and platform tags', () => {
  const notes = extractNotes(`[h2]New features[/h2][list]
[*] [h3]Animal petting[/h3]
[*] [h3]Draught of Mind Rebirth[/h3]
[i]Forget all your abilities.[/i]
[/list]
[h2]PS5[/h2][list][*]Fixed HDR on PS5 Pro[*]Fixed trophies[/list]
[h2]General[/h2][list][*][PC] Fixed DLSS flicker[/list]`)
  assert.deepEqual(notes.map((s) => s.title), ['New features', 'PS5', 'General'])
  assert.deepEqual(notes[0]!.items.map((i) => i.text), ['Animal petting', 'Draught of Mind Rebirth: Forget all your abilities.'])
  assert.deepEqual(notes[1]!.items[0], { text: 'Fixed HDR on PS5 Pro', platforms: ['ps5'], ps5ProOnly: true })
  assert.deepEqual(notes[2]!.items[0]!.platforms, ['pc'])
})
