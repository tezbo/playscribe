// Popular-strip notes check (data-notes-sources-15-press-only). The first-run tour opens a game from the app's Popular strip, the first
// entries of the bundled PS5 index, so each of them must land on an update that shows its notes, or the app says plainly there are none.
// Usage: npx tsx scripts/popular-notes.ts <feed dir holding v1/> [--top 18] [--fail]
// Reports each strip game whose newest update lists no notes, or that the feed does not carry at all. --fail exits 1 when any is found.
import { readFileSync } from 'node:fs'

const read = (p: string) => JSON.parse(readFileSync(p, 'utf8'))

export const popularNotes = (dir: string, top = 18) => {
  const strip = (read(new URL('../../ios/Playscribe/Resources/Data/ps5-index.json', import.meta.url).pathname).games as { i: number; n: string }[]).slice(0, top)
  const byIgdb = new Map<number, Record<string, any>>((read(`${dir}/v1/index.json`).games as Record<string, any>[]).map((g) => [g.igdbId, g]))
  const problems: { name: string; reason: string }[] = []
  for (const s of strip) {
    const g = byIgdb.get(s.i)
    if (!g) { problems.push({ name: s.n, reason: 'not in the feed' }); continue }
    if (!g.releaseCount) { problems.push({ name: s.n, reason: 'no update yet' }); continue }
    const r = read(`${dir}/v1/games/${g.id}.json`).releases[0]
    const items = (r.notes as { items: unknown[] }[]).reduce((n, sec) => n + sec.items.length, 0)
    if (!items) problems.push({ name: s.n, reason: `newest update "${r.displayName}" lists no notes` })
  }
  return { checked: strip.length, problems }
}

if (process.argv[1]?.endsWith('popular-notes.ts')) {
  const dir = process.argv[2]
  if (!dir) throw new Error('usage: popular-notes.ts <feed dir> [--top N] [--fail]')
  const topArg = process.argv.indexOf('--top')
  const { checked, problems } = popularNotes(dir, topArg > 0 ? Number(process.argv[topArg + 1]) : 18)
  for (const p of problems) console.log(`::warning title=Popular strip game without notes::${p.name}: ${p.reason}`)
  console.log(`popular strip: ${checked - problems.length} of ${checked} games show notes`)
  if (process.argv.includes('--fail') && problems.length) process.exit(1)
}
