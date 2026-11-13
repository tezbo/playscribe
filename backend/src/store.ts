import { createHash } from 'node:crypto'
import { now, type DB } from './db.ts'
import newsSources from './sources/news-sources.json' with { type: 'json' }
import { alertOf } from './alerts.ts'
import { artworkUrl, squareCoverUrl } from './artwork.ts'
import { digestOf } from './digest.ts'
import { PS5_LAUNCH } from './ps5-dates.ts'
import { tagNotes } from './ingest/notes.ts'
import type { Field, Game, KindBasis, NoteSection, Platform, PlatformRelease, PlatformStatus, Release, ReleaseKind, ReleaseLinks, Verification } from './types.ts'

// Reads and writes for the release model. Rows hold the spec's nested types as JSON.
type Row = Record<string, any>
const json = <T>(v: unknown, fallback: T): T => (typeof v === 'string' ? (JSON.parse(v) as T) : fallback)

export const coverUrl = (imageId: string) => `https://images.igdb.com/igdb/image/upload/t_cover_big_2x/${imageId}.jpg`

export const gameFromRow = (r: Row): Game => ({
  id: r.id,
  igdbId: r.igdb_id ?? null,
  name: r.name,
  cover: r.cover_image_id ? { imageId: r.cover_image_id, url: coverUrl(r.cover_image_id) } : null,
  squareCover: r.square_cover_image_id ? { imageId: r.square_cover_image_id, url: squareCoverUrl(r.square_cover_image_id) } : null,
  artwork: r.artwork_image_id ? { imageId: r.artwork_image_id, url: artworkUrl(r.artwork_image_id) } : null,
  ps5Release: r.ps5_release ?? null,
  ...(r.ps5_release_precision ? { ps5ReleasePrecision: r.ps5_release_precision } : {}),
  // The label only runs while the 1.0 is ahead; the day it arrives the fields go without waiting for the next IGDB fetch.
  ...(r.ea_since && (!r.full_release || r.full_release > now().slice(0, 10)) ? { eaSince: r.ea_since, ...(r.full_release ? { fullRelease: r.full_release, ...(r.full_release_precision ? { fullReleasePrecision: r.full_release_precision } : {}) } : {}) } : {}),
  ps5TitleIds: json(r.ps5_title_ids, []),
})

export interface GameInput {
  id: string
  name: string
  igdbId?: number | null
  coverImageId?: string | null
  artworkImageId?: string | null
  squareCoverImageId?: string | null
  steamAppId?: number | null
  ps5Release?: string | null
  ps5ReleasePrecision?: string | null
  /** Set only by an IGDB fetch (with igdbRev): null then clears an earlier value. */
  eaSince?: string | null
  fullRelease?: string | null
  fullReleasePrecision?: string | null
  igdbRev?: number
  firstRelease?: string | null
  ps5TitleIds?: string[]
}

export const upsertGame = (db: DB, g: GameInput) => {
  db.prepare(
    `INSERT INTO games (id, igdb_id, name, cover_image_id, artwork_image_id, square_cover_image_id, steam_app_id, ps5_release, ps5_release_precision, first_release, ps5_title_ids, ea_since, full_release, full_release_precision, igdb_rev, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT (id) DO UPDATE SET
       igdb_id = COALESCE(excluded.igdb_id, igdb_id), name = excluded.name,
       cover_image_id = COALESCE(excluded.cover_image_id, cover_image_id),
       artwork_image_id = COALESCE(excluded.artwork_image_id, artwork_image_id),
       -- Fetched together with the key art, so it follows it.
       square_cover_image_id = CASE WHEN excluded.artwork_image_id IS NOT NULL THEN excluded.square_cover_image_id ELSE square_cover_image_id END,
       steam_app_id = COALESCE(excluded.steam_app_id, steam_app_id),
       ps5_release = COALESCE(excluded.ps5_release, ps5_release),
       -- The precision belongs to whichever date is stored, so it changes with the date.
       ps5_release_precision = CASE WHEN excluded.ps5_release IS NOT NULL OR excluded.ps5_release_precision IS NOT NULL THEN excluded.ps5_release_precision ELSE ps5_release_precision END,
       ea_since = CASE WHEN excluded.igdb_rev > 0 THEN excluded.ea_since ELSE ea_since END,
       full_release = CASE WHEN excluded.igdb_rev > 0 THEN excluded.full_release ELSE full_release END,
       full_release_precision = CASE WHEN excluded.igdb_rev > 0 THEN excluded.full_release_precision ELSE full_release_precision END,
       igdb_rev = MAX(igdb_rev, excluded.igdb_rev),
       first_release = COALESCE(excluded.first_release, first_release),
       ps5_title_ids = CASE WHEN excluded.ps5_title_ids = '[]' THEN ps5_title_ids ELSE excluded.ps5_title_ids END`,
  ).run(g.id, g.igdbId ?? null, g.name, g.coverImageId ?? null, g.artworkImageId ?? null, g.squareCoverImageId ?? null, g.steamAppId ?? null, g.ps5Release ?? null, g.ps5ReleasePrecision ?? null, g.firstRelease ?? null, JSON.stringify(g.ps5TitleIds ?? []), g.eaSince ?? null, g.fullRelease ?? null, g.fullReleasePrecision ?? null, g.igdbRev ?? 0, now())
}

