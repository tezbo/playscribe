// Roadmap feed health: a source that fails three polls in a row is reported, once per run, in the workflow
// summary and as an error annotation. Pure over the database, so the CLI and tests share it.
import type { DB } from './db.ts'

export const FAIL_LIMIT = 3

export interface SourceHealth {
  sourceId: string
  failStreak: number
  lastStatus: number | null
  lastError: string | null
  lastFetchedAt: string | null
  blocked: boolean
}

export const failingSources = (db: DB, limit = FAIL_LIMIT): SourceHealth[] =>
  (db.prepare('SELECT * FROM source_state WHERE fail_streak >= ? ORDER BY fail_streak DESC, source_id').all(limit) as Record<string, any>[]).map((r) => ({
    sourceId: r.source_id,
    failStreak: r.fail_streak,
    lastStatus: r.last_status,
    lastError: r.last_error,
    lastFetchedAt: r.last_fetched_at,
    blocked: !!r.blocked,
  }))

/** Markdown for $GITHUB_STEP_SUMMARY; empty when everything is healthy. */
export const healthSummary = (rows: SourceHealth[]) =>
  rows.length
    ? ['## Feed health', '', `${rows.length} source${rows.length === 1 ? '' : 's'} failed ${FAIL_LIMIT} or more polls in a row:`, '', '| Source | Failures | Last status | Last error |', '|---|---|---|---|', ...rows.map((r) => `| ${r.sourceId} | ${r.failStreak} | ${r.lastStatus ?? ''} | ${(r.lastError ?? '').replace(/\|/g, '/').slice(0, 120)}${r.blocked ? ' (blocked: set fetch to manual)' : ''} |`), ''].join('\n')
    : ''
