import { now, tx, type DB } from './db.ts'
import { field, getPlatformRow, upsertPlatform } from './store.ts'
import type { Field, Platform, PlatformStatus } from './types.ts'

// The confirm job: a person has read an official post that names the platform. Their
// confirmation turns the row and its pending facts official. Reported (press) facts stay reported
// unless the person gives a value.
export interface ConfirmInput {
  sourceId: string
  status?: PlatformStatus
  version?: string
  sizeBytes?: number
  liveAt?: string
  bundles?: string[]
}

const promote = <T>(raw: string | null | undefined, sourceId: string): Field<T> | null => {
  const f = raw ? (JSON.parse(raw) as Field<T> | null) : null
  return f && f.verification === 'pending' ? { ...f, verification: 'official', sourceId, checkedAt: now() } : f
}

export const confirmPlatform = (db: DB, releaseId: string, platform: Platform, input: ConfirmInput) =>
  tx(db, () => {
    const row = getPlatformRow(db, releaseId, platform)
    const status = input.status ?? (row?.status !== 'unknown' ? row?.status : undefined) ?? 'live'
    upsertPlatform(db, releaseId, platform, {
      confirm: true,
      verification: 'official',
      status,
      version: input.version ? field(input.version, 'official', input.sourceId) : promote<string>(row?.version, input.sourceId),
      sizeBytes: input.sizeBytes ? field(input.sizeBytes, 'official', input.sourceId) : promote<number>(row?.size_bytes, input.sourceId),
      liveAt: input.liveAt ? field(input.liveAt, 'official', input.sourceId) : (promote<string>(row?.live_at, input.sourceId) ?? (status === 'live' ? field(now(), 'official', input.sourceId) : null)),
      bundles: input.bundles,
    })
    db.prepare(`UPDATE review_items SET resolved_at = ?, resolution = 'confirmed' WHERE release_id = ? AND platform = ? AND resolved_at IS NULL`).run(now(), releaseId, platform)
  })

export const dismissReview = (db: DB, id: number) =>
  Number(db.prepare(`UPDATE review_items SET resolved_at = ?, resolution = 'dismissed' WHERE id = ? AND resolved_at IS NULL`).run(now(), id).changes) > 0
