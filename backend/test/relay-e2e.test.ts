import assert from 'node:assert/strict'
import { execFile } from 'node:child_process'
import { mkdtempSync, readFileSync } from 'node:fs'
import { createServer } from 'node:http'
import type { AddressInfo } from 'node:net'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { test } from 'node:test'
import { promisify } from 'node:util'
import { openDb } from '../src/db.ts'
import { seedGames } from '../src/ingest/pipeline.ts'
import { fakeFetch } from './helpers.ts'
// @ts-ignore the relay Worker is plain JavaScript
import worker from '../../relay/worker.js'

const run = promisify(execFile)

// The Feed job's push path end to end, with the real Worker behind a local server: a phone registers, relay-sync loads it,
// relay-scrub removes it and proves the token is not in the database file that gets published.
const kvStore = () => {
  const m = new Map<string, string>()
  return {
    get: async (k: string) => m.get(k) ?? null,
    put: async (k: string, v: string) => void m.set(k, v),
    delete: async (k: string) => void m.delete(k),
    list: async ({ prefix = '', limit = 1000 }: { prefix?: string; limit?: number; cursor?: string } = {}) => {
      const keys = [...m.keys()].filter((k) => k.startsWith(prefix)).sort().slice(0, limit).map((name) => ({ name }))
      return { keys, list_complete: true }
    },
  }
}

test('relay end to end: register, load into the run, scrub, and no token left in the published database', async () => {
  const env = { KV: kvStore(), ADMIN_TOKEN: 'test-admin' }
  const server = createServer(async (req, res) => {
    const chunks: Buffer[] = []
    for await (const c of req) chunks.push(c as Buffer)
    const body = chunks.length ? Buffer.concat(chunks) : undefined
    const r = await worker.fetch(new Request(`http://relay.test${req.url}`, { method: req.method, headers: req.headers as Record<string, string>, body: req.method === 'GET' ? undefined : body }), env)
    res.writeHead(r.status, { 'content-type': 'application/json' })
    res.end(await r.text())
  })
  await new Promise<void>((ok) => server.listen(0, '127.0.0.1', ok))
  const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`
  try {
    const dir = mkdtempSync(join(tmpdir(), 'relay-e2e-'))
    const dbPath = join(dir, 'state.db')
    const tokenFile = join(dir, 'tokens')
    const db = openDb(dbPath)
    await seedGames({ db, fetchFn: fakeFetch({}), igdb: null })
    db.close()

    const token = 'fa57c0de'.repeat(8)
    const reg = await fetch(`${base}/v1/devices`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ apnsToken: token, environment: 'production', follows: [{ gameId: 'dawnwalker', notify: 'all' }], quietHours: { from: 1320, until: 420, timeZone: 'Australia/Sydney' } }) })
    assert.equal(reg.status, 201)

    const base_env = { ...process.env, DATABASE_PATH: dbPath, RELAY_URL: base }
    const opts = (admin: string) => ({ cwd: join(import.meta.dirname, '..'), env: { ...base_env, RELAY_ADMIN_TOKEN: admin } })
    const node = ['--import', 'tsx', '--no-warnings=ExperimentalWarning']

    // A wrong admin token loads nothing and fails (the Feed job then defers push instead of stopping).
    await assert.rejects(run(process.execPath, [...node, 'scripts/relay-sync.ts', tokenFile], opts('wrong')))
    const check = openDb(dbPath)
    assert.equal((check.prepare('SELECT COUNT(*) AS n FROM devices').get() as { n: number }).n, 0)
    check.close()

    const sync = await run(process.execPath, [...node, 'scripts/relay-sync.ts', tokenFile], opts('test-admin'))
    console.log(sync.stdout.trim())
    assert.match(sync.stdout, /1 devices \(0 opted in to hourly\), 1 follows, 0 follows for games we do not track/)
    const loaded = openDb(dbPath)
    assert.equal((loaded.prepare('SELECT quiet_tz FROM devices').get() as { quiet_tz: string }).quiet_tz, 'Australia/Sydney')
    loaded.close()
    assert.ok(readFileSync(dbPath).includes(token), 'the token is in the database while the run uses it')

    const scrub = await run(process.execPath, [...node, 'scripts/relay-scrub.ts', tokenFile], opts('test-admin'))
    console.log(scrub.stdout.trim())
    assert.match(scrub.stdout, /relay-scrub: 0 device rows left, 0 tokens found in the state database/)
    assert.ok(!readFileSync(dbPath).includes(token), 'the token is gone from the file that would be published')
    assert.ok(!sync.stdout.includes(token) && !scrub.stdout.includes(token), 'no token in any log line')
  } finally {
    server.close()
  }
})
