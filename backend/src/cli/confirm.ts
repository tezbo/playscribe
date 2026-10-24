// The person-confirm step from the command line (or the "Confirm PS5 release" workflow):
//   npm run confirm -- <releaseId> --source <sourceId> [--platform ps5] [--version 01.004.000]
//     [--size-bytes 13000000000] [--status live|announced|notPlanned] [--live-at ISO] [--export <dir>]
//   npm run confirm -- --dismiss <reviewItemId> [--export <dir>]
// Pushes only when PUSH_ENABLED=1 and APNs keys are set (both need the paid Apple Developer
// Program). Without them the release is still marked as having had its one push, so it can never
// push late; the app announces it with a local notification when it syncs.
import { config } from '../config.ts'
import { confirmPlatform, dismissReview } from '../confirm.ts'
import { openDb } from '../db.ts'
import { exportStatic } from '../export.ts'
import { Apns } from '../push/apns.ts'
import { pushPs5Release } from '../push/notify.ts'
import { getRelease } from '../store.ts'
import type { Platform, PlatformStatus } from '../types.ts'

const args = process.argv.slice(2)
const opt = (name: string) => (args.includes(`--${name}`) ? args[args.indexOf(`--${name}`) + 1] || undefined : undefined)
const fail = (msg: string): never => {
  console.error(msg)
  process.exit(1)
}
const db = openDb(config.databasePath)
const exportDir = opt('export')

if (opt('dismiss')) {
  if (!dismissReview(db, Number(opt('dismiss')))) fail(`no open review item ${opt('dismiss')}`)
  console.log(`dismissed review item ${opt('dismiss')}`)
} else {
  const releaseId = args.find((a, i) => !a.startsWith('--') && (i === 0 || !args[i - 1]!.startsWith('--'))) ?? fail('release id required, e.g. dawnwalker@1.1')
  const sourceId = opt('source') ?? fail('--source is required: the official source a person checked')
  const platform = (opt('platform') ?? 'ps5') as Platform
  const version = opt('version')
  if (version && !/^\d{2}\.\d{3}\.\d{3}$/.test(version)) fail('--version must be the console form XX.YYY.ZZZ')
  if (!getRelease(db, releaseId)) fail(`unknown release ${releaseId}`)
  confirmPlatform(db, releaseId, platform, {
    sourceId,
    version,
    status: opt('status') as PlatformStatus | undefined,
    sizeBytes: opt('size-bytes') ? Number(opt('size-bytes')) : undefined,
    liveAt: opt('live-at'),
  })
  const { keyId, teamId, key, topic } = config.apns
  const apns = process.env.PUSH_ENABLED === '1' && keyId && teamId && key ? new Apns({ keyId, teamId, key, topic }) : null
  if (platform === 'ps5') console.log('push:', JSON.stringify(await pushPs5Release(db, apns, releaseId, { maxAgeHours: config.pushMaxAgeHours })))
  apns?.close()
  console.log(JSON.stringify(getRelease(db, releaseId)?.platforms, null, 1))
}
if (exportDir) console.log('exported', exportStatic(db, exportDir))
db.close()
