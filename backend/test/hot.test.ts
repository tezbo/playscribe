import assert from 'node:assert/strict'
import { test } from 'node:test'
import { openDb } from '../src/db.ts'
import { hotGameIds, launchingGameIds, HOT_MAX } from '../src/hot.ts'
import { trackedGames } from '../src/ingest/pipeline.ts'
import * as store from '../src/store.ts'

const at = new Date('2026-11-20T12:00:00Z')
const seed = (db: ReturnType<typeof openDb>) => {
  store.upsertAutoGame(db, { id: 'launch-today', name: 'Launch Today', steamAppId: 1, ps5Release: '2026-11-20' })
  store.upsertAutoGame(db, { id: 'launch-soon', name: 'Launch Soon', steamAppId: 2, ps5Release: '2026-11-22' })
  store.upsertAutoGame(db, { id: 'launched-last-week', name: 'Launched Last Week', steamAppId: 3, ps5Release: '2026-11-13' })
  store.upsertAutoGame(db, { id: 'launched-long-ago', name: 'Launched Long Ago', steamAppId: 4, ps5Release: '2026-11-12' })
  store.upsertAutoGame(db, { id: 'launch-later', name: 'Launch Later', steamAppId: 5, ps5Release: '2026-11-23' })
  store.upsertAutoGame(db, { id: 'launch-month', name: 'Launch This Month', steamAppId: 6, ps5Release: '2026-11-01', ps5ReleasePrecision: 'month' })
  store.upsertAutoGame(db, { id: 'launch-no-steam', name: 'Launch No Steam', ps5Release: '2026-11-20' })
}

test('r060-dayone-patch-watch: a game is launching from 2 days before to 7 days after its exact PS5 day, soonest first', () => {
  const db = openDb(':memory:')
  seed(db)
  assert.deepEqual(launchingGameIds(db, at), ['launched-last-week', 'launch-today', 'launch-soon'])
})

test('r060-dayone-patch-watch: launching games join the hot set after the pinned list and ahead of recent patches', () => {
  const db = openDb(':memory:')
  seed(db)
  const hot = [...hotGameIds(db, at, ['pinned'])]
  assert.deepEqual(hot, ['pinned', 'launched-last-week', 'launch-today', 'launch-soon'])
  assert.equal(hotGameIds(db, at, Array.from({ length: HOT_MAX }, (_, i) => `p${i}`)).size, HOT_MAX)
})

test('r060-dayone-patch-watch: a derived game in its launch window is tracked without waiting for the auto slice', () => {
  const db = openDb(':memory:')
  seed(db)
  const ids = trackedGames(db, at).map((g) => g.id)
  assert.ok(ids.includes('launch-today') && ids.includes('launch-soon') && ids.includes('launched-last-week'))
  assert.ok(!ids.includes('launched-long-ago') && !ids.includes('launch-month') && !ids.includes('launch-no-steam'))
})
