// Publish safety: compares the feed this backend would publish against the live feed and flags anything an installed app
// could trip on: a field that disappears, or changes type. Added fields are only counted (the apps ignore unknown keys).
// Cutover guard (docs/cutover-0.5.0.md): run before shipping backend changes to main.
//
//   npm run publish-diff -- <newFeedDir> [liveBaseUrl]
//   (newFeedDir holds v1/; liveBaseUrl defaults to the feed branch on raw.githubusercontent.com)
//
// Exit code 1 when a removed or retyped field is found. Arrays are compared by their element shape, so a release that
// merely has more notes is not a difference; a field present on some releases and absent on others is not "removed"
// unless every sample in the live feed had it and none in the new feed does.
import { existsSync, readFileSync, readdirSync } from 'node:fs'
import { join } from 'node:path'

const [dir, base = 'https://raw.githubusercontent.com/tezbo/playscribe/feed/v1'] = process.argv.slice(2)
if (!dir) {
  console.error('Usage: npm run publish-diff -- <newFeedDir> [liveBaseUrl]')
  process.exit(2)
}

type Shape = Map<string, Set<string>> // path -> JSON types seen
const typeOf = (v: unknown) => (v === null ? 'null' : Array.isArray(v) ? 'array' : typeof v)
const walk = (v: unknown, path: string, out: Shape) => {
  const t = typeOf(v)
  ;(out.get(path) ?? out.set(path, new Set()).get(path)!).add(t)
  if (Array.isArray(v)) for (const x of v) walk(x, `${path}[]`, out)
  else if (v && typeof v === 'object') for (const [k, x] of Object.entries(v)) walk(x, `${path}.${k}`, out)
}
const shapeOf = (j: unknown, root: string) => {
  const s: Shape = new Map()
  walk(j, root, s)
  return s
}
// info/<n>.json and games keyed by id: collapse dynamic keys so shapes compare.
const generic = (file: string, j: any) => {
  if (file.startsWith('info/') || file.startsWith('upcoming/') && !file.endsWith('events.json')) return { games: Object.values(j.games ?? {}) }
  return j
}

const files = ['index.json', 'latest.json', 'review.json']
const list = (sub: string) => (existsSync(join(dir, 'v1', sub)) ? readdirSync(join(dir, 'v1', sub)).filter((f) => f.endsWith('.json')).map((f) => `${sub}/${f}`) : [])
const all = [...files, ...list('games'), ...list('news'), ...list('info'), ...list('upcoming')]

const problems: string[] = []
let compared = 0
let added = 0
let missingLive = 0
const merged = new Map<string, { live: Shape; next: Shape }>() // per file family
const family = (f: string): string => (f.includes('/') ? f.split('/')[0]! : f)
for (const f of all) {
  const path = join(dir, 'v1', f)
  if (!existsSync(path)) continue
  const next = JSON.parse(readFileSync(path, 'utf8'))
  const res = await fetch(`${base}/${f}`)
  if (res.status !== 200) {
    missingLive++
    continue
  }
  const live = await res.json()
  compared++
  const fam = family(f)
  const entry = merged.get(fam) ?? { live: new Map(), next: new Map() }
  for (const [p, ts] of shapeOf(generic(f, live), fam)) for (const t of ts) (entry.live.get(p) ?? entry.live.set(p, new Set()).get(p)!).add(t)
  for (const [p, ts] of shapeOf(generic(f, next), fam)) for (const t of ts) (entry.next.get(p) ?? entry.next.set(p, new Set()).get(p)!).add(t)
  merged.set(fam, entry)
}
for (const [fam, { live, next }] of merged) {
  for (const [p, ts] of live) {
    const n = next.get(p)
    if (!n) problems.push(`REMOVED  ${p}  (was ${[...ts].join('|')})`)
    else {
      // null alongside the old type is fine; a type the old shape never had is a retype.
      const fresh = [...n].filter((t) => !ts.has(t) && t !== 'null')
      const lost = [...ts].filter((t) => !n.has(t) && t !== 'null')
      if (fresh.length && lost.length) problems.push(`RETYPED  ${p}  ${[...ts].join('|')} -> ${[...n].join('|')}`)
    }
  }
  for (const p of next.keys()) if (!live.has(p)) added++
}
console.log(`compared ${compared} files against ${base} (${missingLive} new files with no live copy)`)
console.log(`added fields: ${added}`)
if (compared === 0) {
  console.error('Nothing compared: check the feed directory (it must contain v1/) and the live URL.')
  process.exit(2)
}
if (problems.length) {
  console.log(`${problems.length} problem(s):`)
  for (const p of problems) console.log(`  ${p}`)
  process.exit(1)
}
console.log('no removed or retyped fields')
