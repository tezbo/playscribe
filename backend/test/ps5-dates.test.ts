import assert from 'node:assert/strict'
import { test } from 'node:test'
import { problemsOf, ps5DatesOf } from '../src/ps5-dates.ts'

const ids = { ps5: 167, ps4: 48 }
const names: Record<number, string> = { 1: 'Full Release', 2: 'Early Access', 3: 'Next-Gen Optimization Patch Release' }
const nameOf = (i?: number) => (i == null ? undefined : names[i])
const at = (iso: string) => Date.parse(iso + 'T00:00:00Z') / 1000

test('a full PS5 release beats early access', () => {
  const rows = [{ platform: 167, status: 2, date: at('2022-09-06') }, { platform: 167, status: 1, date: at('2023-12-05') }]
  assert.deepEqual(ps5DatesOf(rows, ids, nameOf), { d: '2023-12-05', b: undefined })
})

test('early access alone is kept and flagged', () => {
  assert.deepEqual(ps5DatesOf([{ platform: 167, status: 2, date: at('2022-09-06') }], ids, nameOf), { d: '2022-09-06', e: true, b: undefined })
})

test('a later full release on PS4 ends early access (Disney Dreamlight Valley)', () => {
  const rows = [{ platform: 167, status: 2, date: at('2022-09-06') }, { platform: 48, status: 2, date: at('2022-09-06') }, { platform: 48, status: 1, date: at('2023-12-05') }]
  assert.deepEqual(ps5DatesOf(rows, ids, nameOf), { d: '2022-09-06', f: '2023-12-05', b: undefined })
})

test('patch rows and pre-launch rows are not PS5 releases', () => {
  const rows = [{ platform: 167, status: 3, date: at('2025-03-15') }, { platform: 167, status: 1, date: at('2019-10-10') }, { platform: 48, status: 1, date: at('2013-09-17') }]
  assert.deepEqual(ps5DatesOf(rows, ids, nameOf), { d: undefined, b: '2013-09-17' })
  assert.deepEqual(ps5DatesOf(rows, ids, nameOf, { d: '2022-03-15', evidence: 'x' }), { d: '2022-03-15', b: '2013-09-17' })
})

test('the build rejects a PS5 date before launch', () => {
  assert.equal(problemsOf([{ i: 1, n: 'A', d: '2020-11-12' }, { i: 2, n: 'B' }]).length, 0)
  assert.equal(problemsOf([{ i: 3, n: 'C', d: '2020-08-14' }]).length, 1)
})

test('a PS5 date keeps how exact it is: month, quarter, year or TBD', () => {
  const formats: Record<number, string> = { 1: 'YYYYMMMMDD', 2: 'YYYYMMMM', 3: 'YYYY', 4: 'YYYYQ4', 5: 'TBD' }
  const fmt = (i?: number) => (i == null ? undefined : formats[i])
  const of = (rows: object[]) => ps5DatesOf(rows as never, ids, nameOf, undefined, fmt)
  assert.deepEqual(of([{ platform: 167, status: 1, date: at('2027-12-31'), date_format: 3 }]), { d: '2027-12-31', q: 'year', b: undefined })
  assert.deepEqual(of([{ platform: 167, status: 1, date: at('2027-12-31'), date_format: 4 }]).q, 'quarter')
  assert.deepEqual(of([{ platform: 167, status: 1, date: at('2027-03-31'), date_format: 2 }]).q, 'month')
  assert.equal(of([{ platform: 167, status: 1, date: at('2027-03-14'), date_format: 1 }]).q, undefined)
  assert.deepEqual(of([{ platform: 167, date_format: 5 }]), { q: 'tbd', d: undefined, b: undefined })
  // The older category enum: 2 is year.
  assert.equal(of([{ platform: 167, status: 1, date: at('2028-12-31'), category: 2 }]).q, 'year')
})
