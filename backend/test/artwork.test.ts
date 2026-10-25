import assert from 'node:assert/strict'
import { test } from 'node:test'
import { artworkFields, artworkOf, artworkTypes } from '../src/artwork.ts'
import { openDb } from '../src/db.ts'
import * as store from '../src/store.ts'

const types = new Map([
  [1, 'Key art with logo'],
  [2, 'Key art without logo'],
  [3, 'Concept art'],
])

test('square tile art: textless key art beats key art with a logo, then anything wide; portrait art is skipped', () => {
  const rows = [
    { image_id: 'concept', artwork_type: 3, width: 3840, height: 2160 },
    { image_id: 'logo', artwork_type: 1, width: 1920, height: 1080 },
    { image_id: 'tall', artwork_type: 2, width: 1080, height: 1920 },
    { image_id: 'clean', artwork_type: 2, width: 1920, height: 1080 },
  ]
  assert.equal(artworkOf(rows, (i) => types.get(i!)), 'clean')
  assert.equal(artworkOf(rows.slice(0, 3), (i) => types.get(i!)), 'logo')
  // Without IGDB types the widest landscape artwork wins.
  assert.equal(artworkOf(rows, () => undefined), 'concept')
  assert.equal(artworkOf([{ image_id: 'tall', width: 600, height: 900 }], () => undefined), undefined)
  assert.equal(artworkOf(undefined, () => undefined), undefined)
})

test('artwork types are optional: a missing endpoint leaves artwork_type out of the query', async () => {
  const none = await artworkTypes(async () => {
    throw new Error('IGDB artwork_types 404')
  })
  assert.equal(none.size, 0)
  assert.ok(!artworkFields(none).includes('artwork_type'))
  assert.ok(artworkFields(types).includes('artworks.artwork_type'))
})

test('the feed game carries key art, and "none" is remembered without showing', () => {
  const db = openDb(':memory:')
  store.upsertGame(db, { id: 'g', name: 'G', coverImageId: 'cov', artworkImageId: 'art' })
  assert.deepEqual(store.gameFromRow(store.getGameRow(db, 'g')!).artwork, {
    imageId: 'art',
    url: 'https://images.igdb.com/igdb/image/upload/t_1080p/art.jpg',
  })
  // A later run without IGDB keeps it.
  store.upsertGame(db, { id: 'g', name: 'G' })
  assert.equal(store.gameFromRow(store.getGameRow(db, 'g')!).artwork?.imageId, 'art')
  store.upsertGame(db, { id: 'h', name: 'H', artworkImageId: '' })
  assert.equal(store.getGameRow(db, 'h')!.artwork_image_id, '')
  assert.equal(store.gameFromRow(store.getGameRow(db, 'h')!).artwork, null)
})
