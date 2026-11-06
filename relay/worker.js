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
// KV keys: d:<id> device record, t:<apnsToken> -> id, k:<sha256 deviceKey> -> id, n:<UTC date> new devices that day.
// Free-plan limits this is sized for: 1,000 KV writes a day (a relaunch with nothing changed writes nothing),
// 50 KV operations per request (hence the 40 device page).

const NOTIFY = ['all', 'major', 'off']
const MINUTES = 24 * 60
const PAGE = 40
const MAX_BODY = 64 * 1024
const MAX_FOLLOWS = 500
const MAX_TEAM = 20
// A new device costs 4 KV writes (record, token, key, and the day counter); relaunches cost none. 150 new devices a day
// is about 600 of the free plan's 1,000 writes, leaving the rest for changes by existing devices, so a flood of fake
// registrations cannot starve real users. Existing devices are never refused.
export const MAX_NEW_PER_DAY = 150

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

/** tm:<id> lists the team devices, so an alert reads a handful of keys and never walks every device (50 KV operations a request). */
const syncTeamIndex = async (kv, id, team) => {
  const has = (await kv.get(`tm:${id}`)) !== null
  if (team && !has) await kv.put(`tm:${id}`, '1')
  else if (!team && has) await kv.delete(`tm:${id}`)
}

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
      await kv.delete(`tm:${holder}`)
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
  const team = typeof body.team === 'boolean' ? body.team : undefined

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
      team: team ?? existing.team ?? false,
    }
    if (JSON.stringify(next) !== JSON.stringify(existing)) await putJson(kv, `d:${existing.id}`, { ...next, updated: now() })
    if (team !== undefined) await syncTeamIndex(kv, existing.id, team)
    return json(publicView(next), 200)
  }
  const dayKey = `n:${now().slice(0, 10)}`
  const todays = Number((await kv.get(dayKey)) ?? 0)
  if (todays >= MAX_NEW_PER_DAY) {
    const r = bad('too many new devices today, try again tomorrow', 429)
    r.headers.set('retry-after', '3600')
    return r
  }
  await kv.put(dayKey, String(todays + 1), { expirationTtl: 172800 }) // gone after two days, so old counters never pile up
  const id = crypto.randomUUID()
  const key = b64url(crypto.getRandomValues(new Uint8Array(32)))
  const rec = { id, key, token, environment, locale, follows: follows ?? [], quiet: quiet ?? null, team: team ?? false, created: now(), updated: now() }
  await claimToken(kv, token, id)
  await putJson(kv, `d:${id}`, rec)
  await kv.put(`k:${await sha(key)}`, id)
  if (team) await syncTeamIndex(kv, id, true)
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
  if (typeof body.team === 'boolean') next.team = body.team
  if (body.apnsToken !== undefined) {
    const token = body.apnsToken ? body.apnsToken.toLowerCase() : null
    if (token !== d.token) {
      if (d.token) await kv.delete(`t:${d.token}`)
      if (token) await claimToken(kv, token, d.id)
      next.token = token
    }
  }
  if (JSON.stringify(next) !== JSON.stringify(d)) await putJson(kv, `d:${d.id}`, { ...next, updated: now() })
  if (typeof body.team === 'boolean') await syncTeamIndex(kv, d.id, body.team)
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
    if (d?.token) devices.push({ id: d.id, token: d.token, environment: d.environment, locale: d.locale, quiet: d.quiet, team: d.team === true, follows: d.follows, updated: d.updated })
  }
  return json({ devices, cursor: page.list_complete ? null : page.cursor })
}

// ---- Team alerts: App Store Connect webhook -> a push to the devices that switched "Team alerts" on (internal builds). ----
// The alert text is fixed. It never carries the tester's words, because the push is not the place for them.
const hexToBytes = (h) => new Uint8Array((h.match(/../g) ?? []).map((x) => parseInt(x, 16)))

/** HMAC-SHA256 of the raw body against ASC_WEBHOOK_SECRET. Fails closed: no secret, no header or a mismatch all say no.
 *  The header name and format are read from Apple's docs and confirmed by the first webhookPing; the check accepts
 *  either "hmacsha256=<hex>" or bare hex. */
