import assert from 'node:assert/strict'
import { test } from 'node:test'
import worker, { MAX_NEW_PER_DAY } from '../worker.js'

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

// ---- Team alerts ----
const hmacHex = async (secret, body) => {
  const k = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'])
  return [...new Uint8Array(await crypto.subtle.sign('HMAC', k, new TextEncoder().encode(body)))].map((b) => b.toString(16).padStart(2, '0')).join('')
}
const hook = async (env, body, sig) => worker.fetch(new Request('https://relay.test/v1/webhooks/asc', { method: 'POST', headers: sig ? { 'x-apple-signature': sig } : {}, body }), env)

test('team flag: stored on register, changed by PATCH, shown to the admin and nowhere else', async () => {
  const { env } = setup()
  const b = await (await call(env, 'POST', '/v1/devices', { apnsToken: token('b'), team: true })).json()
  assert.equal(b.team, undefined)
  const list = async () => (await (await worker.fetch(new Request('https://relay.test/admin/devices', { headers: { authorization: `Bearer ${ADMIN}` } }), env)).json()).devices
  assert.equal((await list())[0].team, true)
  await call(env, 'PATCH', '/v1/devices/me', { team: false }, b.deviceKey)
  assert.equal((await list())[0].team, false)
})

test('webhook fails closed: no secret, no signature or a wrong one is a 401', async () => {
  const body = JSON.stringify({ data: { id: 'e1', attributes: { eventType: 'BETA_FEEDBACK_SCREENSHOT_SUBMISSION_CREATED' } } })
  assert.equal((await hook({ KV: fakeKv() }, body, 'a'.repeat(64))).status, 401)
  const env = { KV: fakeKv(), ASC_WEBHOOK_SECRET: 's3cret' }
  assert.equal((await hook(env, body)).status, 401)
  assert.equal((await hook(env, body, 'f'.repeat(64))).status, 401)
})

test('webhook: a signed feedback event is accepted once, a replay is a duplicate, other events are ignored', async () => {
  const env = { KV: fakeKv(), ASC_WEBHOOK_SECRET: 's3cret' }
  const body = JSON.stringify({ data: { id: 'e1', attributes: { eventType: 'BETA_FEEDBACK_CRASH_SUBMISSION_CREATED' } } })
  const sig = 'hmacsha256=' + (await hmacHex('s3cret', body))
  const first = await (await hook(env, body, sig)).json()
  assert.equal(first.ok, true)
  assert.equal(first.sent, 0) // no push key in this env
  assert.equal((await (await hook(env, body, sig)).json()).duplicate, true)
  const other = JSON.stringify({ data: { id: 'e2', attributes: { eventType: 'BUILD_UPLOAD_STATE_UPDATED' } } })
  assert.equal((await (await hook(env, other, await hmacHex('s3cret', other))).json()).ignored, true)
})

test('webhook: 60 non-team devices and 2 team devices alert exactly the 2, with a bounded number of KV reads', async () => {
  const kv = fakeKv()
  let reads = 0
  const get = kv.get
  kv.get = async (k) => { reads++; return get(k) }
  const env = { KV: kv, ASC_WEBHOOK_SECRET: 's3cret', APNS_KEY: 'x', APNS_KEY_ID: 'k', APNS_TEAM_ID: 't' }
  for (let i = 0; i < 60; i++) await call(env, 'POST', '/v1/devices', { apnsToken: i.toString(16).padStart(2, '0').repeat(32) })
  await call(env, 'POST', '/v1/devices', { apnsToken: 'aa'.repeat(32) + 'bb', team: true })
  await call(env, 'POST', '/v1/devices', { apnsToken: 'cc'.repeat(33), team: true })
  const sent = []
  const realFetch = globalThis.fetch
  globalThis.fetch = async (url) => { sent.push(String(url)); return new Response('', { status: 200 }) }
  try {
    // Stand-in for the signing key: a real P-256 PKCS8 key.
    const kp = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign'])
    const der = new Uint8Array(await crypto.subtle.exportKey('pkcs8', kp.privateKey))
    env.APNS_KEY = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der))}\n-----END PRIVATE KEY-----`
    const body = JSON.stringify({ data: { id: 'big', attributes: { eventType: 'BETA_FEEDBACK_SCREENSHOT_SUBMISSION_CREATED' } } })
    reads = 0
    const r = await (await hook(env, body, await hmacHex('s3cret', body))).json()
    assert.equal(r.sent, 2)
    assert.equal(sent.length, 2)
    assert.ok(reads < 20, `reads ${reads}`)
  } finally {
    globalThis.fetch = realFetch
  }
})

test('register: past the daily cap new devices get 429, existing devices still register', async () => {
  const { env } = setup()
  const hexTok = (i) => i.toString(16).padStart(64, '0')
  for (let i = 0; i < MAX_NEW_PER_DAY; i++) assert.equal((await call(env, 'POST', '/v1/devices', { apnsToken: hexTok(i) })).status, 201)
  const over = await call(env, 'POST', '/v1/devices', { apnsToken: hexTok(MAX_NEW_PER_DAY + 1) })
  assert.equal(over.status, 429)
  assert.ok(over.headers.get('retry-after'))
  assert.equal((await call(env, 'POST', '/v1/devices', { apnsToken: hexTok(0) })).status, 200)
})

test('delete me: removes the record, token, key and team entry, and a second delete is still 204', async () => {
  const { env } = setup()
  const reg = await (await call(env, 'POST', '/v1/devices', { apnsToken: token('a'), team: true, follows: [{ gameId: 'dawnwalker' }] })).json()
  assert.notEqual(await env.KV.get(`d:${reg.deviceId}`), null)
  assert.notEqual(await env.KV.get(`tm:${reg.deviceId}`), null)
  const del = await call(env, 'DELETE', '/v1/devices/me', undefined, reg.deviceKey)
  assert.equal(del.status, 204)
  assert.equal(await env.KV.get(`d:${reg.deviceId}`), null)
  assert.equal(await env.KV.get(`t:${token('a')}`), null)
  assert.equal(await env.KV.get(`tm:${reg.deviceId}`), null)
  // The key no longer works for anything else, and the Feed job sees no device.
  assert.equal((await call(env, 'GET', '/v1/devices/me/follows', undefined, reg.deviceKey)).status, 401)
  const admin = await (await worker.fetch(new Request('https://relay.test/admin/devices', { headers: { authorization: `Bearer ${ADMIN}` } }), env)).json()
  assert.deepEqual(admin.devices, [])
  assert.equal((await call(env, 'DELETE', '/v1/devices/me', undefined, reg.deviceKey)).status, 204)
})

test('delete me: needs a key, leaves other devices alone, and a re-registration is a new device', async () => {
  const { env } = setup()
  const a = await (await call(env, 'POST', '/v1/devices', { apnsToken: token('a') })).json()
  const b = await (await call(env, 'POST', '/v1/devices', { apnsToken: token('b') })).json()
  assert.equal((await call(env, 'DELETE', '/v1/devices/me')).status, 401)
  await call(env, 'DELETE', '/v1/devices/me', undefined, a.deviceKey)
  assert.notEqual(await env.KV.get(`d:${b.deviceId}`), null)
  const again = await (await call(env, 'POST', '/v1/devices', { apnsToken: token('a') })).json()
  assert.notEqual(again.deviceId, a.deviceId)
})
