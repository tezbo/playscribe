import { readFileSync } from 'node:fs'
import { openDb } from './src/db.ts'
import { runIngest } from './src/ingest/pipeline.ts'
import { fakeFetch } from './test/helpers.ts'
const db = openDb('/tmp/cl/state/clean2.db')
const games = readFileSync('/tmp/cl/games80.txt', 'utf8').trim().split(',')
const before = new Map((db.prepare('SELECT id, game_id, display_name FROM releases').all() as any[]).map((r) => [r.id, r]))
const fake = fakeFetch({})
const fetchFn = (async (input: any, init?: any) => {
  const url = String(input instanceof Request ? input.url : input)
  if (url.includes('api.steampowered.com/ISteamNews')) return fetch(url, init)
  return fake(input, init)
}) as typeof fetch
const logs: string[] = []
const summary = await runIngest({ db, fetchFn: fetchFn as any, igdb: null, log: (m: string) => logs.push(m) } as any, { force: true, until: '2017-01-01T00:00:00.000Z', games })
const after = new Map((db.prepare('SELECT id, game_id, display_name FROM releases').all() as any[]).map((r) => [r.id, r]))
const dropped = [...before.keys()].filter((k) => !after.has(k)), added = [...after.keys()].filter((k) => !before.has(k))
console.log('polled', summary.polled.length, 'errors', summary.errors.length, JSON.stringify(summary.errors.slice(0, 5)))
console.log('backfill', JSON.stringify(summary.backfill), 'added', added.length, 'dropped', dropped.length)
const listed = new Set(readFileSync('/tmp/cl/unreached-news.txt', 'utf8').split('\n').filter(Boolean).map((l) => l.split(' | ')[0]))
console.log('dropped that were on the 183 list:', dropped.filter((d) => listed.has(d)).length, 'dropped NOT on the list:', dropped.filter((d) => !listed.has(d)).length)
console.log('on the list but still present:', [...listed].filter((x) => after.has(x as string)).length)
import { writeFileSync } from 'node:fs'
writeFileSync('/tmp/cl/dry2-dropped.txt', dropped.map((d) => `${d} | ${before.get(d).display_name}`).join('\n') + '\n')
writeFileSync('/tmp/cl/dry2-added.txt', added.map((d) => `${d} | ${after.get(d).display_name}`).join('\n') + '\n')
writeFileSync('/tmp/cl/dry2-log.txt', logs.join('\n'))
