import { createHash } from 'node:crypto'
import type { Digest } from '../digest.ts'
import { inQuietHours } from './quiet.ts'
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
/** The relay matches a dead report by this, so the token itself never has to be stored or sent back. */
export const tokenSha = (token: string) => createHash('sha256').update(token.toLowerCase()).digest('hex')

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

const MAX_HEADLINE = 60

/** Text before any colon, at most 60 characters, cut at a word boundary with an ellipsis only when cut. */
export const headlineOf = (line: string | undefined): string | null => {
  const text = (line ?? '').split(':')[0]!.replace(/\s+/g, ' ').trim()
  if (!text) return null
  if (text.length <= MAX_HEADLINE) return text
  const cut = text.slice(0, MAX_HEADLINE - 1)
  const at = cut.lastIndexOf(' ')
  return `${(at > 20 ? cut.slice(0, at) : cut).replace(/[\s,;.-]+$/, '')}…`
}

/**
 * Alert copy (Iris): counts in the title, body "Update <version>: <headline>". The headline is the first clean new line
 * (digest.topNew); when it is missing, or the headings were poor, the body is the counts line, or "A new update is out" when there is nothing to count.
 */
export const alertCopy = (gameName: string, label: string, d: Digest): { title: string; body: string } => {
  const counts = digestCounts(d)
  const headline = headlineOf(d.topNew?.[0])
  return {
    title: counts ? `${gameName}: ${counts}` : gameName,
    body: headline ? `${label}: ${headline}` : counts ? `${counts}.` : 'A new update is out',
  }
}

/** What one release's alert needs to be sent: the payload and the devices, with nothing left to read from the database. */
export interface PushJob {
  releaseId: string
  payload: { aps: Record<string, unknown>; [k: string]: unknown }
  targets: { id: string; token: string; environment: ApnsEnvironment; quiet: { from: number; until: number; timeZone: string } | null }[]
}

export interface PushDelivery {
  outcome: PushOutcome
  log: { deviceId: string; status: number; reason: string | null }[]
  dead: { id: string; tokenSha: string }[]
}

/**
 * Step one of a push: decide, and claim the release (pushed_at) in the database. Sends nothing. The feed job calls this during the
 * poll and sends only after Publish has put the claim on the feed branch (src/cli/ingest.ts, scripts/push-send.ts); a run that fails
 * before Publish loses its claim with the rest of the run, so the release is claimed again and never alerted from an unpublished state.
 */
