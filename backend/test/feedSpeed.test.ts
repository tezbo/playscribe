import assert from 'node:assert/strict'
import { test } from 'node:test'
import { openDb } from '../src/db.ts'
import { DROP_PRE_LAUNCH_PS5_SQL } from '../src/store.ts'

// feed-hot-run-slow (B1, 0.5.5): every run ends with passes over the whole database. dropPreLaunchPs5 read every release
// once for each PS5 row (a correlated IN list, about 25,000 x 41,000 rows on the 12 Nov feed), so a hot run that polled
// one source spent most of its 18 minutes there. Each PS5 row must look up its own release by id instead.
test('the pre-launch PS5 pass looks up each row\'s release by id, never scanning every release per row', () => {
  const db = openDb(':memory:')
  const plan = (db.prepare(`EXPLAIN QUERY PLAN ${DROP_PRE_LAUNCH_PS5_SQL}`).all('2020-11-12', '2020-11-12') as { detail: string }[]).map((r) => r.detail)
  assert.ok(!plan.some((d) => /^SCAN r\b/.test(d)), plan.join('\n'))
  assert.ok(plan.some((d) => /^SEARCH r USING (INDEX|PRIMARY KEY|INTEGER PRIMARY KEY)/.test(d)), plan.join('\n'))
})
