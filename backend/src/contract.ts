// Contract with the 0.2.0 app (tag 0.2.0, ios/Playscribe/Model/PatchData.swift, Services/FeedClient.swift,
// Services/GameInfo.swift). Every rule below is a place where the Swift decoder throws, which makes the whole
// latest.json, games/<id>.json or info/<n>.json fail to decode. Unknown extra keys are fine; unknown enum
// values, wrong types, missing required keys and unparseable dates or URLs are not. Run on the exported feed
// before publish, so a backend change can ship ahead of the app without breaking installed copies.
// Refresh the rules from the Swift models when a later app version becomes the oldest one in use.
import { readdirSync, readFileSync } from 'node:fs'
import { join } from 'node:path'

const PLATFORM = ['ps5', 'xboxSeries', 'switch2', 'pc']
const KIND = ['dayOne', 'hotfix', 'patch', 'major', 'silent']
const BASIS = ['studio', 'inferred']
const STATUS = ['live', 'announced', 'notPlanned', 'unknown']

type J = any
const isObj = (v: J) => v !== null && typeof v === 'object' && !Array.isArray(v)
// JSONCoding.decoder: ISO 8601, with or without fractional seconds (Date(s, strategy: .iso8601)).
const isDate = (v: J) => typeof v === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:?\d{2})$/.test(v) && !Number.isNaN(Date.parse(v))
// Foundation URL decoding fails on a string URL(string:) rejects (empty, spaces, bare words).
export const isUrl = (v: J) => typeof v === 'string' && /^https?:\/\/[^\s]+$/.test(v)

