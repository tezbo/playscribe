import { now, tx, type DB } from '../db.ts'
import { Blocked, allowedByRobots, type FetchFn } from '../http.ts'
import { registry, type SourceDef } from '../registry.ts'
import * as store from '../store.ts'
import type { Post } from '../types.ts'
import { fetchPosts, looksLikePatch } from './adapters.ts'
import { classify, consoleVersionOf, nameRelease, ps5StatusOf, sizeBytesOf } from './classify.ts'
import type { Igdb } from './igdb.ts'
import { extractNotes, mentionsPs5 } from './notes.ts'

// The poll job from docs/ps5-patch-data.md. Rules that matter:
//  - Only an official source that names PS5 can create a PS5 row, and only as `pending`; a person
//    confirms it (see confirm.ts) before it counts or pushes.
//  - Press (trust: secondary) fills PS5 facts as `reported` and never pushes.
//  - Steam is the PC signal. A Steam post that mentions PS5 is a lead for the review queue, never
//    a PS5 fact.
//  - Each source is polled at most hourly; robots.txt and 403s switch it off.

export interface IngestDeps {
  db: DB
  fetchFn: FetchFn
  igdb: Igdb | null
  log?: (msg: string) => void
}

export interface IngestSummary {
  polled: string[]
  skipped: string[]
  errors: { sourceId: string; error: string }[]
  created: string[]
  revised: string[]
  review: number
}

const MIN_POLL_MS = 55 * 60_000

const norm = (s: string) =>
  ` ${s
    .toLowerCase()
    .replace(/[®™]/g, '')
    .replace(/[^a-z0-9]+/g, ' ')
    .replace(/\bii\b/g, '2')
    .replace(/\biii\b/g, '3')
    .replace(/^the /, '')
    .trim()} `

export const matchesGame = (name: string, text: string) => {
  const n = norm(name).trim()
  return n.length >= 3 && norm(text).includes(` ${n} `)
}

/** Registry games are always tracked; any other game is tracked while a device follows it. */
export const trackedGames = (db: DB) =>
  db.prepare(`SELECT * FROM games WHERE id IN (${Object.keys(registry.games).map(() => '?').join(',') || "''"}) OR id IN (SELECT game_id FROM follows)`).all(...Object.keys(registry.games)) as Record<string, any>[]

export const sourcesFor = (game: Record<string, any>): SourceDef[] => {
  const reg = registry.games[game.id]
  if (reg) return reg.sources
  if (!game.steam_app_id) return []
  return [{ id: `steam-${game.steam_app_id}`, kind: 'steamNews', url: `https://store.steampowered.com/feeds/news/app/${game.steam_app_id}/`, platforms: ['pc'], trust: 'official', fetch: 'auto', ps5Signal: 'explicit' }]
}

/** Writes the registry games, filling ids, covers and PS5 release dates from IGDB when it is configured. */
export const seedGames = async (deps: IngestDeps) => {
  for (const [id, g] of Object.entries(registry.games)) {
    const existing = store.getGameRow(deps.db, id)
    let info = null
    if (deps.igdb && !existing?.cover_image_id) {
      const steamSource = g.sources.find((s) => s.kind === 'steamNews')
      const appid = steamSource ? Number(steamSource.url.match(/\/app\/(\d+)/)?.[1]) : null
      try {
        info = g.igdbId ? await deps.igdb.byId(g.igdbId) : appid ? await deps.igdb.bySteamAppId(appid) : null
      } catch (e) {
        deps.log?.(`igdb ${id}: ${(e as Error).message}`)
      }
    }
    store.upsertGame(deps.db, {
      id,
      name: g.name,
      igdbId: g.igdbId ?? info?.igdbId,
      coverImageId: info?.coverImageId,
      steamAppId: info?.steamAppId,
      ps5Release: info?.ps5Release,
      firstRelease: info?.firstRelease,
      ps5TitleIds: g.ps5TitleIds,
    })
  }
}

