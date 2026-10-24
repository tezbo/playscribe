import { sign } from 'node:crypto'
import { connect, constants, type ClientHttp2Session } from 'node:http2'

// APNs over HTTP/2 with token auth (.p8 key). Docs: "Sending notification requests to APNs" and
// "Establishing a token-based connection to APNs" (developer.apple.com/documentation/usernotifications).
// The provider token is an ES256 JWT; Apple rejects one refreshed more than once in 20 minutes
// and expires it after an hour, so it is reused for 40.
export type ApnsEnvironment = 'sandbox' | 'production'

export interface ApnsConfig {
  keyId: string
  teamId: string
  key: string // PEM of the .p8 file
  topic: string // the app's bundle id
}

export interface SendResult {
  status: number
  reason?: string
  apnsId?: string
}

const HOSTS: Record<ApnsEnvironment, string> = {
  production: 'https://api.push.apple.com',
  sandbox: 'https://api.sandbox.push.apple.com',
}

const b64url = (b: Buffer | string) => Buffer.from(b).toString('base64url')

export const providerToken = (keyId: string, teamId: string, key: string, iat = Math.floor(Date.now() / 1000)) => {
  const head = b64url(JSON.stringify({ alg: 'ES256', kid: keyId }))
  const body = b64url(JSON.stringify({ iss: teamId, iat }))
  const sig = sign('sha256', Buffer.from(`${head}.${body}`), { key, dsaEncoding: 'ieee-p1363' })
  return `${head}.${body}.${b64url(sig)}`
}

export class Apns {
  private token: { value: string; at: number } | null = null
  private sessions = new Map<ApnsEnvironment, ClientHttp2Session>()

  constructor(
    private readonly cfg: ApnsConfig,
    private readonly hosts: Record<ApnsEnvironment, string> = HOSTS,
    private readonly connectOptions: Parameters<typeof connect>[1] = {},
  ) {}

  private jwt() {
    if (!this.token || Date.now() - this.token.at > 40 * 60_000) this.token = { value: providerToken(this.cfg.keyId, this.cfg.teamId, this.cfg.key), at: Date.now() }
    return this.token.value
  }

  private session(env: ApnsEnvironment) {
    const s = this.sessions.get(env)
    if (s && !s.closed && !s.destroyed) return s
    const next = connect(this.hosts[env], this.connectOptions)
    next.on('error', () => this.sessions.delete(env))
    next.on('goaway', () => this.sessions.delete(env))
    this.sessions.set(env, next)
    return next
  }

  send(
    deviceToken: string,
    env: ApnsEnvironment,
    payload: object,
    opts: { collapseId?: string; pushType?: 'alert' | 'background'; priority?: 5 | 10; expiresAt?: number } = {},
  ): Promise<SendResult> {
    return new Promise((resolve, reject) => {
      const req = this.session(env).request({
        [constants.HTTP2_HEADER_METHOD]: 'POST',
        [constants.HTTP2_HEADER_PATH]: `/3/device/${deviceToken}`,
        authorization: `bearer ${this.jwt()}`,
        'apns-topic': this.cfg.topic,
        'apns-push-type': opts.pushType ?? 'alert',
        'apns-priority': String(opts.priority ?? 10),
        'apns-expiration': String(opts.expiresAt ?? Math.floor(Date.now() / 1000) + 24 * 3600),
        ...(opts.collapseId ? { 'apns-collapse-id': opts.collapseId.slice(0, 64) } : {}),
      })
      let status = 0
      let apnsId: string | undefined
      let data = ''
      req.setTimeout(15_000, () => req.close(constants.NGHTTP2_CANCEL))
      req.on('response', (h) => {
        status = Number(h[constants.HTTP2_HEADER_STATUS])
        apnsId = h['apns-id'] as string | undefined
      })
      req.setEncoding('utf8')
      req.on('data', (c) => (data += c))
      req.on('end', () => {
        let reason: string | undefined
        try {
          reason = data ? (JSON.parse(data) as { reason?: string }).reason : undefined
        } catch {
          reason = data
        }
        resolve({ status, reason, apnsId })
      })
      req.on('error', reject)
      req.end(JSON.stringify(payload))
    })
  }

  close() {
    for (const s of this.sessions.values()) s.close()
    this.sessions.clear()
  }
}

/** Responses after which the token is useless and should be forgotten. */
export const tokenIsDead = (r: SendResult) => r.status === 410 || (r.status === 400 && (r.reason === 'BadDeviceToken' || r.reason === 'DeviceTokenNotForTopic'))
