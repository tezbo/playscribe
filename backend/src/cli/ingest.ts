// One poll against the database at DATABASE_PATH.
//   npm run ingest [-- --hot] [-- --force] [-- --export <dir>] [-- --backfill 2024-01-01]
// --hot polls only the hot set (src/hot.ts) every 25 minutes, with no shared press sources.
// --export writes the static feed (src/export.ts) after polling. --backfill reads every source's
// history back to that date (Steam's last 100 posts per game, the press update list page by page,
// at the site's Crawl-delay); it implies --force.
// After the poll, each PS5 update now live gets its one alert, Steam patches included; a press-only
// report gets none
// (only when PUSH_ENABLED=1 and APNs keys are set; otherwise it is marked as alerted and the app
// raises it locally from the feed's `alert`).
import { config } from '../config.ts'
import { openDb } from '../db.ts'
import { exportStatic } from '../export.ts'
import { failingSources, healthSummary } from '../health.ts'
import { infoContractProblems } from '../contract.ts'
import { feedProblems } from '../quality.ts'
import { appendFileSync } from 'node:fs'
import { Igdb } from '../ingest/igdb.ts'
import { runIngest, seedGames } from '../ingest/pipeline.ts'
import { fetchPlus } from '../plusAuto.ts'
import { Apns } from '../push/apns.ts'
import { pushNewPs5 } from '../push/notify.ts'

const args = process.argv.slice(2)
const exportDir = args.includes('--export') ? args[args.indexOf('--export') + 1] : undefined
const db = openDb(config.databasePath)
const igdb = config.twitch.clientId && config.twitch.clientSecret ? new Igdb(config.twitch.clientId, config.twitch.clientSecret) : null
const deps = { db, fetchFn: fetch, igdb, log: console.log }
await seedGames(deps)
const until = args.includes('--backfill') ? new Date(args[args.indexOf('--backfill') + 1]!).toISOString() : undefined
const summary = await runIngest(deps, { force: args.includes('--force') || !!until, until, hot: args.includes('--hot') })
console.log(JSON.stringify(summary, null, 2))
if (!args.includes('--hot')) await fetchPlus(db, fetch, console.log)
const { keyId, teamId, key, topic } = config.apns
const apns = process.env.PUSH_ENABLED === '1' && keyId && teamId && key ? new Apns({ keyId, teamId, key, topic }) : null
const alerts = await pushNewPs5(db, apns, { maxAgeHours: config.pushMaxAgeHours })
if (alerts.length) console.log('alerts:', JSON.stringify(alerts))
apns?.close()
if (exportDir) console.log('exported', exportStatic(db, exportDir))
// Feed health: sources failing 3 polls in a row, and the exported data's quality rules.
const sick = failingSources(db)
for (const h of sick) console.log(`::error title=Source failing::${h.sourceId} failed ${h.failStreak} polls in a row: ${h.lastError ?? h.lastStatus}`)
const problems = exportDir ? feedProblems(exportDir) : []
for (const p of problems) console.log(`::error title=Data quality::${p}`)
if (exportDir) for (const p of infoContractProblems(exportDir)) console.log(`::warning title=Info shard breaks 0.2.0::${p}`)
if (process.env.GITHUB_STEP_SUMMARY) {
  const md = [healthSummary(sick), problems.length ? `## Data quality\n\n${problems.map((p) => `- ${p}`).join('\n')}\n` : ''].filter(Boolean).join('\n')
  if (md) appendFileSync(process.env.GITHUB_STEP_SUMMARY, md + '\n')
}
if (problems.length) process.exitCode = 1
if (summary.errors.length) for (const e of summary.errors) console.log(`::warning::${e.sourceId}: ${e.error}`)
db.close()
