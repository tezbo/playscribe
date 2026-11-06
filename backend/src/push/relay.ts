import { now, type DB } from '../db.ts'
import * as store from '../store.ts'

// The push relay (relay/worker.js) holds the devices. The Feed job loads them into the local database for the length of
// one run so notify.ts can address pushes, then scrubs them again before anything is published: the state database
// goes to the public `feed` branch, and an APNs token must never be in it. docs/push-relay.md.

export interface RelayDevice {
  id: string
  token: string
  environment: 'sandbox' | 'production'
  locale: string | null
  quiet: { from: number; until: number; timeZone: string } | null
  follows: { gameId?: string; igdbId?: number; notify: 'all' | 'major' | 'off' }[]
  updated: string
}

/** Replaces the devices table with the relay's list. Returns counts only; tokens are never logged. */
export const syncDevices = (db: DB, devices: RelayDevice[]) => {
  db.exec('DELETE FROM follows; DELETE FROM devices')
  // One token, one device: the newest registration wins (a relay race can leave two).
  const byToken = new Map<string, RelayDevice>()
  for (const d of [...devices].sort((a, b) => a.updated.localeCompare(b.updated))) byToken.set(d.token.toLowerCase(), d)
  const t = now()
  const insDevice = db.prepare('INSERT INTO devices (id, key_hash, apns_token, environment, locale, quiet_from, quiet_until, quiet_tz, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)')
  const insFollow = db.prepare('INSERT OR REPLACE INTO follows (device_id, game_id, notify) VALUES (?, ?, ?)')
  let devicesIn = 0
  let follows = 0
  let unknown = 0
  for (const [token, d] of byToken) {
    insDevice.run(d.id, `relay:${d.id}`, token, d.environment, d.locale, d.quiet?.from ?? null, d.quiet?.until ?? null, d.quiet?.timeZone ?? null, t, t)
    devicesIn++
    for (const f of d.follows) {
      const gameId = f.gameId ? store.getGameRow(db, f.gameId)?.id : f.igdbId ? (store.getGameByIgdb(db, f.igdbId)?.id as string | undefined) : undefined
      if (gameId) {
        insFollow.run(d.id, gameId, f.notify)
        follows++
      } else unknown++
    }
  }
  return { devices: devicesIn, follows, unknownFollows: unknown }
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
