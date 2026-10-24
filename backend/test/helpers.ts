import type { FetchFn } from '../src/http.ts'

// A fetch that answers from a URL table; anything unlisted is empty (feeds, Steam, pages).
export const fakeFetch = (routes: Record<string, string | { status: number; body?: string }>): FetchFn =>
  (async (input: string | URL | Request) => {
    const url = String(input instanceof Request ? input.url : input)
    for (const [prefix, r] of Object.entries(routes)) {
      if (!url.startsWith(prefix)) continue
      return typeof r === 'string' ? new Response(r, { status: 200 }) : new Response(r.body ?? '', { status: r.status })
    }
    if (url.endsWith('/robots.txt')) return new Response('', { status: 404 })
    if (url.includes('ISteamNews')) return Response.json({ appnews: { newsitems: [] } })
    if (url.includes('feed')) return new Response('<rss><channel></channel></rss>')
    return new Response('<html></html>')
  }) as FetchFn

export const steamNews = (items: { gid: string; title: string; date: string; contents: string; tags?: string[] }[]) =>
  JSON.stringify({ appnews: { newsitems: items.map((i) => ({ ...i, url: '', date: Date.parse(i.date) / 1000 })) } })

export const rss = (items: { title: string; link: string; date: string; body: string }[]) =>
  `<?xml version="1.0"?><rss><channel>${items
    .map((i) => `<item><title>${i.title}</title><link>${i.link}</link><guid>${i.link}</guid><pubDate>${new Date(i.date).toUTCString()}</pubDate><description><![CDATA[${i.body}]]></description></item>`)
    .join('')}</channel></rss>`
