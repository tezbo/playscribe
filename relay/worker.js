// Playscribe push relay: a Cloudflare Worker with one KV namespace (binding KV).
//
// Why it exists: the app has to hand its APNs token and followed games to something that is always on. The Feed job
// runs on GitHub Actions twice an hour and cannot receive requests, so this keeps the registrations and the Feed job
// reads them (GET /admin/devices) just before it polls, sends the pushes itself, and scrubs them again before it
// publishes anything. The APNs key never leaves GitHub. Contract: docs/api.md "Devices", docs/push-relay.md.
//
// The routes the app uses match backend/src/server.ts, so the app needs no new request shapes:
//   POST /v1/devices                    register (idempotent per APNs token), returns { deviceId, deviceKey, follows, unknown }
//   PATCH /v1/devices/me                token, environment, locale, quietHours
//   GET|PUT /v1/devices/me/follows      the followed games
//   GET /admin/devices?cursor=          Feed job only (Bearer ADMIN_TOKEN), 40 devices a page
//
// KV keys: d:<id> device record, t:<apnsToken> -> id, k:<sha256 deviceKey> -> id.
// Free-plan limits this is sized for: 1,000 KV writes a day (a relaunch with nothing changed writes nothing),
// 50 KV operations per request (hence the 40 device page).

const NOTIFY = ['all', 'major', 'off']
const MINUTES = 24 * 60
const PAGE = 40
const MAX_BODY = 64 * 1024
const MAX_FOLLOWS = 500