/** Auto-onboarding: writes a derived game row. Never touches a hand-registered row (auto = 0) or one that already exists under another id. */
export const upsertAutoGame = (db: DB, g: GameInput & { steamIsPcPort?: boolean }) => {
  const existing = getGameRow(db, g.id)
  if (existing && !existing.auto) return false  // hand-registered; an auto row (1) or a retired one (2) is taken over
  upsertGame(db, g)
  db.prepare('UPDATE games SET auto = 1, steam_is_pc_port = ? WHERE id = ?').run(g.steamIsPcPort ? 1 : 0, g.id)
  return true
}

/** Auto rows no longer in the derived set (the game joined the hand registry, or lost its Steam link) are retired (auto = 2):
 * not polled, not exported, history kept. A later derivation that lists the id again reactivates it. Returns the count retired. */
export const retireAutoGames = (db: DB, keep: Set<string>) => {
  const rows = db.prepare('SELECT id FROM games WHERE auto = 1').all() as { id: string }[]
  let n = 0
  for (const { id } of rows) if (!keep.has(id)) { db.prepare('UPDATE games SET auto = 2 WHERE id = ?').run(id); n++ }
  return n
}

/** The next auto games to poll: never polled first, then the longest ago. Hand and followed games are polled every run anyway. */
export const nextAutoSlice = (db: DB, limit: number, exclude: Set<string>) =>
  (db.prepare('SELECT * FROM games WHERE auto = 1 AND steam_app_id IS NOT NULL ORDER BY auto_polled_at IS NOT NULL, auto_polled_at, id').all() as Row[])
    .filter((g) => !exclude.has(g.id))
    .slice(0, limit)

export const markAutoPolled = (db: DB, id: string) => db.prepare('UPDATE games SET auto_polled_at = ? WHERE id = ?').run(now(), id)

export const getGameRow = (db: DB, id: string) => db.prepare('SELECT * FROM games WHERE id = ?').get(id) as Row | undefined
export const getGameByIgdb = (db: DB, igdbId: number) => db.prepare('SELECT * FROM games WHERE igdb_id = ?').get(igdbId) as Row | undefined

const platformFromRow = (r: Row, links: ReleaseLinks): PlatformRelease => ({
  platform: r.platform,
  status: r.status,
  version: json(r.version, null),
  sizeBytes: json(r.size_bytes, null),
  liveAt: json(r.live_at, null),
  bundles: json(r.bundles, []),
  verification: r.verification,
  ...alertOf(r as { platform: string; status: string; verification: string; alert_from?: string | null; live_at?: string | null }, links),
})

export const releaseFromRow = (db: DB, r: Row): Release => {
  // Tagged on read, so stored notes follow the current platform rules.
  const sourceIds = json<string[]>(r.source_ids, [])
  const platformRows = db.prepare('SELECT * FROM platform_releases WHERE release_id = ? ORDER BY platform').all(r.id) as Row[]
  // Only a Steam-only release with no PS5 row: where a PS5 row exists the Steam post is about PS5 too (Quinn, #380).
  const notes = tagNotes(json(r.notes, []), sourceIds.length > 0 && sourceIds.every((id) => id.endsWith('-steam')) && !platformRows.some((p) => p.platform === 'ps5'))
  return {
    id: r.id,
    gameId: r.game_id,
    displayName: r.display_name,
    kind: r.kind,
    kindBasis: r.kind_basis,
    ...(r.ps4 ? { ps4: true as const } : {}),
    announcedAt: r.announced_at,
    notes,
    digest: digestOf(notes),
    sourceIds,
    links: json(r.links, {}),
    platforms: platformRows.map((p) => platformFromRow(p, json(r.links, {}))),
    revision: r.revision,
    updatedAt: r.updated_at,
  }
}

export const getRelease = (db: DB, id: string) => {
  const r = db.prepare('SELECT * FROM releases WHERE id = ?').get(id) as Row | undefined
  return r ? releaseFromRow(db, r) : null
}

