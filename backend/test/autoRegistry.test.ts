import test from 'node:test'
import assert from 'node:assert/strict'
import { buildAutoRegistry, steamAppIdFromUrl } from '../src/ingest/autoRegistry.ts'

const info = new Map([
  [1, { links: { patchNotes: 'https://store.steampowered.com/news/app/111' } }],
  [2, { links: { patchNotes: 'https://store.steampowered.com/news/app/222' } }],
  [3, { links: { patchNotes: 'https://example.com/notes' } }],
  [4, { links: { patchNotes: 'https://store.steampowered.com/news/app/444' } }],
  [5, { links: { patchNotes: 'https://store.steampowered.com/news/app/111' } }],
  [6, { links: { patchNotes: 'https://store.steampowered.com/news/app/666' } }],
])
const index = [
  { i: 1, n: 'Alpha', d: '2025-01-01' },
  { i: 2, n: 'Hand Game', d: '2025-01-01' },
  { i: 3, n: 'No Steam', d: '2025-01-01' },
  { i: 4, n: 'Future', d: '2027-01-01' },
  { i: 5, n: 'Alpha Twin', d: '2025-01-01' },
  { i: 6, n: 'Port', d: '2025-01-01', p: 'Sony Interactive Entertainment' },
]

test('auto registry: hand wins, unreleased and Steam-less skipped, duplicates dropped, Sony ports flagged', () => {
  const r = buildAutoRegistry(index, info, new Set([2]), new Set(), '2026-11-09')
  assert.deepEqual(r.games.map((g) => g.id), ['alpha-1', 'port-6'])
  assert.deepEqual(r.skipped, { handRegistered: 1, notReleased: 1, noSteam: 1, duplicateApp: 1 })
  assert.equal(r.games[1]!.steamIsPcPort, true)
  assert.equal(r.games[0]!.steamIsPcPort, undefined)
  assert.ok(r.games[0]!.sources[0]!.id.endsWith('-steam'))
  assert.equal(r.games[0]!.sources[0]!.url, 'https://store.steampowered.com/feeds/news/app/111/')
})

test('steamAppIdFromUrl reads store and news urls', () => {
  assert.equal(steamAppIdFromUrl('https://store.steampowered.com/app/3751260/Foo'), '3751260')
  assert.equal(steamAppIdFromUrl('https://example.com/app/1'), undefined)
})
