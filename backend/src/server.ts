import { createHash, randomBytes, randomUUID, timingSafeEqual } from 'node:crypto'
import { Hono, type Context } from 'hono'
import { confirmPlatform, dismissReview, type ConfirmInput } from './confirm.ts'
import { now, type DB } from './db.ts'
import type { Igdb } from './ingest/igdb.ts'
import { runIngestExclusive } from './ingest/pipeline.ts'
import { extractNotes } from './ingest/notes.ts'
import { classify, nameRelease } from './ingest/classify.ts'
import type { Apns } from './push/apns.ts'
import { pushPs5Release } from './push/notify.ts'
import * as store from './store.ts'
import type { FetchFn } from './http.ts'
import type { NotifyLevel, Platform } from './types.ts'

// HTTP API, contract in docs/api.md. Public reads need no auth; device routes use the device key
// returned at registration; admin routes (review queue, confirm, ingest) use ADMIN_TOKEN.
export interface AppDeps {
  db: DB
  igdb: Igdb | null
  apns: Apns | null
  fetchFn: FetchFn
  adminToken?: string
  pushMaxAgeHours: number
  log?: (msg: string) => void
}

const PLATFORMS: Platform[] = ['ps5', 'xboxSeries', 'switch2', 'pc']
const NOTIFY: NotifyLevel[] = ['all', 'major', 'off']
const sha = (s: string) => createHash('sha256').update(s).digest('hex')
const bad = (c: Context, message: string, status: 400 | 401 | 404 | 409 | 503 = 400) => c.json({ error: message }, status)

