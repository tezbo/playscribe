// Rebuilds the app's bundled PS5 catalogue, ios/Playscribe/Resources/Data/ps5-index.json, from
// IGDB: every PS5 main game, remake, remaster, expanded game and port (editions folded away by
// version_parent = null), most popular first by IGDB page visits.
//
// Dates: `d` is the game's own PS5 release date and nothing else. Only release_dates rows for the
// PS5 platform count, a full release beats alpha/beta/early access, and a game with no PS5 date
// gets no date (never another platform's). Cover tones already in the file are kept.
//
//   TWITCH_CLIENT_ID=… TWITCH_CLIENT_SECRET=… NODE_USE_ENV_PROXY=1 npm run ps5-index
//   npm run ps5-index -- --inspect 1020,17269     # print every PS5 release_dates row for these ids
import { existsSync, readFileSync, writeFileSync } from 'node:fs'
import { Igdb } from '../src/ingest/igdb.ts'

const OUT = new URL('../../ios/Playscribe/Resources/Data/ps5-index.json', import.meta.url)
const { TWITCH_CLIENT_ID, TWITCH_CLIENT_SECRET } = process.env
if (!TWITCH_CLIENT_ID || !TWITCH_CLIENT_SECRET) {
  console.error('TWITCH_CLIENT_ID and TWITCH_CLIENT_SECRET must be set. Nothing written.')
  process.exit(1)
}
const igdb = new Igdb(TWITCH_CLIENT_ID, TWITCH_CLIENT_SECRET)
const args = process.argv.slice(2)

const [ps5] = await igdb.query<{ id: number }>('platforms', 'fields id; where slug = "ps5"; limit 1;')
if (!ps5) throw new Error('PS5 platform not found')
const statuses = await igdb.query<{ id: number; name: string }>('release_date_statuses', 'fields id,name; limit 50;')
const statusName = new Map(statuses.map((s) => [s.id, s.name]))

interface ReleaseDate { date?: number; platform: number; status?: number; human?: string; release_region?: number }

const day = (s?: number) => (s ? new Date(s * 1000).toISOString().slice(0, 10) : undefined)

/** The game's PS5 release: earliest full release on PS5, else earliest PS5 date of any status. */
export const ps5DateOf = (rows: ReleaseDate[] | undefined, ps5Id: number, nameOf: (id?: number) => string | undefined) => {
  const onPs5 = (rows ?? []).filter((r) => r.platform === ps5Id && r.date)
  const full = onPs5.filter((r) => r.status == null || /full release/i.test(nameOf(r.status) ?? ''))
  const pick = (list: ReleaseDate[]) => list.map((r) => r.date!).sort((a, b) => a - b)[0]
  return day(pick(full) ?? pick(onPs5))
}

if (args.includes('--inspect')) {
  const ids = args[args.indexOf('--inspect') + 1]!.split(',').map(Number)
  const rows = await igdb.query<any>('games', `fields name,first_release_date,release_dates.date,release_dates.platform,release_dates.status,release_dates.human,release_dates.release_region; where id = (${ids.join(',')});`)
  for (const g of rows) {
    console.log(`${g.id} ${g.name} first_release=${day(g.first_release_date)} → d=${ps5DateOf(g.release_dates, ps5.id, (i) => statusName.get(i!))}`)
    for (const r of (g.release_dates ?? []).filter((r: ReleaseDate) => r.platform === ps5.id))
      console.log(`  ${day(r.date) ?? '-'}  ${r.human ?? ''}  status=${statusName.get(r.status!) ?? r.status ?? '-'} region=${r.release_region ?? '-'}`)
  }
  process.exit(0)
}

const types = await igdb.query<{ id: number; type: string }>('game_types', 'fields id,type; limit 50;')
const typeIds = types.filter((t) => ['Main Game', 'Remake', 'Remaster', 'Expanded Game', 'Port'].includes(t.type)).map((t) => t.id)
const [visits] = await igdb.query<{ id: number }>('popularity_types', 'fields id; where name = "Visits"; limit 1;')
if (!visits) throw new Error('Visits popularity type not found')

const rankOf = new Map<number, number>()
for (let offset = 0; offset < 10000; offset += 500) {
  const page = await igdb.query<{ game_id: number }>('popularity_primitives', `fields game_id,value; where popularity_type = ${visits.id}; sort value desc; limit 500; offset ${offset};`)
  for (const p of page) if (!rankOf.has(p.game_id)) rankOf.set(p.game_id, rankOf.size + 1)
  if (page.length < 500) break
}

const old = existsSync(OUT) ? (JSON.parse(readFileSync(OUT, 'utf8')) as { games: { i: number; t?: string[] }[] }) : { games: [] }
const tones = new Map(old.games.filter((g) => g.t).map((g) => [g.i, g.t]))

const games: { i: number; n: string; d?: string; v?: string; p?: string; c?: string; t?: string[]; r: number }[] = []
for (let offset = 0; ; offset += 500) {
  const page = await igdb.query<any>(
    'games',
    'fields name,cover.image_id,release_dates.date,release_dates.platform,release_dates.status,' +
      'involved_companies.company.name,involved_companies.developer,involved_companies.publisher,total_rating_count;' +
      `where platforms = (${ps5.id}) & game_type = (${typeIds.join(',')}) & version_parent = null; sort id asc; limit 500; offset ${offset};`,
  )
  for (const g of page) {
    const company = (role: string) => (g.involved_companies ?? []).find((c: any) => c[role])?.company?.name
    games.push({ i: g.id, n: g.name, d: ps5DateOf(g.release_dates, ps5.id, (i) => statusName.get(i!)), v: company('developer'), p: company('publisher'), c: g.cover?.image_id, t: tones.get(g.id), r: g.total_rating_count ?? 0 })
  }
  if (page.length < 500) break
}
games.sort((a, b) => (rankOf.get(a.i) ?? Infinity) - (rankOf.get(b.i) ?? Infinity) || b.r - a.r)

const index = {
  fetchedAt: new Date().toISOString(),
  count: games.length,
  games: games.map(({ r: _r, ...g }) => Object.fromEntries(Object.entries(g).filter(([, v]) => v !== undefined))),
}
writeFileSync(OUT, JSON.stringify(index) + '\n')
console.log(`wrote ${OUT.pathname}: ${games.length} games, ${games.filter((g) => !g.d).length} without a PS5 date`)
