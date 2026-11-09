// Dry run (and writer) for auto-onboarding: node scripts/auto-registry.ts --info <dir of v1/info shards> [--write <file>] [--sample 20]
// Prints what would be added; writes only with --write. Hand registry entries always win.
import { readdirSync, readFileSync, writeFileSync } from 'node:fs'
import { buildAutoRegistry, type IndexGame, type InfoEntry } from '../src/ingest/autoRegistry.ts'
import { registry, steamAppIdOf } from '../src/registry.ts'

const args = process.argv.slice(2)
const arg = (k: string) => (args.includes(k) ? args[args.indexOf(k) + 1] : undefined)
const infoDir = arg('--info')
if (!infoDir) throw new Error('--info <directory of info shards> is required')
const index = (JSON.parse(readFileSync(new URL('../../ios/Playscribe/Resources/Data/ps5-index.json', import.meta.url), 'utf8')) as { games: IndexGame[] }).games
const info = new Map<number, InfoEntry>()
for (const f of readdirSync(infoDir).filter((f) => f.endsWith('.json'))) {
  for (const [id, e] of Object.entries(JSON.parse(readFileSync(`${infoDir}/${f}`, 'utf8')).games as Record<string, InfoEntry>)) info.set(Number(id), e)
}
const hand = Object.values(registry.games)
const handIgdb = new Set(hand.map((g) => g.igdbId).filter((x): x is number => !!x))
const handApps = new Set(hand.flatMap((g) => g.sources.map(steamAppIdOf)).filter((x): x is number => !!x))
const { games, skipped } = buildAutoRegistry(index, info, handIgdb, handApps, new Date().toISOString().slice(0, 10))
const ports = games.filter((g) => g.steamIsPcPort).length
console.log(JSON.stringify({ index: index.length, infoShardGames: info.size, wouldAdd: games.length, ofWhichSonyPorts: ports, skipped }, null, 2))
// Deterministic spot check: every Nth game, so a re-run shows the same 20.
const n = Number(arg('--sample') ?? 20)
const step = Math.max(1, Math.floor(games.length / n))
for (const g of games.filter((_, i) => i % step === 0).slice(0, n)) console.log(`${g.id}\t${g.name}\tapp ${g.steamAppId}${g.steamIsPcPort ? '\tPC-PORT' : ''}\thttps://store.steampowered.com/app/${g.steamAppId}`)
const out = arg('--write')
if (out) { writeFileSync(out, JSON.stringify({ version: 1, games: Object.fromEntries(games.map(({ id, steamAppId: _a, ...g }) => [id, g])) })); console.log('wrote', out, games.length) }
