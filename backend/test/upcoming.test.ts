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

import { moveOf, shorten, trailerOf, withMoves } from '../src/upcoming.ts'

test('upcoming never blank: summary cut at a word, three genres, the trailer, hypes', () => {
  const long = `${'word '.repeat(80)}end`
  const g = upcomingOf({ igdbId: 9, name: 'I', d: '2027-02-02', summary: long, genres: ['A', 'B', 'C', 'D'], videos: [{ video_id: 'v1', name: 'Gameplay' }, { video_id: 'v2', name: 'Announce Trailer' }], hypes: 120 }, today)!
  assert.ok(g.summary!.length <= 301 && g.summary!.endsWith('…') && !g.summary!.includes('wor…'))
  assert.deepEqual([g.genres, g.trailerId, g.hypes], [['A', 'B', 'C'], 'v2', 120])
  assert.equal(shorten('Short text.'), 'Short text.')
  assert.equal(trailerOf([{ video_id: 'x', name: 'Interview' }]), 'x')
  assert.equal(trailerOf(undefined), undefined)
  const bare = upcomingOf({ igdbId: 10, name: 'J', d: '2027-02-02' }, today)!
  assert.deepEqual(Object.keys(bare).sort(), ['datePrecision', 'date', 'igdbId', 'name', 'status'].sort())
})

test('upcoming date moved: delayed, earlier, dated; narrowing a vague date is not a move; a move shows for 14 days', () => {
  const day = (date: string, id = 1) => upcomingOf({ igdbId: id, name: 'K', d: date }, today)!
  const q = (date: string) => upcomingOf({ igdbId: 1, name: 'K', d: date, q: 'quarter' }, today)!
  assert.equal(moveOf(day('2027-06-01'), day('2027-03-01'), today)?.kind, 'delayed')
  assert.equal(moveOf(day('2027-02-01'), day('2027-03-01'), today)?.kind, 'earlier')
  assert.deepEqual(moveOf(day('2027-06-01'), day('2027-03-01'), today), { kind: 'delayed', previousDate: '2027-03-01', previousPrecision: 'day', movedAt: today })
  assert.equal(moveOf(q('2027-06-30'), day('2027-03-01'), today)?.kind, 'delayed')
  assert.equal(moveOf(day('2027-03-01'), q('2027-03-31'), today)?.kind, 'dated')
  assert.equal(moveOf(upcomingOf({ igdbId: 1, name: 'K', q: 'tbd' }, today)!, day('2027-03-01'), today)?.kind, 'delayed')
  // "Q4" to "November": the date firming up, not a delay or an earlier date.
  assert.equal(moveOf(upcomingOf({ igdbId: 1, name: 'K', d: '2026-11-30', q: 'month' }, today)!, upcomingOf({ igdbId: 1, name: 'K', d: '2026-12-31', q: 'quarter' }, today)!, today), undefined)
  assert.equal(moveOf(day('2027-03-01'), day('2027-03-01'), today), undefined)
  // Carried for 14 days, then gone; a new move replaces it.
  const moved = withMoves([day('2027-06-01')], [day('2027-03-01')], '2026-11-03')[0]!
  assert.equal(withMoves([day('2027-06-01')], [moved], '2026-11-10')[0]!.move?.movedAt, '2026-11-03')
  assert.equal(withMoves([day('2027-06-01')], [moved], '2026-11-20')[0]!.move, undefined)
  assert.equal(withMoves([day('2027-09-01')], [moved], '2026-11-10')[0]!.move?.previousDate, '2027-06-01')
  assert.equal(withMoves([day('2027-06-01', 2)], [day('2027-03-01')], today)[0]!.move, undefined)
})
