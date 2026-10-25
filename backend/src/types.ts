// Wire types. These mirror docs/ps5-patch-data.md exactly; the iOS app decodes the same shapes.
export type Platform = 'ps5' | 'xboxSeries' | 'switch2' | 'pc'
export type ReleaseKind = 'dayOne' | 'hotfix' | 'patch' | 'major' | 'silent'
export type KindBasis = 'studio' | 'inferred'
export type Trust = 'official' | 'secondary'
export type Verification = 'official' | 'reported' | 'pending'
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
