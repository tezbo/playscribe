import { createHash } from 'node:crypto'
import { now, type DB } from './db.ts'
import { tagNotes } from './ingest/notes.ts'
import type { Field, Game, KindBasis, NoteSection, Platform, PlatformRelease, PlatformStatus, Release, ReleaseKind, Verification } from './types.ts'

// Reads and writes for the release model. Rows hold the spec's nested types as JSON.
type Row = Record<string, any>
const json = <T>(v: unknown, fallback: T): T => (typeof v === 'string' ? (JSON.parse(v) as T) : fallback)

export const coverUrl = (imageId: string) => `https://images.igdb.com/igdb/image/upload/t_cover_big_2x/${imageId}.jpg`

export const gameFromRow = (r: Row): Game => ({
  id: r.id,
  igdbId: r.igdb_id ?? null,
  name: r.name,
  cover: r.cover_image_id ? { imageId: r.cover_image_id, url: coverUrl(r.cover_image_id) } : null,
  ps5Release: r.ps5_release ?? null,
  ...(r.ps5_release_precision ? { ps5ReleasePrecision: r.ps5_release_precision } : {}),
  ps5TitleIds: json(r.ps5_title_ids, []),
})

export interface GameInput {
  id: string
  name: string
  igdbId?: number | null
  coverImageId?: string | null
  steamAppId?: number | null
  ps5Release?: string | null
  ps5ReleasePrecision?: string | null
  firstRelease?: string | null
  ps5TitleIds?: string[]
}

export const upsertGame = (db: DB, g: GameInput) => {
  db.prepare(
    `INSERT INTO games (id, igdb_id, name, cover_image_id, steam_app_id, ps5_release, ps5_release_precision, first_release, ps5_title_ids, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT (id) DO UPDATE SET
       igdb_id = COALESCE(excluded.igdb_id, igdb_id), name = excluded.name,
       cover_image_id = COALESCE(excluded.cover_image_id, cover_image_id),
       steam_app_id = COALESCE(excluded.steam_app_id, steam_app_id),
       ps5_release = COALESCE(excluded.ps5_release, ps5_release),
       -- The precision belongs to whichever date is stored, so it changes with the date.
       ps5_release_precision = CASE WHEN excluded.ps5_release IS NOT NULL OR excluded.ps5_release_precision IS NOT NULL THEN excluded.ps5_release_precision ELSE ps5_release_precision END,
       first_release = COALESCE(excluded.first_release, first_release),
       ps5_title_ids = CASE WHEN excluded.ps5_title_ids = '[]' THEN ps5_title_ids ELSE excluded.ps5_title_ids END`,
  ).run(g.id, g.igdbId ?? null, g.name, g.coverImageId ?? null, g.steamAppId ?? null, g.ps5Release ?? null, g.ps5ReleasePrecision ?? null, g.firstRelease ?? null, JSON.stringify(g.ps5TitleIds ?? []), now())
}

export const getGameRow = (db: DB, id: string) => db.prepare('SELECT * FROM games WHERE id = ?').get(id) as Row | undefined
export const getGameByIgdb = (db: DB, igdbId: number) => db.prepare('SELECT * FROM games WHERE igdb_id = ?').get(igdbId) as Row | undefined

const platformFromRow = (r: Row): PlatformRelease => ({
  platform: r.platform,
  status: r.status,
  version: json(r.version, null),
  sizeBytes: json(r.size_bytes, null),
  liveAt: json(r.live_at, null),
  bundles: json(r.bundles, []),
  verification: r.verification,
})

export const releaseFromRow = (db: DB, r: Row): Release => ({
  id: r.id,
  gameId: r.game_id,
  displayName: r.display_name,
  kind: r.kind,
  kindBasis: r.kind_basis,
  announcedAt: r.announced_at,
  // Tagged on read, so stored notes follow the current platform rules.
  notes: tagNotes(json(r.notes, [])),
  sourceIds: json(r.source_ids, []),
  platforms: (db.prepare('SELECT * FROM platform_releases WHERE release_id = ? ORDER BY platform').all(r.id) as Row[]).map(platformFromRow),
  revision: r.revision,
  updatedAt: r.updated_at,
})

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
}

const countItems = (notes: NoteSection[]) => notes.reduce((n, s) => n + s.items.length, 0)

/** Creates or merges a release. Returns the id and what changed. */
export const upsertRelease = (db: DB, input: ReleaseInput): { id: string; created: boolean; revised: boolean } => {
  const id = `${input.gameId}@${input.versionKey}`
  const existing = db.prepare('SELECT * FROM releases WHERE id = ?').get(id) as Row | undefined
  const t = now()
  if (!existing) {
    db.prepare(
      `INSERT INTO releases (id, game_id, version_key, display_name, kind, kind_basis, announced_at, notes, source_ids, content_hash, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    ).run(id, input.gameId, input.versionKey, input.displayName, input.kind, input.kindBasis, input.announcedAt, JSON.stringify(input.notes), JSON.stringify([input.sourceId]), hashNotes(input.displayName, input.notes), t, t)
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
  return { id, created: false, revised }
}

export const addSource = (db: DB, releaseId: string, sourceId: string) => {
  const r = db.prepare('SELECT source_ids FROM releases WHERE id = ?').get(releaseId) as Row | undefined
  const ids = new Set<string>(json(r?.source_ids, []))
  if (!r || ids.has(sourceId)) return
  ids.add(sourceId)
  db.prepare('UPDATE releases SET source_ids = ?, updated_at = ? WHERE id = ?').run(JSON.stringify([...ids]), now(), releaseId)
}

export const getPlatformRow = (db: DB, releaseId: string, platform: Platform) =>
  db.prepare('SELECT * FROM platform_releases WHERE release_id = ? AND platform = ?').get(releaseId, platform) as Row | undefined

export const field = <T>(value: T, verification: Verification, sourceId: string): Field<T> => ({ value, verification, sourceId, checkedAt: now() })

const RANK: Record<Verification, number> = { pending: 0, reported: 1, official: 2 }

/** A field only moves to an equal or stronger verification; official values are never overwritten automatically. */
const mergeField = <T>(old: Field<T> | null, next: Field<T> | null | undefined, force = false): Field<T> | null => {
  if (!next) return old
  if (!old || force || RANK[next.verification] > RANK[old.verification]) return next
  if (RANK[next.verification] === RANK[old.verification] && old.verification !== 'official') return next
  return old
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
  const liveAt = mergeField(json(old?.live_at, null), p.liveAt, p.confirm)
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
