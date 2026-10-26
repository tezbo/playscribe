// One poll against the database at DATABASE_PATH.
//   npm run ingest [-- --force] [-- --export <dir>] [-- --backfill 2024-01-01]
// --export writes the static feed (src/export.ts) after polling. --backfill reads every source's
// history back to that date (Steam's last 100 posts per game, the press update list page by page,
// at the site's Crawl-delay); it implies --force.
// After the poll, each PS5 update now live gets its one alert: standard when a studio post said so,
// quiet "Unconfirmed" when only the press did
// (only when PUSH_ENABLED=1 and APNs keys are set; otherwise it is marked as alerted and the app
// raises it locally from the feed's `alert`).
import { config } from '../config.ts'
import { openDb } from '../db.ts'
import { exportStatic } from '../export.ts'
import { Igdb } from '../ingest/igdb.ts'
import { runIngest, seedGames } from '../ingest/pipeline.ts'
import { Apns } from '../push/apns.ts'
import { pushNewPs5 } from '../push/notify.ts'

const args = process.argv.slice(2)
const exportDir = args.includes('--export') ? args[args.indexOf('--export') + 1] : undefined
const db = openDb(config.databasePath)
const igdb = config.twitch.clientId && config.twitch.clientSecret ? new Igdb(config.twitch.clientId, config.twitch.clientSecret) : null
const deps = { db, fetchFn: fetch, igdb, log: console.log }
await seedGames(deps)
const until = args.includes('--backfill') ? new Date(args[args.indexOf('--backfill') + 1]!).toISOString() : undefined
const summary = await runIngest(deps, { force: args.includes('--force') || !!until, until })
console.log(JSON.stringify(summary, null, 2))
const { keyId, teamId, key, topic } = config.apns
const apns = process.env.PUSH_ENABLED === '1' && keyId && teamId && key ? new Apns({ keyId, teamId, key, topic }) : null
const quiet = await pushNewPs5(db, apns, { maxAgeHours: config.pushMaxAgeHours })
if (quiet.length) console.log('alerts:', JSON.stringify(quiet))
apns?.close()
if (exportDir) console.log('exported', exportStatic(db, exportDir))
if (summary.errors.length) for (const e of summary.errors) console.log(`::warning::${e.sourceId}: ${e.error}`)
db.close()
