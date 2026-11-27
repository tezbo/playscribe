import { mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import type { DB } from './db.ts'
import { issuesOf } from './issues.ts'
import { loadPlus } from './plus.ts'
import { storedPlusMonths, withPlusCovers } from './plusAuto.ts'
import { registry } from './registry.ts'
import { gameFromRow, getRelease, listReleases, newsOf, releaseFromRow, sourceChecks } from './store.ts'

// Writes the read side of the API as static files, so the app can sync from any static host
// (the `feed` branch on GitHub, see .github/workflows/feed.yml). Shapes match docs/api.md.
//   v1/index.json          every game, with its newest release and when it last changed
//   v1/games/<id>.json     one game, all its releases and its known issues
//   v1/news/<id>.json      one game's news headlines (title, date, url), newest first
//   v1/latest.json         the 100 most recently changed releases, for a cheap "anything new?" check
//   v1/review.json         open review items (public post links only)
//   v1/plus.json           the hand-curated PS Plus monthly games (src/sources/plus.json)
// Output is deterministic for the same data, so an unchanged run produces no commit.
const write = (path: string, data: unknown) => writeFileSync(path, JSON.stringify(data, null, 1) + '\n')

/**
 * One game's files and its index entry (null when the game is not published: retired, or derived with no release yet).
 * Auto-onboarded games (0.5.4) are published once they have a release; until then the feed branch and the app's
 * index stay as small as the hand registry. Their news headlines are not kept (pipeline).
 */
const writeGame = (db: DB, root: string, g: ReturnType<typeof gameFromRow>, autoIds: Set<string>, retired: Set<string>) => {
  const releases = listReleases(db, [g.id], { limit: 1000 })
  if (retired.has(g.id) || (autoIds.has(g.id) && releases.length === 0)) return null
  const updatedAt = releases.reduce((m, r) => (r.updatedAt > m ? r.updatedAt : m), '')
  // A registry game with no patch source (registry `sourceGap`) is listed for its basics, but nothing fetches its patches: the
  // app must say it doesn't track its updates, not "No updates yet" (copy-untracked-no-updates-yet). Only that case carries the key.
  const noSource = registry.games[g.id]?.sources.length === 0
  if (!autoIds.has(g.id)) write(join(root, 'news', `${g.id}.json`), { items: newsOf(db, g.id) })
  write(join(root, 'games', `${g.id}.json`), { game: g, releases, issues: issuesOf(g.id, releases) })
  return { ...g, latestReleaseId: releases[0]?.id ?? null, releaseCount: releases.length, updatedAt: updatedAt || null, ...(noSource ? { patchSource: false } : {}) }
}

/**
 * A one-game check (relay "source on add"): rewrites only that game's files, its index entry, latest.json and source-checks.json
 * on top of the feed already in `outDir`. Returns false when there is no index to build on, and the caller exports everything.
 */
export const exportOneGame = (db: DB, outDir: string, gameId: string | null): boolean => {
  const root = join(outDir, 'v1')
  let current: { version: number; updatedAt: string | null; games: Record<string, any>[] }
  try { current = JSON.parse(readFileSync(join(root, 'index.json'), 'utf8')) } catch { return false }
  const row = gameId ? (db.prepare('SELECT * FROM games WHERE id = ?').get(gameId) as Record<string, any> | undefined) : undefined
  if (!gameId || !row) {
    // No game row (no source found, or IGDB does not know it): only the record of the check changes.
    write(join(root, 'source-checks.json'), { version: 1, checks: sourceChecks(db) })
    return !gameId
  }
  mkdirSync(join(root, 'news'), { recursive: true })
  mkdirSync(join(root, 'games'), { recursive: true })
  const autoIds = new Set((db.prepare('SELECT id FROM games WHERE auto = 1').all() as { id: string }[]).map((r) => r.id))
  const retired = new Set((db.prepare('SELECT id FROM games WHERE auto = 2').all() as { id: string }[]).map((r) => r.id))
  const entry = writeGame(db, root, gameFromRow(row), autoIds, retired)
  const games = current.games.filter((g) => g.id !== gameId)
  if (entry) games.push(entry)
  games.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0))
  const newest = [current.updatedAt ?? '', entry?.updatedAt ?? ''].reduce((m, x) => (x > m ? x : m), '')
  write(join(root, 'index.json'), { version: 1, updatedAt: newest || null, games })
  const latest = (db.prepare('SELECT * FROM releases ORDER BY updated_at DESC, id LIMIT 100').all() as Record<string, any>[]).map((r) => releaseFromRow(db, r))
  write(join(root, 'latest.json'), { updatedAt: newest || '1970-01-01T00:00:00.000Z', releases: latest })
  write(join(root, 'source-checks.json'), { version: 1, checks: sourceChecks(db) })
  return true
}

export const exportStatic = (db: DB, outDir: string) => {
  const root = join(outDir, 'v1')
  rmSync(join(root, 'games'), { recursive: true, force: true })
  rmSync(join(root, 'news'), { recursive: true, force: true })
  mkdirSync(join(root, 'news'), { recursive: true })
  mkdirSync(join(root, 'games'), { recursive: true })

  const games = (db.prepare('SELECT * FROM games ORDER BY id').all() as Record<string, any>[]).map(gameFromRow)
  const index = []
  let newest = ''
  const autoIds = new Set((db.prepare('SELECT id FROM games WHERE auto = 1').all() as { id: string }[]).map((r) => r.id))
  const retired = new Set((db.prepare('SELECT id FROM games WHERE auto = 2').all() as { id: string }[]).map((r) => r.id))
  for (const g of games) {
    const e = writeGame(db, root, g, autoIds, retired)
    if (!e) continue
    if (e.updatedAt && e.updatedAt > newest) newest = e.updatedAt
    index.push(e)
  }
  const latest = (db.prepare('SELECT * FROM releases ORDER BY updated_at DESC, id LIMIT 100').all() as Record<string, any>[]).map((r) => releaseFromRow(db, r))
  const review = (db.prepare('SELECT * FROM review_items WHERE resolved_at IS NULL ORDER BY created_at, id').all() as Record<string, any>[]).map((i) => ({
    id: i.id,
    gameId: i.game_id,
    platform: i.platform,
    reason: i.reason,
    sourceId: i.source_id,
    url: i.url,
    title: i.title,
    createdAt: i.created_at,
    releaseId: i.release_id,
    release: i.release_id ? getRelease(db, i.release_id) : null,
  }))
  // "updatedAt" is the newest data change, not the run time, so quiet runs leave files untouched.
  write(join(root, 'index.json'), { version: 1, updatedAt: newest || null, games: index })
  // latest.json's updatedAt must always be a date: the 0.2.0 app (Latest.updatedAt: Date) cannot decode null from an empty feed.
  // What the Feed found when a game was added in the app (docs/api.md): the app reads this for a game with no page yet. Ids and times only.
  write(join(root, 'source-checks.json'), { version: 1, checks: sourceChecks(db) })
  write(join(root, 'latest.json'), { updatedAt: newest || '1970-01-01T00:00:00.000Z', releases: latest })
  write(join(root, 'review.json'), { items: review })
  // Manual months override the automatic ones, month by month.
  const manual = loadPlus(undefined, new Set(games.map((g) => g.id)))
  const months = new Map([...storedPlusMonths(db), ...manual.months].map((m) => [m.month, m]))
  write(join(root, 'plus.json'), { version: 1, months: withPlusCovers(db, [...months.values()]).sort((a, b) => (a.month < b.month ? 1 : -1)) })
  const published = readdirSync(join(root, 'games'))
  return { games: published.length, files: published.length * 2 + 3 }
}
