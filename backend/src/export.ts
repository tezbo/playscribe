import { mkdirSync, readdirSync, rmSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import type { DB } from './db.ts'
import { gameFromRow, getRelease, listReleases, releaseFromRow } from './store.ts'

// Writes the read side of the API as static files, so the app can sync from any static host
// (the `feed` branch on GitHub, see .github/workflows/feed.yml). Shapes match docs/api.md.
//   v1/index.json          every game, with its newest release and when it last changed
//   v1/games/<id>.json     one game and all its releases
//   v1/latest.json         the 100 most recently changed releases, for a cheap "anything new?" check
//   v1/review.json         open review items (public post links only)
// Output is deterministic for the same data, so an unchanged run produces no commit.
const write = (path: string, data: unknown) => writeFileSync(path, JSON.stringify(data, null, 1) + '\n')

export const exportStatic = (db: DB, outDir: string) => {
  const root = join(outDir, 'v1')
  rmSync(join(root, 'games'), { recursive: true, force: true })
  mkdirSync(join(root, 'games'), { recursive: true })

  const games = (db.prepare('SELECT * FROM games ORDER BY id').all() as Record<string, any>[]).map(gameFromRow)
  const index = []
  let newest = ''
  for (const g of games) {
    const releases = listReleases(db, [g.id], { limit: 1000 })
    const updatedAt = releases.reduce((m, r) => (r.updatedAt > m ? r.updatedAt : m), '')
    if (updatedAt > newest) newest = updatedAt
    index.push({ ...g, latestReleaseId: releases[0]?.id ?? null, releaseCount: releases.length, updatedAt: updatedAt || null })
    write(join(root, 'games', `${g.id}.json`), { game: g, releases })
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
  write(join(root, 'latest.json'), { updatedAt: newest || null, releases: latest })
  write(join(root, 'review.json'), { items: review })
  return { games: games.length, files: readdirSync(join(root, 'games')).length + 3 }
}
