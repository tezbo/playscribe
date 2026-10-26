// Which alert a release earns on PS5 (docs/ps5-patch-data.md, App rules). Shared by the push job
// and the feed, so the app's local alert and the server push follow the same rule.
// Since 2026-10-27 (Terry) every update that is live on PS5, Steam-assumed included, gets the one
// standard alert; there is no separate "Unconfirmed" alert any more.
export type AlertStyle = 'standard'

export const alertStyleOf = (row: { status: string; verification: string }): AlertStyle | null => (row.status === 'live' ? 'standard' : null)

export const alertOf = (row: { platform: string; status: string; verification: string }) =>
  row.platform === 'ps5' && alertStyleOf(row) ? { alert: { style: 'standard' } as const } : {}
