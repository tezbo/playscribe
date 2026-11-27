import assert from 'node:assert/strict'
import { test } from 'node:test'
import { openDb } from '../src/db.ts'
import { readFileSync } from 'node:fs'
import { bandaiUpdateLinks, parseBandaiArticle, parseStatuspage, blueskyTitle, parseMojangNotes, parseRiotNews } from '../src/ingest/adapters.ts'
import { pcNumberIsTitled, runIngest, seedGames } from '../src/ingest/pipeline.ts'
import { registry } from '../src/registry.ts'
import * as store from '../src/store.ts'
import { queueNewPs5 } from '../src/push/notify.ts'
import { fakeFetch, rss, steamNews } from './helpers.ts'

// feed-sony-first-party-patch-source: official PS5 sources for games that had none. Each fixture is trimmed from the live source.
const ps5Of = (db: ReturnType<typeof openDb>, id: string) => store.getRelease(db, id)?.platforms.find((p) => p.platform === 'ps5')
const ingest = async (routes: Record<string, string>) => {
  const db = openDb(':memory:')
  const deps = { db, fetchFn: fakeFetch(routes), igdb: null }
  await seedGames(deps)
  const summary = await runIngest(deps, { force: true })
  return { db, summary }
}
const releasesOf = (db: ReturnType<typeof openDb>, game: string) => (db.prepare('SELECT id FROM releases WHERE game_id = ? ORDER BY id').all(game) as { id: string }[]).map((r) => r.id)
const bsky = (posts: { text: string; at: string; repost?: boolean; handle?: string }[], handle: string) =>
  JSON.stringify({
    feed: posts.map((p, i) => ({
      post: { uri: `at://did:plc:x/app.bsky.feed.post/${handle.slice(0, 3)}${i}`, author: { handle: p.handle ?? handle }, record: { text: p.text, createdAt: p.at } },
      ...(p.repost ? { reason: { $type: 'app.bsky.feed.defs#reasonRepost' } } : {}),
    })),
  })

test('Alan Wake 2: Remedy\'s feed gives the update, its own PS5 build, and its date; the PC number is not the name; other posts are not releases', async () => {
  const { db } = await ingest({
    'https://www.alanwake.com/feed/': rss([
      {
        title: 'Alan Wake 2 update 1.2.11 notes',
        link: 'https://www.alanwake.com/news/alan-wake-2-update-1-2-11-notes/',
        date: '2026-10-21T12:00:32Z',
        body: 'These are the latest update notes for Alan Wake 2 21st October 2026 PlayStation 5 (1.200.011) Xbox Series (1.2.0.11) PC (1.2.11) Improvements and additions [PC] Updated FSR support to FSR 4.1 Fixes Fixed HDR toggle to show as intended with compatible displays.',
      },
      { title: 'Alan Wake Remastered PC update notes (1.33)', link: 'https://www.alanwake.com/news/remastered/', date: '2026-02-26T10:45:39Z', body: 'PC only' },
      { title: 'The Anniversary Update explained', link: 'https://www.alanwake.com/news/anniversary/', date: '2024-10-21T13:00:30Z', body: 'Alan Wake 2 gets an update.' },
      { title: 'Gameplay Assist: Making Alan Wake 2 More Approachable', link: 'https://www.alanwake.com/news/assist/', date: '2025-02-06T13:55:45Z', body: 'Alan Wake 2 is easier to pick up.' },
    ]),
  })
  assert.deepEqual(releasesOf(db, 'alan-wake-2'), ['alan-wake-2@1.2.11'])
  const r = store.getRelease(db, 'alan-wake-2@1.2.11')!
  assert.equal(r.displayName, 'Update', 'the PC number 1.2.11 is not shown as the update name')
  const ps5 = ps5Of(db, 'alan-wake-2@1.2.11')!
  assert.deepEqual([ps5.status, ps5.verification, ps5.version?.value, ps5.liveAt?.value.slice(0, 10)], ['live', 'official', '01.200.011', '2026-10-21'])
  assert.ok(!releasesOf(db, 'alan-wake-2').some((id) => /1\.33|assist|2024/i.test(id)), 'feature posts (The Anniversary Update explained) are not releases')
})

