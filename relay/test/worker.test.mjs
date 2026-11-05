import assert from 'node:assert/strict'
import { test } from 'node:test'
import worker from '../worker.js'

// A KV that counts writes, because the free plan allows 1,000 a day and a relaunch must not spend any.
const fakeKv = () => {
  const m = new Map()
  const kv = {
    writes: 0,
    get: async (k) => m.get(k) ?? null,
    put: async (k, v) => { kv.writes++; m.set(k, v) },
    delete: async (k) => { kv.writes++; m.delete(k) },
    list: async ({ prefix = '', limit = 1000, cursor } = {}) => {
      const all = [...m.keys()].filter((k) => k.startsWith(prefix)).sort()
      const start = cursor ? Number(cursor) : 0
      const keys = all.slice(start, start + limit).map((name) => ({ name }))
      const done = start + limit >= all.length
      return { keys, list_complete: done, cursor: done ? undefined : String(start + limit) }
    },
  }
  return kv
}
const ADMIN = 'admin-secret'
const setup = () => ({ env: { KV: fakeKv(), ADMIN_TOKEN: ADMIN } })
const call = (env, method, path, body, key) =>
  worker.fetch(new Request(`https://relay.test${path}`, { method, headers: { 'content-type': 'application/json', ...(key ? { authorization: `Bearer ${key}` } : {}) }, body: body === undefined ? undefined : JSON.stringify(body) }), env)
const token = (c) => c.repeat(64)

test('register: returns an id and a key, stores follows as sent, never resolves them', async () => {
  const { env } = setup()
  const r = await call(env, 'POST', '/v1/devices', { apnsToken: token('a'), environment: 'production', follows: [{ gameId: 'dawnwalker', notify: 'major' }, { igdbId: 1234 }] })
  assert.equal(r.status, 201)
  const b = await r.json()
  assert.ok(b.deviceId && b.deviceKey)
  assert.deepEqual(b.follows, [{ gameId: 'dawnwalker', notify: 'major' }, { igdbId: 1234, notify: 'all' }])
})

test('register: the same token again is the same device and spends no writes when nothing changed', async () => {
  const { env } = setup()
  const body = { apnsToken: token('a'), environment: 'production', follows: [{ gameId: 'dawnwalker', notify: 'all' }] }
  const first = await (await call(env, 'POST', '/v1/devices', body)).json()
  const writes = env.KV.writes
  const again = await call(env, 'POST', '/v1/devices', body)
  assert.equal(again.status, 200)
  const b = await again.json()
  assert.equal(b.deviceId, first.deviceId)
  assert.equal(b.deviceKey, first.deviceKey)
  assert.equal(env.KV.writes, writes)
  // A changed follow list is one write.
  await call(env, 'POST', '/v1/devices', { ...body, follows: [] })
  assert.equal(env.KV.writes, writes + 1)
})

test('register: rejects a bad token, environment, quiet hours and follows', async () => {
  const { env } = setup()
  assert.equal((await call(env, 'POST', '/v1/devices', { environment: 'production' })).status, 400)
  assert.equal((await call(env, 'POST', '/v1/devices', { apnsToken: 'nothex' })).status, 400)
  assert.equal((await call(env, 'POST', '/v1/devices', { apnsToken: token('a'), environment: 'staging' })).status, 400)
  assert.equal((await call(env, 'POST', '/v1/devices', { apnsToken: token('a'), quietHours: { from: 60, until: 60, timeZone: 'Australia/Sydney' } })).status, 400)
  assert.equal((await call(env, 'POST', '/v1/devices', { apnsToken: token('a'), quietHours: { from: 60, until: 120, timeZone: 'Not/AZone' } })).status, 400)
  assert.equal((await call(env, 'POST', '/v1/devices', { apnsToken: token('a'), follows: [{ gameId: 'x', notify: 'loud' }] })).status, 400)
  assert.equal((await call(env, 'POST', '/v1/devices', { apnsToken: token('a'), follows: 'x' })).status, 400)
})

