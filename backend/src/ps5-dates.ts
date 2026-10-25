// Pure date rules for the bundled PS5 index (scripts/ps5-index.ts). See that script for the field meanings.

export const PS5_LAUNCH = '2020-11-12'

export interface ReleaseDate { date?: number; platform: number; status?: number; human?: string; release_region?: number }
export interface PlatformDate { date: string; full: boolean }

export const day = (s?: number) => (s ? new Date(s * 1000).toISOString().slice(0, 10) : undefined)

/**
 * A platform's release: the earliest full release, else the earliest date of any other status
 * (alpha, beta, early access), flagged not full. Patch-release rows are never releases.
 * `notBefore` drops rows dated before the platform existed (IGDB data errors).
 */
export const releaseDateOf = (rows: ReleaseDate[] | undefined, platformId: number, nameOf: (id?: number) => string | undefined, notBefore?: string): PlatformDate | undefined => {
  const on = (rows ?? []).filter((r) => r.platform === platformId && r.date && !/patch/i.test(nameOf(r.status) ?? '') && (!notBefore || day(r.date)! >= notBefore))
  const pick = (list: ReleaseDate[]) => day(list.map((r) => r.date!).sort((a, b) => a - b)[0])
  const full = pick(on.filter((r) => r.status == null || /full release/i.test(nameOf(r.status) ?? '')))
  if (full) return { date: full, full: true }
  const other = pick(on)
  return other ? { date: other, full: false } : undefined
}

export interface Ps5Dates { d?: string; e?: true; b?: string }
export interface Override { d?: string; e?: boolean; b?: string; evidence: string }

/** `d` PS5 release, `e` when `d` is early access (no full release yet), `b` the PS4 release when earlier. */
export const ps5DatesOf = (rows: ReleaseDate[] | undefined, ids: { ps5: number; ps4: number }, nameOf: (id?: number) => string | undefined, override?: Override): Ps5Dates => {
  const ps5 = releaseDateOf(rows, ids.ps5, nameOf, PS5_LAUNCH)
  const ps4 = releaseDateOf(rows, ids.ps4, nameOf)?.date
  const d = override?.d ?? ps5?.date
  const e = override?.d ? override.e === true : ps5 ? !ps5.full : false
  const b = override?.b ?? (ps4 && (!d || ps4 < d) ? ps4 : undefined)
  return { d, ...(e ? { e: true as const } : {}), b }
}

/** Index rows that break the PS5 rules; the build fails on any. */
export const problemsOf = (games: { i: number; n: string; d?: string }[]) =>
  games.filter((g) => g.d && g.d < PS5_LAUNCH).map((g) => `${g.i} ${g.n}: PS5 date ${g.d} is before the PS5 launch (${PS5_LAUNCH})`)