test('Ghost of Yotei and Wolverine: the studios\' own Bluesky posts make PS5 releases; reposts, promo and other games\' posts do not', async () => {
  const { db } = await ingest({
    'https://public.api.bsky.app/xrpc/app.bsky.feed.getAuthorFeed?actor=suckerpunchprod.bsky.social': bsky(
      [
        { text: 'Patch 2.09 for Ghost of Yōtei is now live. This patch adds the option to not skip the prologue when starting New Game+, and fixes an issue that caused a crash.', at: '2026-10-30T17:00:00.000Z' },
        { text: 'Ghost of Yōtei Complete Edition is coming on October 1! Learn about our new story expansion.', at: '2026-08-12T16:00:00.000Z' },
        { text: 'Patch 9.9 for Ghost of Tsushima is now live.', at: '2026-10-31T17:00:00.000Z', repost: true },
      ],
      'suckerpunchprod.bsky.social',
    ),
    'https://public.api.bsky.app/xrpc/app.bsky.feed.getAuthorFeed?actor=insomniac.games': bsky(
      [
        { text: 'Marvel’s Spider-Man 2 now uses QSSR via our latest update, delivering improvements to image sharpness.', at: '2026-11-13T17:00:00.000Z' },
        { text: '🚨 Our latest update for Marvel’s #WolverinePS5 is live and adds a new ‘Hint’ toggle for story-related Scent trails based on community feedback!', at: '2026-10-06T17:00:00.000Z' },
      ],
      'insomniac.games',
    ),
  })
  assert.deepEqual(releasesOf(db, 'yotei'), ['yotei@2.09'])
  const y = ps5Of(db, 'yotei@2.09')!
  assert.deepEqual([y.status, y.verification, y.liveAt?.value.slice(0, 10)], ['live', 'official', '2026-10-30'])
  assert.equal(store.getRelease(db, 'yotei@2.09')!.displayName, 'Patch 2.09')
  const w = releasesOf(db, 'wolverine')
  assert.equal(w.length, 1, 'only the Wolverine post, not the Spider-Man 2 one')
  const wp = ps5Of(db, w[0]!)!
  assert.deepEqual([wp.status, wp.verification, wp.liveAt?.value.slice(0, 10)], ['live', 'official', '2026-10-06'])
})

test('Fortnite: Epic\'s status page makes a release when the downtime is Completed, dated then; scheduled downtime and other incidents are not releases', async () => {
  const item = (title: string, desc: string, pub: string, id: string) => `<item><title>${title}</title><description>${desc}</description><pubDate>${pub}</pubDate><link>https://status.epicgames.com/incidents/${id}</link><guid>https://status.epicgames.com/incidents/${id}</guid></item>`
  const done = (t: string, d: string) => `&lt;p&gt; &lt;small&gt;Nov &lt;var data-var='date'&gt;${d}&lt;/var&gt;, &lt;var data-var='time'&gt;${t}&lt;/var&gt; UTC&lt;/small&gt;&lt;br&gt; &lt;strong&gt;Completed&lt;/strong&gt; - The scheduled maintenance has been completed. &lt;/p&gt;`
  const feed = `<?xml version="1.0"?><rss><channel>${[
    item('Fortnite: Downtime for v43.10 Update', `&lt;p&gt; &lt;small&gt;Nov &lt;var data-var=&apos;date&apos;&gt;12&lt;/var&gt;, &lt;var data-var=&apos;time&apos;&gt;10:49&lt;/var&gt; UTC&lt;/small&gt;&lt;br&gt; &lt;strong&gt;Completed&lt;/strong&gt; - The scheduled maintenance has been completed. &lt;/p&gt; &lt;p&gt; &lt;small&gt;Nov &lt;var data-var=&apos;date&apos;&gt;12&lt;/var&gt;, &lt;var data-var=&apos;time&apos;&gt;09:00&lt;/var&gt; UTC&lt;/small&gt;&lt;br&gt; &lt;strong&gt;In progress&lt;/strong&gt; - Scheduled maintenance is currently in progress. We will provide updates as necessary. &lt;/p&gt; &lt;p&gt; &lt;small&gt;Nov &lt;var data-var=&apos;date&apos;&gt;11&lt;/var&gt;, &lt;var data-var=&apos;time&apos;&gt;22:49&lt;/var&gt; UTC&lt;/small&gt;&lt;br&gt; &lt;strong&gt;Scheduled&lt;/strong&gt; - ⏰ Scheduled downtime for v43.10 begins at 4 AM ET (9 AM UTC). &lt;br /&gt;&lt;br /&gt;Matchmaking will be disabled 30 minutes prior. &lt;/p&gt;`, 'Thu, 12 Nov 2026 10:49:20 +0000', 'a1'),
    item('Fortnite: Downtime for v43.20 Update', '&lt;p&gt;&lt;strong&gt;Scheduled&lt;/strong&gt; - Scheduled downtime for v43.20 begins at 9 AM UTC.&lt;/p&gt;', 'Tue, 24 Nov 2026 22:49:20 +0000', 'a2'),
    item('EOS Maintenance', done('08:00', '10'), 'Tue, 10 Nov 2026 07:30:12 +0000', 'a3'),
    item('Fortnite Login and Matchmaking Issues', '&lt;p&gt;&lt;strong&gt;Resolved&lt;/strong&gt; - restored.&lt;/p&gt;', 'Wed, 18 Nov 2026 19:19:10 +0000', 'a4'),
  ].join('')}</channel></rss>`
  assert.deepEqual(parseStatuspage('x', feed).map((p) => p.title), ['Update v43.10', 'EOS Maintenance'], 'only completed items')
  const { db } = await ingest({ 'https://status.epicgames.com/history.rss': feed })
  assert.deepEqual(releasesOf(db, 'fortnite'), ['fortnite@43.10'])
  const f = ps5Of(db, 'fortnite@43.10')!
  assert.deepEqual([f.status, f.verification, f.liveAt?.value.slice(0, 10)], ['live', 'official', '2026-11-12'])
  assert.equal(f.liveAt?.value, '2026-11-12T10:49:20.000Z', 'dated at the Completed time (the real v43.10 item), not the 09:00 start or the 22:49 scheduling')
})