export const createApp = (deps: AppDeps) => {
  const { db } = deps
  const app = new Hono()
  const searchCache = new Map<string, { at: number; body: unknown }>()

  app.onError((e, c) => {
    deps.log?.(`error ${c.req.method} ${c.req.path}: ${e.message}`)
    return c.json({ error: 'internal error' }, 500)
  })

  app.get('/v1/health', (c) => c.json({ ok: true, time: now() }))

  // ---- Games ----
  app.get('/v1/games/search', async (c) => {
    const q = (c.req.query('q') ?? '').trim()
    if (q.length < 2) return bad(c, 'q must be at least 2 characters')
    if (!deps.igdb) return bad(c, 'search is not configured', 503)
    const key = q.toLowerCase()
    const hit = searchCache.get(key)
    if (hit && Date.now() - hit.at < 6 * 3600_000) return c.json(hit.body)
    const games = await deps.igdb.searchPs5(q)
    const body = { games: games.map((g) => ({ igdbId: g.igdbId, name: g.name, cover: g.coverImageId ? { imageId: g.coverImageId, url: store.coverUrl(g.coverImageId) } : null, ps5Release: g.ps5Release })) }
    searchCache.set(key, { at: Date.now(), body })
    return c.json(body)
  })

  app.get('/v1/games/:id', (c) => {
    const row = store.getGameRow(db, c.req.param('id'))
    return row ? c.json(store.gameFromRow(row)) : bad(c, 'unknown game', 404)
  })

  app.get('/v1/games/:id/releases', (c) => {
    const id = c.req.param('id')
    if (!store.getGameRow(db, id)) return bad(c, 'unknown game', 404)
    return c.json({ releases: store.listReleases(db, [id], { limit: Number(c.req.query('limit') ?? 50) }) })
  })

  app.get('/v1/releases/:id', (c) => {
    const r = store.getRelease(db, c.req.param('id'))
    return r ? c.json(r) : bad(c, 'unknown release', 404)
  })

  // Changes since a cursor, for the given games: the app's sync call.
  app.get('/v1/feed', (c) => {
    const games = (c.req.query('games') ?? '').split(',').map((s) => s.trim()).filter(Boolean).slice(0, 200)
    const since = c.req.query('since') ?? undefined
    const releases = store.listReleases(db, games, { since, limit: 200 })
    const cursor = releases.reduce((m, r) => (r.updatedAt > m ? r.updatedAt : m), since ?? '')
    return c.json({ releases, cursor: cursor || now() })
  })

  // ---- Devices ----
  const device = (c: Context) => {
    const auth = c.req.header('authorization') ?? ''
    const key = auth.startsWith('Bearer ') ? auth.slice(7) : ''
    return key ? (db.prepare('SELECT * FROM devices WHERE key_hash = ?').get(sha(key)) as Record<string, any> | undefined) : undefined
  }

  /** Resolves a follow target: our id, or an IGDB id the app found in its PS5 index. */
  const resolveGame = async (f: { gameId?: string; igdbId?: number }) => {
    if (f.gameId) return store.getGameRow(db, f.gameId)?.id ?? null
    if (!f.igdbId) return null
    const known = store.getGameByIgdb(db, f.igdbId)
    if (known) return known.id as string
    if (!deps.igdb) return null
    const g = await deps.igdb.byId(f.igdbId)
    if (!g) return null
    store.upsertGame(db, { id: g.slug, name: g.name, igdbId: g.igdbId, coverImageId: g.coverImageId, steamAppId: g.steamAppId, ps5Release: g.ps5Release, firstRelease: g.firstRelease })
    return g.slug
  }

  const writeFollows = async (deviceId: string, follows: unknown) => {
    if (!Array.isArray(follows)) return { error: 'follows must be an array' }
    const resolved: { gameId: string; notify: NotifyLevel }[] = []
    const unknown: unknown[] = []
    for (const f of follows.slice(0, 500) as { gameId?: string; igdbId?: number; notify?: NotifyLevel }[]) {
      const notify = f.notify ?? 'all'
      if (!NOTIFY.includes(notify)) return { error: `notify must be one of ${NOTIFY.join(', ')}` }
      const gameId = await resolveGame(f)
      if (gameId) resolved.push({ gameId, notify })
      else unknown.push(f)
    }
    db.prepare('DELETE FROM follows WHERE device_id = ?').run(deviceId)
    const ins = db.prepare('INSERT OR REPLACE INTO follows (device_id, game_id, notify) VALUES (?, ?, ?)')
    for (const f of resolved) ins.run(deviceId, f.gameId, f.notify)
    return { follows: resolved, unknown }
  }

  app.post('/v1/devices', async (c) => {
    const body = (await c.req.json().catch(() => ({}))) as { apnsToken?: string; environment?: string; locale?: string; follows?: unknown }
    const env = body.environment ?? 'production'
    if (env !== 'sandbox' && env !== 'production') return bad(c, 'environment must be sandbox or production')
    if (body.apnsToken && !/^[0-9a-f]{64,200}$/i.test(body.apnsToken)) return bad(c, 'apnsToken must be hex')
    const id = randomUUID()
    const key = randomBytes(32).toString('base64url')
    const t = now()
    // A token moves to the newest registration (reinstall, restore to a new phone).
    if (body.apnsToken) db.prepare('UPDATE devices SET apns_token = NULL WHERE apns_token = ?').run(body.apnsToken.toLowerCase())
    db.prepare('INSERT INTO devices (id, key_hash, apns_token, environment, locale, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)').run(
      id, sha(key), body.apnsToken?.toLowerCase() ?? null, env, body.locale ?? null, t, t,
    )
    const f = body.follows ? await writeFollows(id, body.follows) : { follows: [], unknown: [] }
    if ('error' in f) return bad(c, f.error!)
    return c.json({ deviceId: id, deviceKey: key, ...f }, 201)
  })

  app.patch('/v1/devices/me', async (c) => {
    const d = device(c)
    if (!d) return bad(c, 'unknown device key', 401)
    const body = (await c.req.json().catch(() => ({}))) as { apnsToken?: string | null; environment?: string; locale?: string }
    if (body.environment && body.environment !== 'sandbox' && body.environment !== 'production') return bad(c, 'environment must be sandbox or production')
    if (body.apnsToken && !/^[0-9a-f]{64,200}$/i.test(body.apnsToken)) return bad(c, 'apnsToken must be hex')
    const token = body.apnsToken === undefined ? d.apns_token : body.apnsToken?.toLowerCase() ?? null
    if (token) db.prepare('UPDATE devices SET apns_token = NULL WHERE apns_token = ? AND id != ?').run(token, d.id)
    db.prepare('UPDATE devices SET apns_token = ?, environment = ?, locale = ?, updated_at = ? WHERE id = ?').run(token, body.environment ?? d.environment, body.locale ?? d.locale, now(), d.id)
    return c.json({ deviceId: d.id })
  })

  app.get('/v1/devices/me/follows', (c) => {
    const d = device(c)
    if (!d) return bad(c, 'unknown device key', 401)
    return c.json({ follows: db.prepare('SELECT game_id AS gameId, notify FROM follows WHERE device_id = ? ORDER BY game_id').all(d.id) })
  })

  app.put('/v1/devices/me/follows', async (c) => {
    const d = device(c)
    if (!d) return bad(c, 'unknown device key', 401)
    const body = (await c.req.json().catch(() => ({}))) as { follows?: unknown }
    const f = await writeFollows(d.id, body.follows)
    if ('error' in f) return bad(c, f.error!)
    return c.json(f)
  })

  app.delete('/v1/devices/me', (c) => {
    const d = device(c)
    if (!d) return bad(c, 'unknown device key', 401)
    db.prepare('DELETE FROM devices WHERE id = ?').run(d.id)
    return c.body(null, 204)
  })

  // ---- Admin: review queue, confirm, manual entry, ingest ----
  const admin = new Hono()
  admin.use('*', async (c, next) => {
    const given = Buffer.from((c.req.header('authorization') ?? '').replace(/^Bearer /, ''))
    const want = Buffer.from(deps.adminToken ?? '')
    if (!deps.adminToken || given.length !== want.length || !timingSafeEqual(given, want)) return bad(c, 'admin token required', 401)
    await next()
  })

  admin.get('/review', (c) => {
    const items = db.prepare('SELECT * FROM review_items WHERE resolved_at IS NULL ORDER BY created_at').all() as Record<string, any>[]
    return c.json({
      items: items.map((i) => ({ id: i.id, gameId: i.game_id, platform: i.platform, reason: i.reason, sourceId: i.source_id, url: i.url, title: i.title, createdAt: i.created_at, release: i.release_id ? store.getRelease(db, i.release_id) : null })),
    })
  })

  admin.post('/review/:id/dismiss', (c) => (dismissReview(db, Number(c.req.param('id'))) ? c.json({ ok: true }) : bad(c, 'no open review item with that id', 404)))

  admin.post('/releases/:id/platforms/:platform/confirm', async (c) => {
    const releaseId = c.req.param('id')
    const platform = c.req.param('platform') as Platform
    if (!PLATFORMS.includes(platform)) return bad(c, `platform must be one of ${PLATFORMS.join(', ')}`)
    if (!store.getRelease(db, releaseId)) return bad(c, 'unknown release', 404)
    const body = (await c.req.json().catch(() => ({}))) as ConfirmInput & { push?: boolean }
    if (!body.sourceId) return bad(c, 'sourceId is required: the official source the person checked')
    if (body.version && !/^\d{2}\.\d{3}\.\d{3}$/.test(body.version)) return bad(c, 'version must be the console form XX.YYY.ZZZ')
    confirmPlatform(db, releaseId, platform, body)
    const push = platform === 'ps5' ? await pushPs5Release(db, deps.apns, releaseId, { maxAgeHours: deps.pushMaxAgeHours, allow: body.push }) : null
    return c.json({ release: store.getRelease(db, releaseId), push })
  })

  // For sources marked fetch: manual (the site blocks bots): a person pastes the post.
  admin.post('/releases', async (c) => {
    const b = (await c.req.json().catch(() => ({}))) as { gameId?: string; title?: string; announcedAt?: string; body?: string; sourceId?: string; url?: string; platforms?: Platform[] }
    if (!b.gameId || !b.title || !b.announcedAt || !b.sourceId) return bad(c, 'gameId, title, announcedAt and sourceId are required')
    const game = store.getGameRow(db, b.gameId)
    if (!game) return bad(c, 'unknown game', 404)
    const naming = nameRelease(b.title, b.announcedAt)
    const notes = extractNotes(b.body ?? '')
    const k = classify({ title: b.title, notes, announcedAt: b.announcedAt, previousAnnouncedAt: store.previousAnnouncedAt(db, game.id, b.announcedAt), platformReleaseDate: game.ps5_release })
    const r = store.upsertRelease(db, { gameId: game.id, versionKey: naming.versionKey, displayName: naming.displayName, kind: k.kind, kindBasis: k.kindBasis, announcedAt: b.announcedAt, notes, sourceId: b.sourceId })
    for (const p of (b.platforms ?? []).filter((p) => PLATFORMS.includes(p)))
      store.upsertPlatform(db, r.id, p, { status: 'live', verification: 'pending', liveAt: store.field(b.announcedAt, 'pending', b.sourceId) })
    if (b.platforms?.includes('ps5')) store.addReviewItem(db, { releaseId: r.id, gameId: game.id, platform: 'ps5', reason: 'manualEntry', sourceId: b.sourceId, url: b.url ?? '', title: b.title })
    return c.json({ release: store.getRelease(db, r.id), created: r.created }, r.created ? 201 : 200)
  })

  admin.post('/ingest', async (c) => c.json(await runIngestExclusive({ db, fetchFn: deps.fetchFn, igdb: deps.igdb, log: deps.log }, { force: c.req.query('force') === '1' })))

  admin.get('/sources', (c) => c.json({ sources: db.prepare('SELECT * FROM source_state ORDER BY source_id').all() }))

  app.route('/v1/admin', admin)
  return app
}
