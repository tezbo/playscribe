import { now, type DB } from '../db.ts'
import * as store from '../store.ts'

// The push relay (relay/worker.js) holds the devices. The Feed job loads them into the local database for the length of
// one run so notify.ts can address pushes, then scrubs them again before anything is published: the state database
// goes to the public `feed` branch, and an APNs token must never be in it. docs/push-relay.md.

export interface RelayDevice {
  id: string
  /** Null for the 0.5.4 follow-list opt-in (POST /v1/follows) and for a push device whose token was cleared. */
  token: string | null
  environment: 'sandbox' | 'production' | null
  locale: string | null
  quiet: { from: number; until: number; timeZone: string } | null
  /** The opt-in record holds ids only (no notify); a push device's follows carry the alert level. */
  follows: { gameId?: string; igdbId?: number; notify?: 'all' | 'major' | 'off' }[]
  /** "Help keep my games up to date": while true, the follows join the hourly tier (trackedGames). */
  hourly?: boolean
  updated: string
}

/** Replaces the devices table with the relay's list. Returns counts only; tokens are never logged. */
export const syncDevices = (db: DB, devices: RelayDevice[]) => {
  db.exec('DELETE FROM follows; DELETE FROM devices')
  // One token, one device: the newest registration wins (a relay race can leave two). A record without a token is its own device.
  const byKey = new Map<string, RelayDevice>()
  for (const d of [...devices].sort((a, b) => a.updated.localeCompare(b.updated))) byKey.set(d.token ? `t:${d.token.toLowerCase()}` : `id:${d.id}`, d)
  const t = now()
  const insDevice = db.prepare('INSERT INTO devices (id, key_hash, apns_token, environment, locale, quiet_from, quiet_until, quiet_tz, hourly, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)')
  const insFollow = db.prepare('INSERT OR REPLACE INTO follows (device_id, game_id, notify) VALUES (?, ?, ?)')
  let devicesIn = 0
  let hourly = 0
  let follows = 0
  let unknown = 0
  for (const d of byKey.values()) {
    insDevice.run(d.id, `relay:${d.id}`, d.token?.toLowerCase() ?? null, d.environment ?? 'production', d.locale, d.quiet?.from ?? null, d.quiet?.until ?? null, d.quiet?.timeZone ?? null, d.hourly ? 1 : 0, t, t)
    devicesIn++
    if (d.hourly) hourly++
    for (const f of d.follows) {
      const gameId = f.gameId ? store.getGameRow(db, f.gameId)?.id : f.igdbId ? (store.getGameByIgdb(db, f.igdbId)?.id as string | undefined) : undefined
      if (gameId) {
        insFollow.run(d.id, gameId, f.notify ?? 'all')
        follows++
      } else unknown++
    }
  }
  return { devices: devicesIn, hourly, follows, unknownFollows: unknown }
}

/** Removes every device and follow, then rewrites the file so no deleted page keeps a token. */
export const scrubDevices = (db: DB) => {
  db.exec('PRAGMA secure_delete = ON')
  db.exec('DELETE FROM follows; DELETE FROM devices')
  db.exec('PRAGMA wal_checkpoint(TRUNCATE)')
  db.exec('VACUUM')
}

/** The number of device rows left: the publish step refuses to go on when it is not zero. */
export const deviceRows = (db: DB) => Number((db.prepare('SELECT COUNT(*) AS n FROM devices').get() as { n: number }).n)
