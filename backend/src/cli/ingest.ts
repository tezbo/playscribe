// One poll against the database at DATABASE_PATH.
//   npm run ingest [-- --force] [-- --export <dir>] [-- --backfill 2024-01-01]
// --export writes the static feed (src/export.ts) after polling. --backfill reads every source's
// history back to that date (Steam's last 100 posts per game, the press update list page by page,
// at the site's Crawl-delay); it implies --force.
import { config } from '../config.ts'
import { openDb } from '../db.ts'
import { exportStatic } from '../export.ts'
import { Igdb } from '../ingest/igdb.ts'
import { runIngest, seedGames } from '../ingest/pipeline.ts'

const args = process.argv.slice(2)
const exportDir = args.includes('--export') ? args[args.indexOf('--export') + 1] : undefined
const db = openDb(config.databasePath)
const igdb = config.twitch.clientId && config.twitch.clientSecret ? new Igdb(config.twitch.clientId, config.twitch.clientSecret) : null
const deps = { db, fetchFn: fetch, igdb, log: console.log }
await seedGames(deps)
const until = args.includes('--backfill') ? new Date(args[args.indexOf('--backfill') + 1]!).toISOString() : undefined
const summary = await runIngest(deps, { force: args.includes('--force') || !!until, until })
console.log(JSON.stringify(summary, null, 2))
if (exportDir) console.log('exported', exportStatic(db, exportDir))
if (summary.errors.length) for (const e of summary.errors) console.log(`::warning::${e.sourceId}: ${e.error}`)
db.close()