export const preparePs5Push = (db: DB, releaseId: string, opts: { maxAgeHours: number; allow?: boolean; hasApns?: boolean }): { outcome: PushOutcome; job?: PushJob } => {
  const out: PushOutcome = { releaseId, sent: 0, failed: 0 }
  const row = getPlatformRow(db, releaseId, 'ps5')
  const release = getRelease(db, releaseId)
  const style = row && release ? alertStyleOf(row as { status: string; verification: string }, release.links) : null
  if (!row || !release || !style) return { outcome: { ...out, skipped: 'notLive' } }
  out.style = style
  // Claim the push before sending, so two runs can never both send it.
  const claimed = db.prepare('UPDATE platform_releases SET pushed_at = ? WHERE release_id = ? AND platform = ? AND pushed_at IS NULL').run(now(), releaseId, 'ps5')
  if (!Number(claimed.changes)) return { outcome: { ...out, skipped: 'alreadyPushed' } }
  if (opts.allow === false) return { outcome: { ...out, skipped: 'pushDisabled' } }
  const liveAt = alertFromOf(row) ?? release.announcedAt
  if (Date.now() - Date.parse(liveAt) > opts.maxAgeHours * 3600_000) return { outcome: { ...out, skipped: 'tooOld' } }
  if (opts.hasApns === false) return { outcome: { ...out, skipped: 'noApns' } }

  const game = db.prepare('SELECT name FROM games WHERE id = ?').get(release.gameId) as { name: string }
  const targets = db
    .prepare(
      `SELECT d.id, d.apns_token, d.environment, d.quiet_from, d.quiet_until, d.quiet_tz FROM follows f JOIN devices d ON d.id = f.device_id
       WHERE f.game_id = ? AND d.apns_token IS NOT NULL AND (f.notify = 'all' OR (f.notify = 'major' AND ? = 'major'))`,
    )
    .all(release.gameId, release.kind) as { id: string; apns_token: string; environment: ApnsEnvironment; quiet_from: number | null; quiet_until: number | null; quiet_tz: string | null }[]

  const payload = {
    aps: {
      alert: alertCopy(game.name, release.displayName, release.digest),
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
  return {
    outcome: out,
    job: {
      releaseId,
      payload,
      targets: targets.map((t) => ({
        id: t.id,
        token: t.apns_token,
        environment: t.environment,
        quiet: t.quiet_from === null || t.quiet_until === null || !t.quiet_tz ? null : { from: t.quiet_from, until: t.quiet_until, timeZone: t.quiet_tz },
      })),
    },
  }
}

/** Step two: send a prepared job. Touches no database; the caller records the log and the dead tokens. */
export const deliverPush = async (apns: Apns, job: PushJob, outcome: PushOutcome): Promise<PushDelivery> => {
  const out: PushOutcome = { ...outcome }
  const log: PushDelivery['log'] = []
  const dead: PushDelivery['dead'] = []
  // Inside the device's registered quiet hours the push is passive and silent; the 72 h guard and the once-only claim are unchanged.
  const forDevice = (t: PushJob['targets'][number]) => {
    if (!t.quiet || !inQuietHours({ from: t.quiet.from, until: t.quiet.until, timeZone: t.quiet.timeZone })) return job.payload
    const { sound: _sound, ...aps } = job.payload.aps
    return { ...job.payload, aps: { ...aps, 'interruption-level': 'passive' } }
  }
  for (const t of job.targets) {
    try {
      const r = await apns.send(t.token, t.environment, forDevice(t), { collapseId: job.releaseId })
      log.push({ deviceId: t.id, status: r.status, reason: r.reason ?? null })
      if (r.status === 200) out.sent++
      else {
        out.failed++
        if (tokenIsDead(r)) dead.push({ id: t.id, tokenSha: tokenSha(t.token) })
      }
    } catch (e) {
      out.failed++
      log.push({ deviceId: t.id, status: 0, reason: (e as Error).message })
    }
  }
  return { outcome: out, log, dead }
}

/** Prepare and send in one go (local runs and tests): the old behaviour, claim then send. */
export const pushPs5Release = async (db: DB, apns: Apns | null, releaseId: string, opts: { maxAgeHours: number; allow?: boolean }): Promise<PushOutcome> => {
  const { outcome, job } = preparePs5Push(db, releaseId, { ...opts, hasApns: !!apns })
  if (!job || !apns) return outcome
  const d = await deliverPush(apns, job, outcome)
  const ins = db.prepare('INSERT INTO push_log (release_id, device_id, status, reason, sent_at) VALUES (?, ?, ?, ?, ?)')
  for (const l of d.log) ins.run(releaseId, l.deviceId, l.status, l.reason, now())
  for (const x of d.dead) {
    // Dropped for the rest of this run, and noted so relay-dead.ts can tell the relay, which holds the lasting copy (r071).
    db.prepare('UPDATE devices SET apns_token = NULL, updated_at = ? WHERE id = ?').run(now(), x.id)
    db.prepare('INSERT OR REPLACE INTO dead_tokens (device_id, token_sha, found_at) VALUES (?, ?, ?)').run(x.id, x.tokenSha, now())
  }
  return d.outcome
}

/** After a poll in the feed job: claim every PS5 row now live and return the jobs to send after Publish (nothing is sent here). */
export const queueNewPs5 = (db: DB, opts: { maxAgeHours: number; allow?: boolean; hasApns?: boolean }) => {
  const ids = db.prepare("SELECT release_id FROM platform_releases WHERE platform = 'ps5' AND status = 'live' AND pushed_at IS NULL").all() as { release_id: string }[]
  const outcomes: PushOutcome[] = []
  const jobs: { job: PushJob; outcome: PushOutcome }[] = []
  for (const { release_id } of ids) {
    const r = preparePs5Push(db, release_id, opts)
    if (r.outcome.skipped === 'notLive') continue
    outcomes.push(r.outcome)
    if (r.job) jobs.push({ job: r.job, outcome: r.outcome })
  }
  return { outcomes, jobs }
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