export const contractProblems = {
  field(f: J, where: string, valueOk: (v: J) => boolean): string[] {
    if (f == null) return []
    if (!isObj(f)) return [`${where}: not an object`]
    const out: string[] = []
    if (!valueOk(f.value)) out.push(`${where}.value: wrong type`)
    if (typeof f.verification !== 'string') out.push(`${where}.verification: missing`)
    if (typeof f.sourceId !== 'string') out.push(`${where}.sourceId: missing`)
    if (!isDate(f.checkedAt)) out.push(`${where}.checkedAt: not an ISO date`)
    return out
  },

  release(r: J): string[] {
    const w = r?.id ?? '?'
    if (!isObj(r)) return ['release: not an object']
    const out: string[] = []
    for (const k of ['id', 'gameId', 'displayName']) if (typeof r[k] !== 'string') out.push(`${w}.${k}: missing string`)
    if (!KIND.includes(r.kind)) out.push(`${w}.kind: "${r.kind}" is not a 0.2.0 ReleaseKind`)
    if (!BASIS.includes(r.kindBasis)) out.push(`${w}.kindBasis: "${r.kindBasis}" is not a 0.2.0 KindBasis`)
    if (r.ps4 !== undefined && r.ps4 !== true) out.push(`${w}.ps4: must be true or absent`)
    if (!isDate(r.announcedAt)) out.push(`${w}.announcedAt: not an ISO date`)
    if (!Array.isArray(r.sourceIds) || r.sourceIds.some((s: J) => typeof s !== 'string')) out.push(`${w}.sourceIds: not [String]`)
    if (!Array.isArray(r.notes)) out.push(`${w}.notes: not an array`)
    else
      for (const s of r.notes) {
        if (typeof s?.title !== 'string' || !Array.isArray(s.items)) { out.push(`${w}.notes: bad section`); continue }
        for (const i of s.items) {
          if (typeof i?.text !== 'string') out.push(`${w}.notes item: text is not a string`)
          if (i?.platforms != null && (!Array.isArray(i.platforms) || i.platforms.some((p: J) => !PLATFORM.includes(p)))) out.push(`${w}.notes item: platforms has a value 0.2.0 cannot decode`)
          if (i?.ps5ProOnly != null && typeof i.ps5ProOnly !== 'boolean') out.push(`${w}.notes item: ps5ProOnly is not Bool`)
          if (i?.spoiler != null && typeof i.spoiler !== 'boolean') out.push(`${w}.notes item: spoiler is not Bool`)
        }
      }
    if (!Array.isArray(r.platforms)) out.push(`${w}.platforms: not an array`)
    else
      for (const p of r.platforms) {
        if (!PLATFORM.includes(p?.platform)) out.push(`${w}.platforms: platform "${p?.platform}" is not a 0.2.0 Platform`)
        if (!STATUS.includes(p?.status)) out.push(`${w}.platforms: status "${p?.status}" is not a 0.2.0 PlatformStatus`)
        if (typeof p?.verification !== 'string') out.push(`${w}.platforms: verification missing`)
        if (p?.bundles != null && (!Array.isArray(p.bundles) || p.bundles.some((b: J) => typeof b !== 'string'))) out.push(`${w}.platforms: bundles not [String]`)
        out.push(...this.field(p?.version, `${w}.version`, (v) => typeof v === 'string'))
        out.push(...this.field(p?.sizeBytes, `${w}.sizeBytes`, (v) => Number.isInteger(v)))
        out.push(...this.field(p?.liveAt, `${w}.liveAt`, isDate))
        if (p?.alert != null && (!isObj(p.alert) || typeof p.alert.style !== 'string' || (p.alert.tag != null && typeof p.alert.tag !== 'string'))) out.push(`${w}.platforms: alert needs a string style`)
      }
    if (r.links != null) {
      if (!isObj(r.links)) out.push(`${w}.links: not an object`)
      else for (const k of ['steamNotes', 'ps5Page']) if (r.links[k] != null && !isUrl(r.links[k])) out.push(`${w}.links.${k}: not a URL`)
    }
    for (const k of ['headline', 'summary', 'videoNote', 'pushLine']) if (r[k] != null && typeof r[k] !== 'string') out.push(`${w}.${k}: not a string`)
    return out
  },

  /** latest.json: `Latest { updatedAt: Date; releases: [Release] }`. */
  latest(j: J): string[] {
    if (!isDate(j?.updatedAt)) return ['latest.json: updatedAt is not an ISO date']
    return Array.isArray(j.releases) ? j.releases.flatMap((r: J) => this.release(r)) : ['latest.json: releases is not an array']
  },

  /** games/<id>.json: `GameHistory { releases: [Release] }`. */
  history(j: J): string[] {
    return Array.isArray(j?.releases) ? j.releases.flatMap((r: J) => this.release(r)) : ['history: releases is not an array']
  },

  /** info/<n>.json: `Shard { games: [String: GameBasics] }`. */
  info(j: J): string[] {
    if (!isObj(j?.games)) return ['info: games is not an object']
    const out: string[] = []
    for (const [id, g] of Object.entries<J>(j.games)) {
      for (const k of ['summary', 'storyline', 'firstRelease']) if (g[k] != null && typeof g[k] !== 'string') out.push(`info ${id}.${k}: not a string`)
      if (g.genres != null && (!Array.isArray(g.genres) || g.genres.some((x: J) => typeof x !== 'string'))) out.push(`info ${id}.genres: not [String]`)
      if (g.videos != null && (!Array.isArray(g.videos) || g.videos.some((v: J) => typeof v?.youtubeId !== 'string' || typeof v?.name !== 'string'))) out.push(`info ${id}.videos: needs youtubeId and name`)
      if (g.links != null) for (const k of ['official', 'patchNotes']) if (g.links[k] != null && !isUrl(g.links[k])) out.push(`info ${id}.links.${k}: not a URL`)
    }
    return out
  },
}

const readJson = (root: string, p: string) => JSON.parse(readFileSync(join(root, 'v1', p), 'utf8'))

/** latest.json and every games/<id>.json under a feed root (the folder holding v1/). These block publishing. */
export const feedContractProblems = (root: string): string[] => {
  const out = contractProblems.latest(readJson(root, 'latest.json'))
  for (const f of readdirSync(join(root, 'v1', 'games')).filter((x) => x.endsWith('.json'))) out.push(...contractProblems.history(readJson(root, `games/${f}`)).map((p) => `games/${f}: ${p}`))
  return out
}

/** info/<n>.json shards, written by a weekly job rather than the ingest run, so these are reported as warnings. */
export const infoContractProblems = (root: string): string[] => {
  try {
    return readdirSync(join(root, 'v1', 'info')).filter((x) => x.endsWith('.json')).flatMap((f) => contractProblems.info(readJson(root, `info/${f}`)).map((p) => `info/${f}: ${p}`))
  } catch {
    return []
  }
}
