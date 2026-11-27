// Dawnwalker-baseline coverage report (s-07-dawnwalker-baseline-every-game, AC2/AC4).
// Usage: npx tsx scripts/baseline-coverage.ts <feed dir holding v1/> [--md <out.md>] [--fail-under <percent>]
// Every published game is checked against the feed-derivable fields of design/dawnwalker-baseline-checklist.md. The Companion
// sections (Lore, Tips, Trophies, Maps) are bundled in the app and are not in the feed, so they are reported by the app's catalog, not here.
import { readdirSync, readFileSync, writeFileSync } from 'node:fs'

export interface Field { key: string; label: string; need: string; required: boolean }
export const FIELDS: Field[] = [
  { key: 'cover', label: 'Cover art', need: 'game.cover', required: true },
  { key: 'hero', label: 'Hero art', need: 'game.artwork', required: true },
  { key: 'square', label: 'Square cover', need: 'game.squareCover', required: false },
  { key: 'about', label: 'About', need: 'info.summary', required: true },
  { key: 'story', label: 'Story', need: 'info.storyline', required: false },
  { key: 'genres', label: 'Genres', need: 'info.genres', required: true },
  { key: 'trailers', label: 'Trailers', need: 'info.videos', required: false },
  { key: 'official', label: 'Official site link', need: 'info.links.official', required: true },
  { key: 'notes', label: 'Patch-notes link', need: 'info.links.patchNotes', required: true },
  { key: 'similar', label: 'Games like this', need: 'info.similar', required: false },
  { key: 'ps5date', label: 'PS5 release date', need: 'game.ps5Release', required: true },
  { key: 'update', label: 'At least one update', need: 'releaseCount > 0', required: true },
  { key: 'ps5row', label: 'PS5 row on the newest update', need: 'releases[0].platforms has ps5', required: false },
]

type Row = Record<string, boolean>
const read = (p: string) => JSON.parse(readFileSync(p, 'utf8'))
const filled = (v: unknown) => (Array.isArray(v) ? v.length > 0 : !!v)

export const coverage = (dir: string) => {
  const index = read(`${dir}/v1/index.json`).games as Record<string, any>[]
  const info = new Map<number, any>()
  for (const f of readdirSync(`${dir}/v1/info`).filter((f) => f.endsWith('.json'))) for (const [id, e] of Object.entries(read(`${dir}/v1/info/${f}`).games as Record<string, any>)) info.set(Number(id), e)
  const rows = new Map<string, Row>()
  for (const g of index) {
    const i = info.get(g.igdbId) ?? {}
    let ps5row = false
    if (g.releaseCount > 0) {
      try { ps5row = (read(`${dir}/v1/games/${g.id}.json`).releases[0]?.platforms ?? []).some((p: any) => p.platform === 'ps5') } catch { ps5row = false }
    }
    rows.set(g.id, {
      cover: filled(g.cover), hero: filled(g.artwork), square: filled(g.squareCover), about: filled(i.summary), story: filled(i.storyline), genres: filled(i.genres),
      trailers: filled(i.videos), official: filled(i.links?.official), notes: filled(i.links?.patchNotes), similar: filled(i.similar), ps5date: filled(g.ps5Release),
      update: g.releaseCount > 0, ps5row,
    })
  }
  return { index, rows }
}

if (process.argv[1]?.endsWith('baseline-coverage.ts')) {
  const dir = process.argv[2]!
  const md = process.argv.includes('--md') ? process.argv[process.argv.indexOf('--md') + 1] : undefined
  const { index, rows } = coverage(dir)
  const n = rows.size
  const base = rows.get('dawnwalker')
  const lines = [`# Baseline coverage`, '', `${n} published games checked against ${FIELDS.length} feed fields. Dawnwalker has ${base ? FIELDS.filter((f) => base[f.key]).length : 0} of ${FIELDS.length}.`, '', '| Field | Needed | Filled | Missing | Share |', '|---|---|---:|---:|---:|']
  for (const f of FIELDS) {
    const have = [...rows.values()].filter((r) => r[f.key]).length
    lines.push(`| ${f.label} (${f.need}) | ${f.required ? 'required' : 'honest empty state'} | ${have} | ${n - have} | ${((100 * have) / n).toFixed(1)}% |`)
  }
  const full = [...rows.values()].filter((r) => FIELDS.every((f) => !f.required || r[f.key])).length
  lines.push('', `Games with every required field: ${full} of ${n} (${((100 * full) / n).toFixed(1)}%).`)
  const miss = (key: string) => index.filter((g) => !rows.get(g.id)![key]).map((g) => g.id)
  lines.push('', '## Games missing a required field', '')
  const out = [...rows.entries()].filter(([, r]) => !FIELDS.every((f) => !f.required || r[f.key]))
  lines.push(`${out.length} games miss at least one required field; first 40 by id:`, '', ...out.slice(0, 40).map(([id, r]) => `- ${id}: ${FIELDS.filter((f) => f.required && !r[f.key]).map((f) => f.label).join(', ')}`))
  void miss
  const text = lines.join('\n') + '\n'
  if (md) writeFileSync(md, text); else console.log(text)
  const under = process.argv.includes('--fail-under') ? Number(process.argv[process.argv.indexOf('--fail-under') + 1]) : 0
  if (under && (100 * full) / n < under) { console.log(`::error::only ${((100 * full) / n).toFixed(1)}% of games pass the baseline (floor ${under}%)`); process.exitCode = 1 }
}
