import { now, type DB } from '../db.ts'
import { getPlatformRow, getRelease } from '../store.ts'
import type { Apns, ApnsEnvironment } from './apns.ts'
import { tokenIsDead } from './apns.ts'

// Push rule (docs/ps5-patch-data.md): a release pushes when its PS5 row is live and official,
// exactly once, and never for press-only facts. Followers with notify "major" only hear about
// major updates.
export interface PushOutcome {
  releaseId: string
  sent: number
  failed: number
  skipped?: 'notOfficial' | 'alreadyPushed' | 'tooOld' | 'pushDisabled' | 'noApns'
}

export const pushPs5Release = async (db: DB, apns: Apns | null, releaseId: string, opts: { maxAgeHours: number; allow?: boolean }): Promise<PushOutcome> => {
  const out: PushOutcome = { releaseId, sent: 0, failed: 0 }
  const row = getPlatformRow(db, releaseId, 'ps5')
  const release = getRelease(db, releaseId)
  if (!row || !release || row.status !== 'live' || row.verification !== 'official') return { ...out, skipped: 'notOfficial' }
  // Claim the push before sending, so two runs can never both send it.
  const claimed = db.prepare('UPDATE platform_releases SET pushed_at = ? WHERE release_id = ? AND platform = ? AND pushed_at IS NULL').run(now(), releaseId, 'ps5')
  if (!Number(claimed.changes)) return { ...out, skipped: 'alreadyPushed' }
  if (opts.allow === false) return { ...out, skipped: 'pushDisabled' }
  const liveAt = (JSON.parse(row.live_at ?? 'null') as { value: string } | null)?.value ?? release.announcedAt
  if (Date.now() - Date.parse(liveAt) > opts.maxAgeHours * 3600_000) return { ...out, skipped: 'tooOld' }
  if (!apns) return { ...out, skipped: 'noApns' }

  const game = db.prepare('SELECT name FROM games WHERE id = ?').get(release.gameId) as { name: string }
  const version = (JSON.parse(row.version ?? 'null') as { value: string } | null)?.value
  const targets = db
    .prepare(
      `SELECT d.id, d.apns_token, d.environment FROM follows f JOIN devices d ON d.id = f.device_id
       WHERE f.game_id = ? AND d.apns_token IS NOT NULL AND (f.notify = 'all' OR (f.notify = 'major' AND ? = 'major'))`,
    )
    .all(release.gameId, release.kind) as { id: string; apns_token: string; environment: ApnsEnvironment }[]

  const payload = {
    aps: {
      alert: { title: game.name, body: `${release.displayName} is out on PS5${version ? ` (version ${version})` : ''}. See what changed.` },
      sound: 'default',
      'thread-id': release.gameId,
      'interruption-level': 'active',
      'relevance-score': release.kind === 'major' ? 1 : 0.5,
    },
    gameId: release.gameId,
    releaseId: release.id,
    kind: release.kind,
  }
  const log = db.prepare('INSERT INTO push_log (release_id, device_id, status, reason, sent_at) VALUES (?, ?, ?, ?, ?)')
  for (const t of targets) {
    try {
      const r = await apns.send(t.apns_token, t.environment, payload, { collapseId: release.id })
      log.run(releaseId, t.id, r.status, r.reason ?? null, now())
      if (r.status === 200) out.sent++
      else {
        out.failed++
        if (tokenIsDead(r)) db.prepare('UPDATE devices SET apns_token = NULL, updated_at = ? WHERE id = ?').run(now(), t.id)
      }
    } catch (e) {
      out.failed++
      log.run(releaseId, t.id, 0, (e as Error).message, now())
    }
  }
  return out
}
