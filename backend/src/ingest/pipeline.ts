import { readFileSync } from 'node:fs'
import { hotGameIds, HOT_POLL_MS } from '../hot.ts'
import { now, tx, type DB } from '../db.ts'
import { Blocked, allowedByRobots, type FetchFn } from '../http.ts'
import { registry, type SourceDef } from '../registry.ts'
import * as store from '../store.ts'
import type { PlatformStatus, Post } from '../types.ts'
import newsSources from '../sources/news-sources.json' with { type: 'json' }
import { fetchPosts, looksLikePatch, type PageOpts } from './adapters.ts'
import { classify, consoleVersionOf, nameRelease, ps5LiveStated, ps5StatusOf, sizeBytesOf } from './classify.ts'
import { IGDB_REV, type Igdb } from './igdb.ts'
import { extractNotes, mentionsPs4, mentionsPs5, ps5PageOf } from './notes.ts'

// The poll job from docs/ps5-patch-data.md. Rules that matter:
//  - An official source that names PS5 decides its PS5 row. When the post says outright that
//    the update is live on PS5 (ps5LiveStated) the row is official at once (Terry, 2026-10-26:
//    press-only reports should be rare); otherwise it is `pending` until a person confirms it (confirm.ts).
//  - Press (trust: secondary) fills PS5 facts as `reported`. A press report that an update is live
//    earns no alert and is not shown until Steam or the studio has it; it never makes a row official.
//  - Steam is the source of truth for updates (Terry, 2026-10-27): every Steam patch is taken as out
//    on PS5 too (verification `assumed`, alerted like any other) unless the post says PS5 gets it later
//    or not at all, the game's Steam version is a separate PC port, or the post predates the PS5
//    release. A Steam post that says the update is live on PS5 makes the PS5 row official. Each
//    release keeps the Steam post and the studio's PS5 page for it (links), when one is found.
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

const norm = (s: string) => {
  const n = s
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[®™]/g, '')
    .replace(/'s\b/g, 's')
    .replace(/[^a-z0-9]+/g, ' ')
    .replace(/\bii\b/g, '2')
    .replace(/\biii\b/g, '3')
    .replace(/\biv\b/g, '4')
    .replace(/\bvii\b/g, '7')
    .trim()
  // "The Witcher 3" matches "Witcher 3"; "The Finals" keeps its "the", or it would match any final.
  return ` ${/^the \S+ \S/.test(n) ? n.slice(4) : n} `
}

/** Does the text name the game (or one of its aliases), and not one of the games it must not be confused with? */
export const matchesGame = (name: string, text: string, opts: { aliases?: string[]; exclude?: string[]; tags?: string[] } = {}) => {
  const t = norm(text)
  if ((opts.exclude ?? []).some((x) => t.includes(norm(x)))) return false
  const names = [name, ...(opts.aliases ?? [])].map(norm).filter((n) => n.trim().length >= 3)
  return names.some((n) => t.includes(n)) || (opts.tags ?? []).some((tag) => names.includes(norm(tag)))
}

const matchesPost = (game: Record<string, any>, post: Post) => {
  const reg = registry.games[game.id]
  return matchesGame(game.name, post.title, { aliases: reg?.aliases, exclude: reg?.exclude, tags: post.tags })
}

/** Press status from the headline first ("Live Now", "Next Week"), then the article. */
export const pressStatusOf = (title: string, body: string): PlatformStatus => {
  if (/\b(live|out|available|downloading|rolling out|released|arrives?|lands?|drops?|deployed|now)\b/i.test(title) && !/\b(next week|soon|upcoming|incoming|on the way|tomorrow|teased|planned|will)\b/i.test(title))
    return 'live'
  if (/\b(next week|soon|upcoming|incoming|on the way|tomorrow|teased|planned|will|detailed|dated|confirmed for|coming)\b/i.test(title)) return 'announced'
  return ps5StatusOf(body.slice(0, 600) || title)
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

/** Writes the registry games, filling ids, covers, key art and PS5 release dates from IGDB when it is configured. */
export const seedGames = async (deps: IngestDeps) => {
  for (const [id, g] of Object.entries(registry.games)) {
    const existing = store.getGameRow(deps.db, id)
    let info = null
    // Ask IGDB once per game, and again while its PS5 date is missing or still ahead (it can move or sharpen).
    const today = new Date().toISOString().slice(0, 10)
    if (deps.igdb && (!existing?.cover_image_id || existing.artwork_image_id == null || !existing.ps5_release || existing.ps5_release >= today || (existing.igdb_rev ?? 0) < IGDB_REV || (existing.full_release && existing.full_release >= today))) {
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
      artworkImageId: info?.artworkImageId,
      squareCoverImageId: info?.squareCoverImageId,
      steamAppId: info?.steamAppId,
      ps5Release: info?.ps5Release,
      ps5ReleasePrecision: info?.ps5ReleasePrecision,
      ...(info ? { eaSince: info.eaSince, fullRelease: info.fullRelease, igdbRev: IGDB_REV } : {}),
      firstRelease: info?.firstRelease,
      ps5TitleIds: g.ps5TitleIds,
    })
  }
}

