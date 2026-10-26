// Wire types. These mirror docs/ps5-patch-data.md exactly; the iOS app decodes the same shapes.
export type Platform = 'ps5' | 'xboxSeries' | 'switch2' | 'pc'
export type ReleaseKind = 'dayOne' | 'hotfix' | 'patch' | 'major' | 'silent'
export type KindBasis = 'studio' | 'inferred'
export type Trust = 'official' | 'secondary'
/** assumed: a Steam patch with no word on PS5, taken as out on PS5 too (Terry, 2026-10-27). */
export type Verification = 'official' | 'reported' | 'pending' | 'assumed'
export type PlatformStatus = 'live' | 'announced' | 'notPlanned' | 'unknown'
export type NotifyLevel = 'all' | 'major' | 'off'

export interface Field<T> {
  value: T
  verification: Verification
  sourceId: string
  checkedAt: string
}

export interface NoteItem {
  text: string
  platforms?: Platform[]
  ps5ProOnly: boolean
}

export interface NoteSection {
  title: string
  items: NoteItem[]
}

export interface PlatformRelease {
  platform: Platform
  status: PlatformStatus
  version: Field<string> | null
  sizeBytes: Field<number> | null
  liveAt: Field<string> | null
  bundles: string[]
  verification: Verification
  /** PS5 only: the one alert this release earns, once it is live. */
  alert?: { style: 'standard' }
}

export interface ReleaseLinks {
  steamNotes?: string
  ps5Page?: string
}

export interface Release {
  id: string
  gameId: string
  displayName: string
  kind: ReleaseKind
  kindBasis: KindBasis
  announcedAt: string
  notes: NoteSection[]
  sourceIds: string[]
  /** Where the notes came from: the Steam post, and the studio's own PS5 page for this update when one exists. */
  links: ReleaseLinks
  platforms: PlatformRelease[]
  revision: number
  updatedAt: string
}

export interface Game {
  id: string
  igdbId: number | null
  name: string
  cover: { imageId: string; url: string } | null
  /** Official landscape key art (IGDB t_1080p) for the app to centre-crop to a square tile. Null: use the cover. */
  artwork: { imageId: string; url: string } | null
  /** The studio's own square cover (IGDB t_720p), shown as the tile as it is. Rare; beats artwork when present. */
  squareCover: { imageId: string; url: string } | null
  ps5Release: string | null
  /** How exact ps5Release is when it is not a day: "Q4 2027" is 2027-12-31 with quarter. Absent means a day. */
  ps5ReleasePrecision?: 'month' | 'quarter' | 'year' | 'tbd'
  ps5TitleIds: string[]
}

/** A post as a source adapter hands it over, before it becomes (part of) a release. */
export interface Post {
  sourceId: string
  postId: string
  url: string
  title: string
  publishedAt: string
  /** Plain text, or light HTML/BBCode; notes are extracted from it. */
  body: string
  /** The site's own topic tags for the post (game names, systems), when it lists them. */
  tags?: string[]
  /** Fetches the full post when the listing only had a teaser. Called only for posts that match a game. */
  expand?: () => Promise<Pick<Post, 'body'> & Partial<Pick<Post, 'publishedAt' | 'title'>>>
}