test('the PC number in a studio title is dropped only when the post lists it as PC; no other official RSS name changes', async () => {
  assert.ok(pcNumberIsTitled('Update 1.2.11', 'PlayStation 5 (1.200.011) Xbox Series (1.2.0.11) PC (1.2.11)'))
  assert.ok(!pcNumberIsTitled('Update 1.200.011', 'PlayStation 5 (1.200.011) PC (1.2.11)'), 'a title carrying the PS5 build keeps it')
  assert.ok(!pcNumberIsTitled('Patch 2.09', 'PS5 (1.200.011) is live. PC (1.2.11)'))
  assert.ok(!pcNumberIsTitled('Update', 'PS5 (1.200.011) PC (1.2.11)'), 'no number in the name, nothing to drop')
})

test('a PS5-only official post promising a patch ("will be live soon") does not make the PS5 row official', async () => {
  const { db } = await ingest({
    'https://public.api.bsky.app/xrpc/app.bsky.feed.getAuthorFeed?actor=suckerpunchprod.bsky.social': bsky([{ text: 'Patch 2.10 for Ghost of Yōtei will be live soon. Details to follow.', at: '2026-11-01T17:00:00.000Z' }], 'suckerpunchprod.bsky.social'),
  })
  const ids = releasesOf(db, 'yotei')
  assert.ok(ids.length > 0, 'the post is a release, so the check below ran')
  for (const id of ids) assert.notEqual(ps5Of(db, id)!.verification, 'official', id)
})

test('blueskyTitle names the patch the studio names, else the first sentence', () => {
  assert.equal(blueskyTitle('Patch 2.09 for Ghost of Yōtei is now live. More below.'), 'Patch 2.09')
  assert.equal(blueskyTitle('Hotfix 1.4.2 is out now on PS5'), 'Hotfix 1.4.2')
  assert.equal(blueskyTitle('We just deployed a new update for Marvel\u2019s Wolverine. It fixes things.'), 'Update')
  assert.equal(blueskyTitle('Today, we deployed a hotfix for Marvel\u2019s Wolverine that includes new toggles.'), 'Hotfix')
  assert.equal(blueskyTitle('Ghost of Y\u014dtei Complete Edition is coming on October 1!'), 'Ghost of Y\u014dtei Complete Edition is coming on October 1!')
})

