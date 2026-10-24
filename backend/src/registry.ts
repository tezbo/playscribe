import registryJson from './sources/registry.json' with { type: 'json' }
import type { Platform, Trust } from './types.ts'

// The per-game official source registry, edited by hand (see docs/ps5-patch-data.md).
export interface SourceDef {
  id: string
  kind: 'rss' | 'html' | 'steamNews'
  url: string
  platforms: Platform[]
  trust: Trust
  fetch: 'auto' | 'manual'
  /** always: every item is about PS5 (shared feeds still match the game by name). explicit: the post must name PS5. */
  ps5Signal: 'always' | 'explicit'
}

export interface RegistryGame {
  name: string
  igdbId: number | null
  ps5TitleIds: string[]
  sources: SourceDef[]
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
