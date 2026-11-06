// Feed job, before the poll: load the relay's devices into the database for this run. Writes the tokens to a file
// OUTSIDE the published folder (argv[2]) only so relay-scrub can prove they are gone. Logs counts, never a token.
import { writeFileSync } from 'node:fs'
import { config } from '../src/config.ts'
import { openDb } from '../src/db.ts'
import { syncDevices, type RelayDevice } from '../src/push/relay.ts'

const base = process.env.RELAY_URL?.replace(/\/$/, '')
const admin = process.env.RELAY_ADMIN_TOKEN
const tokenFile = process.argv[2]
if (!base || !admin || !tokenFile) {
  console.error('relay-sync: RELAY_URL, RELAY_ADMIN_TOKEN and a token file path are required')
  process.exit(1)
}
const devices: RelayDevice[] = []
let cursor: string | null = null
for (let page = 0; page < 200; page++) {
  const res: Response = await fetch(`${base}/admin/devices${cursor ? `?cursor=${encodeURIComponent(cursor)}` : ''}`, { headers: { authorization: `Bearer ${admin}` } })
  if (!res.ok) {
    console.error(`relay-sync: relay answered ${res.status}`)
    process.exit(1)
  }
  const body = (await res.json()) as { devices: RelayDevice[]; cursor: string | null }
  devices.push(...body.devices)
  cursor = body.cursor
  if (!cursor) break
}
const db = openDb(config.databasePath)
const counts = syncDevices(db, devices)
db.close()
writeFileSync(tokenFile, devices.map((d) => d.token.toLowerCase()).join('\n') + '\n', { mode: 0o600 })
console.log(`relay-sync: ${counts.devices} devices, ${counts.follows} follows, ${counts.unknownFollows} follows for games we do not track`)