const enc = new TextEncoder()
const hex = (buf) => [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('')
const sha = async (s) => hex(await crypto.subtle.digest('SHA-256', enc.encode(s)))
const b64url = (bytes) => btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json', 'cache-control': 'no-store' } })
const bad = (message, status = 400) => json({ error: message }, status)

/** Same rules as backend/src/push/quiet.ts: whole minutes after local midnight and an IANA zone; null clears. */
export const parseQuietHours = (v) => {
  if (v === null) return null
  if (typeof v !== 'object' || v === undefined) return { error: 'quietHours must be an object or null' }
  const { from, until, timeZone } = v
  const okMin = (n) => Number.isInteger(n) && n >= 0 && n < MINUTES
  if (!okMin(from) || !okMin(until)) return { error: 'quietHours.from and until are whole minutes from 0 to 1439' }
  if (from === until) return { error: 'quietHours.from and until must differ (send null to switch off)' }
  if (typeof timeZone !== 'string' || !timeZone) return { error: 'quietHours.timeZone must be an IANA time zone' }
  try {
    new Intl.DateTimeFormat('en-GB', { timeZone })
  } catch {
    return { error: 'quietHours.timeZone is not a known time zone' }
  }
  return { from, until, timeZone }
}

/** Follows as the app sends them: { gameId } or { igdbId }, plus notify. Resolving to our game ids is the Feed job's work. */
export const parseFollows = (v) => {
  if (!Array.isArray(v)) return { error: 'follows must be an array' }
  const out = []
  for (const f of v.slice(0, MAX_FOLLOWS)) {
    if (!f || typeof f !== 'object') return { error: 'each follow must be an object' }
    const notify = f.notify ?? 'all'
    if (!NOTIFY.includes(notify)) return { error: `notify must be one of ${NOTIFY.join(', ')}` }
    if (typeof f.gameId === 'string' && /^[a-z0-9][a-z0-9._-]{0,99}$/i.test(f.gameId)) out.push({ gameId: f.gameId, notify })
    else if (Number.isInteger(f.igdbId) && f.igdbId > 0) out.push({ igdbId: f.igdbId, notify })
  }
  return { follows: out }
}

const readJson = async (request) => {
  const text = await request.text()
  if (text.length > MAX_BODY) return { tooBig: true }
  if (!text) return { body: {} }
  try {
    const body = JSON.parse(text)
    return body && typeof body === 'object' && !Array.isArray(body) ? { body } : { body: {} }
  } catch {
    return { body: {} }
  }
}

const validToken = (t) => typeof t === 'string' && /^[0-9a-f]{64,200}$/i.test(t)
const putJson = (kv, key, value) => kv.put(key, JSON.stringify(value))
const getJson = async (kv, key) => {
  const raw = await kv.get(key)
  return raw ? JSON.parse(raw) : null
}
const now = () => new Date().toISOString()

const deviceFor = async (kv, request) => {
  const auth = request.headers.get('authorization') ?? ''
  const key = auth.startsWith('Bearer ') ? auth.slice(7) : ''
  if (!key) return null
  const id = await kv.get(`k:${await sha(key)}`)
  return id ? await getJson(kv, `d:${id}`) : null
}

const isAdmin = async (env, request) => {
  if (!env.ADMIN_TOKEN) return false
  const auth = request.headers.get('authorization') ?? ''
  const given = auth.startsWith('Bearer ') ? auth.slice(7) : ''
  if (!given) return false
  // Compare digests so the comparison does not depend on where the strings differ.
  return (await sha(given)) === (await sha(env.ADMIN_TOKEN))
}

const publicView = (d) => ({ deviceId: d.id, deviceKey: d.key, follows: d.follows, unknown: [] })

/** A token moves to the newest registration: whoever held it before loses it. */
const claimToken = async (kv, token, id) => {
  const holder = await kv.get(`t:${token}`)
  if (holder && holder !== id) {
    const old = await getJson(kv, `d:${holder}`)
    if (old) {
      await kv.delete(`d:${holder}`)
      await kv.delete(`k:${await sha(old.key)}`)
    }
  }
  if (holder !== id) await kv.put(`t:${token}`, id)
}

const register = async (env, request) => {
  const kv = env.KV
  const parsed = await readJson(request)
  if (parsed.tooBig) return bad('body too large', 413)
  const body = parsed.body
  const environment = body.environment ?? 'production'
  if (environment !== 'sandbox' && environment !== 'production') return bad('environment must be sandbox or production')
  if (!validToken(body.apnsToken)) return bad('apnsToken must be hex')
  const token = body.apnsToken.toLowerCase()
  const quiet = body.quietHours === undefined ? undefined : parseQuietHours(body.quietHours)
  if (quiet && 'error' in quiet) return bad(quiet.error)
  let follows
  if (body.follows !== undefined) {
    const f = parseFollows(body.follows)
    if ('error' in f) return bad(f.error)
    follows = f.follows
  }
  const locale = typeof body.locale === 'string' ? body.locale.slice(0, 35) : null

  const existingId = await kv.get(`t:${token}`)
  const existing = existingId ? await getJson(kv, `d:${existingId}`) : null
  if (existing) {
    // Same device registering again (every launch does): write only what changed.
    const next = {
      ...existing,
      environment,
      locale: locale ?? existing.locale,
      follows: follows ?? existing.follows,
      quiet: quiet === undefined ? existing.quiet : quiet,
    }
    if (JSON.stringify(next) !== JSON.stringify(existing)) await putJson(kv, `d:${existing.id}`, { ...next, updated: now() })
    return json(publicView(next), 200)
  }
  const id = crypto.randomUUID()
  const key = b64url(crypto.getRandomValues(new Uint8Array(32)))
  const rec = { id, key, token, environment, locale, follows: follows ?? [], quiet: quiet ?? null, created: now(), updated: now() }
  await claimToken(kv, token, id)
  await putJson(kv, `d:${id}`, rec)
  await kv.put(`k:${await sha(key)}`, id)
  return json(publicView(rec), 201)
}

const patchMe = async (env, request) => {
  const kv = env.KV
  const d = await deviceFor(kv, request)
  if (!d) return bad('unknown device key', 401)
  const parsed = await readJson(request)
  if (parsed.tooBig) return bad('body too large', 413)
  const body = parsed.body
  if (body.environment !== undefined && body.environment !== 'sandbox' && body.environment !== 'production') return bad('environment must be sandbox or production')
  if (body.apnsToken && !validToken(body.apnsToken)) return bad('apnsToken must be hex')
  const quiet = body.quietHours === undefined ? undefined : parseQuietHours(body.quietHours)
  if (quiet && 'error' in quiet) return bad(quiet.error)
  const next = { ...d }
  if (body.environment) next.environment = body.environment
  if (typeof body.locale === 'string') next.locale = body.locale.slice(0, 35)
  if (quiet !== undefined) next.quiet = quiet
  if (body.apnsToken !== undefined) {
    const token = body.apnsToken ? body.apnsToken.toLowerCase() : null
    if (token !== d.token) {
      if (d.token) await kv.delete(`t:${d.token}`)
      if (token) await claimToken(kv, token, d.id)
      next.token = token
    }
  }
  if (JSON.stringify(next) !== JSON.stringify(d)) await putJson(kv, `d:${d.id}`, { ...next, updated: now() })
  return json({ deviceId: d.id })
}

const putFollows = async (env, request) => {
  const d = await deviceFor(env.KV, request)
  if (!d) return bad('unknown device key', 401)
  const parsed = await readJson(request)
  if (parsed.tooBig) return bad('body too large', 413)
  const f = parseFollows(parsed.body.follows)
  if ('error' in f) return bad(f.error)
  if (JSON.stringify(f.follows) !== JSON.stringify(d.follows)) await putJson(env.KV, `d:${d.id}`, { ...d, follows: f.follows, updated: now() })
  return json({ follows: f.follows, unknown: [] })
}

const adminDevices = async (env, request) => {
  if (!(await isAdmin(env, request))) return bad('not allowed', 401)
  const cursor = new URL(request.url).searchParams.get('cursor') || undefined
  const page = await env.KV.list({ prefix: 'd:', limit: PAGE, cursor })
  const devices = []
  for (const k of page.keys) {
    const d = await getJson(env.KV, k.name)
    if (d?.token) devices.push({ id: d.id, token: d.token, environment: d.environment, locale: d.locale, quiet: d.quiet, follows: d.follows, updated: d.updated })
  }
  return json({ devices, cursor: page.list_complete ? null : page.cursor })
}

export default {
  async fetch(request, env) {
    const { pathname } = new URL(request.url)
    const m = request.method
    try {
      if (pathname === '/' || pathname === '/health') return json({ ok: true })
      if (pathname === '/v1/devices' && m === 'POST') return await register(env, request)
      if (pathname === '/v1/devices/me' && m === 'PATCH') return await patchMe(env, request)
      if (pathname === '/v1/devices/me/follows' && m === 'PUT') return await putFollows(env, request)
      if (pathname === '/v1/devices/me/follows' && m === 'GET') {
        const d = await deviceFor(env.KV, request)
        return d ? json({ follows: d.follows }) : bad('unknown device key', 401)
      }
      if (pathname === '/admin/devices' && m === 'GET') return await adminDevices(env, request)
      return bad('not found', 404)
    } catch (e) {
      return bad('relay error', 500)
    }
  },
}
