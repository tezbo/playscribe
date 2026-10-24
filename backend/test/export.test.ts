import assert from 'node:assert/strict'
import { mkdtempSync, readFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { test } from 'node:test'
import { confirmPlatform } from '../src/confirm.ts'
import { openDb } from '../src/db.ts'
import { exportStatic } from '../src/export.ts'
import { runIngest, seedGames } from '../src/ingest/pipeline.ts'
import { fakeFetch, rss } from './helpers.ts'

test('static feed: index, per-game files, latest and review, stable across quiet runs', async () => {
  const db = openDb(':memory:')
  const fetchFn = fakeFetch({
    'https://blog.playstation.com/feed/': rss([{ title: 'Black Myth: Wukong Update 1.2 out now on PS5', link: 'https://blog.playstation.com/wukong', date: '2026-10-20T10:00:00Z', body: '<ul><li>Added new boss</li></ul>' }]),
  })
  const deps = { db, fetchFn, igdb: null }
  await seedGames(deps)
  await runIngest(deps)
  const out = mkdtempSync(join(tmpdir(), 'feed-'))
  const read = (p: string) => JSON.parse(readFileSync(join(out, 'v1', p), 'utf8'))

  exportStatic(db, out)
  const index = read('index.json')
  assert.equal(index.games.length, 5)
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
