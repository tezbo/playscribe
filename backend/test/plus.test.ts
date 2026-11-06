// r050-plus-card: the hand-curated PS Plus shard is validated and exported.
import assert from 'node:assert/strict'
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { test } from 'node:test'
import { openDb } from '../src/db.ts'
import { exportStatic } from '../src/export.ts'
import { loadPlus, plusProblems } from '../src/plus.ts'

const good = { months: [{ month: '2026-11', from: '2026-11-04', until: '2026-12-01', games: [{ name: 'Some Game' }, { name: 'Another', gameId: 'kcd2' }] }] }

test('plus.json: a well-formed month passes; newest month sorts first', () => {
  assert.deepEqual(plusProblems(good, new Set(['kcd2'])), [])
  const dir = mkdtempSync(join(tmpdir(), 'plus-'))
  const p = join(dir, 'plus.json')
  writeFileSync(p, JSON.stringify({ months: [{ ...good.months[0], month: '2026-10' }, good.months[0]] }))
  assert.deepEqual(loadPlus(p).months.map((m) => m.month), ['2026-11', '2026-10'])
})

test('plus.json: bad months, dates, names, links and unknown games are all reported', () => {
  const bad = { months: [{ month: '2026-11', from: '2026-11-04', until: '2026-10-01', games: [] }, { month: 'Nov', from: '04/11', until: '2026-11-30', games: [{ name: 'https://x.test' }, { name: '', gameId: 'nope' }] }, { month: '2026-11', from: '2026-11-04', until: '2026-11-30', games: [{ name: 'ok' }] }] }
  const out = plusProblems(bad, new Set(['kcd2'])).join('\n')
  for (const m of ['until is before from', 'games must not be empty', 'month must be YYYY-MM', 'real YYYY-MM-DD', 'must not be a link', '1 to 80', 'not a tracked game', 'repeats']) assert.match(out, new RegExp(m))
  assert.ok(plusProblems(null).length && plusProblems({}).length)
  const dir = mkdtempSync(join(tmpdir(), 'plus-'))
  writeFileSync(join(dir, 'plus.json'), JSON.stringify(bad))
  assert.throws(() => loadPlus(join(dir, 'plus.json')), /plus\.json:/)
})

test('export writes v1/plus.json; the shipped file is valid and empty until a month is typed in', () => {
  const dir = mkdtempSync(join(tmpdir(), 'feed-'))
  exportStatic(openDb(':memory:'), dir)
  const out = JSON.parse(readFileSync(join(dir, 'v1', 'plus.json'), 'utf8'))
  assert.equal(out.version, 1)
  assert.ok(Array.isArray(out.months))
})

test('plus.json: coverId is optional and must look like an IGDB image id', () => {
  const withCover = (coverId: string) => ({ months: [{ month: '2026-11', from: '2026-11-04', until: '2026-12-01', games: [{ name: 'Tomb Raider 4-6 Remastered', coverId }] }] })
  assert.deepEqual(plusProblems(withCover('co1abc')), [])
  assert.match(plusProblems(withCover('https://x.test/a.jpg')).join('\n'), /coverId must be an IGDB image id/)
})
