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

test('0.2.0 contract: a feed exported with every release shape decodes; breaking values are caught', async () => {
  const { contractProblems: c } = await import('../src/contract.ts')
  const ok = { id: 'g@1', gameId: 'g', displayName: 'Update 1', kind: 'patch', kindBasis: 'inferred', announcedAt: '2026-10-22T09:17:48.000Z', notes: [{ title: 'Fixes', items: [{ text: 'x', ps5ProOnly: false, pcOnly: false, category: 'fixed', platforms: ['ps5'] }] }], sourceIds: ['s'], links: { steamNotes: 'https://store.steampowered.com/news/app/1' }, platforms: [{ platform: 'ps5', status: 'live', version: null, sizeBytes: { value: 100, verification: 'assumed', sourceId: 's', checkedAt: '2026-10-22T09:17:48.000Z' }, liveAt: null, bundles: [], verification: 'assumed', alert: { style: 'standard', from: '2026-10-22T09:17:48.000Z' } }] }
  assert.deepEqual(c.release(ok), [])
  assert.equal(c.release({ ...ok, kind: 'update' }).length, 1)
  assert.equal(c.release({ ...ok, notes: [{ title: 't', items: [{ text: 'x', platforms: ['ps4'] }] }] }).length, 1)
  assert.equal(c.release({ ...ok, links: { steamNotes: '' } }).length, 1)
  assert.equal(c.release({ ...ok, platforms: [{ ...ok.platforms[0], status: 'delayed' }] }).length, 1)
  assert.equal(c.latest({ updatedAt: null, releases: [] }).length, 1)
  assert.deepEqual(c.info({ games: { '1': { summary: 's', links: { official: 'https://a.example/x' }, similar: [{ igdbId: 2, name: 'n' }] } } }), [])
  assert.equal(c.info({ games: { '1': { links: { official: 'not a url' } } } }).length, 1)
})

test('0.2.0 contract: a malformed IGDB website URL (seen live in info/38) is caught', async () => {
  const { contractProblems: c, isUrl } = await import('../src/contract.ts')
  assert.ok(!isUrl('https://v.douyin.com/iDuoKPNm/ 8@4.com'))
  assert.ok(isUrl('https://www.minecraft.net/en-us'))
  assert.equal(c.info({ games: { '296238': { links: { official: 'https://v.douyin.com/iDuoKPNm/ 8@4.com' } } } }).length, 1)
})

test('notes never name a source: a quoting line is dropped, a heading becomes Changes, an emptied section goes', async () => {
  const { tagNotes } = await import('../src/ingest/notes.ts')
  const out = tagNotes([
    { title: 'Fixes', items: [{ text: 'Fixed a crash', pcOnly: false, category: 'fixed' }, { text: '"Best shooter of the year" - Gamespot', pcOnly: false, category: 'other' }] },
    { title: 'IGN review', items: [{ text: 'Added a lobby', pcOnly: false, category: 'new' }] },
    { title: 'Press', items: [{ text: 'Eurogamer says hello', pcOnly: false, category: 'other' }] },
  ] as any)
  assert.deepEqual(out.map((s) => [s.title, s.items.map((i) => i.text)]), [['Fixes', ['Fixed a crash']], ['Changes', ['Added a lobby']]])
  assert.deepEqual(releaseProblems({ id: 'x@1', displayName: 'Update 1', notes: out, platforms: [] }), [])
})
