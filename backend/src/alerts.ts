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

/** Roadmap 11: an alert older than this is never raised, by the push job or by the app. */
export const ALERT_MAX_AGE_HOURS = 72

/** When the alert's 72 h guard counts from: the moment a console-later update went live, else its live date. */
export const alertFromOf = (row: { alert_from?: string | null; live_at?: string | null }): string | undefined => {
  if (row.alert_from) return row.alert_from
  try {
    return (JSON.parse(row.live_at ?? 'null') as { value?: string } | null)?.value ?? undefined
  } catch {
    return undefined
  }
}

export const alertOf = (row: { platform: string; status: string; verification: string; alert_from?: string | null; live_at?: string | null }, links: { steamNotes?: string; ps5Page?: string }) => {
  const style = row.platform === 'ps5' ? alertStyleOf(row, links) : null
  if (!style) return {}
  const from = alertFromOf(row)
  const f = from ? { from } : {}
  return style === 'quiet' ? { alert: { style, tag: UNCONFIRMED, ...f } as const } : { alert: { style, ...f } as const }
}
