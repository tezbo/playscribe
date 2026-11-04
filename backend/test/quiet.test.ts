// r050-quiet-hours-push, relay side: a device inside its registered window gets a passive, silent push.
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { confirmPlatform } from '../src/confirm.ts'
import { openDb } from '../src/db.ts'
import { runIngest, seedGames } from '../src/ingest/pipeline.ts'
import { inQuietHours, parseQuietHours } from '../src/push/quiet.ts'
import { pushPs5Release } from '../src/push/notify.ts'
import type { Apns } from '../src/push/apns.ts'
import { createApp } from '../src/server.ts'
import { fakeFetch, rss } from './helpers.ts'

const at = (iso: string) => new Date(iso)

test('window maths: same-day, across midnight, edges, and the zone (including daylight saving)', () => {
  const day = { from: 9 * 60, until: 17 * 60, timeZone: 'UTC' }
  assert.equal(inQuietHours(day, at('2026-11-04T09:00:00Z')), true)
  assert.equal(inQuietHours(day, at('2026-11-04T16:59:00Z')), true)
  assert.equal(inQuietHours(day, at('2026-11-04T17:00:00Z')), false)
  const night = { from: 22 * 60, until: 7 * 60, timeZone: 'UTC' }
  assert.equal(inQuietHours(night, at('2026-11-04T23:30:00Z')), true)
  assert.equal(inQuietHours(night, at('2026-11-04T06:59:00Z')), true)
  assert.equal(inQuietHours(night, at('2026-11-04T07:00:00Z')), false)
  assert.equal(inQuietHours(night, at('2026-11-04T12:00:00Z')), false)
  // 23:30 UTC on 4 Nov is 18:30 in New York (EST) and 23:30 in London (GMT): the zone, not the server clock, decides.
  const ny = { ...night, timeZone: 'America/New_York' }
  assert.equal(inQuietHours(ny, at('2026-11-04T23:30:00Z')), false)
  assert.equal(inQuietHours(ny, at('2026-11-05T03:30:00Z')), true)
  // Daylight saving: 03:30 UTC in July is 23:30 EDT, in January 22:30 EST; both inside 22:00 to 07:00.
  assert.equal(inQuietHours(ny, at('2026-07-05T03:30:00Z')), true)
  assert.equal(inQuietHours(ny, at('2026-01-05T03:30:00Z')), true)
  assert.equal(inQuietHours(ny, at('2026-07-05T01:30:00Z')), false) // 21:30 EDT; would be 20:30 if the offset were stored wrongly
  assert.equal(inQuietHours(null, at('2026-11-04T23:30:00Z')), false)
})

test('quietHours validation: whole minutes, differing ends, a real zone; null clears', () => {
  assert.deepEqual(parseQuietHours({ from: 1320, until: 420, timeZone: 'Europe/London' }), { from: 1320, until: 420, timeZone: 'Europe/London' })
  assert.equal(parseQuietHours(null), null)
  for (const bad of [{ from: 1440, until: 0, timeZone: 'UTC' }, { from: 5, until: 5, timeZone: 'UTC' }, { from: 1.5, until: 3, timeZone: 'UTC' }, { from: 0, until: 60, timeZone: 'Mars/Base' }, { from: 0, until: 60 }, 'x'])
    assert.ok('error' in (parseQuietHours(bad) as object), JSON.stringify(bad))
})

const setup = async () => {
  const db = openDb(':memory:')
  const fetchFn = fakeFetch({
    'https://blog.playstation.com/feed/': rss([{ title: 'Black Myth: Wukong Update 1.2 detailed for PS5', link: 'https://blog.playstation.com/wukong', date: new Date().toISOString(), body: '<ul><li>Added new boss</li></ul>' }]),
  })
  const deps = { db, fetchFn, igdb: null }
  await seedGames(deps)
  await runIngest(deps)
  const app = createApp({ ...deps, apns: null, adminToken: 'secret-admin', pushMaxAgeHours: 72 })
  const call = async (method: string, path: string, body?: unknown, token?: string) => {
    const r = await app.request(path, { method, headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) }, body: body ? JSON.stringify(body) : undefined })
    return { status: r.status, json: r.status === 204 ? null : ((await r.json()) as any) }
  }
  return { db, call }
}

