import assert from 'node:assert/strict'
import { mkdtempSync, readFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { test } from 'node:test'
import { confirmPlatform } from '../src/confirm.ts'
import { openDb } from '../src/db.ts'
import { exportStatic } from '../src/export.ts'
import { registry } from '../src/registry.ts'
import { runIngest, seedGames } from '../src/ingest/pipeline.ts'
import { fakeFetch, rss } from './helpers.ts'

test('static feed: index, per-game files, latest and review, stable across quiet runs', async () => {
  const db = openDb(':memory:')
  const fetchFn = fakeFetch({
    'https://blog.playstation.com/feed/': rss([{ title: 'Black Myth: Wukong Update 1.2 detailed for PS5', link: 'https://blog.playstation.com/wukong', date: '2026-10-20T10:00:00Z', body: '<ul><li>Added new boss</li></ul>' }]),
  })
  const deps = { db, fetchFn, igdb: null }
  await seedGames(deps)
  await runIngest(deps)
  const out = mkdtempSync(join(tmpdir(), 'feed-'))
  const read = (p: string) => JSON.parse(readFileSync(join(out, 'v1', p), 'utf8'))

  exportStatic(db, out)
  const index = read('index.json')
  assert.equal(index.games.length, Object.keys(registry.games).length)
  assert.equal(index.games.find((g: any) => g.id === 'wukong').latestReleaseId, 'wukong@1.2')
  assert.equal(read('games/wukong.json').releases[0].platforms[0].verification, 'pending')
  assert.equal(read('review.json').items[0].releaseId, 'wukong@1.2')
  assert.equal(read('latest.json').releases.length, 1)

  const before = readFileSync(join(out, 'v1', 'index.json'), 'utf8')
  await runIngest(deps, { force: true })
  exportStatic(db, out)
  assert.equal(readFileSync(join(out, 'v1', 'index.json'), 'utf8'), before)

  confirmPlatform(db, 'wukong@1.2', 'ps5', { sourceId: 'playstation-blog' })
  exportStatic(db, out)
  assert.equal(read('games/wukong.json').releases[0].platforms[0].verification, 'official')
  assert.equal(read('review.json').items.length, 0)
})

// copy-untracked-no-updates-yet (Terry's Astro Bot, beta 3): a registry game with no patch source is listed in the index (its page
// still needs its basics), but the app must not say "No updates yet. Checked…" for it. The index says so with `patchSource: false`;
// every game with a source leaves the key out.
test('static feed: a game with no patch source is marked patchSource false in the index', async () => {
  const db = openDb(':memory:')
  const deps = { db, fetchFn: fakeFetch({}), igdb: null }
  await seedGames(deps)
  const out = mkdtempSync(join(tmpdir(), 'feed-'))
  exportStatic(db, out)
  const index = JSON.parse(readFileSync(join(out, 'v1', 'index.json'), 'utf8'))
  const sourceless = Object.entries(registry.games).filter(([, g]) => g.sources.length === 0).map(([id]) => id)
  assert.ok(sourceless.includes('astro-bot'), 'astro-bot has no patch source in the registry')
  for (const g of index.games) {
    if (sourceless.includes(g.id)) assert.equal(g.patchSource, false, `${g.id} is marked`)
    else assert.equal('patchSource' in g, false, `${g.id} has a source and carries no key`)
  }
})