test('patch: quiet hours set and cleared, needs the device key', async () => {
  const { env } = setup()
  const { deviceKey } = await (await call(env, 'POST', '/v1/devices', { apnsToken: token('a') })).json()
  assert.equal((await call(env, 'PATCH', '/v1/devices/me', { quietHours: null })).status, 401)
  assert.equal((await call(env, 'PATCH', '/v1/devices/me', { quietHours: null }, 'wrong')).status, 401)
  const quiet = { from: 22 * 60, until: 7 * 60, timeZone: 'Australia/Sydney' }
  assert.equal((await call(env, 'PATCH', '/v1/devices/me', { quietHours: quiet }, deviceKey)).status, 200)
  const page = await (await call(env, 'GET', '/admin/devices', undefined, ADMIN)).json()
  assert.deepEqual(page.devices[0].quiet, quiet)
  await call(env, 'PATCH', '/v1/devices/me', { quietHours: null }, deviceKey)
  const after = await (await call(env, 'GET', '/admin/devices', undefined, ADMIN)).json()
  assert.equal(after.devices[0].quiet, null)
})

test('follows: PUT replaces, GET reads', async () => {
  const { env } = setup()
  const { deviceKey } = await (await call(env, 'POST', '/v1/devices', { apnsToken: token('a') })).json()
  const put = await call(env, 'PUT', '/v1/devices/me/follows', { follows: [{ gameId: 'yotei', notify: 'off' }] }, deviceKey)
  assert.deepEqual((await put.json()).follows, [{ gameId: 'yotei', notify: 'off' }])
  const got = await (await call(env, 'GET', '/v1/devices/me/follows', undefined, deviceKey)).json()
  assert.deepEqual(got.follows, [{ gameId: 'yotei', notify: 'off' }])
})

test('a token moves to the newest registration through a patch: the old holder is gone', async () => {
  const { env } = setup()
  const a = await (await call(env, 'POST', '/v1/devices', { apnsToken: token('a') })).json()
  const b = await (await call(env, 'POST', '/v1/devices', { apnsToken: token('b') })).json()
  await call(env, 'PATCH', '/v1/devices/me', { apnsToken: token('a') }, b.deviceKey)
  assert.equal((await call(env, 'GET', '/v1/devices/me/follows', undefined, a.deviceKey)).status, 401)
  const page = await (await call(env, 'GET', '/admin/devices', undefined, ADMIN)).json()
  assert.deepEqual(page.devices.map((d) => [d.id, d.token]), [[b.deviceId, token('a')]])
})

test('admin: needs the admin token, pages 40 at a time, never exposes a device key', async () => {
  const { env } = setup()
  for (let i = 0; i < 45; i++) await call(env, 'POST', '/v1/devices', { apnsToken: i.toString(16).padStart(64, '0') })
  assert.equal((await call(env, 'GET', '/admin/devices')).status, 401)
  assert.equal((await call(env, 'GET', '/admin/devices', undefined, 'nope')).status, 401)
  assert.equal((await call({ KV: env.KV }, 'GET', '/admin/devices', undefined, ADMIN)).status, 401, 'no ADMIN_TOKEN configured means closed')
  const p1 = await (await call(env, 'GET', '/admin/devices', undefined, ADMIN)).json()
  assert.equal(p1.devices.length, 40)
  assert.ok(p1.cursor)
  const p2 = await (await call(env, 'GET', `/admin/devices?cursor=${p1.cursor}`, undefined, ADMIN)).json()
  assert.equal(p2.devices.length, 5)
  assert.equal(p2.cursor, null)
  assert.ok(!JSON.stringify([p1, p2]).includes('"key"'))
})

test('unknown routes 404, health is open, oversize bodies are refused', async () => {
  const { env } = setup()
  assert.equal((await call(env, 'GET', '/health')).status, 200)
  assert.equal((await call(env, 'GET', '/nope')).status, 404)
  assert.equal((await call(env, 'POST', '/v1/devices', { apnsToken: token('a'), pad: 'x'.repeat(70 * 1024) })).status, 413)
})