// Terry, 22 Nov: "Not having a source for patches is NOT acceptable. Ever." Every registry game has a source, or a written, dated gap
// with a next step. A game with neither fails here, so a new game cannot be added without one.
test('every registry game has a patch source or a written source gap', () => {
  const bare = Object.entries(registry.games).filter(([, g]) => g.sources.length === 0 && !g.sourceGap).map(([id]) => id)
  assert.deepEqual(bare, [], `registry games with no source and no sourceGap: ${bare.join(', ')}`)
  for (const [id, g] of Object.entries(registry.games)) {
    if (g.sources.length && g.sourceGap) assert.fail(`${id} has sources, so its sourceGap is stale`)
    if (g.sourceGap) for (const k of ['reason', 'next', 'since'] as const) assert.ok(g.sourceGap[k]?.length > 3, `${id}.sourceGap.${k}`)
  }
})

test('the games Terry flagged on 22 Nov: four have an official source, the rest are written gaps; no unofficial account is a source', () => {
  for (const id of ['alan-wake-2', 'yotei', 'wolverine', 'fortnite']) assert.ok(registry.games[id]!.sources.some((s) => s.trust === 'official' && s.fetch === 'auto'), id)
  for (const id of ['gt7', 'astro-bot', 'genshin-impact']) assert.ok(registry.games[id]!.sourceGap, id)
  for (const g of Object.values(registry.games))
    for (const s of g.sources) assert.ok(!/fortnite-(game|status)\.bsky\.social/.test(s.url), `${s.id}: those accounts say they are unaffiliated with Epic`)
})

test('Minecraft: Mojang\'s Bedrock patch-notes file makes one dated update per entry, named by its version', () => {
  const posts = parseMojangNotes('m', [
    { title: 'Minecraft: Bedrock Edition 26.60 Changelog', version: '26.60', date: '2026-10-27', shortText: 'Brrrr!' },
    { title: '26.40 Chaos', version: '26.40', date: '2026-08-04T15:46:00.367Z' },
    { title: 'Broken', date: 'soon' },
  ], { '26.60': '<p>Added drops</p><p>Fixed a crash</p>' })
  assert.deepEqual(posts.map((p) => [p.title, p.publishedAt]), [['Update 26.60', '2026-10-27T00:00:00.000Z'], ['Update 26.40', '2026-08-04T15:46:00.367Z']])
  assert.equal(posts[0]!.body, 'Added drops Fixed a crash')
})

test('Valorant: the game-updates page lists patch notes with Riot\'s own publish time; other categories are skipped', () => {
  const item = (title: string, cat: string, url: string) => ({ title, action: { type: 'weblink', payload: { url } }, category: { machineName: cat }, description: { type: 'html', body: 'Replays bookmarks' }, publishedAt: '2026-11-10T14:00:00.000Z', analytics: { contentId: url } })
  const html = `<html><script id="__NEXT_DATA__" type="application/json">${JSON.stringify({ props: { pageProps: { page: { blades: [{ items: [item('VALORANT Patch Notes 13.10', 'game_updates', '/en-us/news/game-updates/valorant-patch-notes-13-10'), item('Esports news', 'esports', '/en-us/news/esports/x')] }] } } } })}</script></html>`
  const posts = parseRiotNews('v', 'https://playvalorant.com', html)
  assert.deepEqual(posts.map((p) => [p.title, p.url, p.publishedAt]), [['VALORANT Patch Notes 13.10', 'https://playvalorant.com/en-us/news/game-updates/valorant-patch-notes-13-10', '2026-11-10T14:00:00.000Z']])
  assert.deepEqual(parseRiotNews('v', 'https://playvalorant.com', '<html></html>'), [])
})

