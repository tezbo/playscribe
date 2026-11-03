import assert from 'node:assert/strict'
import { mkdtempSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { test } from 'node:test'
import { openDb } from '../src/db.ts'
import { exportStatic } from '../src/export.ts'
import { failingSources, healthSummary } from '../src/health.ts'
import { runIngest, seedGames } from '../src/ingest/pipeline.ts'
import { coverageProblems, feedProblems, releaseProblems } from '../src/quality.ts'
import { registry } from '../src/registry.ts'
import { fakeFetch } from './helpers.ts'

test('roadmap feed health: a source failing three polls in a row is reported, and a good poll clears it', async () => {
  const db = openDb(':memory:')
  const deps = { db, fetchFn: fakeFetch({ 'https://': { status: 500 } }), igdb: null }
  await seedGames(deps)
  for (let i = 0; i < 2; i++) await runIngest(deps, { force: true })
  assert.deepEqual(failingSources(db), [])
  await runIngest(deps, { force: true })
  const sick = failingSources(db)
  assert.ok(sick.length > 0 && sick.every((s) => s.failStreak >= 3))
  assert.match(healthSummary(sick), /failed 3 or more polls in a row/)
  assert.equal(healthSummary([]), '')
  db.prepare('UPDATE source_state SET fail_streak = 0').run()
  assert.deepEqual(failingSources(db), [])
})

test('data quality: no PC version shown as PS5, no source names in user-facing text', () => {
  const ok = { id: 'g@1', displayName: 'Update 1.1', platforms: [{ platform: 'ps5', version: { value: '1.1' } }, { platform: 'pc', version: { value: '1.2' } }], notes: [{ title: 'Fixes', items: [{ text: 'Fixed a crash' }] }] }
  assert.deepEqual(releaseProblems(ok), [])
  const same = { ...ok, platforms: [{ platform: 'ps5', version: { value: '1.2' } }, { platform: 'pc', version: { value: '1.2' } }] }
  assert.equal(releaseProblems(same).length, 1)
  const named = { ...ok, notes: [{ title: 'Fixes', items: [{ text: 'Via Push Square: fixed a crash' }] }] }
  assert.equal(releaseProblems(named).length, 1)
})

test('data quality: every indexed game has a release or an official link; link-only games are covered', async () => {
  assert.deepEqual(coverageProblems({ games: [{ id: 'nope', releaseCount: 0 }, { id: 'x', releaseCount: 2 }] }), ['nope: no release and no official site or patch-notes link'])
  for (const id of ['death-stranding-2', 'ff16', 'ff7-rebirth', 'ghost-of-tsushima', 'spider-man-2', 'stellar-blade', 'minecraft', 'rocket-league', 'valorant', 'fortnite', 'astro-bot', 'gt7', 'yotei', 'wolverine', 'alan-wake-2', 'genshin-impact']) {
    const l = registry.games[id]?.links
    assert.ok(l?.official?.startsWith('https://'), id)
    if (!['death-stranding-2', 'ff16', 'ff7-rebirth', 'ghost-of-tsushima', 'spider-man-2', 'stellar-blade'].includes(id)) assert.ok(l?.patchNotes?.startsWith('https://'), id)
  }
  const db = openDb(':memory:')
  const deps = { db, fetchFn: fakeFetch({}), igdb: null }
  await seedGames(deps)
  const out = mkdtempSync(`${tmpdir()}/q-`)
  exportStatic(db, out)
  assert.deepEqual(feedProblems(out), [])
})
