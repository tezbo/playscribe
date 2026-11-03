// Data-quality rules for the exported feed, run in tests and before the feed is published:
//  - a PC version is never shown as a PS5 version;
//  - no source names or credits in user-facing fields (Terry's rule: verification tags are the only provenance).
import { readdirSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import { feedContractProblems } from './contract.ts'
import { registry as defaultRegistry, steamAppIdOf, type Registry } from './registry.ts'

/** Names of the sources we read, as users would see them. "Steam" is left out: Steam Deck and Steam links are product names. */
export const SOURCE_NAMES = /\b(push\s*square|playstation\s*life\s*style|playstationlifestyle|playstation\.?\s*blog|pushsquare|ign|gamespot|eurogamer|vgc|videogameschronicle)\b/i

const textOf = (r: any): { where: string; text: string }[] => [
  { where: `${r.id} displayName`, text: r.displayName ?? '' },
  ...(r.notes ?? []).flatMap((s: any) => [{ where: `${r.id} note title`, text: s.title ?? '' }, ...(s.items ?? []).map((i: any) => ({ where: `${r.id} note`, text: i.text ?? '' }))]),
]

export const releaseProblems = (r: any): string[] => {
  const out: string[] = []
  const ps5 = r.platforms?.find((p: any) => p.platform === 'ps5')
  const pc = r.platforms?.find((p: any) => p.platform === 'pc')
  if (ps5?.version && pc?.version && ps5.version.value === pc.version.value) out.push(`${r.id}: PS5 version equals the PC version (${pc.version.value})`)
  for (const t of textOf(r)) if (SOURCE_NAMES.test(t.text)) out.push(`${t.where}: names a source ("${t.text.match(SOURCE_NAMES)![0]}")`)
  return out
}

/** A game page is never blank: every game in the index has a release, or an official link (registry `links`, or a Steam page whose news is the patch-notes link). */
export const coverageProblems = (index: { games: { id: string; releaseCount?: number }[] }, reg: Registry = defaultRegistry): string[] =>
  index.games.flatMap((g) => {
    if ((g.releaseCount ?? 0) > 0) return []
    const r = reg.games[g.id]
    if (r?.links?.official || r?.links?.patchNotes) return []
    if (r && !r.steamIsPcPort && r.sources.some(steamAppIdOf)) return []
    return [`${g.id}: no release and no official site or patch-notes link`]
  })

/** Reads v1/games/*.json under a feed root. */
export const feedProblems = (root: string): string[] => {
  const dir = join(root, 'v1', 'games')
  const games = readdirSync(dir)
    .filter((f) => f.endsWith('.json'))
    .flatMap((f) => (JSON.parse(readFileSync(join(dir, f), 'utf8')).releases ?? []).flatMap(releaseProblems))
  return [...games, ...feedContractProblems(root), ...coverageProblems(JSON.parse(readFileSync(join(root, 'v1', 'index.json'), 'utf8')))]
}