// Quinn, #601: a Steam patch is taken as out on PS5 unless the game is marked steamIsPcPort, so the older Ubisoft games (no PS5 build
// of their own, PC installer and launcher updates) are marked, and the live-service ones only make releases from patch-note titles.
test('Steam posts of the old Ubisoft games make PC rows and no PS5 row; live-service games make PS5 rows from patch posts only', async () => {
  const at = (n: number) => new Date(Date.now() - n * 3600e3).toISOString()
  const steam = (app: string, items: Parameters<typeof steamNews>[0]) => [`https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=${app}&`, steamNews(items)] as const
  const { db } = await ingest(
    Object.fromEntries([
      steam('812140', [{ gid: 'o1', title: 'Installer update', date: at(30), contents: 'The Ubisoft Connect installer was updated for PC.', tags: ['patchnotes'] }, { gid: 'o2', title: "Assassin's Creed Odyssey - 1.3.0 Patch Notes", date: at(20), contents: 'Fixed a crash.', tags: ['patchnotes'] }]),
      steam('252950', [{ gid: 'r1', title: 'Rocket League S24 Patch Notes v2.76', date: at(30), contents: 'Fixed a crash.', tags: ['patchnotes'] }, { gid: 'r2', title: 'Rocket League Heads to the Streets in Season 24', date: at(20), contents: 'A new season trailer.' }]),
    ]),
  )
  const odyssey = releasesOf(db, 'assassins-creed-odyssey')
  assert.ok(odyssey.length > 0, 'its patch notes are still releases (PC rows)')
  for (const id of odyssey) assert.equal(ps5Of(db, id), undefined, `${id}: a PC-only post must not create a PS5 row`)
  const rl = releasesOf(db, 'rocket-league')
  assert.deepEqual(rl, ['rocket-league@2.76'], 'only the patch-notes post is a release')
  assert.equal(ps5Of(db, rl[0]!)!.verification, 'assumed', 'never official from a Steam post')
})

test('every registry game on a Steam source with no PS5 release is either a PC port or patch-only (nothing assumes PS5 for a game we cannot place on PS5)', () => {
  const noPs5 = ['assassins-creed-odyssey', 'assassins-creed-origins', 'assassins-creed-unity', 'assassins-creed-syndicate', 'far-cry-5', 'far-cry-4', 'far-cry-primal', 'far-cry-new-dawn', 'the-division', 'ghost-recon-wildlands', 'ghost-recon-breakpoint']
  for (const g of noPs5) assert.equal(registry.games[g]!.steamIsPcPort, true, g)
  for (const g of ['rocket-league', 'the-division-2', 'for-honor', 'the-crew-2']) assert.ok(registry.games[g]!.sources.every((s) => s.patchOnly && s.titleMatch), g)
})

// bug-059 backfill: scoped to one game (Quinn's condition), nothing else is polled, and no shared press feed is read.
test('a backfill with games set reads only those games', async () => {
  const at = new Date(Date.now() - 20 * 3600e3).toISOString()
  const db = openDb(':memory:')
  const deps = {
    db,
    fetchFn: fakeFetch({
      'https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=252950&': steamNews([{ gid: 'r1', title: 'Rocket League S24 Patch Notes v2.76', date: at, contents: 'Fixed a crash.', tags: ['patchnotes'] }]),
      'https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=2221490&': steamNews([{ gid: 'd1', title: 'Title Update Y7S3.3', date: at, contents: 'Fixed a crash.', tags: ['patchnotes'] }]),
    }),
    igdb: null,
  }
  await seedGames(deps)
  const summary = await runIngest(deps, { force: true, until: '2020-01-01T00:00:00.000Z', games: ['rocket-league'] })
  assert.deepEqual(releasesOf(db, 'rocket-league'), ['rocket-league@2.76'])
  assert.deepEqual(releasesOf(db, 'the-division-2'), [], 'a game outside the list is not polled')
  assert.deepEqual(summary.polled.filter((id) => !id.startsWith('rocket-league')), [], 'only the named game\'s sources were read')
})

