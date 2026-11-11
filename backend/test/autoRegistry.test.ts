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

import { mkdtempSync, readdirSync, readFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { openDb } from '../src/db.ts'
import { exportStatic } from '../src/export.ts'
import { runIngest, seedGames } from '../src/ingest/pipeline.ts'
import { seedAutoGames, type AutoGame } from '../src/ingest/autoRegistry.ts'
import * as store from '../src/store.ts'
import { fakeFetch, steamNews } from './helpers.ts'

const auto = (id: string, app: number, extra: Partial<AutoGame> = {}): AutoGame => ({
  id, steamAppId: app, name: id, igdbId: Number(id.replace(/\D/g, '')) || 1, ps5TitleIds: [], ps5Release: '2024-01-01',
  sources: [{ id: `auto-${app}-steam`, kind: 'steamNews', url: `https://store.steampowered.com/feeds/news/app/${app}/`, platforms: ['pc'], trust: 'official', fetch: 'auto', ps5Signal: 'explicit' }],
  ...extra,
})

test('auto games: polled in a slice, published only once they have a release, never over a hand game', async () => {
  const db = openDb(':memory:')
  const recent = new Date(Date.now() - 3600_000 * 5).toISOString()
  const fetchFn = fakeFetch({
    'https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=111': steamNews([{ gid: 'a1', title: 'Patch 1.2', date: recent, contents: 'Patch 1.2 is live.[list][*]Fixed a crash[/list]', tags: ['patchnotes'] }]),
    'https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=333': steamNews([{ gid: 'c1', title: 'Patch 2.0', date: recent, contents: 'PC patch.[list][*]Fixed shaders[/list]', tags: ['patchnotes'] }]),
  })
  const deps = { db, fetchFn, igdb: null }
  await seedGames(deps)
  // A hand game's id is never taken over by an auto entry.
  assert.equal(store.upsertAutoGame(db, { id: 'dawnwalker', name: 'Impostor', steamAppId: 1 }), false)
  assert.equal(store.getGameRow(db, 'dawnwalker')!.name, 'The Blood of Dawnwalker')
  assert.equal(seedAutoGames(db, [auto('alpha-1', 111), auto('quiet-2', 222), auto('port-3', 333, { steamIsPcPort: true })]), 3)

  // Slice of 2, never-polled first (by id), so alpha and port are polled; quiet waits for the next run.
  const s1 = await runIngest(deps, { autoSlice: 2 })
  assert.equal(s1.auto, 2)
  assert.ok(store.getGameRow(db, 'quiet-2')!.auto_polled_at == null)
  const alpha = store.getRelease(db, 'alpha-1@1.2')!
  assert.equal(alpha.platforms.find((p) => p.platform === 'ps5')?.verification, 'assumed')
  // A Sony PC port's Steam patch says nothing about PS5.
  assert.equal(store.getRelease(db, 'port-3@2.0')!.platforms.some((p) => p.platform === 'ps5'), false)

  // Next run rotates to the one not yet polled.
  const s2 = await runIngest(deps, { autoSlice: 1, force: true })
  assert.equal(s2.auto, 1)
  assert.ok(store.getGameRow(db, 'quiet-2')!.auto_polled_at != null)

  // Export: auto games with a release are in the index and have a game file, the quiet one is absent, and none has a news file.
  const out = mkdtempSync(join(tmpdir(), 'auto-export-'))
  exportStatic(db, out)
  const index = JSON.parse(readFileSync(join(out, 'v1', 'index.json'), 'utf8')).games.map((g: { id: string }) => g.id)
  assert.ok(index.includes('alpha-1') && index.includes('port-3') && index.includes('dawnwalker'))
  assert.ok(!index.includes('quiet-2'))
  const files = readdirSync(join(out, 'v1', 'games'))
  assert.ok(files.includes('alpha-1.json') && !files.includes('quiet-2.json'))
  assert.ok(!readdirSync(join(out, 'v1', 'news')).includes('alpha-1.json'))

  // Hot runs and backfills never touch the slice; a zero budget stops it before the first game.
  assert.equal((await runIngest(deps, { autoSlice: 5, hot: true })).auto, undefined)
  assert.equal((await runIngest(deps, { autoSlice: 5, force: true, autoBudgetMs: -1 })).autoStopped, true)
})
