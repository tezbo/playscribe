import assert from 'node:assert/strict'
import { test } from 'node:test'
import { openDb } from '../src/db.ts'
import { runIngest, seedGames } from '../src/ingest/pipeline.ts'
import { createApp } from '../src/server.ts'
import { fakeFetch, rss } from './helpers.ts'

const setup = async () => {
  const db = openDb(':memory:')
  const fetchFn = fakeFetch({
    'https://blog.playstation.com/feed/': rss([{ title: 'Black Myth: Wukong Update 1.2 detailed for PS5', link: 'https://blog.playstation.com/wukong', date: new Date().toISOString(), body: '<ul><li>Added new boss</li></ul>' }]),
  })
  const deps = { db, fetchFn, igdb: null }
  await seedGames(deps)
  await runIngest(deps)
  const app = createApp({ ...deps, apns: null, adminToken: 'secret-admin', pushMaxAgeHours: 72 })
  const call = async (method: string, path: string, body?: unknown, token?: string) => {
    const r = await app.request(path, { method, headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) }, body: body ? JSON.stringify(body) : undefined })
    return { status: r.status, json: r.status === 204 ? null : ((await r.json()) as any) }
  }
  return { db, call }
}

test('device registration, follows and the feed', async () => {
  const { call } = await setup()
  const reg = await call('POST', '/v1/devices', { apnsToken: 'ab'.repeat(32), environment: 'sandbox', follows: [{ gameId: 'wukong', notify: 'major' }, { gameId: 'nope' }] })
  assert.equal(reg.status, 201)
  assert.deepEqual(reg.json.follows, [{ gameId: 'wukong', notify: 'major' }])
  assert.equal(reg.json.unknown.length, 1)
  const key = reg.json.deviceKey

  assert.equal((await call('GET', '/v1/devices/me/follows')).status, 401)
  assert.deepEqual((await call('GET', '/v1/devices/me/follows', undefined, key)).json.follows, [{ gameId: 'wukong', notify: 'major' }])
  assert.equal((await call('PUT', '/v1/devices/me/follows', { follows: [{ gameId: 'kcd2', notify: 'loud' }] }, key)).status, 400)

  const feed = await call('GET', '/v1/feed?games=wukong')
  assert.equal(feed.json.releases[0].id, 'wukong@1.2')
  assert.equal(feed.json.releases[0].platforms[0].verification, 'pending')
  const after = await call('GET', `/v1/feed?games=wukong&since=${encodeURIComponent(feed.json.cursor)}`)
  assert.equal(after.json.releases.length, 0)

  assert.equal((await call('GET', '/v1/games/wukong')).json.name, 'Black Myth: Wukong')
  assert.equal((await call('GET', '/v1/games/search?q=wu')).status, 503)
  assert.equal((await call('DELETE', '/v1/devices/me', undefined, key)).status, 204)
  assert.equal((await call('GET', '/v1/devices/me/follows', undefined, key)).status, 401)
})

test('admin: review queue and confirm need the admin token', async () => {
  const { call } = await setup()
  assert.equal((await call('GET', '/v1/admin/review')).status, 401)
  assert.equal((await call('GET', '/v1/admin/review', undefined, 'wrong')).status, 401)
  const q = await call('GET', '/v1/admin/review', undefined, 'secret-admin')
  const item = q.json.items.find((i: any) => i.release?.id === 'wukong@1.2')
  assert.ok(item)
  assert.equal((await call('POST', '/v1/admin/releases/wukong@1.2/platforms/ps5/confirm', { sourceId: 'playstation-blog', version: '1.2' }, 'secret-admin')).status, 400)
  const ok = await call('POST', '/v1/admin/releases/wukong@1.2/platforms/ps5/confirm', { sourceId: 'playstation-blog', version: '01.002.000' }, 'secret-admin')
  assert.equal(ok.status, 200)
  assert.equal(ok.json.release.platforms[0].verification, 'official')
  assert.equal(ok.json.push.skipped, 'noApns')
  assert.equal((await call('GET', '/v1/admin/review', undefined, 'secret-admin')).json.items.filter((i: any) => i.release?.id === 'wukong@1.2').length, 0)
})

test('admin: manual entry for a blocked source', async () => {
  const { call } = await setup()
  const r = await call('POST', '/v1/admin/releases', { gameId: 'dawnwalker', title: 'Update 1.1', announcedAt: '2026-10-22T09:00:00Z', sourceId: 'dawnwalker-news', url: 'https://dawnwalkergame.com/news/update-1-1', platforms: ['ps5'], body: '[list][*]Added animal petting[/list]' }, 'secret-admin')
  assert.equal(r.status, 201)
  assert.equal(r.json.release.kind, 'major')
  assert.equal(r.json.release.platforms[0].verification, 'pending')
})
