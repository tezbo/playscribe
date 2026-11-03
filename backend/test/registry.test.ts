import assert from 'node:assert/strict'
import { test } from 'node:test'
import { registry } from '../src/registry.ts'

test('the PlayStation Blog stays on manual fetch in production: its terms bar automated access', () => {
  assert.equal(registry.shared.find((s) => s.id === 'playstation-blog')!.fetch, 'manual')
  assert.ok(registry.shared.filter((s) => /playstation\.com/.test(s.url)).every((s) => s.fetch === 'manual'))
})
