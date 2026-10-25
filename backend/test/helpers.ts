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

/** A press update list in Push Square's markup, one entry per item. */
export const pressIndexPage = (items: { title: string; path: string; date: string; tags?: string[]; teaser?: string }[]) =>
  `<html><head><base href="https://www.pushsquare.com/" /></head><body><ul>${items
    .map(
      (i) =>
        `<li class="item item-content item-article item-medium" data-type="article" data-subject="${i.path}"><div class="info"><p class="heading"><a class="title accent-hover" href="${i.path}"><span class="category accent">News</span> <span class="title accent-hover">${i.title}</span></a></p><p class="text">${i.teaser ?? ''}</p><ul class="list"><li class=" first"><time class="date" datetime="${i.date}">x</time></li>${(i.tags ?? ['PS5', 'Updates']).map((t) => `<li><a class="tag" href="tags/${t.toLowerCase()}">${t}</a></li>`).join('')}</ul></div></li>`,
    )
    .join('')}</ul></div></section></body></html>`

export const pressArticle = (title: string, body: string) =>
  `<html><head><meta property="og:title" content="${title}" /></head><body><article><div class="body body-text article-text"><p>${body}</p></div></article></body></html>`
