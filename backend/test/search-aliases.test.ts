import assert from 'node:assert/strict'
import { test } from 'node:test'
import { initialism, searchAliases } from '../src/search-aliases.ts'

test('abbreviations players type find the game: GTA, COD, RDR2, AC, FF', () => {
  assert.ok(searchAliases('Grand Theft Auto V').some((a) => /^GTA ?V$/i.test(a) || a === 'GTA5'))
  assert.ok(searchAliases('Grand Theft Auto V').includes('GTA V'))
  assert.ok(searchAliases('Call of Duty: Modern Warfare II').some((a) => a.startsWith('COD')))
  assert.ok(searchAliases('Red Dead Redemption 2').includes('RDR2'))
  assert.ok(searchAliases("Assassin's Creed Odyssey").includes('AC Odyssey'))
  assert.ok(searchAliases('Final Fantasy VII Rebirth').some((a) => a.startsWith('FF')))
})

test('aliases never repeat the name, stay short, and come from IGDB too', () => {
  assert.deepEqual(searchAliases('Hades'), [])
  const a = searchAliases('Grand Theft Auto V', ['Grand Theft Auto V', 'GTA 5', 'x'.repeat(60)])
  assert.ok(a.includes('GTA 5'))
  assert.ok(!a.includes('Grand Theft Auto V'))
  assert.ok(a.every((s) => s.length <= 40) && a.length <= 5)
  assert.equal(initialism('Elden Ring'), null)
  assert.equal(initialism('Red Dead Redemption 2'), 'RDR2')
})
