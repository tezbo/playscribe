import assert from 'node:assert/strict'
import { test } from 'node:test'
import worker, { FOLLOWS_TTL_SECONDS, MAX_NEW_PER_DAY, dispatchFeed, FEED_HOT_CRON, FEED_FULL_CRON, parseBlocklist } from '../worker.js'

// A KV that counts writes, because the free plan allows 1,000 a day and a relaunch must not spend any.
const fakeKv = () => {
  const m = new Map()
  const kv = {
    writes: 0,
    raw: m,
    ttl: new Map(), // key -> expirationTtl of its last write, so a test can see which records expire
    get: async (k) => m.get(k) ?? null,
    put: async (k, v, opts) => { kv.writes++; m.set(k, v); kv.ttl.set(k, opts?.expirationTtl ?? null) },
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

test('register: a per-address limit refuses new devices from one address, never a known device, and counts per address', async () => {
  const { env } = setup()
  const seen = {}
  env.REGISTER_LIMIT = { limit: async ({ key }) => ({ success: (seen[key] = (seen[key] ?? 0) + 1) <= 2 }) }
  const hexTok = (i) => i.toString(16).padStart(64, '0')
  const from = (ip, i) => worker.fetch(new Request('https://relay.test/v1/devices', { method: 'POST', headers: { 'content-type': 'application/json', 'cf-connecting-ip': ip }, body: JSON.stringify({ apnsToken: hexTok(i) }) }), env)
  assert.equal((await from('1.1.1.1', 1)).status, 201)
  assert.equal((await from('1.1.1.1', 2)).status, 201)
  const over = await from('1.1.1.1', 3)
  assert.equal(over.status, 429)
  assert.equal(over.headers.get('retry-after'), '60')
  assert.equal((await from('2.2.2.2', 4)).status, 201) // another address is untouched
  assert.equal((await from('1.1.1.1', 1)).status, 200) // a known device relaunching is never limited
  assert.equal(seen['1.1.1.1'], 3) // the known device did not spend a count
  assert.equal(await env.KV.get(`t:${hexTok(3)}`), null) // the refused device wrote nothing
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

// ---- 0.5.4 follow-list opt-in: a record without a token, ids only (docs/api.md "Follow list without alerts") ----

test('follows opt-in: POST /v1/follows stores ids and a key, no token, and the record expires in 90 days', async () => {
  const { env } = setup()
  const r = await call(env, 'POST', '/v1/follows', { follows: [{ gameId: 'dawnwalker' }, { igdbId: 329130 }] })
  assert.equal(r.status, 201)
  const b = await r.json()
  assert.deepEqual(Object.keys(b).sort(), ['deviceKey', 'follows'])
  assert.deepEqual(b.follows, [{ gameId: 'dawnwalker' }, { igdbId: 329130 }])
  const page = await (await call(env, 'GET', '/admin/devices', undefined, ADMIN)).json()
  assert.equal(page.devices.length, 1)
  const d = page.devices[0]
  assert.equal(d.token, null)
  assert.equal(d.hourly, true)
  assert.deepEqual(d.follows, [{ gameId: 'dawnwalker' }, { igdbId: 329130 }])
  // The stored record holds nothing but the id, key, follows, flag and two times.
  const stored = JSON.parse(env.KV.raw.get(`d:${d.id}`))
  assert.deepEqual(Object.keys(stored).sort(), ['created', 'follows', 'hourly', 'id', 'key', 'token', 'updated'])
  assert.equal(stored.token, null)
  assert.equal(env.KV.ttl.get(`d:${d.id}`), FOLLOWS_TTL_SECONDS)
  const keyEntry = [...env.KV.raw.keys()].find((k) => k.startsWith('k:'))
  assert.equal(env.KV.ttl.get(keyEntry), FOLLOWS_TTL_SECONDS)
  // It counts as a new device for the day.
  assert.equal(Number(env.KV.raw.get(`n:${new Date().toISOString().slice(0, 10)}`)), 1)
  // A push registration, by contrast, never expires.
  await call(env, 'POST', '/v1/devices', { apnsToken: token('a') })
  const pushKey = [...env.KV.raw.keys()].find((k) => k.startsWith('d:') && k !== `d:${d.id}`)
  assert.equal(env.KV.ttl.get(pushKey), null)
})

test('follows opt-in: anything beyond the ids is refused', async () => {
  const { env } = setup()
  const post = (body) => call(env, 'POST', '/v1/follows', body)
  assert.equal((await post({ follows: [{ gameId: 'dawnwalker' }], locale: 'en-AU' })).status, 400)
  assert.equal((await post({ follows: [{ gameId: 'dawnwalker' }], apnsToken: token('a') })).status, 400)
  assert.equal((await post({ follows: [{ gameId: 'dawnwalker', notify: 'all' }] })).status, 400)
  assert.equal((await post({ follows: [{ gameId: 'dawnwalker', igdbId: 1 }] })).status, 400)
  assert.equal((await post({ follows: [{ name: 'The Witcher 3' }] })).status, 400)
  assert.equal((await post({ follows: [{ igdbId: -1 }] })).status, 400)
  assert.equal((await post({ follows: 'dawnwalker' })).status, 400)
  assert.equal((await post({})).status, 400)
  const { error } = await (await post({ follows: [], team: true, locale: 'en' })).json()
  assert.equal(error, 'only follows may be sent here, not locale, team')
  assert.equal([...env.KV.raw.keys()].filter((k) => k.startsWith('d:')).length, 0)
})

test('follows opt-in: PUT replaces the ids, refuses a notify level, and the weekly "still here" renews the expiry', async () => {
  const { env } = setup()
  const { deviceKey } = await (await call(env, 'POST', '/v1/follows', { follows: [{ gameId: 'dawnwalker' }] })).json()
  const id = [...env.KV.raw.keys()].find((k) => k.startsWith('d:')).slice(2)
  const writes = env.KV.writes
  // Unchanged, within the week: no write at all.
  assert.equal((await call(env, 'PUT', '/v1/devices/me/follows', { follows: [{ gameId: 'dawnwalker' }] }, deviceKey)).status, 200)
  assert.equal(env.KV.writes, writes)
  // A level or an extra field is a 400 on this kind of record.
  assert.equal((await call(env, 'PUT', '/v1/devices/me/follows', { follows: [{ gameId: 'dawnwalker', notify: 'major' }] }, deviceKey)).status, 400)
  assert.equal((await call(env, 'PUT', '/v1/devices/me/follows', { follows: [{ gameId: 'dawnwalker' }], locale: 'en' }, deviceKey)).status, 400)
  // Changed: one record write plus the key entry, both with the expiry.
  const r = await call(env, 'PUT', '/v1/devices/me/follows', { follows: [{ gameId: 'dawnwalker' }, { igdbId: 7 }] }, deviceKey)
  assert.deepEqual(await r.json(), { follows: [{ gameId: 'dawnwalker' }, { igdbId: 7 }], unknown: [] })
  assert.equal(env.KV.writes, writes + 2)
  assert.equal(env.KV.ttl.get(`d:${id}`), FOLLOWS_TTL_SECONDS)
  // Unchanged, but the record is eight days old: written again (the "still here"), so the expiry moves on.
  const rec = JSON.parse(env.KV.raw.get(`d:${id}`))
  env.KV.raw.set(`d:${id}`, JSON.stringify({ ...rec, updated: new Date(Date.now() - 8 * 86400 * 1000).toISOString() }))
  const before = env.KV.writes
  await call(env, 'PUT', '/v1/devices/me/follows', { follows: [{ gameId: 'dawnwalker' }, { igdbId: 7 }] }, deviceKey)
  assert.equal(env.KV.writes, before + 2)
  assert.ok(Date.now() - Date.parse(JSON.parse(env.KV.raw.get(`d:${id}`)).updated) < 60_000)
  // Switched off: the record and key go, and the key no longer works.
  assert.equal((await call(env, 'DELETE', '/v1/devices/me', undefined, deviceKey)).status, 204)
  assert.equal([...env.KV.raw.keys()].filter((k) => k.startsWith('d:') || k.startsWith('k:')).length, 0)
  assert.equal((await call(env, 'PUT', '/v1/devices/me/follows', { follows: [] }, deviceKey)).status, 401)
})

test('follows opt-in on a push device: PATCH hourly sets the flag; a cleared token makes the record expire', async () => {
  const { env } = setup()
  const { deviceKey } = await (await call(env, 'POST', '/v1/devices', { apnsToken: token('a'), follows: [{ gameId: 'dawnwalker', notify: 'major' }] })).json()
  let page = await (await call(env, 'GET', '/admin/devices', undefined, ADMIN)).json()
  assert.equal(page.devices[0].hourly, false)
  assert.equal((await call(env, 'PATCH', '/v1/devices/me', { hourly: true }, deviceKey)).status, 200)
  page = await (await call(env, 'GET', '/admin/devices', undefined, ADMIN)).json()
  assert.equal(page.devices[0].hourly, true)
  assert.equal(page.devices[0].token, token('a'))
  assert.equal(env.KV.ttl.get(`d:${page.devices[0].id}`), null)
  // Alerts stopped (token cleared): the record is now token-less and expires like an opt-in record.
  await call(env, 'PATCH', '/v1/devices/me', { apnsToken: null }, deviceKey)
  page = await (await call(env, 'GET', '/admin/devices', undefined, ADMIN)).json()
  assert.equal(page.devices[0].token, null)
  assert.equal(env.KV.ttl.get(`d:${page.devices[0].id}`), FOLLOWS_TTL_SECONDS)
})

test('follows opt-in: PATCH on a record without a token takes hourly only, until the PATCH that adds a token', async () => {
  const { env } = setup()
  const { deviceKey } = await (await call(env, 'POST', '/v1/follows', { follows: [{ gameId: 'dawnwalker' }] })).json()
  const patch = (body) => call(env, 'PATCH', '/v1/devices/me', body, deviceKey)
  for (const body of [{ locale: 'en-AU' }, { quietHours: { from: 60, until: 120, timeZone: 'Australia/Sydney' } }, { team: true }, { environment: 'sandbox' }, { hourly: false, locale: 'en' }]) {
    assert.equal((await patch(body)).status, 400, JSON.stringify(body))
  }
  assert.equal((await patch({ locale: 'en', team: true })).status, 400)
  assert.equal((await (await patch({ locale: 'en', team: true })).json()).error, 'a record without alerts takes only hourly, not locale, team')
  let page = await (await call(env, 'GET', '/admin/devices', undefined, ADMIN)).json()
  assert.deepEqual([page.devices[0].locale, page.devices[0].quiet, page.devices[0].team], [null, null, false])
  // The flag itself can be turned off and on.
  assert.equal((await patch({ hourly: false })).status, 200)
  page = await (await call(env, 'GET', '/admin/devices', undefined, ADMIN)).json()
  assert.equal(page.devices[0].hourly, false)
  // Alerts allowed later: the same PATCH that brings the token may bring the alert fields, and the record becomes a push device.
  assert.equal((await patch({ apnsToken: token('b'), environment: 'sandbox', locale: 'en-AU', hourly: true })).status, 200)
  page = await (await call(env, 'GET', '/admin/devices', undefined, ADMIN)).json()
  assert.deepEqual([page.devices[0].token, page.devices[0].environment, page.devices[0].locale, page.devices[0].hourly], [token('b'), 'sandbox', 'en-AU', true])
  assert.equal(env.KV.ttl.get(`d:${page.devices[0].id}`), null)
  assert.equal((await patch({ team: true })).status, 200)
})

// Feed cron (docs/decisions/feed-cron-worker.md): the Worker starts the Feed workflow when GitHub's schedule did not.
const github = (lastRunAgoMs, dispatchStatus = 204) => {
  const calls = []
  const fetchImpl = async (url, init = {}) => {
    calls.push({ url, init })
    if (url.endsWith('/runs?per_page=1')) {
      const runs = lastRunAgoMs === null ? [] : [{ created_at: new Date(1_800_000_000_000 - lastRunAgoMs).toISOString() }]
      return new Response(JSON.stringify({ workflow_runs: runs }), { status: 200 })
    }
    return new Response(null, { status: dispatchStatus })
  }
  return { calls, fetchImpl }
}
const NOW = 1_800_000_000_000

test('feed cron: a full tick dispatches a poll with hot false, to main, with the token', async () => {
  const gh = github(null)
  const r = await dispatchFeed({ FEED_DISPATCH_TOKEN: 'ghp' }, FEED_FULL_CRON, NOW, gh.fetchImpl)
  assert.deepEqual(r, { dispatched: true, hot: false })
  const post = gh.calls.find((c) => c.init.method === 'POST')
  assert.equal(post.url, 'https://api.github.com/repos/tezbo/playscribe/actions/workflows/feed.yml/dispatches')
  assert.equal(post.init.headers.authorization, 'Bearer ghp')
  assert.deepEqual(JSON.parse(post.init.body), { ref: 'main', inputs: { action: 'poll', hot: 'false' } })
})

test('feed cron: the hot tick sends hot true', async () => {
  const gh = github(60 * 60_000)
  const r = await dispatchFeed({ FEED_DISPATCH_TOKEN: 'ghp' }, FEED_HOT_CRON, NOW, gh.fetchImpl)
  assert.deepEqual(r, { dispatched: true, hot: true })
  assert.deepEqual(JSON.parse(gh.calls.at(-1).init.body).inputs, { action: 'poll', hot: 'true' })
})

test('feed cron: a run GitHub started in the last 10 minutes is not doubled', async () => {
  const gh = github(5 * 60_000)
  const r = await dispatchFeed({ FEED_DISPATCH_TOKEN: 'ghp' }, FEED_FULL_CRON, NOW, gh.fetchImpl)
  assert.equal(r.dispatched, false)
  assert.equal(gh.calls.length, 1, 'only the runs check was made')
})

test('feed cron: without the token nothing is called; a refused dispatch is reported, not thrown', async () => {
  const gh = github(null)
  assert.deepEqual(await dispatchFeed({}, FEED_FULL_CRON, NOW, gh.fetchImpl), { dispatched: false, reason: 'no FEED_DISPATCH_TOKEN' })
  assert.equal(gh.calls.length, 0)
  const refused = github(null, 403)
  assert.deepEqual(await dispatchFeed({ FEED_DISPATCH_TOKEN: 'ghp' }, FEED_FULL_CRON, NOW, refused.fetchImpl), { dispatched: false, reason: 'GitHub answered 403', hot: false })
  const down = await dispatchFeed({ FEED_DISPATCH_TOKEN: 'ghp' }, FEED_FULL_CRON, NOW, async () => { throw new Error('dns') })
  assert.equal(down.reason, 'GitHub unreachable')
})

test('block list: parses ids and addresses from whitespace or commas; nothing is blocked without the secret', () => {
  const b = parseBlocklist('  dev_ABC, 1.2.3.4\n2001:db8::1 ,, other-id ')
  assert.deepEqual([...b.ids], ['dev_abc', 'other-id'])
  assert.deepEqual([...b.ips], ['1.2.3.4', '2001:db8::1'])
  assert.deepEqual(parseBlocklist(undefined), { ids: new Set(), ips: new Set() })
})

test('block list: a blocked address gets 403 on every /v1 route and writes nothing; other addresses are untouched', async () => {
  const { env } = setup()
  env.BLOCKLIST = '9.9.9.9'
  const from = (ip, path, body) => worker.fetch(new Request(`https://relay.test${path}`, { method: 'POST', headers: { 'content-type': 'application/json', 'cf-connecting-ip': ip }, body: JSON.stringify(body) }), env)
  const r = await from('9.9.9.9', '/v1/devices', { apnsToken: token('a') })
  assert.equal(r.status, 403)
  assert.deepEqual(await r.json(), { error: 'blocked' })
  assert.equal((await from('9.9.9.9', '/v1/follows', { follows: [{ gameId: 'dawnwalker' }] })).status, 403)
  assert.equal(env.KV.writes, 0)
  assert.equal((await from('1.1.1.1', '/v1/devices', { apnsToken: token('a') })).status, 201)
  const health = await worker.fetch(new Request('https://relay.test/health', { headers: { 'cf-connecting-ip': '9.9.9.9' } }), env)
  assert.equal(health.status, 200)
})

test('block list: a blocked device id is refused everywhere but DELETE, and the Feed job never sees it', async () => {
  const { env } = setup()
  const reg = await (await call(env, 'POST', '/v1/devices', { apnsToken: token('b'), follows: [{ gameId: 'dawnwalker' }] })).json()
  const other = await (await call(env, 'POST', '/v1/devices', { apnsToken: token('c') })).json()
  env.BLOCKLIST = `${reg.deviceId.toUpperCase()}, some-other-id`
  assert.equal((await call(env, 'POST', '/v1/devices', { apnsToken: token('b') })).status, 403) // relaunch of the blocked device
  assert.equal((await call(env, 'PATCH', '/v1/devices/me', { locale: 'en-AU' }, reg.deviceKey)).status, 403)
  assert.equal((await call(env, 'PUT', '/v1/devices/me/follows', { follows: [] }, reg.deviceKey)).status, 403)
  assert.equal((await call(env, 'GET', '/v1/devices/me/follows', undefined, reg.deviceKey)).status, 403)
  assert.equal((await call(env, 'GET', '/v1/devices/me/follows', undefined, other.deviceKey)).status, 200)
  const admin = await (await worker.fetch(new Request('https://relay.test/admin/devices', { headers: { authorization: `Bearer ${ADMIN}` } }), env)).json()
  assert.deepEqual(admin.devices.map((d) => d.id), [other.deviceId])
  assert.equal((await call(env, 'DELETE', '/v1/devices/me', undefined, reg.deviceKey)).status, 204)
  assert.equal(await env.KV.get(`d:${reg.deviceId}`), null)
})

// r071-relay-dead-tokens
const shaHex = async (s) => [...new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s)))].map((b) => b.toString(16).padStart(2, '0')).join('')
const dead = (env, devices, key = ADMIN) => call(env, 'POST', '/admin/devices/dead', { devices }, key)

test('dead tokens: a push device is removed with its token, key and team entries; its key then gets 401 so the app registers again', async () => {
  const { env } = setup()
  const b = await (await call(env, 'POST', '/v1/devices', { apnsToken: token('a'), environment: 'production', team: true, follows: [{ gameId: 'dawnwalker', notify: 'major' }] })).json()
  await call(env, 'PATCH', '/v1/devices/me', { team: true }, b.deviceKey)
  assert.equal(env.KV.raw.has(`tm:${b.deviceId}`), true)
  const r = await dead(env, [{ id: b.deviceId, tokenSha: await shaHex(token('a')) }])
  assert.deepEqual(await r.json(), { removed: 1, cleared: 0, skipped: 0 })
  assert.deepEqual([...env.KV.raw.keys()].filter((k) => !k.startsWith('n:')), [])
  assert.equal((await call(env, 'GET', '/v1/devices/me/follows', undefined, b.deviceKey)).status, 401)
})

test('dead tokens: a follow-list opt-in keeps helping as an ids-only record with the 90-day expiry', async () => {
  const { env } = setup()
  const b = await (await call(env, 'POST', '/v1/devices', { apnsToken: token('b'), environment: 'sandbox', locale: 'en-AU', quietHours: { from: 1320, until: 420, timeZone: 'Australia/Sydney' }, follows: [{ gameId: 'dawnwalker', notify: 'major' }, { igdbId: 338121 }] })).json()
  await call(env, 'PATCH', '/v1/devices/me', { hourly: true }, b.deviceKey)
  const r = await dead(env, [{ id: b.deviceId, tokenSha: await shaHex(token('b')) }])
  assert.deepEqual(await r.json(), { removed: 0, cleared: 1, skipped: 0 })
  const rec = JSON.parse(env.KV.raw.get(`d:${b.deviceId}`))
  assert.deepEqual(Object.keys(rec).sort(), ['created', 'follows', 'hourly', 'id', 'key', 'token', 'updated'])
  assert.equal(rec.token, null)
  assert.deepEqual(rec.follows, [{ gameId: 'dawnwalker' }, { igdbId: 338121 }])
  assert.equal(env.KV.raw.has(`t:${token('b')}`), false)
  assert.equal(env.KV.ttl.get(`d:${b.deviceId}`), FOLLOWS_TTL_SECONDS)
  // The app's key still works, and a later PATCH with a fresh token brings alerts back.
  assert.equal((await call(env, 'PATCH', '/v1/devices/me', { apnsToken: token('c'), environment: 'production' }, b.deviceKey)).status, 200)
  assert.equal(env.KV.raw.get(`t:${token('c')}`), b.deviceId)
})

test('dead tokens: a device that registered a new token since the run, an unknown id, or a token-less record is left alone', async () => {
  const { env } = setup()
  const b = await (await call(env, 'POST', '/v1/devices', { apnsToken: token('d'), environment: 'production', follows: [] })).json()
  await call(env, 'PATCH', '/v1/devices/me', { apnsToken: token('e') }, b.deviceKey)
  const opt = await (await call(env, 'POST', '/v1/follows', { follows: [{ gameId: 'dawnwalker' }] })).json()
  const optId = env.KV.raw.get(`k:${await shaHex(opt.deviceKey)}`)
  const writes = env.KV.writes
  const r = await dead(env, [{ id: b.deviceId, tokenSha: await shaHex(token('d')) }, { id: 'nobody', tokenSha: await shaHex(token('f')) }, { id: optId, tokenSha: await shaHex(token('d')) }])
  assert.deepEqual(await r.json(), { removed: 0, cleared: 0, skipped: 3 })
  assert.equal(env.KV.writes, writes)
  assert.equal(env.KV.raw.get(`t:${token('e')}`), b.deviceId)
})

test('dead tokens: admin only, and the body is checked', async () => {
  const { env } = setup()
  const sha = await shaHex(token('a'))
  assert.equal((await dead(env, [{ id: 'x', tokenSha: sha }], 'wrong')).status, 401)
  assert.equal((await call(env, 'POST', '/admin/devices/dead', { devices: [] })).status, 401)
  assert.equal((await dead(env, Array.from({ length: 7 }, (_, i) => ({ id: `x${i}`, tokenSha: sha })))).status, 400)
  assert.equal((await dead(env, [{ id: 'x', tokenSha: 'abc' }])).status, 400)
  assert.equal((await dead(env, [{ id: 'x', tokenSha: sha }])).status, 200)
})
