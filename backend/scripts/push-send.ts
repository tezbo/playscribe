// Feed job, after Publish has succeeded: sends the alerts the poll claimed (src/cli/ingest.ts wrote them to PUSH_QUEUE) and tells the relay
// which tokens came back dead. Nothing is read from the state database: by now the claim (pushed_at) is on the feed branch, so a failure
// here loses at most this run's alerts and can never repeat one. Logs counts only, never a token. Never blocks the feed (continue-on-error).
import { existsSync, readFileSync, rmSync } from 'node:fs'
import { config } from '../src/config.ts'
import { Apns } from '../src/push/apns.ts'
import { deliverPush, type PushJob, type PushOutcome } from '../src/push/notify.ts'
import { reportDead, type DeadReport } from '../src/push/relay.ts'

const file = process.argv[2]
if (!file || !existsSync(file)) {
  console.log('push-send: nothing queued')
  process.exit(0)
}
const jobs = JSON.parse(readFileSync(file, 'utf8')) as { job: PushJob; outcome: PushOutcome }[]
rmSync(file)
const { keyId, teamId, key, topic } = config.apns
if (process.env.PUSH_ENABLED !== '1' || !keyId || !teamId || !key) {
  console.log(`push-send: ${jobs.length} queued, APNs not configured`)
  process.exit(0)
}
const apns = new Apns({ keyId, teamId, key, topic })
const dead: DeadReport[] = []
const outcomes: PushOutcome[] = []
for (const j of jobs) {
  const d = await deliverPush(apns, j.job, j.outcome)
  outcomes.push(d.outcome)
  dead.push(...d.dead)
}
apns.close()
console.log('push-send: alerts', JSON.stringify(outcomes))
const base = process.env.RELAY_URL?.replace(/\/$/, '')
const admin = process.env.RELAY_ADMIN_TOKEN
if (dead.length && base && admin) {
  const r = await reportDead(dead, base, admin)
  console.log(`push-send: ${dead.length} dead tokens reported: ${r.removed} devices removed, ${r.cleared} follow-list records kept without a token, ${r.skipped} already changed, ${r.failedBatches} batches refused`)
}
