// Picks a game's tile art from its IGDB artworks: the studio's official promotional images, landscape
// and usually 16:9. The app centre-crops it to the square game tile, and falls back to the portrait
// cover over a blurred fill when a game has none. Store tile art (PS Store) is never used: no Sony
// store data (docs/ps5-patch-data.md).
//
// IGDB types artworks (artwork_types, checked 2026-10-25: Key art without/with logo, Artwork,
// Concept art, Square cover, logos, icons, covers…). A studio square cover is the tile as it is;
// otherwise textless key art crops best, then key art with a logo, then other art.
export interface Artwork {
  image_id?: string
  artwork_type?: number
  width?: number
  height?: number
}

/** IGDB's artwork type names by id, or an empty map where IGDB has no artwork_types endpoint (then the widest artwork wins). */
export const artworkTypes = async (query: <T>(endpoint: string, body: string) => Promise<T[]>) => {
  try {
    const rows = await query<{ id: number; name?: string; slug?: string }>('artwork_types', 'fields *; limit 50;')
    return new Map(rows.map((t) => [t.id, t.name ?? t.slug ?? '']))
  } catch {
    return new Map<number, string>()
  }
}

/** The artworks fields to request; artwork_type only where IGDB has types. */
export const artworkFields = (types: Map<number, string>) =>
  'artworks.image_id,artworks.width,artworks.height' + (types.size ? ',artworks.artwork_type' : '')

export const artworkUrl = (imageId: string) => `https://images.igdb.com/igdb/image/upload/t_1080p/${imageId}.jpg`
export const squareCoverUrl = (imageId: string) => `https://images.igdb.com/igdb/image/upload/t_720p/${imageId}.jpg`

// Rank by IGDB type name. Logos, icons, infographics and alternative or historical covers are not
// tile art; with no type at all (IGDB without artwork_types) an artwork counts as plain art.
const rankOfType = (name: string | undefined) => {
  const n = (name ?? '').toLowerCase()
  if (/key ?art/.test(n)) return /(without|no) logo|textless/.test(n) ? 0 : 1
  if (/logo|icon|infographic|cover|screenshot/.test(n)) return undefined
  return 2
}

/** Landscape key art: textless first, then with a logo, then other art; the widest within a rank. */
export const artworkOf = (rows: Artwork[] | undefined, typeName: (id: number | undefined) => string | undefined): string | undefined =>
  (rows ?? [])
    .filter((a) => a.image_id && (a.width ?? 1) >= (a.height ?? 0))
    .map((a, i) => ({ id: a.image_id!, rank: rankOfType(typeName(a.artwork_type)), w: a.width ?? 0, i }))
    .filter((a) => a.rank !== undefined)
    .sort((a, b) => a.rank! - b.rank! || b.w - a.w || a.i - b.i)[0]?.id

/** The studio's square cover (IGDB "Square cover" artwork), used as the tile as it is. Rare. */
export const squareCoverOf = (rows: Artwork[] | undefined, typeName: (id: number | undefined) => string | undefined): string | undefined =>
  (rows ?? []).filter((a) => a.image_id && /square cover/i.test(typeName(a.artwork_type) ?? '')).sort((a, b) => (b.width ?? 0) - (a.width ?? 0))[0]?.image_id