/** A press report of a version this many days before the stored release of that number, or PS5_RECYCLED_DAYS after it, is a different patch. */
const PS5_ERA_GAP_DAYS = 45
const PS5_RECYCLED_DAYS = 365
const BLOCK_RETRY_MS = 24 * 3600e3
const due = (db: DB, s: SourceDef, force: boolean, minMs = MIN_POLL_MS) => {
  const st = db.prepare('SELECT * FROM source_state WHERE source_id = ?').get(s.id) as Record<string, any> | undefined
  if (s.fetch !== 'auto') return false
  // A block (403/429, or robots.txt) is retried politely, one request every BLOCK_RETRY_MS, and cleared by a success.
  // Push Square's 403 on 2026-10-31 was sticky: the press list was never read again, so no press report arrived after it.
  if (st?.blocked && Date.now() - Date.parse(st.last_fetched_at ?? 0) < BLOCK_RETRY_MS) return false
  if (force) return true
  return !st?.last_fetched_at || Date.now() - Date.parse(st.last_fetched_at) >= minMs
}

const recordState = (db: DB, sourceId: string, status: number, error: string | null, blocked = false) =>
  db
    .prepare(
      `INSERT INTO source_state (source_id, last_fetched_at, last_status, last_error, blocked, fail_streak) VALUES (?, ?, ?, ?, ?, CASE WHEN ? = 200 THEN 0 ELSE 1 END)
       ON CONFLICT (source_id) DO UPDATE SET last_fetched_at = excluded.last_fetched_at, last_status = excluded.last_status,
         last_error = excluded.last_error, blocked = excluded.blocked,
         fail_streak = CASE WHEN excluded.last_status = 200 THEN 0 ELSE fail_streak + 1 END`,
    )
    .run(sourceId, now(), status, error, blocked ? 1 : 0, status)

