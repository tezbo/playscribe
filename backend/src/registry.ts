import registryJson from './sources/registry.json' with { type: 'json' }
import type { Platform, Trust } from './types.ts'

// The per-game official source registry, edited by hand (see docs/ps5-patch-data.md).
export interface SourceDef {
  id: string
  /** pressIndex: a press site's paged list of update articles; matching articles are opened for their facts. */
  kind: 'rss' | 'html' | 'steamNews' | 'pressIndex' | 'bluesky' | 'statuspage' | 'mojangNotes' | 'riotNews'
  url: string
  platforms: Platform[]
  trust: Trust
  fetch: 'auto' | 'manual'
  /** always: every item is about PS5 (shared feeds still match the game by name). explicit: the post must name PS5. */
  ps5Signal: 'always' | 'explicit'
  /** A feed shared by several games or products: a post counts only if its text names one of these (case and accents ignored). */
  mentions?: string[]
  /** Only posts that read like a patch post become releases; the rest are dropped (an official account's other posts). */
  patchOnly?: boolean
  /** With patchOnly: a regex the post's title must also match (Remedy's feed has "update notes" posts and feature posts alike). */
  titleMatch?: string
}

/** A game with no readable official source, written down on purpose (docs/ps5-patch-data.md, "Sources of record"). */
export interface SourceGap {
  /** Why there is none: the terms, the block, or the absence. */
  reason: string
  /** The next step to close it, and who owns it. */
  next: string
  since: string
}

export interface RegistryGame {
  name: string
  /** Other names the press uses ("GTA 5", "Dawnwalker"); matched like the name. */
  aliases?: string[]
  /** Names that contain this one but are other games ("Minecraft Dungeons" for Minecraft). */
  exclude?: string[]
  igdbId: number | null
  ps5TitleIds: string[]
  /** The Steam version is a separate PC port with its own patches, so a Steam patch says nothing about PS5. */
  steamIsPcPort?: boolean
  /** Official site and patch-notes page for games with no Steam page or readable official feed; overrides IGDB's. */
  links?: { official?: string; patchNotes?: string }
  sources: SourceDef[]
  /** Set only when `sources` is empty: the reason and next step. A registry game with neither fails the registry test. */
  sourceGap?: SourceGap
}

export interface Registry {
  version: number
  shared: SourceDef[]
  games: Record<string, RegistryGame>
}

export const registry = registryJson as unknown as Registry

export const steamAppIdOf = (s: SourceDef) => {
  const m = s.url.match(/\/app\/(\d+)/)
  return m ? Number(m[1]) : null
}
