// Feed job, after the pushes and before the scrub (r071-relay-dead-tokens): tells the relay which devices' APNs tokens came
// back dead this run (410, or 400 BadDeviceToken / DeviceTokenNotForTopic), so it stops holding them. The relay removes a
// push-only record and turns a follow-list opt-in into its ids-only form. Sends device ids and token hashes, never a token.
// Logs counts only. Never blocks the feed: the step is continue-on-error, and a report that does not arrive is simply made
// again the next time a push to that token fails.
import { config } from '../src/config.ts'
import { openDb } from '../src/db.ts'
import { deadTokens, reportDead } from '../src/push/relay.ts'

const base = process.env.RELAY_URL?.replace(/\/$/, '')
const admin = process.env.RELAY_ADMIN_TOKEN
if (!base || !admin) {
  console.error('relay-dead: RELAY_URL and RELAY_ADMIN_TOKEN are required')
  process.exit(1)
}
const db = openDb(config.databasePath)
const reports = deadTokens(db)
db.close()
if (!reports.length) {
  console.log('relay-dead: no dead tokens this run')
  process.exit(0)
}
const r = await reportDead(reports, base, admin)
console.log(`relay-dead: ${reports.length} dead tokens reported: ${r.removed} devices removed, ${r.cleared} follow-list records kept without a token, ${r.skipped} already changed, ${r.failedBatches} batches refused`)
if (r.failedBatches) process.exit(1)
