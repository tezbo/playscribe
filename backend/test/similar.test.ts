import assert from 'node:assert/strict'
import { test } from 'node:test'
import { similarOf } from '../src/similar.ts'

test('roadmap 18: similar games are capped at 8, unique, named, and never the game itself', () => {
  const rows = Array.from({ length: 12 }, (_, i) => ({ id: i + 1, name: `G${i + 1}`, cover: i % 2 ? { image_id: `c${i + 1}` } : undefined }))
  const out = similarOf([...rows, { id: 3, name: 'dup' }, { id: 99 }], 1)!
  assert.equal(out.length, 8)
  assert.ok(out.every((g) => g.igdbId !== 1))
  assert.deepEqual(out[0], { igdbId: 2, name: 'G2', coverId: 'c2' })
  assert.deepEqual(out[1], { igdbId: 3, name: 'G3' })
  assert.equal(similarOf(undefined), undefined)
  assert.equal(similarOf([{ id: 5 }]), undefined)
})

test('r051 similar-why: a reason only where studio or genre data supports it', () => {
  const self = { genres: [{ name: 'Indie' }, { name: 'Role-playing (RPG)' }], involved_companies: [{ developer: true, company: { name: 'Larian' } }, { developer: false, company: { name: 'Pub' } }] }
  const out = similarOf(
    [
      { id: 2, name: 'Same dev', involved_companies: [{ developer: true, company: { name: 'LARIAN' } }], genres: [{ name: 'Strategy' }] },
      { id: 3, name: 'Same genre', genres: [{ name: 'Role-playing (RPG)' }] },
      { id: 4, name: 'Only broad', genres: [{ name: 'Indie' }] },
      { id: 5, name: 'Publisher only', involved_companies: [{ developer: false, company: { name: 'Larian' } }] },
      { id: 6, name: 'No data' },
    ],
    1,
    self,
  )!
  assert.deepEqual(out.map((g) => g.why), ['Same studio', 'Same genre: Role-playing (RPG)', undefined, undefined, undefined])
  assert.ok(!('why' in out[4]!))
  assert.ok(similarOf([{ id: 2, name: 'x', genres: [{ name: 'RPG' }] }], 1)!.every((g) => !g.why), 'no self data, no reason')
})
