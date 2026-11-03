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
