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
//   DELETE /v1/devices/me               forget this device: record, token, key and team entry are removed (204; idempotent)
//   POST /v1/follows                    0.5.4 "Help keep my games up to date": a record WITHOUT a token, follow ids only,
//                                       hourly polling; returns { deviceKey, follows }. The body may hold nothing but follows.
//   GET /admin/devices?cursor=          Feed job only (Bearer ADMIN_TOKEN), 40 devices a page
//   POST /admin/devices/dead            Feed job only: devices whose APNs token is dead are removed, or cleared to ids only
//                                       when they opted in to the follow list (r071; see adminDead)
//
// Cron (scheduled handler): GitHub's own schedule for the Feed workflow fires late or not at all for hours at a time
// (11 Nov 2026: one full poll in 4.5 hours, no hot runs), so this Worker's cron triggers, at :22 and :52, start the Feed
// workflow by workflow_dispatch when GitHub has not started a run in the last 10 minutes. Needs FEED_DISPATCH_TOKEN
// (fine-grained GitHub token, this repository only, Actions read and write); without it the handler does nothing.
// Decision: docs/decisions/feed-cron-worker.md.
//
// KV keys: d:<id> device record, t:<apnsToken> -> id, k:<sha256 deviceKey> -> id, n:<UTC date> new devices that day.
// A record with no APNs token (the follow-list opt-in, or a push device whose token was cleared) expires 90 days after
// its last write; the app's weekly "still here" is the same PUT of its list, which is rewritten once a week even when
// unchanged. A record with a token is kept until the device deletes it, as before.
// Free-plan limits this is sized for: 1,000 KV writes a day (a relaunch with nothing changed writes nothing),
// 50 KV operations per request (hence the 40 device page).

const NOTIFY = ['all', 'major', 'off']
const MINUTES = 24 * 60
const PAGE = 40
const MAX_BODY = 64 * 1024
const MAX_FOLLOWS = 500
const MAX_TEAM = 20
/** A record without a token lives this long after its last write (docs/api.md "Follow list without alerts"). */
export const FOLLOWS_TTL_SECONDS = 90 * 86400
/** The "still here" cadence: an unchanged follow list is written again once this much time has passed. */
const STILL_HERE_MS = 7 * 86400 * 1000
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

/** The follow-list opt-in sends ids and nothing else: each item is exactly { gameId } or { igdbId }. Anything more is a 400,
 *  so a build that adds a field cannot slip it past the relay (the app has the same test on its side). */