// The derived registry took Blade Assault's playtest app (1426470) and an unlisted app (4184360) from IGDB; Steam refuses both (403/404), so
// those two games had no readable source. The hand entries below point at the real store apps and win over the derived rows.
test('Blade Assault and Peace Walker Master Collection read their real Steam apps, not the refused ones', () => {
  const blade = registry.games['blade-assault-207392']!.sources[0]!
  const walker = registry.games['metal-gear-solid-peace-walker-master-collection-version-391792']!.sources[0]!
  assert.match(blade.url, /\/app\/1367300\//)
  assert.match(walker.url, /\/app\/2492660\//)
})

test('a repair-only backfill creates no release from a post it has not made one for', async () => {
  const at = new Date(Date.now() - 20 * 3600e3).toISOString()
  const db = openDb(':memory:')
  const deps = { db, fetchFn: fakeFetch({ 'https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=252950&': steamNews([{ gid: 'r1', title: 'Rocket League S24 Patch Notes v2.76', date: at, contents: 'Fixed a crash.', tags: ['patchnotes'] }]) }), igdb: null }
  await seedGames(deps)
  await runIngest(deps, { force: true, until: '2020-01-01T00:00:00.000Z', games: ['rocket-league'], noNewReleases: true })
  assert.deepEqual(releasesOf(db, 'rocket-league'), [])
  await runIngest(deps, { force: true, until: '2020-01-01T00:00:00.000Z', games: ['rocket-league'] })
  assert.deepEqual(releasesOf(db, 'rocket-league'), ['rocket-league@2.76'], 'without the flag the same post makes its release')
})

test('a known console build fills an empty PS5 version as reported, and a post number is never overwritten', async () => {
  const db = openDb(':memory:')
  await seedGames({ db, fetchFn: fakeFetch({}), igdb: null })
  for (const key of ['1.1', '1.2']) {
    const { id } = store.upsertRelease(db, { gameId: 'dawnwalker', versionKey: key, displayName: `Update ${key}`, kind: 'major', kindBasis: 'inferred', announcedAt: '2026-11-13T16:30:00.000Z', notes: [], sourceId: 'x' })
    store.upsertPlatform(db, id, 'ps5', { status: 'live', verification: 'reported', version: key === '1.1' ? store.field('01.006.001', 'official', 'studio') : null })
  }
  assert.equal(store.applyKnownBuilds(db, { dawnwalker: { '1.1': '01.006.000', '1.2': '01.007.000' } }), 1)
  assert.equal(ps5Of(db, 'dawnwalker@1.2')?.version?.value, '01.007.000')
  assert.equal(ps5Of(db, 'dawnwalker@1.2')?.version?.verification, 'reported')
  assert.equal(ps5Of(db, 'dawnwalker@1.1')?.version?.value, '01.006.001', 'a number from a post stays')
  assert.equal(store.applyKnownBuilds(db, { dawnwalker: { '1.2': '01.007.000' } }), 0)
})

const bandaiFx = (n: string) => readFileSync(new URL(`./fixtures/${n}`, import.meta.url), 'utf8')
const bandaiRoutes = (art12: string, art11: string) => ({
  'https://www.bandainamcoent.com/games/dawnwalker': bandaiFx('bandai-dawnwalker-game.html'),
  'https://www.bandainamcoent.com/news/the-blood-of-dawnwalker-update-1-2': art12,
  'https://www.bandainamcoent.com/news/the-blood-of-dawnwalker-update-1-1': art11,
})
const art11 = () => bandaiFx('bandai-dawnwalker-update-1-2.html').replace(/Update 1\.2/g, 'Update 1.1').replace('2026-11-17', '2026-10-22')

test('Bandai Namco game page: the update article is dated by its own publish time and counts as official on PS5', async () => {
  const game = bandaiFx('bandai-dawnwalker-game.html')
  assert.deepEqual(bandaiUpdateLinks(game, 'https://www.bandainamcoent.com/games/dawnwalker').map((u) => u.split('/').pop()), ['the-blood-of-dawnwalker-update-1-1', 'the-blood-of-dawnwalker-update-1-2'])
  const post = parseBandaiArticle('dawnwalker-bandai-news', 'https://www.bandainamcoent.com/news/the-blood-of-dawnwalker-update-1-2', bandaiFx('bandai-dawnwalker-update-1-2.html'))!
  assert.equal(post.title, 'The Blood of Dawnwalker - Update 1.2')
  assert.equal(post.publishedAt, '2026-11-17T08:00:00.000Z')
  assert.match(post.body, /out now on PC, PlayStation 5/)
})

test('Bandai post for 1.2 replaces the reported 13 Nov date with the official 17 Nov one; newest stays 1.2 and nothing is pushed again', async () => {
  const db = openDb(':memory:')
  const deps = { db, fetchFn: fakeFetch(bandaiRoutes(bandaiFx('bandai-dawnwalker-update-1-2.html'), art11())), igdb: null }
  await seedGames(deps)
  // What the feed held before: a press report dated 13 Nov (a "coming next week" article, not the release), already alerted.
  const { id } = store.upsertRelease(db, { gameId: 'dawnwalker', versionKey: '1.2', displayName: 'Update 1.2', kind: 'major', kindBasis: 'inferred', announcedAt: '2026-11-13T16:30:00.000Z', notes: [], sourceId: 'pushsquare' })
  store.upsertPlatform(db, id, 'ps5', { status: 'live', verification: 'reported', liveAt: store.field('2026-11-13T16:30:00.000Z', 'reported', 'pushsquare') })
  db.prepare("UPDATE platform_releases SET pushed_at = '2026-11-17T10:24:19.374Z' WHERE release_id = ?").run(id)
  await runIngest(deps, { force: true, games: ['dawnwalker'] })
  const ps5 = ps5Of(db, 'dawnwalker@1.2')!
  assert.deepEqual([ps5.status, ps5.verification, ps5.liveAt?.verification, ps5.liveAt?.value], ['live', 'official', 'official', '2026-11-17T08:00:00.000Z'])
  const rel = db.prepare("SELECT version_key, announced_at FROM releases WHERE game_id = 'dawnwalker' ORDER BY announced_at DESC").all() as { version_key: string; announced_at: string }[]
  assert.equal(rel[0]!.version_key, '1.2', 'newest update is still 1.2')
  assert.equal(rel[0]!.announced_at, '2026-11-17T08:00:00.000Z')
  assert.equal(queueNewPs5(db, { maxAgeHours: 72 }).jobs.length, 0, 'already pushed, and the 1.1 post is a month old: nothing is sent')
})

test('a Bandai post that says PC only makes no PS5 row, and a PC-only hotfix carries no PS5 signal', async () => {
  const pcOnly = (title: string) => bandaiFx('bandai-dawnwalker-update-1-2.html').replace(/Update 1\.2/g, title).replace(/out now on PC, PlayStation 5, and Xbox Series X\|S/, 'out now on PC only')
  const db = openDb(':memory:')
  const deps = { db, fetchFn: fakeFetch(bandaiRoutes(pcOnly('Update 1.2'), pcOnly('Hotfix 1.1.1 (PC only)'))), igdb: null }
  await seedGames(deps)
  await runIngest(deps, { force: true, games: ['dawnwalker'] })
  assert.equal(ps5Of(db, 'dawnwalker@1.2'), undefined, 'PC-only 1.2 has no PS5 row')
  assert.equal(ps5Of(db, 'dawnwalker@1.1.1'), undefined, 'a PC-only hotfix has no PS5 row')
})

test('moving a release date to the official PS5 time sends no alert for an old update that was never pushed, and a lagging console is not a wrong date', async () => {
  const db = openDb(':memory:')
  await seedGames({ db, fetchFn: fakeFetch({}), igdb: null })
  const make = (key: string, announced: string, ps5Live: string, pushed: boolean) => {
    const { id } = store.upsertRelease(db, { gameId: 'dawnwalker', versionKey: key, displayName: `Update ${key}`, kind: 'major', kindBasis: 'inferred', announcedAt: announced, notes: [], sourceId: 'pushsquare' })
    store.upsertPlatform(db, id, 'ps5', { status: 'live', verification: 'official', liveAt: store.field(ps5Live, 'official', 'dawnwalker-bandai-news') })
    if (pushed) db.prepare("UPDATE platform_releases SET pushed_at = '2026-01-01T00:00:00.000Z' WHERE release_id = ?").run(id)
    return id
  }
  const old = make('0.9', '2026-08-01T10:00:00.000Z', '2026-09-05T08:00:00.000Z', false)
  const lag = make('0.8', '2026-01-31T10:00:00.000Z', '2026-08-12T08:00:00.000Z', true)
  const before = queueNewPs5(db, { maxAgeHours: 72 }).jobs.length
  store.preferOfficialDate(db, old)
  store.preferOfficialDate(db, lag)
  const date = (id: string) => (db.prepare('SELECT announced_at a FROM releases WHERE id = ?').get(id) as { a: string }).a
  assert.equal(date(old), '2026-08-01T10:00:00.000Z', 'a five-week gap is a lagging console, not a press error: unchanged')
  assert.equal(date(lag), '2026-01-31T10:00:00.000Z')
  const near = make('0.7', '2026-09-01T10:00:00.000Z', '2026-09-05T08:00:00.000Z', false)
  store.preferOfficialDate(db, near)
  assert.equal(date(near), '2026-09-05T08:00:00.000Z', 'four days later, backed by no official time: moved')
  assert.equal(queueNewPs5(db, { maxAgeHours: 72 }).jobs.length, before, 'the move changes no alert: the 72 h and 30-day guards read the PS5 live time')
  assert.equal(before, 0)
})

// s-07-source-on-add-backend: one IGDB game through the Feed.
test('a one-game check finds the game on IGDB, reads its Steam news, and records what it found', async () => {
  const { checkOneGame } = await import('../src/ingest/checkOne.ts')
  const at = new Date(Date.now() - 20 * 3600e3).toISOString()
  const db = openDb(':memory:')
  const igdb = { async byId(id: number) { return id === 555 ? { igdbId: 555, name: 'Brand New Game', coverImageId: 'cc1', artworkImageId: '', ps5Release: '2026-01-01', ps5ReleasePrecision: null, steamAppId: 4242 } : id === 556 ? { igdbId: 556, name: 'No Steam Game', steamAppId: null } : null } } as never
  const deps = { db, igdb, fetchFn: fakeFetch({ 'https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=4242&': steamNews([{ gid: 'p1', title: 'Patch 1.2 notes', date: at, contents: 'Fixed a crash.', tags: ['patchnotes'] }]) }) }
  await seedGames({ ...deps, igdb: null })
  const r = await checkOneGame(deps, 555)
  assert.deepEqual([r.status, r.releases], ['polled', 1])
  assert.equal((db.prepare('SELECT status FROM source_checks WHERE igdb_id = 555').get() as { status: string }).status, 'polled')
  assert.equal((await checkOneGame(deps, 556)).status, 'no-source')
  assert.equal((await checkOneGame(deps, 557)).status, 'unknown')
  assert.deepEqual(store.sourceChecks(db).map((c) => [c.igdbId, c.status]).sort(), [[555, 'polled'], [556, 'no-source'], [557, 'unknown']])
  // A later derivation that does not list the game must not retire it.
  assert.equal(store.retireAutoGames(db, new Set()), 0)
})

test('a one-game export rewrites only that game, its index entry, latest and the check record; the rest of the feed is untouched', async () => {
  const { exportStatic, exportOneGame } = await import('../src/export.ts')
  const { mkdtempSync, readFileSync, writeFileSync } = await import('node:fs')
  const { tmpdir } = await import('node:os')
  const { join } = await import('node:path')
  const at = new Date(Date.now() - 20 * 3600e3).toISOString()
  const db = openDb(':memory:')
  const deps = { db, igdb: null, fetchFn: fakeFetch({ 'https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=252950&': steamNews([{ gid: 'r1', title: 'Rocket League S24 Patch Notes v2.76', date: at, contents: 'Fixed a crash.', tags: ['patchnotes'] }]) }) }
  await seedGames(deps)
  await runIngest(deps, { force: true, games: ['rocket-league'] })
  const dir = mkdtempSync(join(tmpdir(), 'one-'))
  exportStatic(db, dir)
  const other = join(dir, 'v1/games/dawnwalker.json')
  writeFileSync(other, 'SENTINEL') // a full export would rewrite this
  const before = JSON.parse(readFileSync(join(dir, 'v1/index.json'), 'utf8')).games.length
  store.recordSourceCheck(db, { igdbId: 9, gameId: null, name: 'X', status: 'no-source', releases: 0 })
  assert.equal(exportOneGame(db, dir, 'rocket-league'), true)
  assert.equal(readFileSync(other, 'utf8'), 'SENTINEL')
  const idx = JSON.parse(readFileSync(join(dir, 'v1/index.json'), 'utf8')).games
  assert.equal(idx.length, before)
  assert.deepEqual(idx.map((g: { id: string }) => g.id), [...idx.map((g: { id: string }) => g.id)].sort())
  assert.equal(idx.find((g: { id: string }) => g.id === 'rocket-league').releaseCount, 1)
  assert.equal(JSON.parse(readFileSync(join(dir, 'v1/source-checks.json'), 'utf8')).checks[0].status, 'no-source')
  const full = mkdtempSync(join(tmpdir(), 'full-'))
  exportStatic(db, full)
  for (const f of ['index.json', 'latest.json', 'games/rocket-league.json']) assert.equal(readFileSync(join(dir, 'v1', f), 'utf8'), readFileSync(join(full, 'v1', f), 'utf8'), `${f} is what a full export writes`)
  assert.equal(exportOneGame(db, join(dir, 'nowhere'), 'rocket-league'), false, 'no index to build on: the caller exports everything')
})