const due = (db: DB, s: SourceDef, force: boolean) => {
  const st = db.prepare('SELECT * FROM source_state WHERE source_id = ?').get(s.id) as Record<string, any> | undefined
  if (s.fetch !== 'auto' || st?.blocked) return false
  if (force) return true
  return !st?.last_fetched_at || Date.now() - Date.parse(st.last_fetched_at) >= MIN_POLL_MS
}

const recordState = (db: DB, sourceId: string, status: number, error: string | null, blocked = false) =>
  db
    .prepare(
      `INSERT INTO source_state (source_id, last_fetched_at, last_status, last_error, blocked) VALUES (?, ?, ?, ?, ?)
       ON CONFLICT (source_id) DO UPDATE SET last_fetched_at = excluded.last_fetched_at, last_status = excluded.last_status,
         last_error = excluded.last_error, blocked = MAX(blocked, excluded.blocked)`,
    )
    .run(sourceId, now(), status, error, blocked ? 1 : 0)

const poll = async (deps: IngestDeps, s: SourceDef, summary: IngestSummary): Promise<Post[] | null> => {
  try {
    if (s.kind !== 'steamNews' && !(await allowedByRobots(deps.fetchFn, s.url))) {
      recordState(deps.db, s.id, 0, 'disallowed by robots.txt', true)
      summary.errors.push({ sourceId: s.id, error: 'disallowed by robots.txt; set fetch to manual' })
      return null
    }
    const posts = await fetchPosts(deps.fetchFn, s)
    recordState(deps.db, s.id, 200, null)
    summary.polled.push(s.id)
    return posts
  } catch (e) {
    const blocked = e instanceof Blocked
    recordState(deps.db, s.id, blocked ? e.status : 0, (e as Error).message, blocked)
    summary.errors.push({ sourceId: s.id, error: blocked ? `${(e as Error).message}; set fetch to manual` : (e as Error).message })
    return null
  }
}

const handlePost = (deps: IngestDeps, game: Record<string, any>, s: SourceDef, post: Post, summary: IngestSummary) => {
  const { db } = deps
  const text = `${post.title}\n${post.body}`
  const track = (r: { id: string; created: boolean; revised: boolean }) => {
    if (r.created) summary.created.push(r.id)
    else if (r.revised) summary.revised.push(r.id)
    return r.id
  }
  const review = (releaseId: string | null, reason: string) => {
    const res = store.addReviewItem(db, { releaseId, gameId: game.id, platform: 'ps5', reason, sourceId: s.id, url: post.url, title: post.title })
    summary.review += Number(res.changes)
  }

  if (s.kind === 'html') {
    review(null, 'sourceLink')
    return null
  }

  const naming = nameRelease(post.title, post.publishedAt)
  const notes = extractNotes(post.body)
  const kind = () =>
    classify({ title: post.title, notes, announcedAt: post.publishedAt, previousAnnouncedAt: store.previousAnnouncedAt(db, game.id, post.publishedAt), platformReleaseDate: game.ps5_release })

  if (s.trust === 'secondary') {
    // Press: attach to the release it reports on, or record a silent update.
    if (!looksLikePatch(post.title)) return null
    const byKey = db.prepare('SELECT id FROM releases WHERE game_id = ? AND version_key = ?').get(game.id, naming.versionKey) as { id: string } | undefined
    const near = byKey
      ? null
      : (db
          .prepare(
            `SELECT id FROM releases WHERE game_id = ? AND ABS(julianday(announced_at) - julianday(?)) <= 3
             ORDER BY ABS(julianday(announced_at) - julianday(?)) LIMIT 1`,
          )
          .get(game.id, post.publishedAt, post.publishedAt) as { id: string } | undefined)
    const releaseId =
      byKey?.id ??
      near?.id ??
      track(store.upsertRelease(db, { gameId: game.id, versionKey: naming.versionKey, displayName: naming.displayName, kind: 'silent', kindBasis: 'inferred', announcedAt: post.publishedAt, notes: [], sourceId: s.id }))
    if (byKey || near) store.addSource(db, releaseId, s.id)
    const version = consoleVersionOf(text)
    const size = sizeBytesOf(text)
    store.upsertPlatform(db, releaseId, 'ps5', {
      status: 'live',
      verification: 'reported',
      version: version ? store.field(version, 'reported', s.id) : null,
      sizeBytes: size ? store.field(size, 'reported', s.id) : null,
      liveAt: store.field(post.publishedAt, 'reported', s.id),
    })
    return releaseId
  }

  const pcOnly = s.platforms.every((p) => p === 'pc')
  const namesPs5 = s.ps5Signal === 'always' || mentionsPs5(text)
  if (!pcOnly && !namesPs5) return null // an official multi-platform post that doesn't name PS5 says nothing about PS5

  const k = kind()
  const releaseId = track(store.upsertRelease(db, { gameId: game.id, versionKey: naming.versionKey, displayName: naming.displayName, kind: k.kind, kindBasis: k.kindBasis, announcedAt: post.publishedAt, notes, sourceId: s.id }))

  if (pcOnly) {
    store.upsertPlatform(db, releaseId, 'pc', { status: 'live', verification: 'official', liveAt: store.field(post.publishedAt, 'official', s.id) })
    if (mentionsPs5(text)) review(releaseId, 'steamMentionsPs5')
    return releaseId
  }

  const status = ps5StatusOf(text)
  const version = consoleVersionOf(text)
  const size = sizeBytesOf(text)
  store.upsertPlatform(db, releaseId, 'ps5', {
    status,
    verification: 'pending',
    version: version ? store.field(version, 'pending', s.id) : null,
    sizeBytes: size ? store.field(size, 'pending', s.id) : null,
    liveAt: status === 'live' ? store.field(post.publishedAt, 'pending', s.id) : null,
  })
  review(releaseId, 'officialPost')
  return releaseId
}

