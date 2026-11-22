import { XMLParser } from 'fast-xml-parser'
import { getJson, getText, type FetchFn } from '../http.ts'
import type { SourceDef } from '../registry.ts'
import { steamAppIdOf } from '../registry.ts'
import type { Post } from '../types.ts'
import { isNewsOnlyTitle } from './claims.ts'

// Source adapters. Each turns one registry source into posts that look like patch notes.
// Steam's patch posts are not always tagged "patchnotes", so titles count too. "Community
// Update" posts are newsletters, not patches.
export const PATCH_TITLE = /\b(update|patch|hot\s*-?fix|day[\s-]*one)\b|^\s*v?\d+(?:\.\d+)+\s+is\s+(?:here|out|live)\b/i
const NOT_PATCH = /community update|dev(eloper)? update|roadmap|sale\b|discount|giveaway|anti-?cheat|an update (from|on)\b|patch delay|release schedule|matchmaking test|survey/i
export const looksLikePatch = (title: string) => PATCH_TITLE.test(title) && !NOT_PATCH.test(title)

interface SteamNews {
  appnews: { newsitems: { gid: string; title: string; url: string; date: number; contents: string; tags?: string[] }[] }
}

const steam = async (fetchFn: FetchFn, s: SourceDef, count: number, until?: string): Promise<Post[]> => {
  const appid = steamAppIdOf(s)
  if (!appid) throw new Error(`${s.id}: no Steam app id in ${s.url}`)
  // A poll reads the newest posts. A backfill pages back with `enddate` (Steam returns posts older than it) until a page
  // is short or older than `until`, so busy games get their full history: 100 posts reach back only a year or two.
  const items: SteamNews['appnews']['newsitems'] = []
  let end: number | undefined
  for (let page = 0; page < (until ? 60 : 1); page++) {
    const d = await getJson<SteamNews>(
      fetchFn,
      `https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=${appid}&count=${count}&maxlength=0&feeds=steam_community_announcements${end ? `&enddate=${end}` : ''}`,
    )
    const got = d.appnews.newsitems
    items.push(...got)
    const oldest = got.reduce((m, n) => Math.min(m, n.date), Infinity)
    if (!until || got.length < count || (end !== undefined && oldest >= end) || oldest * 1000 < Date.parse(until)) break
    end = oldest
  }
  const seen = new Set<string>()
  return items
    .filter((n) => !seen.has(n.gid) && !!seen.add(n.gid))
    .map((n) => ({
      sourceId: s.id,
      postId: n.gid,
      url: `https://store.steampowered.com/news/app/${appid}/view/${n.gid}`,
      title: n.title,
      publishedAt: new Date(n.date * 1000).toISOString(),
      body: n.contents,
      ...(!isNewsOnlyTitle(n.title, { patchnotesTag: !!n.tags?.includes('patchnotes') }) && (n.tags?.includes('patchnotes') || looksLikePatch(n.title)) ? {} : { news: true }),
    }))
}

const xml = new XMLParser({ ignoreAttributes: false, attributeNamePrefix: '@', textNodeName: '#text' })
const text = (v: unknown): string => {
  if (v == null) return ''
  if (typeof v === 'string' || typeof v === 'number') return String(v)
  if (Array.isArray(v)) return text(v[0])
  if (typeof v === 'object') return text((v as Record<string, unknown>)['#text'] ?? (v as Record<string, unknown>)['@href'] ?? '')
  return ''
}
const list = <T>(v: T | T[] | undefined): T[] => (v == null ? [] : Array.isArray(v) ? v : [v])

export const parseFeed = (sourceId: string, body: string): Post[] => {
  const doc = xml.parse(body) as Record<string, any>
  const rssItems = list(doc.rss?.channel?.item)
  const atomEntries = list(doc.feed?.entry)
  const posts: Post[] = []
  for (const i of rssItems) {
    const url = text(i.link)
    posts.push({
      sourceId,
      postId: text(i.guid) || url,
      url,
      title: text(i.title),
      publishedAt: new Date(text(i.pubDate) || text(i['dc:date']) || Date.now()).toISOString(),
      body: text(i['content:encoded']) || text(i.description),
    })
  }
  for (const e of atomEntries) {
    const links = list(e.link) as Record<string, string>[]
    const url = (links.find((l) => !l['@rel'] || l['@rel'] === 'alternate') ?? links[0])?.['@href'] ?? ''
    posts.push({
      sourceId,
      postId: text(e.id) || url,
      url,
      title: text(e.title),
      publishedAt: new Date(text(e.published) || text(e.updated) || Date.now()).toISOString(),
      body: text(e.content) || text(e.summary),
    })
  }
  return posts
}

