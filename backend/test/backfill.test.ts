import assert from 'node:assert/strict'
import { test } from 'node:test'
import { fetchPosts } from '../src/ingest/adapters.ts'
import { registry } from '../src/registry.ts'
import type { FetchFn } from '../src/http.ts'

// Full history per game (Terry): a backfill pages Steam back with enddate, instead of stopping at the newest 100 posts.
test('steam backfill pages back with enddate until the since date; a normal poll reads one page', async () => {
  const day = 86400
  const all = Array.from({ length: 250 }, (_, i) => ({ gid: String(i), title: `Patch 1.${i}`, date: 1_800_000_000 - i * day, contents: 'x', tags: ['patchnotes'] }))
  const calls: string[] = []
  const fetchFn = (async (input: string | URL | Request) => {
    const url = String(input instanceof Request ? input.url : input)
    calls.push(url)
    const end = Number(new URL(url).searchParams.get('enddate') ?? Infinity)
    const count = Number(new URL(url).searchParams.get('count'))
    return Response.json({ appnews: { newsitems: all.filter((n) => n.date < end).slice(0, count) } })
  }) as FetchFn
  const source = registry.games['dawnwalker']!.sources.find((s) => s.kind === 'steamNews')!
  const poll = await fetchPosts(fetchFn, source)
  assert.equal(poll.length, 20)
  assert.equal(calls.length, 1)
  calls.length = 0
  const back = await fetchPosts(fetchFn, source, { until: new Date((1_800_000_000 - 240 * day) * 1000).toISOString() })
  assert.equal(back.length, 250 - 0)
  assert.equal(new Set(back.map((p) => p.postId)).size, 250)
  assert.equal(calls.length, 3)
  assert.ok(calls[1]!.includes('enddate='))
})
