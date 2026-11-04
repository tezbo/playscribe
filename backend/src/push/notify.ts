import type { Digest } from '../digest.ts'
import { alertFromOf, alertStyleOf, type AlertStyle } from '../alerts.ts'
import { now, type DB } from '../db.ts'
import { getPlatformRow, getRelease } from '../store.ts'
import type { Apns, ApnsEnvironment } from './apns.ts'
import { tokenIsDead } from './apns.ts'

// Push rule (docs/ps5-patch-data.md): a release alerts once, when its PS5 row goes live. Since
// 2026-10-27 that includes a Steam patch taken as out on PS5 (verification "assumed"); they all get
// the normal alert. A release only the press reports (neither Steam nor the studio has it) earns no
// alert and is not shown; if Steam or the studio later has it, it alerts then, once.
// A later confirmation does not alert again.
// Followers with notify "major" only hear about major updates.
export interface PushOutcome {
  releaseId: string
  sent: number
  failed: number
  style?: AlertStyle
  skipped?: 'notLive' | 'alreadyPushed' | 'tooOld' | 'pushDisabled' | 'noApns'
}

/** Counts only, no generated text; null when there is nothing to count. */
export const digestCounts = (d: Digest): string | null => {
  if (d.new + d.fixed + d.balance + d.ps5 === 0) return null
  return [d.new && `${d.new} new`, d.fixed && `${d.fixed} fixed`, d.balance && `${d.balance} balance`, d.ps5 && `${d.ps5} PS5-only`].filter(Boolean).join(', ')
}

/**
 * Alert copy (Iris): counts in the title, body "Update <version>: <headline>". The headline is the first clean new line
 * (digest.topNew); when it is missing, or the headings were poor, the body is the counts line, or "A new update is out" when there is nothing to count.
 */
export const alertCopy = (gameName: string, label: string, d: Digest): { title: string; body: string } => {
  const counts = digestCounts(d)
  const headline = d.topNew?.[0]
  return {
    title: counts ? `${gameName}: ${counts}` : gameName,
    body: headline ? `${label}: ${headline}` : counts ? `${counts}.` : 'A new update is out',
  }
}

export const pushPs5Release = async (db: DB, apns: Apns | null, releaseId: string, opts: { maxAgeHours: number; allow?: boolean }): Promise<PushOutcome> => {
  const out: PushOutcome = { releaseId, sent: 0, failed: 0 }
  const row = getPlatformRow(db, releaseId, 'ps5')
  const release = getRelease(db, releaseId)
  const style = row && release ? alertStyleOf(row as { status: string; verification: string }, release.links) : null
  if (!row || !release || !style) return { ...out, skipped: 'notLive' }
  out.style = style
  // Claim the push before sending, so two runs can never both send it.
  const claimed = db.prepare('UPDATE platform_releases SET pushed_at = ? WHERE release_id = ? AND platform = ? AND pushed_at IS NULL').run(now(), releaseId, 'ps5')
  if (!Number(claimed.changes)) return { ...out, skipped: 'alreadyPushed' }
  if (opts.allow === false) return { ...out, skipped: 'pushDisabled' }
  const liveAt = alertFromOf(row) ?? release.announcedAt
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
      alert: alertCopy(game.name, version ? `Update ${version}` : release.displayName, release.digest),
      sound: 'default',
      'thread-id': release.gameId,
      'interruption-level': 'active',
      'relevance-score': release.kind === 'major' ? 1 : 0.5,
    },
    gameId: release.gameId,
    releaseId: release.id,
    kind: release.kind,
    digest: { new: release.digest.new, fixed: release.digest.fixed, balance: release.digest.balance, ps5: release.digest.ps5 },
    verification: row.verification,
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

/** After a poll: the one alert for each PS5 row that is now live (none for a press-only report). */
export const pushNewPs5 = async (db: DB, apns: Apns | null, opts: { maxAgeHours: number; allow?: boolean }) => {
  const ids = db
    .prepare("SELECT release_id FROM platform_releases WHERE platform = 'ps5' AND status = 'live' AND pushed_at IS NULL")
    .all() as { release_id: string }[]
  const out: PushOutcome[] = []
  for (const { release_id } of ids) {
    const o = await pushPs5Release(db, apns, release_id, opts)
    if (o.skipped !== 'notLive') out.push(o)
  }
  return out
}