export const runIngest = async (deps: IngestDeps, opts: { force?: boolean } = {}): Promise<IngestSummary> => {
  const summary: IngestSummary = { polled: [], skipped: [], errors: [], created: [], revised: [], review: 0 }
  const games = trackedGames(deps.db)

  for (const game of games) {
    for (const s of sourcesFor(game)) {
      if (!due(deps.db, s, !!opts.force)) {
        summary.skipped.push(s.id)
        continue
      }
      const posts = await poll(deps, s, summary)
      // Oldest first, so hotfix inference sees the release before it.
      for (const post of (posts ?? []).sort((a, b) => a.publishedAt.localeCompare(b.publishedAt))) {
        if (store.isSeen(deps.db, s.id, post.postId)) continue
        tx(deps.db, () => store.markSeen(deps.db, s.id, post.postId, handlePost(deps, game, s, post, summary)))
      }
    }
  }

  for (const s of registry.shared) {
    if (!due(deps.db, s, !!opts.force)) {
      summary.skipped.push(s.id)
      continue
    }
    const posts = await poll(deps, s, summary)
    for (const post of (posts ?? []).sort((a, b) => a.publishedAt.localeCompare(b.publishedAt))) {
      if (store.isSeen(deps.db, s.id, post.postId)) continue
      tx(deps.db, () => {
        let releaseId: string | null = null
        // Shared feeds cover every game: a post counts only if its title names the game and reads like a patch.
        if (looksLikePatch(post.title))
          for (const game of games) if (matchesGame(game.name, post.title)) releaseId = handlePost(deps, game, s, post, summary) ?? releaseId
        store.markSeen(deps.db, s.id, post.postId, releaseId)
      })
    }
  }
  deps.log?.(`ingest: polled ${summary.polled.length}, new ${summary.created.length}, revised ${summary.revised.length}, review +${summary.review}, errors ${summary.errors.length}`)
  return summary
}

// One ingest at a time per process, whether the scheduler or an admin call started it.
let running: Promise<IngestSummary> | null = null
export const runIngestExclusive = (deps: IngestDeps, opts: { force?: boolean } = {}) =>
  (running ??= runIngest(deps, opts).finally(() => (running = null)))
