import { XMLParser } from 'fast-xml-parser'
import { getJson, getText, type FetchFn } from '../http.ts'
import type { SourceDef } from '../registry.ts'
import { steamAppIdOf } from '../registry.ts'
import type { Post } from '../types.ts'

// Source adapters. Each turns one registry source into posts that look like patch notes.
// Steam's patch posts are not always tagged "patchnotes", so titles count too. "Community
// Update" posts are newsletters, not patches.
export const PATCH_TITLE = /\b(update|patch|hot\s*-?fix|day[\s-]*one)\b/i
const NOT_PATCH = /community update|dev(eloper)? update|roadmap|sale\b|discount|giveaway/i
export const looksLikePatch = (title: string) => PATCH_TITLE.test(title) && !NOT_PATCH.test(title)

interface SteamNews {
  appnews: { newsitems: { gid: string; title: string; url: string; date: number; contents: string; tags?: string[] }[] }
}

const steam = async (fetchFn: FetchFn, s: SourceDef): Promise<Post[]> => {
  const appid = steamAppIdOf(s)
  if (!appid) throw new Error(`${s.id}: no Steam app id in ${s.url}`)
  const d = await getJson<SteamNews>(
    fetchFn,
    `https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=${appid}&count=20&maxlength=0&feeds=steam_community_announcements`,
  )
  return d.appnews.newsitems
    .filter((n) => n.tags?.includes('patchnotes') || looksLikePatch(n.title))
    .map((n) => ({
      sourceId: s.id,
      postId: n.gid,
      url: `https://store.steampowered.com/news/app/${appid}/view/${n.gid}`,
      title: n.title,
      publishedAt: new Date(n.date * 1000).toISOString(),
      body: n.contents,
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

export const fetchPosts = async (fetchFn: FetchFn, s: SourceDef): Promise<Post[]> => {
  if (s.kind === 'steamNews') return steam(fetchFn, s)
  const body = await getText(fetchFn, s.url, { accept: s.kind === 'rss' ? 'application/rss+xml, application/atom+xml, application/xml' : 'text/html' })
  return s.kind === 'rss' ? parseFeed(s.id, body) : parseLinks(s.id, s.url, body)
}
