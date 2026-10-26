// Which alert a release earns on PS5 (docs/ps5-patch-data.md, App rules). Shared by the push job
// and the feed, so the app's local alert and the server push follow the same rule.
export type AlertStyle = 'standard' | 'quiet'
export const UNCONFIRMED = 'Unconfirmed'

/** standard when live and official; quiet ("Unconfirmed") when live and press-reported; else none. */
export const alertStyleOf = (row: { status: string; verification: string }): AlertStyle | null =>
  row.status !== 'live' ? null : row.verification === 'official' ? 'standard' : row.verification === 'reported' ? 'quiet' : null

export const alertOf = (row: { platform: string; status: string; verification: string }) => {
  const style = row.platform === 'ps5' ? alertStyleOf(row) : null
  return style === 'quiet' ? { alert: { style, tag: UNCONFIRMED } as const } : style ? { alert: { style } as const } : {}
}
