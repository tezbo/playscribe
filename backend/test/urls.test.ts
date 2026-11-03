import assert from 'node:assert/strict'
import { test } from 'node:test'
import { isUrl } from '../src/urls.ts'

test('info shard links: a malformed IGDB website (seen live in info/38) is not a URL the app can decode', () => {
  assert.ok(!isUrl('https://v.douyin.com/iDuoKPNm/ 8@4.com'))
  assert.ok(!isUrl(''))
  assert.ok(!isUrl(undefined))
  assert.ok(!isUrl('www.example.com'))
  assert.ok(isUrl('https://www.minecraft.net/en-us'))
})
