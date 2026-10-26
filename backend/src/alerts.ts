// Which alert a release earns on PS5 (docs/ps5-patch-data.md, App rules). Shared by the push job
// and the feed, so the app's local alert and the server push follow the same rule.
// Since 2026-10-27 (Terry) Steam is the source of truth: every update live on PS5, Steam-assumed
// included, is "Released" and gets the standard alert. Only a release the press reports and neither
// Steam nor the studio has (no links) is "Unconfirmed", with its one quiet alert.
export type AlertStyle = 'standard' | 'quiet'
export const UNCONFIRMED = 'Unconfirmed'

export const pressOnly = (links: { steamNotes?: string; ps5Page?: string }) => !links.steamNotes && !links.ps5Page

export const alertStyleOf = (row: { status: string; verification: string }, links: { steamNotes?: string; ps5Page?: string }): AlertStyle | null =>
  row.status !== 'live' ? null : row.verification === 'reported' && pressOnly(links) ? 'quiet' : 'standard'

export const alertOf = (row: { platform: string; status: string; verification: string }, links: { steamNotes?: string; ps5Page?: string }) => {
  const style = row.platform === 'ps5' ? alertStyleOf(row, links) : null
  return style === 'quiet' ? { alert: { style, tag: UNCONFIRMED } as const } : style ? { alert: { style } as const } : {}
}
