import assert from 'node:assert/strict'
import { test } from 'node:test'
import { classify, consoleVersionOf, nameRelease, ps5LiveStated, ps5StatusOf, sizeBytesOf, studioKindOf } from '../src/ingest/classify.ts'
import { extractNotes, platformsFor, ps5PageOf, tagNotes } from '../src/ingest/notes.ts'

test('only a post that says the update is out on PS5 counts as official PS5 evidence', () => {
  assert.ok(ps5LiveStated('Patch 1.04 is now live on PC, PS5 and Xbox Series X|S.'))
  assert.ok(ps5LiveStated('The PS5 version of Hotfix 2 is available now.'))
  assert.ok(ps5LiveStated('Update 3 is rolling out on PlayStation 5 and PC'))
  assert.ok(!ps5LiveStated('Update 3 is live on PC. The PS5 version follows next week.'))
  assert.ok(!ps5LiveStated('Patch 5 is live now and fixes PS5 controller button prompts.'))
  assert.ok(!ps5LiveStated('We are working on the PS5 patch. Stay tuned!'))
  assert.ok(ps5LiveStated('Title Update 1.1.1 - Release Notes. PATCH SIZES: PS5®: 12.40 GB Xbox Series X|S: 32 GB'))
  assert.ok(!ps5LiveStated('Patch 1.4.6 is live on Steam now. PS5 players should expect it in a day or two. PS5: 3 GB'))
  assert.ok(!ps5LiveStated('Update 1.1 is out now on PC! Notes for PlayStation 5 follow on our site.'))
})

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

test('PC-only lines are tagged PC so PS5 pages leave them out', () => {
  assert.deepEqual(platformsFor('Update to the FrameGen technology, including dedicated settings.'), ['pc'])
  assert.deepEqual(platformsFor('Game may crash on switching FrameGen from OFF to ON (on AMD Radeon RX 9070 XT only).'), ['pc'])
  assert.deepEqual(platformsFor('Implemented support for the Steam Controller.'), ['pc'])
  assert.deepEqual(platformsFor('Fixed a crash when switching from controller to keyboard and mouse.'), ['pc'])
  assert.deepEqual(platformsFor('Added DualSense® support on Steam'), ['pc'])
  // A line that also names a console is not PC-only; words that only look like PC terms are not tags.
  assert.deepEqual(platformsFor('Fixed a crash on PS5 and AMD GPUs'), ['ps5', 'pc'])
  assert.equal(platformsFor('Improved performance on consoles and AMD GPUs'), undefined)
  assert.equal(platformsFor('Fixed rocket launcher ammo not refilling'), undefined)
  assert.equal(platformsFor('Fixed the tavern windows rendering black'), undefined)
  assert.equal(platformsFor('Fixed mod.io browsing in the Mod Manager'), undefined)
  assert.deepEqual(platformsFor('Fixed a crash on Xbox when resuming'), ['xboxSeries'])
})

test('a heading about one platform tags its items, and stored notes are re-tagged on read', () => {
  const notes = extractNotes('[h2]Steam Deck[/h2][list][*]Improved loading times[/list][h2]Fixes[/h2][list][*]Fixed a crash on PC when alt-tabbing[*]Fixed a door[/list]')
  assert.deepEqual(notes[0]!.items[0]!.platforms, ['pc'])
  assert.deepEqual(notes[1]!.items.map((i) => i.platforms), [['pc'], undefined])
  const stored = [{ title: 'Highlights', items: [{ text: 'Updated FrameGen', ps5ProOnly: false }] }]
  assert.deepEqual(tagNotes(stored)[0]!.items[0]!.platforms, ['pc'])
})

test('dates and times in titles are not versions; newsletters are not patches', async () => {
  const { looksLikePatch } = await import('../src/ingest/adapters.ts')
  assert.equal(nameRelease('Apex Legends: Latest Update 5/14/2026', '2026-05-14T00:00:00Z').versionKey, 'major-2026-05-14')
  assert.equal(nameRelease('Apex Legends: Latest Update 5PM PT', '2026-05-14T00:00:00Z').versionKey, 'major-2026-05-14')
  assert.equal(nameRelease('Update 7.2.1', '2026-10-22T00:00:00Z').versionKey, '7.2.1')
  assert.equal(looksLikePatch('An Update from the Anti Cheat Team - 10/08/2026'), false)
  assert.equal(looksLikePatch('Patch Delay Update'), false)
})

test('the PS5 version is the console form, next to PS5 in a multi-platform post', () => {
  assert.equal(consoleVersionOf('PS5: Ver.1.005.000 / Steam: Ver.1.005.001'), '01.005.000')
  assert.equal(consoleVersionOf('Steam Ver.1.005.001 is live; PS5 follows.'), null)
  assert.equal(consoleVersionOf('Steam: Ver.1.005.001 / PS5: Ver.1.005.000'), '01.005.000')
  assert.equal(consoleVersionOf('Version 01.004.000 (PS5) and 1.4.0 (PC)'), '01.004.000')
  assert.equal(consoleVersionOf('The update brings the game to 01.012.000.', { ps5Only: true }), '01.012.000')
  assert.equal(consoleVersionOf('Version 1.0.21.23831 on PC', { ps5Only: true }), null)
})

test('ps5PageOf finds the studio page about the PS5 update, never Steam or a store', () => {
  assert.equal(ps5PageOf('PS5 patch notes: https://example.com/news/1-2\nhttps://youtu.be/x'), 'https://example.com/news/1-2')
  assert.equal(ps5PageOf('<a href="https://example.com/ps5-update">notes</a>'), 'https://example.com/ps5-update')
  assert.equal(ps5PageOf('[url=https://store.playstation.com/x]Buy on PS5[/url] [url=https://example.com/blog]Dev blog[/url]'), null)
})