export const parseIdFollows = (v) => {
  if (!Array.isArray(v)) return { error: 'follows must be an array' }
  if (v.length > MAX_FOLLOWS) return { error: `follows holds at most ${MAX_FOLLOWS} games` }
  const out = []
  for (const f of v) {
    if (!f || typeof f !== 'object' || Array.isArray(f)) return { error: 'each follow must be an object' }
    const keys = Object.keys(f)
    if (keys.length !== 1) return { error: 'each follow is exactly { gameId } or { igdbId }' }
    if (keys[0] === 'gameId' && typeof f.gameId === 'string' && /^[a-z0-9][a-z0-9._-]{0,99}$/i.test(f.gameId)) out.push({ gameId: f.gameId })
    else if (keys[0] === 'igdbId' && Number.isInteger(f.igdbId) && f.igdbId > 0) out.push({ igdbId: f.igdbId })
    else return { error: 'each follow is exactly { gameId } or { igdbId }' }
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
/** Writes a device record; one with no token also gets its expiry, and its key entry is renewed with it. */
const putDevice = async (kv, d) => {
  if (d.token) return putJson(kv, `d:${d.id}`, d)
  await kv.put(`d:${d.id}`, JSON.stringify(d), { expirationTtl: FOLLOWS_TTL_SECONDS })
  await kv.put(`k:${await sha(d.key)}`, d.id, { expirationTtl: FOLLOWS_TTL_SECONDS })
}
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

// r070-relay-block-list: BLOCKLIST is a Worker secret (never a repo file or the feed branch) holding device ids and
// addresses, separated by whitespace or commas. A blocked address gets 403 on every /v1 route; a blocked device id gets
// 403 on everything but DELETE /v1/devices/me, so it can still be forgotten, and the Feed job never sees it.
export const parseBlocklist = (v) => {
  const ids = new Set()
  const ips = new Set()
  for (const raw of String(v ?? '').split(/[\s,]+/)) {
    const e = raw.trim().toLowerCase()
    if (!e) continue
    if (/^[0-9a-f:.]+$/.test(e) && /[.:]/.test(e)) ips.add(e)
    else ids.add(e)
  }
  return { ids, ips }
}
// Parsed once per Worker instance; cached at module level keyed on the secret's text, so env is never written to.
let blocklistCache
const blocklistOf = (env) => {
  if (!blocklistCache || blocklistCache.src !== env.BLOCKLIST) blocklistCache = { src: env.BLOCKLIST, list: parseBlocklist(env.BLOCKLIST) }
  return blocklistCache.list
}
const blockedAddress = (env, request) => blocklistOf(env).ips.has((request.headers.get('cf-connecting-ip') ?? '').toLowerCase())
const blockedId = (env, id) => !!id && blocklistOf(env).ids.has(String(id).toLowerCase())
const BLOCKED = () => bad('blocked', 403)

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

/** The two limits every new record passes. A new device also passes a per-address limit (Workers Rate Limiting binding: no KV
 *  writes, so it cannot spend the budget it protects). Known devices relaunching are never limited. Without the binding (tests,
 *  a deploy that omits it) that part is skipped. Then the day counter: at most MAX_NEW_PER_DAY new records a day. */
const newDeviceLimit = async (env, request) => {
  if (env.REGISTER_LIMIT) {
    const ip = request.headers.get('cf-connecting-ip') ?? 'unknown'
    const { success } = await env.REGISTER_LIMIT.limit({ key: ip })
    if (!success) {
      const r = bad('too many registrations from this address, try again in a minute', 429)
      r.headers.set('retry-after', '60')
      return r
    }
  }
  const dayKey = `n:${now().slice(0, 10)}`
  const todays = Number((await env.KV.get(dayKey)) ?? 0)
  if (todays >= MAX_NEW_PER_DAY) {
    const r = bad('too many new devices today, try again tomorrow', 429)
    r.headers.set('retry-after', '3600')
    return r
  }
  await env.KV.put(dayKey, String(todays + 1), { expirationTtl: 172800 }) // gone after two days, so old counters never pile up
  return null
}

/** POST /v1/follows: the follow-list opt-in. Stores the ids and a fresh key, nothing else; the body may hold nothing but
 *  `follows`. The record has no token, so it expires 90 days after its last write (see putDevice). */
const registerFollows = async (env, request) => {
  const parsed = await readJson(request)
  if (parsed.tooBig) return bad('body too large', 413)
  const extra = Object.keys(parsed.body).filter((k) => k !== 'follows')
  if (extra.length) return bad(`only follows may be sent here, not ${extra.sort().join(', ')}`)
  const f = parseIdFollows(parsed.body.follows)
  if ('error' in f) return bad(f.error)
  const limited = await newDeviceLimit(env, request)
  if (limited) return limited
  const id = crypto.randomUUID()
  const key = b64url(crypto.getRandomValues(new Uint8Array(32)))
  const rec = { id, key, token: null, follows: f.follows, hourly: true, created: now(), updated: now() }
  await putDevice(env.KV, rec)
  return json({ deviceKey: key, follows: rec.follows }, 201)
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
  if (existing && blockedId(env, existing.id)) return BLOCKED()
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
  const limited = await newDeviceLimit(env, request)
  if (limited) return limited
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
  if (blockedId(env, d.id)) return BLOCKED()
  const parsed = await readJson(request)
  if (parsed.tooBig) return bad('body too large', 413)
  const body = parsed.body
  // A record without a token holds ids and the hourly flag only. It takes the alert fields (environment, locale, quiet hours,
  // team) only in the PATCH that gives it a token, so an opt-in record can never quietly grow a field the promise excludes.
  if (!d.token && !body.apnsToken) {
    const extra = Object.keys(body).filter((k) => k !== 'hourly')
    if (extra.length) return bad(`a record without alerts takes only hourly, not ${extra.sort().join(', ')}`)
  }
  if (body.environment !== undefined && body.environment !== 'sandbox' && body.environment !== 'production') return bad('environment must be sandbox or production')
  if (body.apnsToken && !validToken(body.apnsToken)) return bad('apnsToken must be hex')
  const quiet = body.quietHours === undefined ? undefined : parseQuietHours(body.quietHours)
  if (quiet && 'error' in quiet) return bad(quiet.error)
  const next = { ...d }
  if (body.environment) next.environment = body.environment
  if (typeof body.locale === 'string') next.locale = body.locale.slice(0, 35)
  if (quiet !== undefined) next.quiet = quiet
  if (typeof body.team === 'boolean') next.team = body.team
  // The follow-list opt-in on a device that also has alerts: its follows join the hourly tier while this is true.
  if (typeof body.hourly === 'boolean') next.hourly = body.hourly
  if (body.apnsToken !== undefined) {
    const token = body.apnsToken ? body.apnsToken.toLowerCase() : null
    if (token !== d.token) {
      if (d.token) await kv.delete(`t:${d.token}`)
      if (token) await claimToken(kv, token, d.id)
      next.token = token
    }
  }
  if (JSON.stringify(next) !== JSON.stringify(d)) await putDevice(kv, { ...next, updated: now() })
  if (typeof body.team === 'boolean') await syncTeamIndex(kv, d.id, body.team)
  return json({ deviceId: d.id })
}

/** The device's own request to be forgotten (alerts switched off, app reset). Removes every key that names it. A key the
 *  relay no longer knows means it is already gone, so that is 204 too and the app can treat any 204 as done. */
const deleteMe = async (env, request) => {
  const kv = env.KV
  const auth = request.headers.get('authorization') ?? ''
  const key = auth.startsWith('Bearer ') ? auth.slice(7) : ''
  if (!key) return bad('missing device key', 401)
  const d = await deviceFor(kv, request)
  if (d) {
    await kv.delete(`d:${d.id}`)
    await kv.delete(`k:${await sha(d.key)}`)
    if (d.token && (await kv.get(`t:${d.token}`)) === d.id) await kv.delete(`t:${d.token}`)
    if ((await kv.get(`tm:${d.id}`)) !== null) await kv.delete(`tm:${d.id}`)
  }
  return new Response(null, { status: 204, headers: { 'cache-control': 'no-store' } })
}

const putFollows = async (env, request) => {
  const d = await deviceFor(env.KV, request)
  if (!d) return bad('unknown device key', 401)
  if (blockedId(env, d.id)) return BLOCKED()
  const parsed = await readJson(request)
  if (parsed.tooBig) return bad('body too large', 413)
  // A record without a token holds ids only, and is rewritten once a week even when unchanged (the "still here"), which
  // renews its expiry. A push device's list is written only when it changes.
  const idsOnly = !d.token
  if (idsOnly) {
    const extra = Object.keys(parsed.body).filter((k) => k !== 'follows')
    if (extra.length) return bad(`only follows may be sent here, not ${extra.sort().join(', ')}`)
  }
  const f = idsOnly ? parseIdFollows(parsed.body.follows) : parseFollows(parsed.body.follows)
  if ('error' in f) return bad(f.error)
  const changed = JSON.stringify(f.follows) !== JSON.stringify(d.follows)
  const stale = idsOnly && Date.now() - Date.parse(d.updated) >= STILL_HERE_MS
  if (changed || stale) await putDevice(env.KV, { ...d, follows: f.follows, updated: now() })
  return json({ follows: f.follows, unknown: [] })
}

const adminDevices = async (env, request) => {
  if (!(await isAdmin(env, request))) return bad('not allowed', 401)
  const cursor = new URL(request.url).searchParams.get('cursor') || undefined
  const page = await env.KV.list({ prefix: 'd:', limit: PAGE, cursor })
  const devices = []
  for (const k of page.keys) {
    const d = await getJson(env.KV, k.name)
    if (d && blockedId(env, d.id)) continue
    if (d) devices.push({ id: d.id, token: d.token ?? null, environment: d.environment ?? null, locale: d.locale ?? null, quiet: d.quiet ?? null, team: d.team === true, hourly: d.hourly === true, follows: d.follows, updated: d.updated })
  }
  return json({ devices, cursor: page.list_complete ? null : page.cursor })
}

/** r071-relay-dead-tokens: the Feed job reports devices whose APNs token came back dead (410, or 400 BadDeviceToken or
 *  DeviceTokenNotForTopic). Body { devices: [{ id, tokenSha }] }, tokenSha = sha256 hex of the lower-case token that failed.
 *  A record acts only while it still holds that token, so a device that registered a new token since the run loaded is left
 *  alone. A record without the follow-list opt-in is removed like DELETE /v1/devices/me (if the app is still installed, its
 *  next request gets 401 and it registers again). An opt-in record (hourly) keeps helping: it becomes the ids-only record
 *  POST /v1/follows makes (no token, environment, locale, quiet hours, team or alert levels), with the 90-day expiry.
 *  At most DEAD_BATCH ids a request: each costs up to 7 KV operations against the 50 a request allows. */
export const DEAD_BATCH = 6
const adminDead = async (env, request) => {
  if (!(await isAdmin(env, request))) return bad('not allowed', 401)
  const parsed = await readJson(request)
  if (parsed.tooBig) return bad('body too large', 413)
  const list = parsed.body.devices
  if (!Array.isArray(list) || list.length > DEAD_BATCH) return bad(`devices must be an array of at most ${DEAD_BATCH}`)
  if (!list.every((e) => e && typeof e.id === 'string' && /^[0-9a-f]{64}$/.test(e.tokenSha ?? ''))) return bad('each entry is { id, tokenSha }')
  const kv = env.KV
  const out = { removed: 0, cleared: 0, skipped: 0 }
  for (const { id, tokenSha } of list) {
    const d = await getJson(kv, `d:${id}`)
    if (!d || !d.token || (await sha(d.token)) !== tokenSha) {
      out.skipped++
      continue
    }
    if ((await kv.get(`t:${d.token}`)) === d.id) await kv.delete(`t:${d.token}`)
    if ((await kv.get(`tm:${d.id}`)) !== null) await kv.delete(`tm:${d.id}`)
    if (d.hourly === true) {
      const follows = d.follows.map((f) => (f.gameId ? { gameId: f.gameId } : { igdbId: f.igdbId }))
      await putDevice(kv, { id: d.id, key: d.key, token: null, follows, hourly: true, created: d.created, updated: now() })
      out.cleared++
    } else {
      await kv.delete(`d:${d.id}`)
      await kv.delete(`k:${await sha(d.key)}`)
      out.removed++
    }
  }
  return json(out)
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
  if (!(await signatureOk(env, request, raw))) {
    return bad('not allowed', 401)
  }
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

/** The Feed workflow's repository and file; the dispatch and the "already running" check both name them. */
const FEED_REPO = 'tezbo/playscribe'
const FEED_WORKFLOW = 'feed.yml'
/** A Feed run created this recently means GitHub's own schedule fired, so the cron does not start a second one. */
const FEED_RECENT_MS = 10 * 60_000
/** The Worker's hot cron; anything else is a full poll. deploy.sh registers both. */
export const FEED_HOT_CRON = '52 * * * *'
export const FEED_FULL_CRON = '22 * * * *'

/**
 * Starts the Feed workflow for a cron tick, unless a run began in the last 10 minutes. `hot` follows the cron that fired.
 * Returns what it did, for tests and the Worker log; never throws, because a cron handler has no one to answer.
 */
export async function dispatchFeed(env, cron, now = Date.now(), fetchImpl = fetch) {
  const token = env.FEED_DISPATCH_TOKEN
  if (!token) return { dispatched: false, reason: 'no FEED_DISPATCH_TOKEN' }
  const hot = cron === FEED_HOT_CRON
  const headers = { authorization: `Bearer ${token}`, accept: 'application/vnd.github+json', 'user-agent': 'playscribe-relay', 'x-github-api-version': '2022-11-28' }
  const base = `https://api.github.com/repos/${FEED_REPO}/actions/workflows/${FEED_WORKFLOW}`
  try {
    const recent = await fetchImpl(`${base}/runs?per_page=1`, { headers })
    if (recent.ok) {
      const { workflow_runs: runs = [] } = await recent.json()
      const last = runs[0]?.created_at ? Date.parse(runs[0].created_at) : 0
      if (now - last < FEED_RECENT_MS) return { dispatched: false, reason: 'a run started in the last 10 minutes', hot }
    }
    const r = await fetchImpl(`${base}/dispatches`, {
      method: 'POST', headers: { ...headers, 'content-type': 'application/json' },
      body: JSON.stringify({ ref: 'main', inputs: { action: 'poll', hot: hot ? 'true' : 'false' } }),
    })
    return r.status === 204 ? { dispatched: true, hot } : { dispatched: false, reason: `GitHub answered ${r.status}`, hot }
  } catch (e) {
    return { dispatched: false, reason: 'GitHub unreachable', hot }
  }
}

export default {
  async scheduled(controller, env, ctx) {
    const result = await dispatchFeed(env, controller.cron)
    console.log(`feed cron ${controller.cron}: ${JSON.stringify(result)}`)
  },
  async fetch(request, env) {
    const { pathname } = new URL(request.url)
    const m = request.method
    try {
      if (pathname === '/' || pathname === '/health') return json({ ok: true })
      if (pathname.startsWith('/v1/') && blockedAddress(env, request)) return BLOCKED()
      if (pathname === '/v1/devices' && m === 'POST') return await register(env, request)
      if (pathname === '/v1/devices/me' && m === 'PATCH') return await patchMe(env, request)
      if (pathname === '/v1/devices/me' && m === 'DELETE') return await deleteMe(env, request)
      if (pathname === '/v1/follows' && m === 'POST') return await registerFollows(env, request)
      if (pathname === '/v1/devices/me/follows' && m === 'PUT') return await putFollows(env, request)
      if (pathname === '/v1/devices/me/follows' && m === 'GET') {
        const d = await deviceFor(env.KV, request)
        if (!d) return bad('unknown device key', 401)
        return blockedId(env, d.id) ? BLOCKED() : json({ follows: d.follows })
      }
      if (pathname === '/v1/webhooks/asc' && m === 'POST') return await ascWebhook(env, request)
      if (pathname === '/admin/devices' && m === 'GET') return await adminDevices(env, request)
      if (pathname === '/admin/devices/dead' && m === 'POST') return await adminDead(env, request)
      return bad('not found', 404)
    } catch (e) {
      return bad('relay error', 500)
    }
  },
}
