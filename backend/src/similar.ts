// Roadmap 18: similar games from IGDB similar_games, in the info shard. Max 8, ids unique, nameless entries dropped.
export interface SimilarGame {
  igdbId: number
  name: string
  coverId?: string
}
export const SIMILAR_MAX = 8

export const similarOf = (rows: { id?: number; name?: string; cover?: { image_id?: string } }[] | undefined, selfId?: number): SimilarGame[] | undefined => {
  const seen = new Set<number>()
  const out: SimilarGame[] = []
  for (const g of rows ?? []) {
    if (!g.id || !g.name || g.id === selfId || seen.has(g.id)) continue
    seen.add(g.id)
    out.push({ igdbId: g.id, name: g.name, ...(g.cover?.image_id ? { coverId: g.cover.image_id } : {}) })
    if (out.length === SIMILAR_MAX) break
  }
  return out.length ? out : undefined
}