export const signatureOk = async (env, request, raw) => {
  if (!env.ASC_WEBHOOK_SECRET) return false
  const header = request.headers.get('x-apple-signature') ?? ''
  const hexSig = header.replace(/^hmacsha256=/i, '').trim().toLowerCase()
  if (!/^[0-9a-f]{64}$/.test(hexSig)) return false
  const key = await crypto.subtle.importKey('raw', enc.encode(env.ASC_WEBHOOK_SECRET), { name: 'HMAC', hash: 'SHA-256' }, false, ['verify'])
  return crypto.subtle.verify('HMAC', key, hexToBytes(hexSig), enc.encode(raw))
}

const pemBytes = (pem) => Uint8Array.from(atob(pem.replace(/-----[^-]+-----|\s/g, '')), (c) => c.charCodeAt(0))
const apnsJwt = async (env) => {
  const key = await crypto.subtle.importKey('pkcs8', pemBytes(env.APNS_KEY), { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign'])
  const part = (o) => b64url(enc.encode(JSON.stringify(o)))
  const head = `${part({ alg: 'ES256', kid: env.APNS_KEY_ID })}.${part({ iss: env.APNS_TEAM_ID, iat: Math.floor(Date.now() / 1000) })}`
  const sig = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, enc.encode(head))
  return `${head}.${b64url(new Uint8Array(sig))}`
}

const ALERT = { crash: 'New TestFlight crash report', screenshot: 'New TestFlight feedback' }
const sendTeamAlert = async (env, kind) => {
  if (!env.APNS_KEY || !env.APNS_KEY_ID || !env.APNS_TEAM_ID) return { sent: 0, skipped: 'push key not set' }
  const jwt = await apnsJwt(env)
  let sent = 0
  // At most MAX_TEAM devices: each send is a subrequest and the free plan allows 50 a request.
  const ids = (await env.KV.list({ prefix: 'tm:', limit: MAX_TEAM })).keys.map((k) => k.name.slice(3))
  for (const id of ids) {
    const d = await getJson(env.KV, `d:${id}`)
    if (!d?.team || !d.token) continue
    const host = d.environment === 'sandbox' ? 'api.sandbox.push.apple.com' : 'api.push.apple.com'
    const r = await fetch(`https://${host}/3/device/${d.token}`, {
      method: 'POST',
      headers: { authorization: `bearer ${jwt}`, 'apns-topic': env.APNS_TOPIC ?? 'tezbo.Playscribe', 'apns-push-type': 'alert', 'apns-priority': '10' },
      body: JSON.stringify({ aps: { alert: { title: 'Playscribe', body: ALERT[kind] ?? ALERT.screenshot }, sound: 'default' } }),
    })
    if (r.ok) sent++
  }
  return { sent }
}

const ascWebhook = async (env, request) => {
  const raw = await request.text()
  if (raw.length > MAX_BODY) return bad('body too large', 413)
  if (!(await signatureOk(env, request, raw))) return bad('not allowed', 401)
  let ev
  try { ev = JSON.parse(raw) } catch { return bad('bad json') }
  const type = String(ev?.data?.attributes?.eventType ?? ev?.eventType ?? '')
  const id = String(ev?.data?.id ?? '')
  if (!/FEEDBACK/.test(type)) return json({ ok: true, ignored: true })
  if (id) {
    if (await env.KV.get(`w:${id}`)) return json({ ok: true, duplicate: true })
  }
  // Marked done only after the send, so a failure part-way is retried by Apple rather than swallowed.
  const result = await sendTeamAlert(env, /CRASH/.test(type) ? 'crash' : 'screenshot')
  if (id) await env.KV.put(`w:${id}`, '1', { expirationTtl: 86400 })
  return json({ ok: true, ...result })
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
      if (pathname === '/v1/webhooks/asc' && m === 'POST') return await ascWebhook(env, request)
      if (pathname === '/admin/devices' && m === 'GET') return await adminDevices(env, request)
      return bad('not found', 404)
    } catch (e) {
      return bad('relay error', 500)
    }
  },
}
