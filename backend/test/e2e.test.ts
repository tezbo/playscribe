import assert from 'node:assert/strict'
import { mkdtempSync, readFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { test } from 'node:test'
import { feedContractProblems } from '../src/contract.ts'
import { openDb } from '../src/db.ts'
import { exportStatic } from '../src/export.ts'
import { runIngest, seedGames } from '../src/ingest/pipeline.ts'
import { feedProblems } from '../src/quality.ts'
import { fakeFetch, steamNews } from './helpers.ts'

// End to end (Terry's standing order): one realistic Steam patch travels source -> store -> export -> every guard and
// every field the 0.5.0 app reads, and a second patch in the next poll moves the right things.
const recent = (h: number) => new Date(Date.now() - h * 3600_000).toISOString()
const STEAM = 'https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=3751260'

const body1 = `Update 1.3 is out now on PC, PS5 and Xbox Series X|S.
[h2]New Features[/h2][list][*]Added photo mode[*]Added a new boss, the Hollow King[/list]
[h2]Bug Fixes[/h2][list][*]Fixed a crash when loading saves[*]Fixed HDR on PS5 Pro[*]Fixed Steam Deck suspend freezing the game[/list]
[h2]Balance[/h2][list][*]Reduced the damage of the Hollow King[/list]
[h2]PC[/h2][list][*]Added DLSS 4 support[/list]
[h2]Known issues[/h2][list][*]Saves may fail to load after fast travel[/list]`

const body2 = `Hotfix 1.3.1 is live on PC, PS5 and Xbox Series X|S.
[h2]Bug Fixes[/h2][list][*]Fixed saves failing to load after fast travel[*]Fixed a typo[/list]`

test('end to end: a Steam patch becomes a PS5 release with a digest, an alert, issues, and passes every guard', async () => {
  const db = openDb(':memory:')
  const steam = (items: Parameters<typeof steamNews>[0]) => fakeFetch({ [STEAM]: steamNews(items) })
  const p1 = { gid: '101', title: 'The Blood of Dawnwalker - Update 1.3', date: recent(5), contents: body1, tags: ['patchnotes'] }
  await seedGames({ db, fetchFn: steam([p1]), igdb: null })
  await runIngest({ db, fetchFn: steam([p1]), igdb: null }, { force: true })

  const out = mkdtempSync(join(tmpdir(), 'e2e-'))
  exportStatic(db, out)
  const read = (p: string) => JSON.parse(readFileSync(join(out, 'v1', p), 'utf8'))
  const rel = read('games/dawnwalker.json').releases.find((r: any) => r.id === 'dawnwalker@1.3')
  assert.ok(rel, 'the patch is a release')
  assert.equal(rel.kind, 'major')
  const ps5 = rel.platforms.find((p: any) => p.platform === 'ps5')
  assert.deepEqual([ps5.status, ps5.alert?.style], ['live', 'standard'])
  assert.ok(ps5.alert.from)
  // Digest: PC-only lines (Steam Deck, the PC section) are left out of the counts.
  assert.deepEqual([rel.digest.new, rel.digest.fixed, rel.digest.balance], [2, 2, 1])
  assert.deepEqual(rel.digest.topNew, ['Added photo mode', 'Added a new boss, the Hollow King'])
  assert.ok(rel.notes.some((s: any) => s.items.some((i: any) => i.pcOnly)))
  // Known issue opened.
  const issues = read('games/dawnwalker.json').issues
  assert.deepEqual(issues.map((i: any) => [i.text, i.status]), [['Saves may fail to load after fast travel', 'open']])
  assert.equal(read('latest.json').releases[0].id, 'dawnwalker@1.3')
  assert.deepEqual(feedContractProblems(out), [])
  assert.deepEqual(feedProblems(out), [])

  // Next poll: a hotfix that fixes the known issue.
  const p2 = { gid: '102', title: 'Hotfix 1.3.1', date: recent(1), contents: body2, tags: ['patchnotes'] }
  await runIngest({ db, fetchFn: steam([p2, p1]), igdb: null }, { force: true })
  exportStatic(db, out)
  const after = read('games/dawnwalker.json')
  assert.deepEqual(after.issues.map((i: any) => [i.status, i.addressedBy]), [['addressed', 'dawnwalker@1.3.1']])
  assert.equal(read('latest.json').releases[0].id, 'dawnwalker@1.3.1')
  assert.deepEqual(after.releases.find((r: any) => r.id === 'dawnwalker@1.3.1').digest.fixed, 2)
  // Re-reading changes nothing: no duplicate release, the same files.
  const before = readFileSync(join(out, 'v1', 'games', 'dawnwalker.json'), 'utf8')
  await runIngest({ db, fetchFn: steam([p2, p1]), igdb: null }, { force: true })
  exportStatic(db, out)
  assert.equal(readFileSync(join(out, 'v1', 'games', 'dawnwalker.json'), 'utf8'), before)
  assert.deepEqual(feedContractProblems(out), [])
})