export const listReleases = (db: DB, gameIds: string[], opts: { since?: string; limit?: number } = {}) => {
  if (!gameIds.length) return []
  const rows = db
    .prepare(
      `SELECT * FROM releases WHERE game_id IN (${gameIds.map(() => '?').join(',')}) AND updated_at > ?
       ORDER BY announced_at DESC LIMIT ?`,
    )
    .all(...gameIds, opts.since ?? '', opts.limit ?? 100) as Row[]
  return rows.map((r) => releaseFromRow(db, r))
}

export const previousAnnouncedAt = (db: DB, gameId: string, before: string) =>
  ((db.prepare('SELECT announced_at FROM releases WHERE game_id = ? AND announced_at < ? ORDER BY announced_at DESC LIMIT 1').get(gameId, before) as Row | undefined)
    ?.announced_at as string | undefined) ?? null

export const hashNotes = (displayName: string, notes: NoteSection[]) => createHash('sha256').update(JSON.stringify([displayName, notes])).digest('hex').slice(0, 32)

export interface ReleaseInput {
  gameId: string
  versionKey: string
  displayName: string
  kind: ReleaseKind
  kindBasis: KindBasis
  announcedAt: string
  notes: NoteSection[]
  sourceId: string
  /** A PS4 patch for a game that plays on PS5 (sticky once set). */
  ps4?: boolean
}

const countItems = (notes: NoteSection[]) => notes.reduce((n, s) => n + s.items.length, 0)

