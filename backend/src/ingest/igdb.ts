import { USER_AGENT, type FetchFn } from '../http.ts'

// IGDB, through a Twitch app token. Called only from the server: IGDB refuses browser calls and
// the client secret must never reach the app. The limit is 4 requests a second.
export interface IgdbGame {
  igdbId: number
  slug: string
  name: string
  coverImageId: string | null
  ps5Release: string | null
  firstRelease: string | null
  steamAppId: number | null
  onPs5: boolean
}

const day = (s?: number) => (s ? new Date(s * 1000).toISOString().slice(0, 10) : null)
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))

export class Igdb {
  private token: { value: string; expiresAt: number } | null = null
  private ids: { steam: number; ps5: number } | null = null
  private last = 0

  constructor(
    private readonly clientId: string,
    private readonly clientSecret: string,
    private readonly fetchFn: FetchFn = fetch,
  ) {}

  private async auth() {
    if (this.token && Date.now() < this.token.expiresAt - 60_000) return this.token.value
    const r = await this.fetchFn(
      `https://id.twitch.tv/oauth2/token?client_id=${encodeURIComponent(this.clientId)}&client_secret=${encodeURIComponent(this.clientSecret)}&grant_type=client_credentials`,
      { method: 'POST', headers: { 'user-agent': USER_AGENT } },
    )
    if (!r.ok) throw new Error(`Twitch token ${r.status}`)
    const t = (await r.json()) as { access_token: string; expires_in: number }
    this.token = { value: t.access_token, expiresAt: Date.now() + t.expires_in * 1000 }
    return t.access_token
  }

  async query<T>(endpoint: string, body: string, attempt = 0): Promise<T[]> {
    const wait = this.last + 260 - Date.now()
    if (wait > 0) await sleep(wait)
    this.last = Date.now()
    const r = await this.fetchFn(`https://api.igdb.com/v4/${endpoint}`, {
      method: 'POST',
      headers: { 'user-agent': USER_AGENT, 'Client-ID': this.clientId, Authorization: `Bearer ${await this.auth()}`, Accept: 'application/json' },
      body,
    })
    if (r.status === 429 && attempt < 3) {
      await sleep(1000 * (attempt + 1))
      return this.query(endpoint, body, attempt + 1)
    }
    if (r.status === 401 && attempt < 1) {
      this.token = null
      return this.query(endpoint, body, attempt + 1)
    }
    if (!r.ok) throw new Error(`IGDB ${endpoint} ${r.status}: ${await r.text()}`)
    return r.json() as Promise<T[]>
  }

  private async lookups() {
    if (this.ids) return this.ids
    const [steam] = await this.query<{ id: number }>('external_game_sources', 'fields id; where name = "Steam"; limit 1;')
    const [ps5] = await this.query<{ id: number }>('platforms', 'fields id; where slug = "ps5"; limit 1;')
    if (!steam || !ps5) throw new Error('IGDB: Steam source or PS5 platform not found')
    this.ids = { steam: steam.id, ps5: ps5.id }
    return this.ids
  }

  private static FIELDS = 'fields name,slug,first_release_date,cover.image_id,platforms,release_dates.date,release_dates.platform,external_games.uid,external_games.external_game_source;'

  private async toGame(g: any): Promise<IgdbGame> {
    const { steam, ps5 } = await this.lookups()
    const ps5Dates = (g.release_dates ?? []).filter((d: any) => d.platform === ps5 && d.date).map((d: any) => d.date as number).sort()
    const steamUid = (g.external_games ?? []).find((e: any) => e.external_game_source === steam)?.uid
    return {
      igdbId: g.id,
      slug: g.slug,
      name: g.name,
      coverImageId: g.cover?.image_id ?? null,
      ps5Release: day(ps5Dates[0]),
      firstRelease: day(g.first_release_date),
      steamAppId: steamUid ? Number(steamUid) : null,
      onPs5: (g.platforms ?? []).includes(ps5),
    }
  }

  async byId(igdbId: number) {
    const [g] = await this.query<any>('games', `${Igdb.FIELDS} where id = ${Math.trunc(igdbId)};`)
    return g ? this.toGame(g) : null
  }

  async bySteamAppId(appid: number) {
    const { steam } = await this.lookups()
    const [ext] = await this.query<{ game: number }>('external_games', `fields game; where external_game_source = ${steam} & uid = "${Math.trunc(appid)}"; limit 1;`)
    return ext ? this.byId(ext.game) : null
  }

  /** PS5 games only, editions folded into their parent. */
  async searchPs5(q: string, limit = 20) {
    const { ps5 } = await this.lookups()
    const safe = q.replace(/["\\]/g, ' ').slice(0, 80)
    const rows = await this.query<any>('games', `${Igdb.FIELDS} search "${safe}"; where platforms = (${ps5}) & version_parent = null; limit ${Math.min(limit, 50)};`)
    return Promise.all(rows.map((g) => this.toGame(g)))
  }
}
