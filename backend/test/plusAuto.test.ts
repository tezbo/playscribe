// r050-plus-card: automatic lineup from Push Square's monthly announcement, with manual override.
import assert from 'node:assert/strict'
import { mkdtempSync, readFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { test } from 'node:test'
import { openDb } from '../src/db.ts'
import { exportStatic } from '../src/export.ts'
import { announcementLinks, fetchPlus, parsePlusEssential, storedPlusMonths } from '../src/plusAuto.ts'
import { fakeFetch } from './helpers.ts'

const article = readFileSync(new URL('./fixtures/ps-plus-essential-nov-2026.html', import.meta.url), 'utf8')
const URL_NOV = 'https://www.pushsquare.com/news/2026/10/ps-plus-essential-games-for-november-2026-announced'
const list = `<a href="news/2026/10/ps-plus-essential-games-for-november-2026-announced">x</a><a href="news/2026/10/ps-plus-essential-games-for-november-2026-announced#comments">x</a><a href="news/2026/10/ps-plus-extra-game-removals-for-november-2026-confirmed">no</a>`

test('parser: month, claim window (ends the day before the next lineup) and game names', () => {
  assert.deepEqual(parsePlusEssential(article), { month: '2026-11', from: '2026-11-03', until: '2026-11-30', games: [{ name: 'Dead Island 2' }, { name: 'Tomb Raider 4-6 Remastered' }, { name: 'Monster Train 2' }] })
  assert.equal(parsePlusEssential('<html><h1>Something else</h1></html>'), null)
  assert.equal(parsePlusEssential(article.replace(/<ul>.*?<\/ul>/s, '')), null, 'no games means no lineup')
  // December lineup rolls the year: "rotated out ... on 5th January" ends 4 Jan next year.
  const dec = article.replace('November 2026 Announced', 'December 2026 Announced').replace('on 1st December', 'on 5th January').replace('3rd November 2026', '1st December 2026')
  assert.equal(parsePlusEssential(dec)?.until, '2027-01-04')
})

test('parser: the October wording ("starting Tuesday 6th October ... running until 2nd November", no year) parses too', () => {
  const oct = readFileSync(new URL('./fixtures/ps-plus-essential-oct-2026.html', import.meta.url), 'utf8')
  assert.deepEqual(parsePlusEssential(oct), { month: '2026-10', from: '2026-10-06', until: '2026-11-02', games: [{ name: 'F1 25' }, { name: 'Hunt: Showdown 1896' }, { name: 'Earth Defense Force: World Brothers 2' }] })
})

test('links: only monthly announcements, once each', () => {
  assert.deepEqual(announcementLinks(list), [URL_NOV])
})

test('fetchPlus stores a month once; a failure keeps what is stored; manual override wins in the export', async () => {
  const db = openDb(':memory:')
  const fetchFn = fakeFetch({ 'https://www.pushsquare.com/tags/ps-plus': list, [URL_NOV]: article })
  assert.equal(await fetchPlus(db, fetchFn), 1)
  assert.equal(await fetchPlus(db, fetchFn), 0)
  assert.equal(storedPlusMonths(db).length, 1)
  const logs: string[] = []
  assert.equal(await fetchPlus(db, fakeFetch({ 'https://www.pushsquare.com/tags/ps-plus': { status: 500 } }), (m) => logs.push(m)), 0)
  assert.ok(logs.length && storedPlusMonths(db).length === 1)
  const dir = mkdtempSync(join(tmpdir(), 'feed-'))
  exportStatic(db, dir)
  const out = JSON.parse(readFileSync(join(dir, 'v1', 'plus.json'), 'utf8'))
  assert.equal(out.months[0].month, '2026-11')
  assert.equal(out.months[0].games.length, 3)
})

test('lineup covers are resolved by exact title (roman numerals match digits) and added at export', async () => {
  const { openDb } = await import('../src/db.ts')
  const { resolvePlusCovers, withPlusCovers, plusTitleKey } = await import('../src/plusAuto.ts')
  assert.equal(plusTitleKey('Tomb Raider IV-VI Remastered'), plusTitleKey('Tomb Raider 4-6 Remastered'))
  const db = openDb(':memory:')
  const month = { month: '2026-11', from: '2026-11-04', until: '2026-12-01', games: [{ name: 'Tomb Raider 4-6 Remastered' }, { name: 'Mystery Game' }, { name: 'Has One', coverId: 'abcd1' }] }
  db.prepare('INSERT INTO plus_months (month, data, fetched_at) VALUES (?, ?, ?)').run(month.month, JSON.stringify(month), new Date().toISOString())
  const asked: string[] = []
  const igdb = {
    async query(endpoint: string, body: string) {
      asked.push(body)
      if (endpoint === 'platforms') return [{ id: 167 }]
      if (body.includes('Tomb Raider')) return [{ name: 'Tomb Raider: Legend', cover: { image_id: 'wrong1' } }, { name: 'Tomb Raider IV-VI Remastered', cover: { image_id: 'co9abc' } }]
      return [{ name: 'Something Else', cover: { image_id: 'nope1' } }]
    },
  } as never
  assert.equal(await resolvePlusCovers(db, igdb), 1)
  const out = withPlusCovers(db, [month])[0]!.games
  assert.deepEqual(out.map((g) => g.coverId), ['co9abc', undefined, 'abcd1'])
  const before = asked.length
  await resolvePlusCovers(db, igdb) // answers are remembered
  assert.equal(asked.length, before)
})

test('a bundle IGDB lists only as separate games gets no cover: a cover must match the exact product', async () => {
  const { openDb } = await import('../src/db.ts')
  const { resolvePlusCovers, withPlusCovers } = await import('../src/plusAuto.ts')
  const db = openDb(':memory:')
  const month = { month: '2026-11', from: '2026-11-04', until: '2026-12-01', games: [{ name: 'Tomb Raider 4-6 Remastered' }] }
  db.prepare('INSERT INTO plus_months (month, data, fetched_at) VALUES (?, ?, ?)').run(month.month, JSON.stringify(month), new Date().toISOString())
  const igdb = { async query(endpoint: string) { return endpoint === 'platforms' ? [{ id: 167 }] : [{ name: 'Tomb Raider: The Last Revelation', cover: { image_id: 'co9fnl' } }] } } as never
  assert.equal(await resolvePlusCovers(db, igdb), 0)
  assert.equal(withPlusCovers(db, [month])[0]!.games[0]!.coverId, undefined)
})
