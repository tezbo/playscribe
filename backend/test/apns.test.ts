import assert from 'node:assert/strict'
import { createPublicKey, generateKeyPairSync, verify } from 'node:crypto'
import { createServer } from 'node:http2'
import type { AddressInfo } from 'node:net'
import { test } from 'node:test'
import { Apns, providerToken, tokenIsDead } from '../src/push/apns.ts'

const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' })
const pem = privateKey.export({ type: 'pkcs8', format: 'pem' }).toString()

test('provider token is an ES256 JWT that verifies', () => {
  const jwt = providerToken('KEY123', 'TEAM456', pem, 1_700_000_000)
  const [h, b, s] = jwt.split('.')
  assert.deepEqual(JSON.parse(Buffer.from(h!, 'base64url').toString()), { alg: 'ES256', kid: 'KEY123' })
  assert.deepEqual(JSON.parse(Buffer.from(b!, 'base64url').toString()), { iss: 'TEAM456', iat: 1_700_000_000 })
  assert.ok(verify('sha256', Buffer.from(`${h}.${b}`), { key: createPublicKey(privateKey), dsaEncoding: 'ieee-p1363' }, Buffer.from(s!, 'base64url')))
})

test('sends over HTTP/2 with APNs headers and reads error reasons', async () => {
  const seen: Record<string, unknown>[] = []
  const server = createServer()
  server.on('stream', (stream, headers) => {
    let body = ''
    stream.on('data', (c) => (body += c))
    stream.on('end', () => {
      seen.push({ ...headers, body })
      const dead = String(headers[':path']).endsWith('dead')
      stream.respond({ ':status': dead ? 410 : 200, 'apns-id': 'abc' })
      stream.end(dead ? JSON.stringify({ reason: 'Unregistered' }) : '')
    })
  })
  await new Promise<void>((r) => server.listen(0, r))
  const url = `http://localhost:${(server.address() as AddressInfo).port}`
  const apns = new Apns({ keyId: 'K', teamId: 'T', key: pem, topic: 'co.example.app' }, { production: url, sandbox: url })
  const ok = await apns.send('tok', 'production', { aps: { alert: 'hi' } }, { collapseId: 'r1' })
  const gone = await apns.send('dead', 'sandbox', {})
  apns.close()
  server.close()
  assert.deepEqual(ok, { status: 200, reason: undefined, apnsId: 'abc' })
  assert.equal(gone.reason, 'Unregistered')
  assert.ok(tokenIsDead(gone))
  assert.equal(seen[0]![':path'], '/3/device/tok')
  assert.equal(seen[0]!['apns-topic'], 'co.example.app')
  assert.equal(seen[0]!['apns-push-type'], 'alert')
  assert.equal(seen[0]!['apns-collapse-id'], 'r1')
  assert.match(String(seen[0]!.authorization), /^bearer .+\..+\..+$/)
})
