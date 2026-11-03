import assert from 'node:assert/strict'
import { test } from 'node:test'
import { releaseDayEvents, shardOf, shardsOf, statusOf, upcomingOf } from '../src/upcoming.ts'

const today = '2026-11-03'

test('roadmap 14: status and precision follow IGDB, and no date is invented', () => {
  assert.equal(statusOf('2027-03-05', 'day', today), 'dated')
  assert.equal(statusOf('2026-11-03', 'day', today), 'released')
  assert.equal(statusOf('2027-12-31', 'quarter', today), 'announced')
  assert.equal(statusOf(undefined, 'tbd', today), 'announced')
  const tbd = upcomingOf({ igdbId: 1, name: 'A', q: 'tbd' }, today)!
  assert.deepEqual([tbd.date, tbd.datePrecision, tbd.status], [undefined, 'tbd', 'announced'])
  const q = upcomingOf({ igdbId: 2, name: 'B', d: '2027-12-31', q: 'quarter' }, today)!
  assert.deepEqual([q.date, q.datePrecision, q.status], ['2027-12-31', 'quarter', 'announced'])
  assert.equal(upcomingOf({ igdbId: 3, name: 'C' }, today), null)
})

test('roadmap 14: old releases drop out; recent ones stay for the release-day event', () => {
  assert.equal(upcomingOf({ igdbId: 4, name: 'D', d: '2026-10-01' }, today), null)
  assert.equal(upcomingOf({ igdbId: 5, name: 'E', d: '2026-03-31', q: 'quarter' }, today), null)
  const fresh = upcomingOf({ igdbId: 6, name: 'F', d: '2026-11-02' }, today)!
  assert.equal(fresh.status, 'released')
  const future = upcomingOf({ igdbId: 7, name: 'G', d: '2026-11-20' }, today)!
  assert.deepEqual(releaseDayEvents([fresh, future], today), [{ igdbId: 6, name: 'F', date: '2026-11-02' }])
  assert.deepEqual(releaseDayEvents([fresh], '2026-11-10'), [])
})

test('roadmap 14: shards are igdbId % 10', () => {
  const g = upcomingOf({ igdbId: 4321, name: 'H', d: '2027-01-01' }, today)!
  assert.equal(shardOf(4321), 1)
  assert.deepEqual(Object.keys(shardsOf([g])[1]!), ['4321'])
})
