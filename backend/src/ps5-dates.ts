// Pure date rules for the bundled PS5 index (scripts/ps5-index.ts). See that script for the field meanings.

export const PS5_LAUNCH = '2020-11-12'

export interface ReleaseDate { date?: number; platform: number; status?: number; human?: string; release_region?: number; date_format?: number; category?: number }
/** How exact a date is. A day is the default and is never written; "Q4 2027" is stored as 2027-12-31 with `quarter`. */
export type Precision = 'month' | 'quarter' | 'year' | 'tbd'
export interface PlatformDate { date: string; full: boolean; precision?: Precision }

/**
 * IGDB's format for a release_dates row: `date_format` (an id into date_formats, whose names are
 * YYYYMMMMDD, YYYYMMMM, YYYY, YYYYQ1…Q4, TBD), or the older `category` enum (0 day … 7 TBD).
 */
export const precisionOf = (r: ReleaseDate, formatName: (id?: number) => string | undefined): Precision | undefined => {
  const f = r.date_format != null ? formatName(r.date_format) : r.category != null ? ['YYYYMMMMDD', 'YYYYMMMM', 'YYYY', 'YYYYQ1', 'YYYYQ2', 'YYYYQ3', 'YYYYQ4', 'TBD'][r.category] : undefined
  if (!f || f === 'YYYYMMMMDD') return undefined
  if (f === 'YYYYMMMM') return 'month'
  if (f === 'YYYY') return 'year'
  if (/^YYYYQ\d$/.test(f)) return 'quarter'
  return f === 'TBD' ? 'tbd' : undefined
}

export const day = (s?: number) => (s ? new Date(s * 1000).toISOString().slice(0, 10) : undefined)

/**
 * A platform's release: the earliest full release, else the earliest date of any other status
 * (alpha, beta, early access), flagged not full. Patch-release rows are never releases.
 * `notBefore` drops rows dated before the platform existed (IGDB data errors).
 */
export const releaseDateOf = (
  rows: ReleaseDate[] | undefined,
  platformId: number,
  nameOf: (id?: number) => string | undefined,
  notBefore?: string,
  formatName: (id?: number) => string | undefined = () => undefined,
): PlatformDate | undefined => {
  const on = (rows ?? []).filter((r) => r.platform === platformId && r.date && !/patch/i.test(nameOf(r.status) ?? '') && (!notBefore || day(r.date)! >= notBefore))
  // The earliest row; on the same day an exact date beats a vaguer one.
  const pick = (list: ReleaseDate[]) => list.sort((a, b) => a.date! - b.date! || Number(!!precisionOf(a, formatName)) - Number(!!precisionOf(b, formatName)))[0]
  const out = (r: ReleaseDate | undefined, full: boolean): PlatformDate | undefined => {
    if (!r) return undefined
    const precision = precisionOf(r, formatName)
    return { date: day(r.date)!, full, ...(precision ? { precision } : {}) }
  }
  return out(pick(on.filter((r) => r.status == null || /full release/i.test(nameOf(r.status) ?? ''))), true) ?? out(pick(on), false)
}

export interface Ps5Dates { d?: string; q?: Precision; e?: true; f?: string; b?: string }
export interface Override { d?: string; e?: boolean; b?: string; evidence: string }

/**
 * `d` PS5 release. When `d` is early access: `f` the later full PS4 release (it plays on
 * PS5; IGDB often records the 1.0 launch on one platform only), or `e` when there is none yet.
 * `b` the PS4 release when earlier than `d`. `q` how exact `d` is when it is not a day ("Q4 2027"
 * is d 2027-12-31, q quarter), or `tbd` when IGDB lists a PS5 release with no date yet.
 */
export const ps5DatesOf = (
  rows: ReleaseDate[] | undefined,
  ids: { ps5: number; ps4: number },
  nameOf: (id?: number) => string | undefined,
  override?: Override,
  formatName: (id?: number) => string | undefined = () => undefined,
): Ps5Dates => {
  const ps5 = releaseDateOf(rows, ids.ps5, nameOf, PS5_LAUNCH, formatName)
  const ps4 = releaseDateOf(rows, ids.ps4, nameOf)?.date
  const d = override?.d ?? ps5?.date
  const early = override?.d ? override.e === true : ps5 ? !ps5.full : false
  const fullOf = (platform: number) => {
    const r = releaseDateOf(rows, platform, nameOf, PS5_LAUNCH)
    return r?.full && d && r.date > d ? r.date : undefined
  }
  const f = early && !override?.d ? fullOf(ids.ps4) : undefined
  const b = override?.b ?? (ps4 && (!d || ps4 < d) ? ps4 : undefined)
  const tbd = !d && (rows ?? []).some((r) => r.platform === ids.ps5 && !r.date && precisionOf(r, formatName) === 'tbd')
  const q = override?.d ? undefined : (ps5?.precision ?? (tbd ? 'tbd' : undefined))
  return { d, ...(q ? { q } : {}), ...(early && !f ? { e: true as const } : {}), ...(f ? { f } : {}), b }
}

/** Index rows that break the PS5 rules; the build fails on any. */
export const problemsOf = (games: { i: number; n: string; d?: string }[]) =>
  games.filter((g) => g.d && g.d < PS5_LAUNCH).map((g) => `${g.i} ${g.n}: PS5 date ${g.d} is before the PS5 launch (${PS5_LAUNCH})`)
