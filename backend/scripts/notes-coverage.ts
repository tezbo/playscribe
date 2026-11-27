// Notes coverage over the whole feed (data-notes-coverage-all-games): for each published game's newest update, does the player see real notes?
// Usage: npx tsx scripts/notes-coverage.ts <feed dir holding v1/> [--list]
//   noNotes       the newest update lists no notes (split: only press reports have it, or an official source gave a post that parsed to nothing)
//   oneBigItem    one item over 1,500 characters among at most 3 items (a post flattened into a blob)
//   singleItem    one short item: mostly a studio's one-liner, so honest
//   noHeadline    notes exist but the Feed found no line to quote, so the app shows no subtitle (never a filler)
//   filler        notes exist and the Feed sent no headline and no key changes at all (what the app drew as "Fixes and tuning" before the Feed wrote headlines)
import { readdirSync, readFileSync } from 'node:fs'

const PRESS = (id: string) => /pushsquare|playstationlifestyle|psblog|playstation-blog/.test(id)

export const notesCoverage = (dir: string) => {
  const out = { games: 0, published: 0, noNotesPressOnly: [] as string[], noNotesOfficial: [] as string[], oneBigItem: [] as string[], singleItem: 0, withNotes: 0, withHeadline: 0, noHeadline: 0, filler: 0 }
  for (const f of readdirSync(`${dir}/v1/games`).filter((f) => f.endsWith('.json'))) {
    out.games++
    const d = JSON.parse(readFileSync(`${dir}/v1/games/${f}`, 'utf8'))
    const r = d.releases[0]
    if (!r) continue
    out.published++
    const items: string[] = r.notes.flatMap((s: any) => s.items.map((i: any) => i.text))
    if (!items.length) { (r.sourceIds.every(PRESS) ? out.noNotesPressOnly : out.noNotesOfficial).push(d.game.id); continue }
    out.withNotes++
    if (Math.max(...items.map((t) => t.length)) > 1500 && items.length <= 3) out.oneBigItem.push(d.game.id)
    if (items.length === 1) out.singleItem++
    if (r.headline) out.withHeadline++
    else out.noHeadline++
    if (!r.headline && !r.keyChanges?.length && r.headline === undefined && !('headline' in r) && !('keyChanges' in r)) out.filler++
  }
  return out
}

if (process.argv[1]?.endsWith('notes-coverage.ts')) {
  const dir = process.argv[2]
  if (!dir) throw new Error('usage: notes-coverage.ts <feed dir> [--list]')
  const c = notesCoverage(dir)
  const list = process.argv.includes('--list')
  console.log(`games ${c.published} published of ${c.games}; ${c.withNotes} have notes`)
  console.log(`no notes, press only:     ${c.noNotesPressOnly.length}${list ? ' ' + c.noNotesPressOnly.join(', ') : ''}`)
  console.log(`no notes, official post:  ${c.noNotesOfficial.length}${list ? ' ' + c.noNotesOfficial.join(', ') : ''}`)
  console.log(`one big item:             ${c.oneBigItem.length}${list ? ' ' + c.oneBigItem.join(', ') : ''}`)
  console.log(`single short item:        ${c.singleItem}`)
  console.log(`headline from the notes:  ${c.withHeadline}; none found (no subtitle): ${c.noHeadline}`)
  console.log(`filler (Feed sent no headline or key changes): ${c.filler}`)
}
