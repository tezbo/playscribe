// All runtime settings come from the environment. Secrets (Twitch, APNs, admin token) are
// repository secrets for the feed workflow, or exported locally, and never live in the repo.
const env = process.env

const int = (name: string, fallback: number) => {
  const v = env[name]
  return v ? Number.parseInt(v, 10) : fallback
}

// A .p8 key can be pasted as PEM text (with literal \n) or as base64 of the whole file.
const pem = (v: string | undefined) => {
  if (!v) return undefined
  if (v.includes('BEGIN PRIVATE KEY')) return v.replace(/\\n/g, '\n')
  return Buffer.from(v, 'base64').toString('utf8')
}

export const config = {
  port: int('PORT', 8080),
  databasePath: env.DATABASE_PATH ?? './data/playscribe.db',
  adminToken: env.ADMIN_TOKEN,
  ingestIntervalMinutes: int('INGEST_INTERVAL_MINUTES', 30),
  /** Releases older than this when first seen are recorded silently, never pushed. */
  pushMaxAgeHours: int('PUSH_MAX_AGE_HOURS', 72),
  twitch: { clientId: env.TWITCH_CLIENT_ID, clientSecret: env.TWITCH_CLIENT_SECRET },
  apns: {
    keyId: env.APNS_KEY_ID,
    teamId: env.APNS_TEAM_ID,
    topic: env.APNS_TOPIC ?? 'co.codeconnectors.playscribe',
    key: pem(env.APNS_KEY_P8),
  },
}

export type Config = typeof config
