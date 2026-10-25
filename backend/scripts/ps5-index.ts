// Rebuilds the app's bundled PS5 catalogue, ios/Playscribe/Resources/Data/ps5-index.json, from
// IGDB: every PS5 main game, remake, remaster, expanded game and port (editions folded away by
// version_parent = null), most popular first by IGDB page visits.
//
// Dates:
//   d  the game's own PS5 release. Only PS5 release_dates rows count; a full release beats
//      alpha/beta/early access; "patch release" rows (IGDB's next-gen upgrade patches) are not
//      releases and never count, nor are rows dated before the PS5 launch. No PS5 date means no
//      `d`, never another platform's date.
//   e  true when `d` is early access (or alpha/beta): the game has no full PS5 release yet.
//   b  the PS4 release, only when it came before `d` (or there is no `d`): PS4 games play on PS5,
//      so this is when PS5 owners could first play it (Roblox: PS4 Oct 2023, native PS5 Apr 2026).
// Known IGDB gaps are corrected from scripts/ps5-date-overrides.json, each with its evidence.
// Cover tones already in the file are kept.
//
//   TWITCH_CLIENT_ID=… TWITCH_CLIENT_SECRET=… NODE_USE_ENV_PROXY=1 npm run ps5-index
//   npm run ps5-index -- --inspect 1020,17269     # print every PS5/PS4 release_dates row for these ids
import { existsSync, readFileSync, writeFileSync } from 'node:fs'
import { Igdb } from '../src/ingest/igdb.ts'
import { day, ps5DatesOf, problemsOf, type Override, type ReleaseDate } from '../src/ps5-dates.ts'

const OUT = new URL('../../ios/Playscribe/Resources/Data/ps5-index.json', import.meta.url)
const { TWITCH_CLIENT_ID, TWITCH_CLIENT_SECRET } = process.env
if (!TWITCH_CLIENT_ID || !TWITCH_CLIENT_SECRET) {
  console.error('TWITCH_CLIENT_ID and TWITCH_CLIENT_SECRET must be set. Nothing written.')
  process.exit(1)
}
const igdb = new Igdb(TWITCH_CLIENT_ID, TWITCH_CLIENT_SECRET)
const args = process.argv.slice(2)

const [ps5] = await igdb.query<{ id: number }>('platforms', 'fields id; where slug = "ps5"; limit 1;')
const [ps4] = await igdb.query<{ id: number }>('platforms', 'fields id; where slug = "ps4--1"; limit 1;')
if (!ps5 || !ps4) throw new Error('PS5 or PS4 platform not found')
const overrides = JSON.parse(readFileSync(new URL('./ps5-date-overrides.json', import.meta.url), 'utf8')) as Record<string, Override>
const statuses = await igdb.query<{ id: number; name: string }>('release_date_statuses', 'fields id,name; limit 50;')
const statusName = new Map(statuses.map((s) => [s.id, s.name]))

const datesOf = (id: number, rows: ReleaseDate[] | undefined) =>
  ps5DatesOf(rows, { ps5: ps5.id, ps4: ps4.id }, (i) => statusName.get(i!), overrides[String(id)])

if (args.includes('--inspect')) {
  const ids = args[args.indexOf('--inspect') + 1]!.split(',').map(Number)
  const rows = await igdb.query<any>('games', `fields name,first_release_date,release_dates.date,release_dates.platform,release_dates.status,release_dates.human,release_dates.release_region; where id = (${ids.join(',')});`)
  for (const g of rows) {
    const { d, e, b } = datesOf(g.id, g.release_dates)
    console.log(`${g.id} ${g.name} first_release=${day(g.first_release_date)} → d=${d ?? '-'}${e ? ' (early access)' : ''} b=${b ?? '-'}`)
    for (const r of (g.release_dates ?? []).filter((r: ReleaseDate) => r.platform === ps5.id || r.platform === ps4.id))
      console.log(`  ${r.platform === ps5.id ? 'PS5' : 'PS4'} ${day(r.date) ?? '-'}  ${r.human ?? ''}  status=${statusName.get(r.status!) ?? r.status ?? '-'} region=${r.release_region ?? '-'}`)
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

const games: { i: number; n: string; d?: string; e?: true; b?: string; v?: string; p?: string; c?: string; t?: string[]; r: number }[] = []
for (let offset = 0; ; offset += 500) {
  const page = await igdb.query<any>(
    'games',
    'fields name,cover.image_id,release_dates.date,release_dates.platform,release_dates.status,' +
      'involved_companies.company.name,involved_companies.developer,involved_companies.publisher,total_rating_count;' +
      `where platforms = (${ps5.id}) & game_type = (${typeIds.join(',')}) & version_parent = null; sort id asc; limit 500; offset ${offset};`,
  )
  for (const g of page) {
    const company = (role: string) => (g.involved_companies ?? []).find((c: any) => c[role])?.company?.name
    games.push({ i: g.id, n: g.name, ...datesOf(g.id, g.release_dates), v: company('developer'), p: company('publisher'), c: g.cover?.image_id, t: tones.get(g.id), r: g.total_rating_count ?? 0 })
  }
  if (page.length < 500) break
}
games.sort((a, b) => (rankOf.get(a.i) ?? Infinity) - (rankOf.get(b.i) ?? Infinity) || b.r - a.r)

const problems = problemsOf(games)
if (problems.length) {
  console.error(problems.join('\n') + '\nNothing written.')
  process.exit(1)
}

const index = {
  fetchedAt: new Date().toISOString(),
  count: games.length,
  games: games.map(({ r: _r, ...g }) => Object.fromEntries(Object.entries(g).filter(([, v]) => v !== undefined))),
}
writeFileSync(OUT, JSON.stringify(index) + '\n')
console.log(`wrote ${OUT.pathname}: ${games.length} games, ${games.filter((g) => !g.d).length} without a PS5 date, ${games.filter((g) => g.e).length} in early access`)