test('PATCH /v1/devices/me stores, keeps and clears the window; bad input is a 400', async () => {
  const { db, call } = await setup()
  const reg = await call('POST', '/v1/devices', { apnsToken: 'ab'.repeat(32), environment: 'sandbox' })
  const key = reg.json.deviceKey
  const row = () => db.prepare('SELECT quiet_from, quiet_until, quiet_tz FROM devices WHERE id = ?').get(reg.json.deviceId) as any
  assert.deepEqual({ ...row() }, { quiet_from: null, quiet_until: null, quiet_tz: null })
  assert.equal((await call('PATCH', '/v1/devices/me', { quietHours: { from: 1320, until: 420, timeZone: 'Europe/London' } }, key)).status, 200)
  assert.deepEqual({ ...row() }, { quiet_from: 1320, quiet_until: 420, quiet_tz: 'Europe/London' })
  await call('PATCH', '/v1/devices/me', { locale: 'en-GB' }, key) // absent field leaves it alone
  assert.equal(row().quiet_tz, 'Europe/London')
  assert.equal((await call('PATCH', '/v1/devices/me', { quietHours: { from: 5, until: 5, timeZone: 'UTC' } }, key)).status, 400)
  assert.equal((await call('PATCH', '/v1/devices/me', { quietHours: null }, key)).status, 200)
  assert.deepEqual({ ...row() }, { quiet_from: null, quiet_until: null, quiet_tz: null })
  const withWindow = await call('POST', '/v1/devices', { apnsToken: 'cd'.repeat(32), quietHours: { from: 60, until: 120, timeZone: 'UTC' } })
  assert.equal(withWindow.status, 201)
})

test('push: a device inside its window gets passive and no sound; others and unregistered devices are unchanged', async () => {
  const { db } = await setup()
  const id = (db.prepare("SELECT id FROM releases WHERE game_id = 'wukong'").get() as { id: string }).id
  const t = new Date().toISOString()
  const mins = (new Date().getUTCHours() * 60) + new Date().getUTCMinutes()
  const inside = { from: (mins + 1440 - 30) % 1440, until: (mins + 30) % 1440 }
  const outside = { from: (mins + 120) % 1440, until: (mins + 180) % 1440 }
  const devs: [string, number | null, number | null][] = [['in', inside.from, inside.until], ['out', outside.from, outside.until], ['none', null, null]]
  for (const [dev, from, until] of devs) {
    db.prepare("INSERT INTO devices (id, key_hash, apns_token, environment, quiet_from, quiet_until, quiet_tz, created_at, updated_at) VALUES (?, ?, ?, 'production', ?, ?, ?, ?, ?)").run(dev, `h${dev}`, dev.padEnd(64, '0'), from, until, from === null ? null : 'UTC', t, t)
    db.prepare("INSERT INTO follows (device_id, game_id, notify) VALUES (?, 'wukong', 'all')").run(dev)
  }
  const sent: Record<string, any> = {}
  const apns = { send: async (token: string, _e: string, payload: any) => ((sent[token.slice(0, 4).replace(/0+$/, '')] = payload), { status: 200 }) } as unknown as Apns
  confirmPlatform(db, id, 'ps5', { sourceId: 'playstation-blog', version: '01.006.000' })
  assert.equal((await pushPs5Release(db, apns, id, { maxAgeHours: 72 })).sent, 3)
  assert.equal(sent.in.aps['interruption-level'], 'passive')
  assert.equal(sent.in.aps.sound, undefined)
  for (const k of ['out', 'none']) {
    assert.equal(sent[k].aps['interruption-level'], 'active')
    assert.equal(sent[k].aps.sound, 'default')
  }
  assert.equal(sent.in.aps.alert.body, sent.none.aps.alert.body, 'same copy; only the level and sound differ')
})