const poll = async (deps: IngestDeps, s: SourceDef, summary: IngestSummary, opts: PageOpts = {}): Promise<Post[] | null> => {
  try {
    if (s.kind !== 'steamNews' && !(await allowedByRobots(deps.fetchFn, s.url))) {
      recordState(deps.db, s.id, 0, 'disallowed by robots.txt', true)
      summary.errors.push({ sourceId: s.id, error: 'disallowed by robots.txt; set fetch to manual' })
      return null
    }
    const posts = await fetchPosts(deps.fetchFn, s, { ...opts, seen: (id) => store.isSeen(deps.db, s.id, id) })
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

const handlePost = (deps: IngestDeps, game: Record<string, any>, s: SourceDef, post: Post, summary: IngestSummary, ps4 = false) => {
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

  let naming = nameRelease(post.title, post.publishedAt)
  const notes = extractNotes(post.body, 'Changes', s.kind === 'steamNews' && (!game.ps5_release || post.publishedAt.slice(0, 10) < game.ps5_release))
  const kind = () =>
    classify({ title: post.title, notes, announcedAt: post.publishedAt, previousAnnouncedAt: store.previousAnnouncedAt(db, game.id, post.publishedAt), platformReleaseDate: game.ps5_release })

  if (s.trust === 'secondary') {
    // Press: attach to the release it reports on, or record a silent update.
    if (!looksLikePatch(post.title)) return null
    // The same version number months or years apart is a different patch (PS5 "1.03" in 2023, the PC port's "1.03" in 2025):
    // beyond PS5_ERA_GAP_DAYS the press report gets its own release, keyed by version and date, so history stays true.
    const sameKey = db.prepare('SELECT id, announced_at FROM releases WHERE game_id = ? AND version_key = ?').get(game.id, naming.versionKey) as { id: string; announced_at: string } | undefined
    // Press earlier than the stored patch by more than 45 days (PS5 era before a PC port), or later by more than a year (a recycled
    // version number). A port that merely lags by weeks or months is still the same patch.
    const gapDays = sameKey ? (Date.parse(sameKey.announced_at) - Date.parse(post.publishedAt)) / 86400e3 : 0
    const apart = gapDays > PS5_ERA_GAP_DAYS || gapDays < -PS5_RECYCLED_DAYS
    const byKey = apart ? undefined : sameKey
    if (apart) naming = { ...naming, versionKey: `${naming.versionKey}-${post.publishedAt.slice(0, 10)}` }
    // By date only when one side has no version: "Patch 1.7" is never the release "Update 1.6".
    const dateKey = /^[a-z]+-\d{4}-\d{2}-\d{2}$/
    const near = byKey
      ? null
      : (db
          .prepare(
            `SELECT id, version_key FROM releases WHERE game_id = ? AND ABS(julianday(announced_at) - julianday(?)) <= 3
             ORDER BY ABS(julianday(announced_at) - julianday(?))`,
          )
          .all(game.id, post.publishedAt, post.publishedAt) as { id: string; version_key: string }[]).find((r) => dateKey.test(naming.versionKey) || dateKey.test(r.version_key))
    // The same patch under another spelling of its version ("1.4" and "1.4.0"), announced within 3 days.
    const alike = byKey || near ? null : store.equivalentRelease(db, game.id, naming.versionKey, post.publishedAt)
    const releaseId =
      byKey?.id ??
      near?.id ??
      alike?.id ??
      // A press headline is the site's words, not a release name: without a version it is just a PS5 update.
      track(store.upsertRelease(db, { gameId: game.id, versionKey: naming.versionKey, displayName: /^[a-z]+-\d{4}-/.test(naming.versionKey) ? (ps4 ? 'PS4 update' : 'PS5 update') : naming.displayName, kind: 'silent', kindBasis: 'inferred', announcedAt: post.publishedAt, notes: [], sourceId: s.id, ps4 }))
    if (byKey || near || alike) store.addSource(db, releaseId, s.id)
    // A PS4 build number is never a PS5 version.
    const version = ps4 ? null : consoleVersionOf(text, { ps5Only: true })
    const size = sizeBytesOf(post.body) ?? sizeBytesOf(post.title)
    // A PS5-aware report joining a release once labelled PS4 means the game now has a native version: the label goes.
    if (!ps4) db.prepare('UPDATE releases SET ps4 = 0 WHERE id = ? AND ps4 = 1').run(releaseId)
    const status = pressStatusOf(post.title, post.body)
    store.upsertPlatform(db, releaseId, 'ps5', {
      status,
      verification: 'reported',
      version: version ? store.field(version, 'reported', s.id) : null,
      sizeBytes: size ? store.field(size, 'reported', s.id) : null,
      liveAt: status === 'live' ? store.field(post.publishedAt, 'reported', s.id) : null,
    })
    return releaseId
  }

  // A studio post that says the update is live on PS5: official without a person, so the release
  // is On PS5 and its pending review items are closed.
  const officialPs5 = (releaseId: string, ps5Only = true) => {
    db.prepare('UPDATE releases SET ps4 = 0 WHERE id = ? AND ps4 = 1').run(releaseId)
    const version = consoleVersionOf(text, { ps5Only })
    const size = sizeBytesOf(text)
    store.upsertPlatform(db, releaseId, 'ps5', {
      status: 'live',
      verification: 'official',
      version: version ? store.field(version, 'official', s.id) : null,
      sizeBytes: size ? store.field(size, 'official', s.id) : null,
      liveAt: store.field(post.publishedAt, 'official', s.id),
    })
    db.prepare(`UPDATE review_items SET resolved_at = ?, resolution = 'autoConfirmed' WHERE release_id = ? AND platform = 'ps5' AND resolved_at IS NULL`).run(now(), releaseId)
  }
  // A studio's own post that names PS5 is that update's PS5 page; a Steam post may link to one.
  const links = () => (s.kind === 'steamNews' ? { steamNotes: post.url, ps5Page: ps5PageOf(post.body) ?? undefined } : { ps5Page: post.url })

  const pcOnly = s.platforms.every((p) => p === 'pc')
  const namesPs5 = s.ps5Signal === 'always' || mentionsPs5(text)
  if (!pcOnly && !namesPs5) return null // an official multi-platform post that doesn't name PS5 says nothing about PS5

  const k = kind()
  // A studio or Steam post spelling a version another way ("1.4.0" for "1.4") joins the release already stored.
  const versionKey = store.equivalentRelease(db, game.id, naming.versionKey, post.publishedAt)?.version_key ?? naming.versionKey
  const releaseId = track(store.upsertRelease(db, { gameId: game.id, versionKey, displayName: naming.displayName, kind: k.kind, kindBasis: k.kindBasis, announcedAt: post.publishedAt, notes, sourceId: s.id }))

  if (pcOnly) {
    store.upsertPlatform(db, releaseId, 'pc', { status: 'live', verification: 'official', liveAt: store.field(post.publishedAt, 'official', s.id) })
    store.addLinks(db, releaseId, links())
    if (ps5LiveStated(text)) officialPs5(releaseId)
    else if (!registry.games[game.id]?.steamIsPcPort && !(game.ps5_release && post.publishedAt.slice(0, 10) < game.ps5_release)) {
      // Taken as out on PS5 too, unless the post says otherwise. Never the PC version or size: those are PC facts.
      const status = ps5StatusOf(text)
      store.upsertPlatform(db, releaseId, 'ps5', { status, verification: 'assumed', liveAt: status === 'live' ? store.field(post.publishedAt, 'assumed', s.id) : null })
      if (mentionsPs5(text)) review(releaseId, 'steamMentionsPs5')
    }
    return releaseId
  }
  store.addLinks(db, releaseId, links())

  if (ps5LiveStated(text)) {
    officialPs5(releaseId, s.ps5Signal !== 'always')
    return releaseId
  }
  const status = ps5StatusOf(text)
  const version = consoleVersionOf(text, { ps5Only: s.ps5Signal === 'always' })
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

export interface IngestOpts {
  force?: boolean
  /** Backfill: read each source's history back to this date (Steam's last 100 posts, press list pages). */
  until?: string
  /** Poll only the hot set (hot.ts), at the shorter hot interval, and skip the shared press sources. */
  hot?: boolean
}

export const runIngest = async (deps: IngestDeps, opts: IngestOpts = {}): Promise<IngestSummary> => {
  const summary: IngestSummary = { polled: [], skipped: [], errors: [], created: [], revised: [], review: 0 }
  const hot = hotGameIds(deps.db)
  const games = trackedGames(deps.db).filter((g) => !opts.hot || hot.has(g.id))

  for (const game of games) {
    for (const s of sourcesFor(game)) {
      if (!due(deps.db, s, !!opts.force, hot.has(game.id) ? HOT_POLL_MS : MIN_POLL_MS)) {
        summary.skipped.push(s.id)
        continue
      }
      const posts = await poll(deps, s, summary, { until: opts.until })
      // Oldest first, so hotfix inference sees the release before it.
      for (const post of (posts ?? []).sort((a, b) => a.publishedAt.localeCompare(b.publishedAt))) {
        // A backfill re-reads official posts already seen, so new rules apply to old releases; reading
      // is idempotent. Press posts are not re-read (each costs a page at the site's Crawl-delay).
      if (store.isSeen(deps.db, s.id, post.postId) && !(opts.until && s.trust === 'official')) continue
        if (post.news) {
          tx(deps.db, () => {
            if (s.kind === 'steamNews' && s.trust === 'official' && 'steamNews' in newsSources.sources) store.addNews(deps.db, game.id, post)
            store.markSeen(deps.db, s.id, post.postId, null)
          })
          continue
        }
        tx(deps.db, () => store.markSeen(deps.db, s.id, post.postId, handlePost(deps, game, s, post, summary)))
      }
    }
  }

  for (const s of opts.hot ? [] : registry.shared) {
    if (!due(deps.db, s, !!opts.force)) {
      summary.skipped.push(s.id)
      continue
    }
    const posts = await poll(deps, s, summary, { until: opts.until })
    for (const post of (posts ?? []).sort((a, b) => a.publishedAt.localeCompare(b.publishedAt))) {
      if (store.isSeen(deps.db, s.id, post.postId)) continue
      if (opts.until && post.publishedAt < opts.until) continue
      // Shared feeds cover every game: a post counts only if it names the game and reads like a patch;
      // a press list counts only posts about PS5.
      // A news-listed shared feed's non-patch posts that name a tracked game are news headlines (title, date, link); the
      // Push Square news feed is news only, its patch articles come through the press index.
      if (s.id in newsSources.sources && (!looksLikePatch(post.title) || s.id === 'pushsquare-news')) {
        tx(deps.db, () => {
          for (const g of games.filter((g) => matchesPost(g, post))) store.addNews(deps.db, g.id, post)
          store.markSeen(deps.db, s.id, post.postId, null)
        })
        continue
      }
      const namesPs5 = mentionsPs5(post.title) || (post.tags ?? []).some((t) => /^PS5$/i.test(t))
      // A PS4 patch counts for a game that plays on PS5 by backward compatibility: no native PS5 release, or the post
      // predates it (docs/ps5-patch-data.md). It is stored on the PS5 row and labelled ps4 on the release. This holds for
      // every shared source, so a PS4-only post from an RSS feed is never stored as a PS5 update.
      const aboutPs4 = !namesPs5 && (mentionsPs4(post.title) || (post.tags ?? []).some((t) => /^PS4$/i.test(t)))
      const aboutPs5 = !aboutPs4 && (s.kind !== 'pressIndex' || namesPs5)
      const playsOnPs5 = (g: Record<string, any>) => !g.ps5_release || post.publishedAt.slice(0, 10) < g.ps5_release
      // Only the press path labels ps4; an official shared post (PlayStation Blog) is about PS5 or it is left alone.
      const ps4Ok = aboutPs4 && s.trust === 'secondary'
      const matched = looksLikePatch(post.title) && (aboutPs5 || ps4Ok) ? games.filter((g) => matchesPost(g, post) && (aboutPs5 || playsOnPs5(g))) : []
      let full = post
      if (matched.length && post.expand) {
        try {
          full = { ...post, ...(await post.expand()) }
        } catch (e) {
          summary.errors.push({ sourceId: s.id, error: `${post.url}: ${(e as Error).message}` })
          continue // not marked seen, so the next run tries again
        }
      }
      tx(deps.db, () => {
        let releaseId: string | null = null
        for (const game of matched) releaseId = handlePost(deps, game, s, full, summary, ps4Ok) ?? releaseId
        store.markSeen(deps.db, s.id, post.postId, releaseId)
      })
    }
  }
  const folded = store.mergeSilentDuplicates(deps.db)
  if (folded) deps.log?.(`ingest: folded ${folded} press-only duplicates into the release they report`)
  const dropped = store.dropPreLaunchPs5(deps.db)
  if (dropped) deps.log?.(`ingest: dropped ${dropped} Steam-assumed PS5 rows dated before the game's PS5 launch`)
  const ps4Since = ps4SinceFromIndex()
  if (ps4Since) {
    const relabelled = store.labelPreLaunchPs4(deps.db, ps4Since)
    if (relabelled) deps.log?.(`ingest: labelled ${relabelled} press-reported releases dated before the PS5 era as PS4 updates`)
  } else deps.log?.('ingest: PS5 index not readable, skipped the PS4 relabel pass (fail closed)')
  const repaired = store.repairAssumedLiveAt(deps.db)
  if (repaired) deps.log?.(`ingest: moved ${repaired} Steam-assumed PS5 dates back to their Steam post`)
  const promoted = store.promoteAnnounced(deps.db)
  const settled = store.settleOldAnnouncements(deps.db)
  if (settled) deps.log?.(`ingest: ${settled} press announcements older than 30 days, with a later PS5 release live, now read as live`)
  deps.log?.(`ingest: promoted ${promoted} console-later Steam updates to live`)
  deps.log?.(`ingest: polled ${summary.polled.length}, new ${summary.created.length}, revised ${summary.revised.length}, review +${summary.review}, errors ${summary.errors.length}`)
  return summary
}

// One ingest at a time per process, whether the scheduler or an admin call started it.
let running: Promise<IngestSummary> | null = null
export const runIngestExclusive = (deps: IngestDeps, opts: IngestOpts = {}) =>
  (running ??= runIngest(deps, opts).finally(() => (running = null)))

/**
 * IGDB id to PS4 release day, from the bundled PS5 index (`b`: set only when the game had a PS4 release before its PS5 one).
 * Fails closed: undefined when the index cannot be read, and the passes that need it then do nothing (an empty map would
 * read as "no game had a PS4 release" and drop real rows).
 */
const ps4SinceCache = new Map<string, Map<number, string>>()
export const ps4SinceFromIndex = (url: URL = new URL('../../../ios/Playscribe/Resources/Data/ps5-index.json', import.meta.url)) => {
  const cached = ps4SinceCache.get(url.href)
  if (cached) return cached
  try {
    const raw = JSON.parse(readFileSync(url, 'utf8'))
    const map = new Map<number, string>()
    for (const g of raw.games ?? raw) if (typeof g.i === 'number' && typeof g.b === 'string') map.set(g.i, g.b)
    if (!map.size) return undefined
    ps4SinceCache.set(url.href, map)
    return map
  } catch {
    return undefined
  }
}
