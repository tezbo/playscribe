import assert from 'node:assert/strict'
import { test } from 'node:test'
import { openDb } from '../src/db.ts'
import { parseStatuspage, blueskyTitle, parseMojangNotes, parseRiotNews } from '../src/ingest/adapters.ts'
import { pcNumberIsTitled, runIngest, seedGames } from '../src/ingest/pipeline.ts'
import { registry } from '../src/registry.ts'
import * as store from '../src/store.ts'
import { fakeFetch, rss } from './helpers.ts'

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
