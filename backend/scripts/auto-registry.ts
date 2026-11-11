// Auto-onboarding dry run: npx tsx scripts/auto-registry.ts --info <dir of v1/info shards> [--write <file>] [--sample 20]
// Prints what the poll would follow (the Feed job runs it every full poll, so the log always shows the current count) and a
// deterministic 20-game spot check; writes the list only with --write. Hand registry entries always win.
import { readdirSync, readFileSync, writeFileSync } from 'node:fs'
import { deriveAutoRegistry, INDEX_URL, type IndexGame } from '../src/ingest/autoRegistry.ts'

const args = process.argv.slice(2)
const arg = (k: string) => (args.includes(k) ? args[args.indexOf(k) + 1] : undefined)
const infoDir = arg('--info')
if (!infoDir) throw new Error('--info <directory of info shards> is required')
const { games, skipped } = deriveAutoRegistry(infoDir)
const index = (JSON.parse(readFileSync(INDEX_URL, 'utf8')) as { games: IndexGame[] }).games
const info = { size: readdirSync(infoDir).filter((f) => f.endsWith('.json')).reduce((n, f) => n + Object.keys(JSON.parse(readFileSync(`${infoDir}/${f}`, 'utf8')).games).length, 0) }
const ports = games.filter((g) => g.steamIsPcPort).length
console.log(JSON.stringify({ index: index.length, infoShardGames: info.size, wouldAdd: games.length, ofWhichSonyPorts: ports, skipped }, null, 2))
// Deterministic spot check: every Nth game, so a re-run shows the same 20.
const n = Number(arg('--sample') ?? 20)
const step = Math.max(1, Math.floor(games.length / n))
for (const g of games.filter((_, i) => i % step === 0).slice(0, n)) console.log(`${g.id}\t${g.name}\tapp ${g.steamAppId}${g.steamIsPcPort ? '\tPC-PORT' : ''}\thttps://store.steampowered.com/app/${g.steamAppId}`)
const out = arg('--write')
if (out) { writeFileSync(out, JSON.stringify({ version: 1, games: Object.fromEntries(games.map(({ id, steamAppId: _a, ...g }) => [id, g])) })); console.log('wrote', out, games.length) }
