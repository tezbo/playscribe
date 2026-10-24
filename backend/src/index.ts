import { serve } from '@hono/node-server'
import { config } from './config.ts'
import { openDb } from './db.ts'
import { Igdb } from './ingest/igdb.ts'
import { runIngestExclusive, seedGames } from './ingest/pipeline.ts'
import { Apns } from './push/apns.ts'
import { createApp } from './server.ts'

const log = (msg: string) => console.log(`${new Date().toISOString()} ${msg}`)
const db = openDb(config.databasePath)
const igdb = config.twitch.clientId && config.twitch.clientSecret ? new Igdb(config.twitch.clientId, config.twitch.clientSecret) : null
const { keyId, teamId, key, topic } = config.apns
const apns = keyId && teamId && key ? new Apns({ keyId, teamId, key, topic }) : null
if (!igdb) log('IGDB not configured (TWITCH_CLIENT_ID / TWITCH_CLIENT_SECRET): search and game lookup are off')
if (!apns) log('APNs not configured (APNS_KEY_ID / APNS_TEAM_ID / APNS_KEY_P8): confirmed releases will not push')

const deps = { db, fetchFn: fetch, igdb, log }
const app = createApp({ ...deps, apns, adminToken: config.adminToken, pushMaxAgeHours: config.pushMaxAgeHours })
serve({ fetch: app.fetch, port: config.port }, (i) => log(`listening on :${i.port}`))

const tick = () => runIngestExclusive(deps).catch((e) => log(`ingest failed: ${(e as Error).message}`))
await seedGames(deps)
void tick()
setInterval(tick, config.ingestIntervalMinutes * 60_000).unref()
