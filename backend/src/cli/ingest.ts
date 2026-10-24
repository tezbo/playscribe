// One-off ingest against a local database: npm run ingest [-- --force]
import { config } from '../config.ts'
import { openDb } from '../db.ts'
import { Igdb } from '../ingest/igdb.ts'
import { runIngest, seedGames } from '../ingest/pipeline.ts'

const db = openDb(config.databasePath)
const igdb = config.twitch.clientId && config.twitch.clientSecret ? new Igdb(config.twitch.clientId, config.twitch.clientSecret) : null
const deps = { db, fetchFn: fetch, igdb, log: console.log }
await seedGames(deps)
console.log(JSON.stringify(await runIngest(deps, { force: process.argv.includes('--force') }), null, 2))
