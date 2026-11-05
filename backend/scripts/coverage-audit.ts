// Coverage audit of the published feed: games with no history, releases with no links, Steam-assumed PS5 rows dated
// before the game's PS5 launch, and a PS5 version that equals the PC one. Read-only; needs only the public feed.
//
//   npm run coverage-audit [-- https://raw.githubusercontent.com/tezbo/playscribe/feed/v1]
const base = (process.argv[2] ?? 'https://raw.githubusercontent.com/tezbo/playscribe/feed/v1').replace(/\/$/, '')
const get = async (path: string) => (await fetch(`${base}/${path}`)).json() as Promise<any>
const index = (await get('index.json')).games as any[]
const problems: string[] = []
let releases = 0
for (const g of index) {
  const { releases: rs } = await get(`games/${g.id}.json`)
  releases += rs.length
  if (!rs.length) problems.push(`${g.id}: no releases`)
  const noLinks = rs.filter((r: any) => !r.links?.steamNotes && !r.links?.ps5Page).length
  if (noLinks) problems.push(`${g.id}: ${noLinks} of ${rs.length} releases have no links`)
  for (const r of rs) {
    const ps5 = r.platforms.find((p: any) => p.platform === 'ps5')
    const pc = r.platforms.find((p: any) => p.platform === 'pc')
    if (ps5?.status === 'live' && ps5.verification === 'assumed' && g.ps5Release && r.announcedAt.slice(0, 10) < g.ps5Release) problems.push(`${r.id}: assumed live on PS5 before the PS5 launch (${g.ps5Release})`)
    if (ps5?.version && pc?.version && ps5.version.value === pc.version.value) problems.push(`${r.id}: PS5 version equals the PC version`)
  }
}
console.log(`${index.length} games, ${releases} releases, ${problems.length} problems`)
for (const p of problems) console.log(` - ${p}`)
process.exitCode = problems.some((p) => /PS5 version equals|before the PS5 launch/.test(p)) ? 1 : 0
