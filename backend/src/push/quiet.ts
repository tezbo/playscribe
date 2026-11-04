// Quiet hours (r050-quiet-hours-push, option A). The app registers a window (minutes after local midnight) and an IANA
// time zone; the relay then sends pushes inside the window as `passive` with no sound. No window registered means
// today's behaviour. Daylight saving is handled by storing the zone, never an offset.
export interface QuietHours {
  from: number
  until: number
  timeZone: string
}

const MINUTES = 24 * 60

export const parseQuietHours = (v: unknown): QuietHours | null | { error: string } => {
  if (v === null) return null
  if (typeof v !== 'object' || v === undefined) return { error: 'quietHours must be an object or null' }
  const { from, until, timeZone } = v as Record<string, unknown>
  const okMin = (n: unknown) => typeof n === 'number' && Number.isInteger(n) && n >= 0 && n < MINUTES
  if (!okMin(from) || !okMin(until)) return { error: 'quietHours.from and until are whole minutes from 0 to 1439' }
  if (from === until) return { error: 'quietHours.from and until must differ (send null to switch off)' }
  if (typeof timeZone !== 'string' || !timeZone) return { error: 'quietHours.timeZone must be an IANA time zone' }
  try {
    new Intl.DateTimeFormat('en-GB', { timeZone })
  } catch {
    return { error: 'quietHours.timeZone is not a known time zone' }
  }
  return { from: from as number, until: until as number, timeZone }
}

/** Minutes after midnight at `at` in the zone. */
export const localMinutes = (at: Date, timeZone: string): number => {
  const parts = new Intl.DateTimeFormat('en-GB', { timeZone, hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).formatToParts(at)
  const get = (t: string) => Number(parts.find((p) => p.type === t)?.value)
  return get('hour') * 60 + get('minute')
}

/** True when `at` falls in [from, until); a window with until < from wraps past midnight (22:00 to 07:00). */
export const inQuietHours = (q: QuietHours | null, at: Date = new Date()): boolean => {
  if (!q) return false
  let m: number
  try {
    m = localMinutes(at, q.timeZone)
  } catch {
    return false
  }
  return q.from < q.until ? m >= q.from && m < q.until : m >= q.from || m < q.until
}