/** Creates or merges a release. Returns the id and what changed. */
export const upsertRelease = (db: DB, input: ReleaseInput): { id: string; created: boolean; revised: boolean } => {
  const id = `${input.gameId}@${input.versionKey}`
  const existing = db.prepare('SELECT * FROM releases WHERE id = ?').get(id) as Row | undefined
  const t = now()
  if (!existing) {
    db.prepare(
      `INSERT INTO releases (id, game_id, version_key, display_name, kind, kind_basis, announced_at, notes, source_ids, content_hash, created_at, updated_at, ps4)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    ).run(id, input.gameId, input.versionKey, input.displayName, input.kind, input.kindBasis, input.announcedAt, JSON.stringify(input.notes), JSON.stringify([input.sourceId]), hashNotes(input.displayName, input.notes), t, t, input.ps4 ? 1 : 0)
    return { id, created: true, revised: false }
  }
  const sourceIds = new Set<string>(json(existing.source_ids, []))
  sourceIds.add(input.sourceId)
  // Keep the fuller set of notes; a studio label beats an inferred kind; a silent (press-only)
  // release becomes a real one when an official post turns up.
  const oldNotes = json<NoteSection[]>(existing.notes, [])
  const notes = countItems(input.notes) > countItems(oldNotes) ? input.notes : oldNotes
  const studioWins = input.kindBasis === 'studio' || existing.kind_basis !== 'studio'
  const kind = existing.kind === 'silent' || studioWins ? input.kind : existing.kind
  const kindBasis = existing.kind === 'silent' || studioWins ? input.kindBasis : existing.kind_basis
  const displayName = existing.kind === 'silent' ? input.displayName : existing.display_name
  const announcedAt = input.announcedAt < existing.announced_at ? input.announcedAt : existing.announced_at
  const hash = hashNotes(displayName, notes)
  const revised = hash !== existing.content_hash || kind !== existing.kind
  const sourcesChanged = sourceIds.size !== json<string[]>(existing.source_ids, []).length
  if (revised || sourcesChanged || announcedAt !== existing.announced_at)
    db.prepare(
      `UPDATE releases SET display_name = ?, kind = ?, kind_basis = ?, announced_at = ?, notes = ?, source_ids = ?, content_hash = ?,
         revision = revision + ?, updated_at = ? WHERE id = ?`,
    ).run(displayName, kind, kindBasis, announcedAt, JSON.stringify(notes), JSON.stringify([...sourceIds]), hash, revised ? 1 : 0, t, id)
  if (input.ps4 && !existing.ps4) db.prepare('UPDATE releases SET ps4 = 1, updated_at = ? WHERE id = ?').run(t, id)
  return { id, created: false, revised }
}

export const addSource = (db: DB, releaseId: string, sourceId: string) => {
  const r = db.prepare('SELECT source_ids FROM releases WHERE id = ?').get(releaseId) as Row | undefined
  const ids = new Set<string>(json(r?.source_ids, []))
  if (!r || ids.has(sourceId)) return
  ids.add(sourceId)
  db.prepare('UPDATE releases SET source_ids = ?, updated_at = ? WHERE id = ?').run(JSON.stringify([...ids]), now(), releaseId)
}

/** Records where a release's notes live. The first Steam post and the first PS5 page found are kept. */
export const addLinks = (db: DB, releaseId: string, links: ReleaseLinks) => {
  const r = db.prepare('SELECT links FROM releases WHERE id = ?').get(releaseId) as Row | undefined
  if (!r) return
  const old = json<ReleaseLinks>(r.links, {})
  const next = { ...links, ...old }
  if (JSON.stringify(next) !== JSON.stringify(old)) db.prepare('UPDATE releases SET links = ?, updated_at = ? WHERE id = ?').run(JSON.stringify(next), now(), releaseId)
}

export const getPlatformRow = (db: DB, releaseId: string, platform: Platform) =>
  db.prepare('SELECT * FROM platform_releases WHERE release_id = ? AND platform = ?').get(releaseId, platform) as Row | undefined

export const field = <T>(value: T, verification: Verification, sourceId: string): Field<T> => ({ value, verification, sourceId, checkedAt: now() })

const RANK: Record<Verification, number> = { assumed: 0, pending: 1, reported: 2, official: 3 }

/** A field only moves to an equal or stronger verification; official values are never overwritten automatically. */
const mergeField = <T>(old: Field<T> | null, next: Field<T> | null | undefined, force = false): Field<T> | null => {
  if (!next) return old
  if (!old || force || RANK[next.verification] > RANK[old.verification]) return next
  if (RANK[next.verification] === RANK[old.verification] && old.verification !== 'official') return next
  // Roadmap 4/9: the same fact read again keeps its value and verification but carries the new fetch date.
  if (next.value === old.value && next.verification === old.verification) return { ...old, checkedAt: next.checkedAt }
  return old
}

/**
 * When a fact went live is the earliest evidence: a second post for the same release (a hotfix note, a re-post) must not
 * push a non-official date later. Stronger evidence still wins, and a confirmation overrides.
 */
const mergeLiveAt = (old: Field<string> | null, next: Field<string> | null | undefined, force = false): Field<string> | null => {
  if (old && next && !force && RANK[next.verification] === RANK[old.verification] && old.verification !== 'official' && next.value > old.value) return { ...old, checkedAt: next.checkedAt }
  return mergeField(old, next, force)
}

export interface PlatformInput {
  status?: PlatformStatus
  version?: Field<string> | null
  sizeBytes?: Field<number> | null
  liveAt?: Field<string> | null
  bundles?: string[]
  verification: Verification
  /** A person's confirmation: may overwrite official values. */
  confirm?: boolean
}

export const upsertPlatform = (db: DB, releaseId: string, platform: Platform, p: PlatformInput) => {
  const old = getPlatformRow(db, releaseId, platform)
  const t = now()
  const oldV = (old?.verification ?? 'pending') as Verification
  const verification = !old || p.confirm || RANK[p.verification] > RANK[oldV] ? p.verification : oldV
  // Status follows the strongest evidence: once confirmed, only another confirmation changes it.
  const status = p.status && (!old || p.confirm || oldV !== 'official') ? p.status : (old?.status ?? 'unknown')
  const version = mergeField(json(old?.version, null), p.version, p.confirm)
  const sizeBytes = mergeField(json(old?.size_bytes, null), p.sizeBytes, p.confirm)
  const liveAt = mergeLiveAt(json(old?.live_at, null), p.liveAt, p.confirm)
  const bundles = p.bundles ?? json(old?.bundles, [])
  db.prepare(
    `INSERT INTO platform_releases (release_id, platform, status, version, size_bytes, live_at, bundles, verification, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT (release_id, platform) DO UPDATE SET status = excluded.status, version = excluded.version, size_bytes = excluded.size_bytes,
       live_at = excluded.live_at, bundles = excluded.bundles, verification = excluded.verification, updated_at = excluded.updated_at`,
  ).run(releaseId, platform, status, JSON.stringify(version), JSON.stringify(sizeBytes), JSON.stringify(liveAt), JSON.stringify(bundles), verification, t)
  if (old && (old.status !== status || old.verification !== verification)) db.prepare('UPDATE releases SET updated_at = ? WHERE id = ?').run(t, releaseId)
  if (!old) db.prepare('UPDATE releases SET updated_at = ? WHERE id = ?').run(t, releaseId)
}

export const addReviewItem = (
  db: DB,
  item: { releaseId: string | null; gameId: string; platform: Platform; reason: string; sourceId: string; url: string; title: string },
) =>
  db
    .prepare(
      `INSERT INTO review_items (release_id, game_id, platform, reason, source_id, url, title, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT (source_id, url) DO NOTHING`,
    )
    .run(item.releaseId, item.gameId, item.platform, item.reason, item.sourceId, item.url, item.title, now())

export const markSeen = (db: DB, sourceId: string, postId: string, releaseId: string | null) =>
  db.prepare('INSERT OR IGNORE INTO seen_posts (source_id, post_id, release_id, seen_at) VALUES (?, ?, ?, ?)').run(sourceId, postId, releaseId, now())

export const isSeen = (db: DB, sourceId: string, postId: string) => !!db.prepare('SELECT 1 FROM seen_posts WHERE source_id = ? AND post_id = ?').get(sourceId, postId)

/**
 * Steam rule (Terry, 2026-10-27): a Steam patch counts as released on PS5. When its post said consoles get it
 * "next week", the PS5 row starts as announced; a week after the Steam release it is taken as live, dated
 * from Steam, so no update stays PC only. It earns its one alert when it goes live (alert_from), but only while the Steam post is
 * under 30 days old: for an older one the alert counts from the Steam date and stays silent (alerts.ts alertFromOf).
 */
/** A console-later Steam patch counts as live on PS5 this long after its Steam post (Terry, 2026-10-27). */
export const PS5_LIVE_AFTER_MS = 7 * 86400e3

export const promoteAnnounced = (db: DB, at = new Date(), quiet = false) => {
  const rows = db
    .prepare(
      `SELECT p.release_id, c.live_at AS pc_live FROM platform_releases p
       JOIN platform_releases c ON c.release_id = p.release_id AND c.platform = 'pc' AND c.status = 'live'
       WHERE p.platform = 'ps5' AND p.status = 'announced' AND p.verification = 'assumed' AND (p.live_at IS NULL OR p.live_at = 'null')`,
    )
    .all() as { release_id: string; pc_live: string | null }[]
  let n = 0
  for (const r of rows) {
    const pc = json<Field<string> | null>(r.pc_live, null)
    if (!pc?.value) continue
    const age = at.getTime() - Date.parse(pc.value)
    if (!(age >= PS5_LIVE_AFTER_MS)) continue
    upsertPlatform(db, r.release_id, 'ps5', { status: 'live', verification: 'assumed', liveAt: field(pc.value, 'assumed', pc.sourceId) })
    // Roadmap 11: its one alert (and the 72 h guard) counts from the moment it went live on PS5, a week after Steam, not from
    // Steam's date. Never from `at`: a run that reads the post long after that week (the first poll of an auto-onboarded game,
    // feed-stale-announced-rows) would otherwise publish a years-old patch as news. An hourly run promotes within the hour.
    // `quiet` (a backfill reading old posts): the alert counts from the Steam date, so the 72 h guard keeps it silent.
    const wentLive = new Date(Date.parse(pc.value) + PS5_LIVE_AFTER_MS).toISOString()
    db.prepare("UPDATE platform_releases SET alert_from = ? WHERE release_id = ? AND platform = 'ps5'").run(quiet ? pc.value : wentLive, r.release_id)
    n++
  }
  return n
}

/**
 * A post that stated a later time for the update (r050-feed-ps5-claim-fixes) left the PS5 row announced with that time as
 * live_at. Once the time has passed the row is live, and it earns its one alert from now. Official rows stay official:
 * this is the time the studio gave, not a person's confirmation, so it is a direct update.
 */
export const promoteStated = (db: DB, at = new Date(), quiet = false) => {
  const rows = db.prepare("SELECT release_id, live_at FROM platform_releases WHERE platform = 'ps5' AND status = 'announced' AND live_at IS NOT NULL").all() as { release_id: string; live_at: string }[]
  let n = 0
  for (const r of rows) {
    const f = json<Field<string> | null>(r.live_at, null)
    if (!f?.value || !(Date.parse(f.value) <= at.getTime())) continue
    // Its one alert counts from the moment it went live; a time long past (a backfill reading old posts) is not news, so the
    // alert guard sees that old time and stays quiet.
    const alertFrom = quiet || at.getTime() - Date.parse(f.value) > 6 * 3600e3 ? f.value : at.toISOString()
    db.prepare("UPDATE platform_releases SET status = 'live', alert_from = ?, updated_at = ? WHERE release_id = ? AND platform = 'ps5'").run(alertFrom, at.toISOString(), r.release_id)
    db.prepare('UPDATE releases SET updated_at = ? WHERE id = ?').run(at.toISOString(), r.release_id)
    n++
  }
  return n
}

/** PS5 rows held announced until a time their post stated (r050, #466): promoteStated takes each live once the time passes. */
export const heldPs5Rows = (db: DB) =>
  (db.prepare("SELECT COUNT(*) AS n FROM platform_releases WHERE platform = 'ps5' AND status = 'announced' AND live_at IS NOT NULL AND live_at != 'null'").get() as { n: number }).n

/**
 * The PS5 row this very post (source and post date) created under the old rules, if it is still untouched by anyone else.
 * Two posts of one source on the same day share a release (DDV: two Steam posts a minute apart): an assumed row written by
 * the later one, on the same UTC day and not before this post, is this post's as well.
 */
const ownPs5Row = (db: DB, releaseId: string, sourceId: string, publishedAt: string) => {
  const row = getPlatformRow(db, releaseId, 'ps5')
  const f = json<Field<string> | null>(row?.live_at, null)
  if (!row || !f || f.sourceId !== sourceId) return null
  if (f.value === publishedAt) return row
  return f.verification === 'assumed' && f.value > publishedAt && f.value.slice(0, 10) === publishedAt.slice(0, 10) ? row : null
}

/** True when this release's PS5 row is an assumed claim held announced until a time this source's post stated. */
export const heldByStatedTime = (db: DB, releaseId: string, sourceId: string) => {
  const row = getPlatformRow(db, releaseId, 'ps5')
  const f = json<Field<string> | null>(row?.live_at, null)
  return !!row && row.status === 'announced' && row.verification === 'assumed' && !!f?.value && f.sourceId === sourceId
}

/** Backfill repair: the post's old claim ("live at the post time") is replaced by what it really says. */
export const repairOwnLiveAt = (db: DB, releaseId: string, sourceId: string, publishedAt: string, liveAt: Field<string> | null, status: PlatformStatus) => {
  if (status === 'live' && liveAt?.value === publishedAt) return
  if (!ownPs5Row(db, releaseId, sourceId, publishedAt)) return
  db.prepare("UPDATE platform_releases SET status = ?, live_at = ?, alert_from = NULL, updated_at = ? WHERE release_id = ? AND platform = 'ps5'").run(status, JSON.stringify(liveAt), now(), releaseId)
  db.prepare('UPDATE releases SET updated_at = ? WHERE id = ?').run(now(), releaseId)
}

/** Backfill repair: a PS5 row that a test build or a PC-only post made is removed. */
export const dropOwnPs5Row = (db: DB, releaseId: string, sourceId: string, publishedAt: string) => {
  if (!ownPs5Row(db, releaseId, sourceId, publishedAt)) return
  db.prepare("DELETE FROM platform_releases WHERE release_id = ? AND platform = 'ps5'").run(releaseId)
  db.prepare('UPDATE releases SET updated_at = ? WHERE id = ?').run(now(), releaseId)
}

/**
 * History: a press-only announcement ("Patch 2.12 Will Rebalance...") more than 30 days old, in a game that has since had a
 * later release live on PS5, has happened. A patch announced and then delayed with nothing after it stays announced
 * (never claim an unconfirmed release). Safe to run every ingest.
 */
export const settleOldAnnouncements = (db: DB, at = new Date()) => {
  const rows = db
    .prepare(
      `SELECT r.id, r.announced_at FROM releases r JOIN platform_releases p ON p.release_id = r.id AND p.platform = 'ps5'
       WHERE p.status = 'announced' AND p.verification = 'reported' AND r.announced_at < ?
         AND EXISTS (SELECT 1 FROM releases l JOIN platform_releases lp ON lp.release_id = l.id AND lp.platform = 'ps5' AND lp.status = 'live' WHERE l.game_id = r.game_id AND l.announced_at > r.announced_at)`,
    )
    .all(new Date(at.getTime() - 30 * 86400e3).toISOString()) as { id: string; announced_at: string }[]
  for (const r of rows) upsertPlatform(db, r.id, 'ps5', { status: 'live', verification: 'reported', liveAt: field(r.announced_at, 'reported', 'pushsquare') })
  return rows.length
}

/** A news headline for a game: title, date and link only (roadmap 17). Never the post body. */
export const addNews = (db: DB, gameId: string, post: { url: string; title: string; publishedAt: string; sourceId: string }) =>
  db
    .prepare('INSERT OR IGNORE INTO news (game_id, url, title, published_at, source_id) VALUES (?, ?, ?, ?, ?)')
    .run(gameId, post.url, post.title.trim().slice(0, 200), post.publishedAt, post.sourceId)

const newsVerification = (sourceId: string): 'official' | 'reported' =>
  (newsSources.sources as Record<string, { verification?: string }>)[sourceId]?.verification === 'reported' ? 'reported' : 'official'

/**
 * Prune pass (r054-news-promo-merch-filter): news rows already stored whose headline the promo rule now hides. Steam posts are
 * markSeen, so without this the rows from before the rule stayed in the feed. Returns the removed rows for the log.
 */
export const pruneNews = (db: DB, hide: (title: string) => boolean) => {
  const rows = db.prepare('SELECT game_id, url, title FROM news').all() as { game_id: string; url: string; title: string }[]
  const gone = rows.filter((r) => hide(r.title))
  const del = db.prepare('DELETE FROM news WHERE game_id = ? AND url = ?')
  for (const r of gone) del.run(r.game_id, r.url)
  return gone.map((r) => ({ gameId: r.game_id, title: r.title }))
}

export const newsOf = (db: DB, gameId: string, limit = 20) =>
  (db.prepare('SELECT title, published_at, url, source_id FROM news WHERE game_id = ? ORDER BY published_at DESC, url LIMIT ?').all(gameId, limit) as { title: string; published_at: string; url: string; source_id: string }[]).map((n) => ({
    gameId,
    title: n.title,
    date: n.published_at,
    url: n.url,
    verification: newsVerification(n.source_id),
  }))

/**
 * Coverage audit, 2026-11-03: Steam patches dated before a game's PS5 launch were flagged live on PS5 when the
 * row was made before IGDB gave the PS5 date. Only rows taken as out on PS5 from Steam alone (`assumed`) are
 * dropped. A release whose only sources are Steam posts, announced more than a day before the PS5 launch (Steam re-dated old posts; BG3's 2021 patches), loses its PS5 row whatever its tag; launch-day patches stay. Anything a press source said about PS5 stays. Safe to run every ingest.
 */
// Each PS5 row looks up its own release by id (feed-hot-run-slow): the IN list it replaced was correlated on the row's
// verification, so SQLite read every release once per PS5 row, about 15 minutes of every run on the 12 Nov feed.
export const DROP_PRE_LAUNCH_PS5_SQL = `DELETE FROM platform_releases WHERE platform = 'ps5' AND EXISTS (
           SELECT 1 FROM releases r JOIN games g ON g.id = r.game_id
           WHERE r.id = platform_releases.release_id AND r.ps4 = 0 AND (
             (platform_releases.verification = 'assumed' AND substr(r.announced_at, 1, 10) < COALESCE(g.ps5_release, ?))
             OR (json_array_length(r.source_ids) > 0 AND NOT EXISTS (SELECT 1 FROM json_each(r.source_ids) WHERE value NOT LIKE '%-steam')
                 AND substr(r.announced_at, 1, 10) < date(COALESCE(g.ps5_release, ?), '-1 day'))))`
export const dropPreLaunchPs5 = (db: DB) => Number(db.prepare(DROP_PRE_LAUNCH_PS5_SQL).run(PS5_LAUNCH, PS5_LAUNCH).changes)

/**
 * Data trust audit (r050): a PS5 row that a press source reported for a post dated before the game's PS5 release (or
 * before the PS5 existed, when the game has no PS5 date) is a PS4-era patch when the game had a PS4 release by then
 * (`ps4Since`: IGDB id to the PS4 release day, from the bundled index's `b`). It plays on PS5 through backward
 * compatibility, so it is labelled "PS4 update" and carries no PS5 version. A PS5-only game's day-one patch, announced
 * before launch, is not touched. Safe to run every ingest.
 */
const shiftDay = (day: string, days: number) => new Date(Date.parse(`${day}T00:00:00Z`) + days * 86400e3).toISOString().slice(0, 10)
export const labelPreLaunchPs4 = (db: DB, ps4Since: Map<number, string>) => {
  const rows = db
    .prepare(
      `SELECT r.id, g.igdb_id AS igdb, g.ps5_release AS ps5, substr(r.announced_at, 1, 10) AS day FROM releases r JOIN games g ON g.id = r.game_id
       JOIN platform_releases pr ON pr.release_id = r.id AND pr.platform = 'ps5'
       WHERE r.ps4 = 0 AND pr.verification = 'reported'
         AND substr(r.announced_at, 1, 10) < COALESCE(g.ps5_release, ?)
         AND EXISTS (SELECT 1 FROM json_each(r.source_ids) WHERE value NOT LIKE '%-steam')`,
    )
    .all(PS5_LAUNCH) as { id: string; igdb: number | null; ps5: string | null; day: string }[]
  const label = db.prepare('UPDATE releases SET ps4 = 1 WHERE id = ?')
  const noVersion = db.prepare("UPDATE platform_releases SET version = NULL WHERE release_id = ? AND platform = 'ps5'")
  let n = 0
  for (const r of rows) {
    // No PS5 date at all means the game reaches PS5 only as its PS4 version, so any PS4-era press row is a PS4 update.
    const since = r.igdb == null ? undefined : ps4Since.get(r.igdb)
    // A post within a week of the game's PS5 release is its day-one patch (the Witcher 3 next-gen notes, two days ahead).
    if (r.ps5 !== null && (!since || r.day < since || r.day >= shiftDay(r.ps5, -7))) continue
    label.run(r.id)
    noVersion.run(r.id)
    n++
  }
  return n
}

/** "1.4" and "1.4.0" are the same patch: trailing zero parts are dropped, keeping two parts ("2.0" stays "2.0"). */
export const versionIdentity = (key: string) => {
  const parts = key.toLowerCase().split('.')
  if (!parts.every((p) => /^\d+$/.test(p))) return key.toLowerCase()
  while (parts.length > 2 && /^0+$/.test(parts[parts.length - 1]!)) parts.pop()
  return parts.join('.')
}

/**
 * The stored release that is the same patch under another spelling of its version ("Update 1.4" from the press,
 * "Update 1.4.0" from Steam), announced within 3 days. Months apart they are different patches and stay separate.
 */
export const equivalentRelease = (db: DB, gameId: string, versionKey: string, announcedAt: string): { id: string; version_key: string } | undefined => {
  const want = versionIdentity(versionKey)
  return (
    db
      .prepare(`SELECT id, version_key FROM releases WHERE game_id = ? AND version_key != ? AND ABS(julianday(announced_at) - julianday(?)) <= 3 ORDER BY ABS(julianday(announced_at) - julianday(?))`)
      .all(gameId, versionKey, announcedAt, announcedAt) as { id: string; version_key: string }[]
  ).find((r) => versionIdentity(r.version_key) === want)
}

/**
 * Repair for duplicates stored before equivalentRelease existed: a press-only (silent) release that is the same patch as a
 * real one is folded into it (its reported PS5 version and size, its source) and removed. Safe to run every ingest.
 */
export const mergeSilentDuplicates = (db: DB) => {
  let merged = 0
  const silent = db.prepare(`SELECT * FROM releases WHERE kind = 'silent'`).all() as Row[]
  for (const s of silent) {
    const target = equivalentRelease(db, s.game_id, s.version_key, s.announced_at)
    const t = target && (db.prepare('SELECT * FROM releases WHERE id = ?').get(target.id) as Row)
    if (!t || t.kind === 'silent') continue
    const ps5 = getPlatformRow(db, s.id, 'ps5')
    if (ps5) upsertPlatform(db, t.id, 'ps5', { status: ps5.status, verification: 'reported', version: json(ps5.version, null) ?? undefined, sizeBytes: json(ps5.size_bytes, null) ?? undefined })
    const sources = new Set<string>([...json<string[]>(t.source_ids, []), ...json<string[]>(s.source_ids, [])])
    db.prepare('UPDATE releases SET source_ids = ?, updated_at = ? WHERE id = ?').run(JSON.stringify([...sources]), now(), t.id)
    db.prepare('UPDATE review_items SET release_id = ? WHERE release_id = ?').run(t.id, s.id)
    db.prepare('DELETE FROM platform_releases WHERE release_id = ?').run(s.id)
    db.prepare('DELETE FROM releases WHERE id = ?').run(s.id)
    merged++
  }
  return merged
}

/**
 * Backfill repair: a post re-read under newer naming rules (10.2.2a, not 10.2) lands on a new release; the release the same
 * post made earlier, if that post was its only source and it was announced at the same moment, was a mislabelled copy and goes.
 */
export const dropSupersededRelease = (db: DB, oldId: string, newId: string, sourceId: string) => {
  const o = db.prepare('SELECT * FROM releases WHERE id = ?').get(oldId) as Row | undefined
  const n = db.prepare('SELECT * FROM releases WHERE id = ?').get(newId) as Row | undefined
  if (!o || !n || o.game_id !== n.game_id || o.announced_at !== n.announced_at) return false
  const sources = json<string[]>(o.source_ids, [])
  if (sources.length !== 1 || sources[0] !== sourceId) return false
  db.prepare('UPDATE review_items SET release_id = ? WHERE release_id = ?').run(newId, oldId)
  db.prepare('UPDATE seen_posts SET release_id = ? WHERE release_id = ?').run(newId, oldId)
  db.prepare('DELETE FROM platform_releases WHERE release_id = ?').run(oldId)
  db.prepare('DELETE FROM releases WHERE id = ?').run(oldId)
  return true
}

/**
 * Backfill repair: a release that an announcement headline ("Title Update coming this week!") made is removed when this post
 * is its only source and its day; a release other posts also feed only loses the PS5 row this post made.
 */
export const dropAnnouncementRelease = (db: DB, releaseId: string, sourceId: string, publishedAt: string) => {
  const r = db.prepare('SELECT * FROM releases WHERE id = ?').get(releaseId) as Row | undefined
  if (!r) return false
  const sources = json<string[]>(r.source_ids, [])
  if (sources.length !== 1 || sources[0] !== sourceId || r.announced_at !== publishedAt) {
    dropOwnPs5Row(db, releaseId, sourceId, publishedAt)
    return false
  }
  db.prepare('UPDATE review_items SET release_id = NULL WHERE release_id = ?').run(releaseId)
  db.prepare('UPDATE seen_posts SET release_id = NULL WHERE release_id = ?').run(releaseId)
  db.prepare('DELETE FROM platform_releases WHERE release_id = ?').run(releaseId)
  db.prepare('DELETE FROM releases WHERE id = ?').run(releaseId)
  return true
}
