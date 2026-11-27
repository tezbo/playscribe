import assert from 'node:assert/strict'
import { mkdirSync, mkdtempSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { test } from 'node:test'
import { coverage, FIELDS } from '../scripts/baseline-coverage.ts'

test('baseline coverage: a game with every required part passes, one missing About and hero art does not', () => {
  const dir = mkdtempSync(join(tmpdir(), 'base-'))
  for (const d of ['v1/info', 'v1/games']) mkdirSync(join(dir, d), { recursive: true })
  const game = (id: string, igdbId: number, art: boolean) => ({ id, igdbId, cover: 'c1', artwork: art ? 'a1' : null, squareCover: null, ps5Release: '2026-01-01', releaseCount: 1, ps5TitleIds: [] })
  writeFileSync(join(dir, 'v1/index.json'), JSON.stringify({ games: [game('good', 1, true), game('thin', 2, false)] }))
  writeFileSync(join(dir, 'v1/info/0.json'), JSON.stringify({ games: { 1: { summary: 's', genres: ['RPG'], links: { patchNotes: 'https://x.test' } }, 2: { genres: ['RPG'], links: { patchNotes: 'https://x.test' } } } }))
  for (const id of ['good', 'thin']) writeFileSync(join(dir, `v1/games/${id}.json`), JSON.stringify({ releases: [{ platforms: [{ platform: 'ps5' }] }] }))
  const { rows } = coverage(dir)
  const required = FIELDS.filter((f) => f.required)
  assert.ok(required.every((f) => rows.get('good')![f.key]))
  assert.deepEqual(required.filter((f) => !rows.get('thin')![f.key]).map((f) => f.key), ['hero', 'about'])
  assert.equal(rows.get('good')!.story, false, 'Story is an honest empty state, not a failure')
})
