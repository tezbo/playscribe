import { mkdirSync, readdirSync, rmSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import type { DB } from './db.ts'
import { issuesOf } from './issues.ts'
import { loadPlus } from './plus.ts'
import { storedPlusMonths, withPlusCovers } from './plusAuto.ts'
import { gameFromRow, getRelease, listReleases, newsOf, releaseFromRow } from './store.ts'

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
  for (const g of games) {
    const releases = listReleases(db, [g.id], { limit: 1000 })
    // Auto-onboarded games (0.5.4) are published once they have a release; until then the feed branch and the app's
    // index stay as small as the hand registry. Their news headlines are not kept (pipeline).
    if (autoIds.has(g.id) && releases.length === 0) continue
    const updatedAt = releases.reduce((m, r) => (r.updatedAt > m ? r.updatedAt : m), '')
    if (updatedAt > newest) newest = updatedAt
    index.push({ ...g, latestReleaseId: releases[0]?.id ?? null, releaseCount: releases.length, updatedAt: updatedAt || null })
    if (!autoIds.has(g.id)) write(join(root, 'news', `${g.id}.json`), { items: newsOf(db, g.id) })
    write(join(root, 'games', `${g.id}.json`), { game: g, releases, issues: issuesOf(g.id, releases) })
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
  write(join(root, 'latest.json'), { updatedAt: newest || '1970-01-01T00:00:00.000Z', releases: latest })
  write(join(root, 'review.json'), { items: review })
  // Manual months override the automatic ones, month by month.
  const manual = loadPlus(undefined, new Set(games.map((g) => g.id)))
  const months = new Map([...storedPlusMonths(db), ...manual.months].map((m) => [m.month, m]))
  write(join(root, 'plus.json'), { version: 1, months: withPlusCovers(db, [...months.values()]).sort((a, b) => (a.month < b.month ? 1 : -1)) })
  return { games: games.length - [...autoIds].filter((id) => !readdirSync(join(root, 'games')).includes(`${id}.json`)).length, files: readdirSync(join(root, 'games')).length * 2 + 3 }
}