// A news index page without a feed: only links whose text reads like a patch post. These never
// become releases by themselves; they go to the review queue for a person to open.
export const parseLinks = (sourceId: string, pageUrl: string, html: string): Post[] => {
  const out = new Map<string, Post>()
  for (const m of html.matchAll(/<a\b[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/gi)) {
    const title = m[2]!.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim()
    if (!title || title.length > 160 || !looksLikePatch(title)) continue
    const url = new URL(m[1]!, pageUrl).toString()
    out.set(url, { sourceId, postId: url, url, title, publishedAt: new Date().toISOString(), body: '' })
  }
  return [...out.values()]
}

const plain = (html: string) =>
  html
    .replace(/<(script|style|figure|aside)[\s\S]*?<\/\1>/gi, ' ')
    .replace(/<\/(p|li|h\d|div)>|<br\s*\/?>/gi, '\n')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n)))
    .replace(/&(amp|quot|#039|apos|nbsp|lt|gt);/g, (_, e) => ({ amp: '&', quot: '"', '#039': "'", apos: "'", nbsp: ' ', lt: '<', gt: '>' })[e as string]!)
    .replace(/[ \t]+/g, ' ')
    .replace(/\n\s*/g, '\n')
    .trim()

/**
 * One page of a press site's update list (Push Square's /tags/updates, dgpCMS markup): each item's
 * link, title, time (the article's latest revision, which for "live now" posts is when it went
 * live), teaser and topic tags.
 */
export const parsePressIndex = (sourceId: string, pageUrl: string, html: string): Post[] => {
  const posts: Post[] = []
  const base = html.match(/<base href="([^"]+)"/)?.[1] ?? pageUrl
  for (const m of html.matchAll(/<li class="item item-content item-article[^"]*" data-type="article" data-subject="([^"]+)"[\s\S]*?(?=<li class="item |<\/ul>\s*<\/div>\s*<\/section>|$)/g)) {
    const block = m[0]
    const title = block.match(/<span class="title[^"]*">([\s\S]*?)<\/span>/)?.[1]
    const at = block.match(/datetime="([^"]+)"/)?.[1]
    // News posts only: guides and features recap old patches ("Elden Ring: all patch notes").
    if (!title || !at || !/^news\//.test(m[1]!)) continue
    const url = new URL(m[1]!, base).toString()
    posts.push({
      sourceId,
      postId: url,
      url,
      title: plain(title),
      publishedAt: new Date(at).toISOString(),
      body: plain(block.match(/<p class="text">([\s\S]*?)<\/p>/)?.[1] ?? ''),
      tags: [...block.matchAll(/<a class="tag" href="[^"]+">([^<]+)<\/a>/g)].map((t) => plain(t[1]!)),
    })
  }
  return posts
}

/** The article text of a press post, kept only in memory: the pipeline reads facts from it (version, size, status). */
export const parsePressArticle = (html: string): { body: string; title?: string } => {
  const title = plain(html.match(/<meta property="og:title" content="([^"]+)"/)?.[1] ?? '')
  const body = plain(html.match(/class="body body-text article-text"[^>]*>([\s\S]*?)<\/article>/)?.[1] ?? html.match(/class="body body-text[^"]*"[^>]*>([\s\S]*?)<\/div>\s*<\/div>/)?.[1] ?? '')
  return title ? { title, body } : { body }
}

export interface PageOpts {
  /** Stop paging once a page is entirely older than this (backfill), else after `maxPages`. */
  until?: string
  maxPages?: number
  /** Stop paging at the first page whose posts have all been seen. */
  seen?: (postId: string) => boolean
}

const pressIndex = async (fetchFn: FetchFn, s: SourceDef, opts: PageOpts): Promise<Post[]> => {
  const out = new Map<string, Post>()
  for (let page = 1; page <= (opts.until ? 200 : (opts.maxPages ?? 3)); page++) {
    const pageUrl = page === 1 ? s.url : `${s.url}${s.url.includes('?') ? '&' : '?'}page=${page}`
    let html: string
    try {
      html = await getText(fetchFn, pageUrl, { accept: 'text/html' })
    } catch (e) {
      if (page > 1 && /^404 /.test((e as Error).message)) break // past the last page
      throw e
    }
    const posts = parsePressIndex(s.id, pageUrl, html).filter((p) => !out.has(p.postId))
    if (!posts.length) break
    for (const p of posts)
      out.set(p.postId, { ...p, expand: async () => ({ ...parsePressArticle(await getText(fetchFn, p.url, { accept: 'text/html' })) }) })
    if (opts.until ? posts.every((p) => p.publishedAt < opts.until!) : opts.seen && posts.every((p) => opts.seen!(p.postId))) break
  }
  return [...out.values()]
}

const fold = (t: string) => t.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase()
const namesAny = (text: string, names: string[]) => names.some((n) => fold(text).includes(fold(n)))

interface BskyFeed {
  cursor?: string
  feed: { post: { uri: string; author: { handle: string }; record: { text?: string; createdAt?: string } }; reason?: unknown }[]
}

/** The patch name a studio post gives ("Patch 2.09 for ...", "Update 1.72", "hotfix"), else its first sentence. */
export const blueskyTitle = (text: string) => {
  const flat = text.replace(/\s+/g, ' ').trim()
  const v = flat.match(/\b(patch|update|hot\s*-?fix)\s*v?(\d+(?:\.\d+){1,3}[a-z]?)\b/i)
  if (v) return `${v[1]!.replace(/[\s-]/g, '').toLowerCase().replace(/^./, (c) => c.toUpperCase())} ${v[2]}`
  const first = flat.split(/(?<=[.!?])\s/)[0]!
  return first.length > 120 ? `${first.slice(0, 117)}...` : first
}

/**
 * A studio's own Bluesky account, read through Bluesky's public API (no sign-in, no scraping): the posts the account itself wrote,
 * newest first. Reposts and replies are skipped. A backfill pages back until `until`.
 */
const bluesky = async (fetchFn: FetchFn, s: SourceDef, until?: string): Promise<Post[]> => {
  const handle = s.url.match(/bsky\.app\/profile\/([^/?#]+)/)?.[1]
  if (!handle) throw new Error(`${s.id}: no Bluesky handle in ${s.url}`)
  const out: Post[] = []
  let cursor: string | undefined
  for (let page = 0; page < (until ? 20 : 1); page++) {
    const d = await getJson<BskyFeed>(
      fetchFn,
      `https://public.api.bsky.app/xrpc/app.bsky.feed.getAuthorFeed?actor=${encodeURIComponent(handle)}&limit=100&filter=posts_no_replies${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ''}`,
    )
    for (const f of d.feed) {
      const text = f.post.record.text?.trim()
      if (f.reason || !text || !f.post.record.createdAt || f.post.author.handle.toLowerCase() !== handle.toLowerCase()) continue
      out.push({
        sourceId: s.id,
        postId: f.post.uri,
        url: `https://bsky.app/profile/${handle}/post/${f.post.uri.split('/').pop()}`,
        title: blueskyTitle(text),
        publishedAt: new Date(f.post.record.createdAt).toISOString(),
        body: text,
      })
    }
    cursor = d.cursor
    if (!cursor || !until || out.length === 0 || out.every((p) => p.publishedAt < until)) break
  }
  return out
}

/**
 * An Atlassian Statuspage history feed (Epic's public status page). A maintenance item counts once it says "Completed": the update
 * is then live, at the time of that last entry. Scheduled or in-progress downtime is not a release yet.
 */
export const parseStatuspage = (sourceId: string, body: string): Post[] => {
  const doc = xml.parse(body) as Record<string, any>
  const posts: Post[] = []
  for (const i of list(doc.rss?.channel?.item)) {
    const desc = text(i.description).replace(/<var[^>]*>|<\/var>/g, '').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim()
    if (!/\bCompleted\b/.test(desc)) continue
    const ver = text(i.title).match(/\bv(\d+\.\d+(?:\.\d+)?)\b/i)?.[1]
    posts.push({
      sourceId,
      postId: text(i.guid) || text(i.link),
      url: text(i.link),
      title: ver ? `Update v${ver}` : text(i.title),
      publishedAt: new Date(text(i.pubDate)).toISOString(),
      body: `${text(i.title)}. ${desc}`,
    })
  }
  return posts
}

/** Posts of a source that names its game(s): drop what names none, mark what is not a patch post as news. */
const forGame = (s: SourceDef, posts: Post[]): Post[] =>
  s.mentions || s.patchOnly
    ? posts
        .filter((p) => !s.mentions || namesAny(`${p.title}\n${p.body}`, s.mentions))
        .map((p) => (s.patchOnly && (!looksLikePatch(`${p.title}`) && !looksLikePatch(p.body.slice(0, 200)) || isNewsOnlyTitle(p.title)) ? { ...p, news: true } : p))
    : posts

export const fetchPosts = async (fetchFn: FetchFn, s: SourceDef, opts: PageOpts = {}): Promise<Post[]> => {
  if (s.kind === 'steamNews') return steam(fetchFn, s, opts.until ? 100 : 20, opts.until)
  if (s.kind === 'pressIndex') return pressIndex(fetchFn, s, opts)
  if (s.kind === 'bluesky') return forGame(s, await bluesky(fetchFn, s, opts.until))
  if (s.kind === 'statuspage') return forGame(s, parseStatuspage(s.id, await getText(fetchFn, s.url, { accept: 'application/rss+xml, application/xml' })))
  const body = await getText(fetchFn, s.url, { accept: s.kind === 'rss' ? 'application/rss+xml, application/atom+xml, application/xml' : 'text/html' })
  return s.kind === 'rss' ? forGame(s, parseFeed(s.id, body)) : parseLinks(s.id, s.url, body)
}
