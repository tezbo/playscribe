// Roadmap 18: similar games from IGDB similar_games, in the info shard. Max 8, ids unique, nameless entries dropped.
export interface SimilarGame {
  igdbId: number
  name: string
  coverId?: string
  /** Why it is similar, only where IGDB data supports it: "Same studio" or "Same genre: <genre>". */
  why?: string
}
type Row = { id?: number; name?: string; cover?: { image_id?: string }; genres?: { name?: string }[]; involved_companies?: { developer?: boolean; company?: { name?: string } }[] }
/** The game the row is similar to: its genres and developers, for the reason line. */
export type Self = { genres?: { name?: string }[]; involved_companies?: Row['involved_companies'] }
// Too broad to say anything about two games.
const BROAD = new Set(['Indie', 'Adventure'])
const developers = (r: { involved_companies?: Row['involved_companies'] } | undefined) =>
  new Set((r?.involved_companies ?? []).filter((c) => c.developer && c.company?.name).map((c) => c.company!.name!.toLowerCase()))
export const whyOf = (self: Self | undefined, other: Row): string | undefined => {
  if (!self) return undefined
  const mine = developers(self)
  if (mine.size && [...developers(other)].some((d) => mine.has(d))) return 'Same studio'
  const theirs = new Set((other.genres ?? []).map((g) => g.name).filter(Boolean))
  const shared = (self.genres ?? []).map((g) => g.name).find((n) => n && !BROAD.has(n) && theirs.has(n))
  return shared ? `Same genre: ${shared}` : undefined
}
export const SIMILAR_MAX = 8

export const similarOf = (rows: Row[] | undefined, selfId?: number, self?: Self): SimilarGame[] | undefined => {
  const seen = new Set<number>()
  const out: SimilarGame[] = []
  for (const g of rows ?? []) {
    if (!g.id || !g.name || g.id === selfId || seen.has(g.id)) continue
    seen.add(g.id)
    const why = whyOf(self, g)
    out.push({ igdbId: g.id, name: g.name, ...(g.cover?.image_id ? { coverId: g.cover.image_id } : {}), ...(why ? { why } : {}) })
    if (out.length === SIMILAR_MAX) break
  }
  return out.length ? out : undefined
}
