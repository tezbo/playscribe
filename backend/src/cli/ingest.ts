// One poll against the database at DATABASE_PATH.
//   npm run ingest [-- --force] [-- --export <dir>]
// --export writes the static feed (src/export.ts) after polling.
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
const summary = await runIngest(deps, { force: args.includes('--force') })
console.log(JSON.stringify(summary, null, 2))
if (exportDir) console.log('exported', exportStatic(db, exportDir))
if (summary.errors.length) for (const e of summary.errors) console.log(`::warning::${e.sourceId}: ${e.error}`)
db.close()
