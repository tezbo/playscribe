// Picks a game's key art from its IGDB artworks: the studio's official promotional images, landscape
// and usually 16:9. The app centre-crops it to the square game tile, and falls back to the portrait
// cover over a blurred fill when a game has none. Store tile art (PS Store) is never used: no Sony
// store data (docs/ps5-patch-data.md).
//
// IGDB types artworks (artwork_types): textless key art crops best, so it wins over key art with a
// logo, which wins over anything else (concept art, wallpapers). Wider images win within a type.
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

const rankOfType = (name: string | undefined) => {
  const n = (name ?? '').toLowerCase()
  if (/key ?art/.test(n) && /(without|no) logo|textless/.test(n)) return 0
  if (/key ?art/.test(n)) return 1
  if (/screenshot/.test(n)) return 3
  return 2
}

export const artworkOf = (rows: Artwork[] | undefined, typeName: (id: number | undefined) => string | undefined): string | undefined =>
  (rows ?? [])
    .filter((a) => a.image_id && (a.width ?? 1) >= (a.height ?? 0))
    .map((a, i) => ({ id: a.image_id!, rank: rankOfType(typeName(a.artwork_type)), w: a.width ?? 0, i }))
    .sort((a, b) => a.rank - b.rank || b.w - a.w || a.i - b.i)[0]?.id
