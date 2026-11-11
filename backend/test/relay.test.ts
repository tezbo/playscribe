import assert from 'node:assert/strict'
import { mkdtempSync, readFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { test } from 'node:test'
import { openDb } from '../src/db.ts'
import { seedGames, trackedGames } from '../src/ingest/pipeline.ts'
import { deviceRows, scrubDevices, syncDevices, type RelayDevice } from '../src/push/relay.ts'
import { fakeFetch } from './helpers.ts'

const dev = (id: string, c: string, over: Partial<RelayDevice> = {}): RelayDevice => ({
  id, token: c.repeat(64), environment: 'production', locale: null, quiet: null, follows: [{ gameId: 'dawnwalker', notify: 'all' }], updated: '2026-11-05T00:00:00.000Z', ...over,
})

test('relay: devices load with their follows and quiet hours; unknown games are counted, not invented', async () => {
  const db = openDb(':memory:')
  await seedGames({ db, fetchFn: fakeFetch({}), igdb: null })
  const r = syncDevices(db, [dev('d1', 'a', { quiet: { from: 1320, until: 420, timeZone: 'Australia/Sydney' }, follows: [{ gameId: 'dawnwalker', notify: 'major' }, { gameId: 'no-such-game', notify: 'all' }] })])
  assert.deepEqual(r, { devices: 1, hourly: 0, follows: 1, unknownFollows: 1 })
  const row = db.prepare('SELECT quiet_from, quiet_until, quiet_tz, environment FROM devices WHERE id = ?').get('d1') as any
  assert.deepEqual([row.quiet_from, row.quiet_until, row.quiet_tz, row.environment], [1320, 420, 'Australia/Sydney', 'production'])
  assert.equal((db.prepare('SELECT notify FROM follows WHERE device_id = ?').get('d1') as any).notify, 'major')
})

test('relay: one token is one device (the newest registration wins) and a second sync replaces the first', async () => {
  const db = openDb(':memory:')
  await seedGames({ db, fetchFn: fakeFetch({}), igdb: null })
  syncDevices(db, [dev('old', 'a', { updated: '2026-11-01T00:00:00.000Z' }), dev('new', 'a', { updated: '2026-11-05T00:00:00.000Z' })])
  assert.deepEqual((db.prepare('SELECT id FROM devices').all() as any[]).map((r) => r.id), ['new'])
  syncDevices(db, [dev('other', 'b')])
  assert.deepEqual((db.prepare('SELECT id FROM devices').all() as any[]).map((r) => r.id), ['other'])
})

test('relay scrub: no device row and no token byte is left in the database file', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'relay-'))
  const path = join(dir, 'state.db')
  const db = openDb(path)
  await seedGames({ db, fetchFn: fakeFetch({}), igdb: null })
  const token = 'c0ffee'.repeat(10) + 'abcd'
  syncDevices(db, [dev('d1', 'a', { token })])
  assert.equal(deviceRows(db), 1)
  scrubDevices(db)
  assert.equal(deviceRows(db), 0)
  db.close()
  assert.ok(!readFileSync(path).includes(token), 'the token must not survive in the file')
})

test('relay: a follow-list opt-in record (no token, ids only) loads, puts its games in the hourly tier, and leaves no token behind', async () => {
  const db = openDb(':memory:')
  await seedGames({ db, fetchFn: fakeFetch({}), igdb: null })
  // A game outside the registry that a device could follow (an auto-onboarded one, say).
  db.prepare("INSERT INTO games (id, name, igdb_id, steam_app_id, auto, created_at) VALUES ('ninja-gaiden-4-1', 'Ninja Gaiden 4', 338121, 2560190, 1, '2026-11-11T00:00:00.000Z')").run()
  const optIn: RelayDevice = { id: 'o1', token: null, environment: null, locale: null, quiet: null, hourly: true, follows: [{ igdbId: 338121 }], updated: '2026-11-11T00:00:00.000Z' }
  const pushOnly = dev('p1', 'a', { follows: [{ gameId: 'dawnwalker', notify: 'all' }, { igdbId: 338121, notify: 'major' }] })
  const r = syncDevices(db, [optIn, pushOnly])
  assert.deepEqual(r, { devices: 2, hourly: 1, follows: 3, unknownFollows: 0 })
  const row = db.prepare('SELECT apns_token, environment, hourly FROM devices WHERE id = ?').get('o1') as any
  assert.deepEqual([row.apns_token, row.environment, row.hourly], [null, 'production', 1])
  assert.equal((db.prepare('SELECT notify FROM follows WHERE device_id = ?').get('o1') as any).notify, 'all')
  assert.ok(trackedGames(db).some((g) => g.id === 'ninja-gaiden-4-1'), 'the opted-in follow is polled hourly')
  // Without the opt-in the same follow addresses alerts only: the game is not tracked.
  syncDevices(db, [pushOnly])
  assert.ok(!trackedGames(db).some((g) => g.id === 'ninja-gaiden-4-1'), 'a push-only follow does not add a game to the hourly tier')
  // Two token-less records are two devices (dedupe is per token).
  syncDevices(db, [optIn, { ...optIn, id: 'o2' }])
  assert.equal(deviceRows(db), 2)
  scrubDevices(db)
  assert.equal(deviceRows(db), 0)
})
