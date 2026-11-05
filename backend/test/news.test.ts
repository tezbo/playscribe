import assert from 'node:assert/strict'
import { mkdtempSync, readFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { test } from 'node:test'
import { excerptOf, exportNews } from '../src/news.ts'
import { registry, steamAppIdOf } from '../src/registry.ts'
import { fakeFetch, rss, steamNews } from './helpers.ts'

const [gameId, game] = Object.entries(registry.games).find(([, g]) => g.sources.some((s) => s.kind === 'steamNews'))!
const appid = steamAppIdOf(game.sources.find((s) => s.kind === 'steamNews')!)

test('news: studio posts that are not patches, press headlines matched to games, wider news kept', async () => {
  const fetchFn = fakeFetch({
    [`https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=${appid}`]: steamNews([
      { gid: '1', title: 'New story trailer is here', date: '2026-11-01T10:00:00Z', contents: '[h2]Watch now[/h2]\n[img]{STEAM_CLAN_IMAGE}/x.png[/img]\nThe trailer shows the next chapter.' },
      { gid: '2', title: 'Hotfix 1.0.3 notes', date: '2026-11-02T10:00:00Z', contents: 'Fixed a crash' },
      { gid: '3', title: 'Patch notes', date: '2026-11-03T10:00:00Z', contents: 'x', tags: ['patchnotes'] },
    ]),
    'https://www.pushsquare.com/feeds/latest': rss([
      { title: `${game.name} gets a surprise expansion`, link: 'https://www.pushsquare.com/news/a', date: '2026-11-04T10:00:00Z', body: 'Article text we never keep' },
      { title: 'Some other PS5 news', link: 'https://www.pushsquare.com/news/b', date: '2026-11-03T12:00:00Z', body: 'x' },
    ]),
  })
  const out = mkdtempSync(join(tmpdir(), 'news-'))
  const r = await exportNews(fetchFn, out)
  assert.deepEqual(r.errors, [])
  const read = (p: string) => JSON.parse(readFileSync(join(out, 'v1', p), 'utf8'))
  const g = read(`news/${gameId}.json`).items
  assert.deepEqual(g.map((i: any) => [i.title, i.kind]), [[`${game.name} gets a surprise expansion`, 'reported'], ['New story trailer is here', 'official']])
  assert.equal(g[1].excerpt, 'Watch now The trailer shows the next chapter.')
  assert.equal(g[0].excerpt, undefined)
  const global = read('news.json')
  assert.equal(global.items.length, 3)
  assert.equal(global.items.find((i: any) => i.title === 'Some other PS5 news').gameId, null)
  assert.equal(global.updatedAt, '2026-11-04T10:00:00.000Z')

  // A failing source keeps what was published before; a quiet run changes nothing.
  const before = readFileSync(join(out, 'v1', 'news.json'), 'utf8')
  const down = (async () => new Response('', { status: 500 })) as typeof fetch
  const again = await exportNews(down, out)
  assert.ok(again.errors.length > 0)
  assert.equal(readFileSync(join(out, 'v1', 'news.json'), 'utf8'), before)
})

test('news: excerpts are plain, short and cut at a word', () => {
  assert.equal(excerptOf('[b]Hello[/b] <br> world'), 'Hello world')
  const long = excerptOf('word '.repeat(100), 50)
  assert.ok(long.length <= 51 && long.endsWith('…'))
})
