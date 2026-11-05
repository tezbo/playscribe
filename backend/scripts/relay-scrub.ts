// Feed job, after the poll and before Publish: remove the devices again and prove no token is left in the database
// file that is about to be published. Exits 1 (and the publish does not run) if one is. Logs counts, never a token.
import { existsSync, readFileSync } from 'node:fs'
import { config } from '../src/config.ts'
import { openDb } from '../src/db.ts'
import { deviceRows, scrubDevices } from '../src/push/relay.ts'

const tokenFile = process.argv[2]
const db = openDb(config.databasePath)
scrubDevices(db)
const rows = deviceRows(db)
db.close()
let leaked = 0
if (tokenFile && existsSync(tokenFile)) {
  const bytes = readFileSync(config.databasePath)
  for (const token of readFileSync(tokenFile, 'utf8').split('\n').filter(Boolean)) if (bytes.includes(token)) leaked++
}
console.log(`relay-scrub: ${rows} device rows left, ${leaked} tokens found in the state database`)
if (rows !== 0 || leaked !== 0) process.exit(1)
