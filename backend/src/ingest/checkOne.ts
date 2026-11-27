// Source on add (s-07-source-on-add-backend): one IGDB game through the Feed, asked for by the relay route POST /v1/sources/check.
// Finds the game (the feed's own row, else IGDB for its Steam page), reads its sources now, and records what was found with the time.
import { listReleases, recordSourceCheck, type SourceCheckStatus, upsertAutoGame } from '../store.ts'
import { slugOf } from './autoRegistry.ts'
import { runIngest, sourcesFor, type IngestDeps } from './pipeline.ts'

export interface CheckResult { igdbId: number; gameId: string | null; status: SourceCheckStatus; releases: number }

export const checkOneGame = async (deps: IngestDeps, igdbId: number): Promise<CheckResult> => {
  const { db } = deps
  const done = (c: Omit<CheckResult, 'igdbId'>, name: string | null): CheckResult => {
    recordSourceCheck(db, { igdbId, name, ...c })
    return { igdbId, ...c }
  }
  let row = db.prepare('SELECT * FROM games WHERE igdb_id = ? AND auto <> 2').get(igdbId) as Record<string, any> | undefined
  if (!row) {
    const g = deps.igdb ? await deps.igdb.byId(igdbId) : null
    if (!g) return done({ gameId: null, status: 'unknown', releases: 0 }, null)
    if (!g.steamAppId) return done({ gameId: null, status: 'no-source', releases: 0 }, g.name)
    const id = slugOf({ i: igdbId, n: g.name })
    upsertAutoGame(db, { id, name: g.name, igdbId, steamAppId: g.steamAppId, coverImageId: g.coverImageId, artworkImageId: g.artworkImageId || null, ps5Release: g.ps5Release, ps5ReleasePrecision: g.ps5ReleasePrecision })
    row = db.prepare('SELECT * FROM games WHERE id = ?').get(id) as Record<string, any>
  }
  if (!sourcesFor(row).length) return done({ gameId: row.id, status: 'no-source', releases: 0 }, row.name)
  // Recorded before the read, so the game is kept out of the derived set's retirement even if the read fails.
  recordSourceCheck(db, { igdbId, gameId: row.id, name: row.name, status: 'polled', releases: 0 })
  await runIngest(deps, { force: true, games: [row.id], named: true })
  return done({ gameId: row.id, status: 'polled', releases: listReleases(db, [row.id], { limit: 1000 }).length }, row.name)
}
