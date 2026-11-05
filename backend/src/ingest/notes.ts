import { readFileSync } from 'node:fs'
import { SOURCE_NAMES } from '../quality.ts'
import type { NoteCategory, NoteItem, NoteSection, Platform } from '../types.ts'

// Turns a post body (Steam BBCode, feed HTML or plain text) into grouped notes.
const ENTITIES: Record<string, string> = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', '#39': "'" }
const decode = (s: string) =>
  s
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n)))
    .replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCodePoint(Number.parseInt(n, 16)))
    .replace(/&([a-z0-9#]+);/gi, (m, n) => ENTITIES[n.toLowerCase()] ?? m)

export const toLines = (body: string) =>
  decode(
    body
      .replace(/\r/g, '')
      // Platform tags look like BBCode; keep them as "PC:" so they survive tag stripping.
      .replace(/\[(PC|PS5|PS4|Xbox|Xbox Series X\|?S)\]/gi, '$1:')
      // A list item that is itself a small heading ("[*] [h3]Animal petting[/h3]") is an item.
      .replace(/(\[\*\]|<li[^>]*>)\s*(?:\[h\d\]([\s\S]*?)\[\/h\d\]|<h\d[^>]*>([\s\S]*?)<\/h\d>)/gi, (_, li, a, b) => `${li}${a ?? b}`)
      .replace(/\[\/list\]|\[\/olist\]|<\/ul>|<\/ol>/gi, '\n§end\n')
      .replace(/\[h\d\]([\s\S]*?)\[\/h\d\]/gi, '\n## $1\n')
      .replace(/<h\d[^>]*>([\s\S]*?)<\/h\d>/gi, '\n## $1\n')
      .replace(/\[\*\]|<li[^>]*>/gi, '\n- ')
      .replace(/<br\s*\/?>|<\/p>|<\/li>|<\/div>|\[\/?p\]|\[\/?list\]|\[\/?olist\]/gi, '\n')
      .replace(/\[img\][\s\S]*?\[\/img\]|\[previewyoutube[^\]]*\][\s\S]*?\[\/previewyoutube\]/gi, '')
      .replace(/\[\/\*\]/g, '')
      .replace(/\[\/?[a-z0-9]+(=[^\]]*)?\]/gi, '')
      .replace(/<[^>]+>/g, ''),
  )
    .split('\n')
    .map((l) => l.replace(/\s+/g, ' ').trim())
    .filter(Boolean)

const PS5 = /\b(PS5|PlayStation\s*®?\s*5)\b/i
const PRO = /\bPS5\s*Pro\b|PlayStation\s*®?\s*5\s*Pro/i
const PC = /^\s*(\[PC\]|PC:|\(PC\))|\bPC only\b|\(PC\)/i
const XBOX = /\bXbox Series\b|^\s*(\[Xbox\]|Xbox:)/i

// Shared with ios/tools/build_fixtures.py so the bundled fixtures follow the same rules.
const TERMS = JSON.parse(readFileSync(new URL('./platform-terms.json', import.meta.url), 'utf8')) as Record<'pcNames' | 'pc' | 'ps5' | 'xboxSeries' | 'consoles', string[]>
const any = (list: string[]) => new RegExp(list.map((p) => `(?:${p})`).join('|'), 'i')
const NAMES = { pc: any([...TERMS.pcNames, ...TERMS.pc]), ps5: any(TERMS.ps5), xboxSeries: any(TERMS.xboxSeries), consoles: any(TERMS.consoles) }

/**
 * Which platforms an item is about, or undefined for every platform. A section heading ("PC",
 * "PS5 fixes") decides for its items; otherwise the item's own words do. PC-only words (FrameGen,
 * DLSS, AMD, Steam Deck, mouse and keyboard…) tag it PC unless it also names a console.
 */
export const platformsFor = (text: string, section?: Platform[]): Platform[] | undefined => {
  if (section) return section
  const p: Platform[] = []
  const ps5 = NAMES.ps5.test(text)
  const xbox = NAMES.xboxSeries.test(text)
  if (ps5) p.push('ps5')
  if (PC.test(text) || (NAMES.pc.test(text) && !NAMES.consoles.test(text))) p.push('pc')
  if (xbox) p.push('xboxSeries')
  return p.length ? p : undefined
}

/** A line tagged for PC and no console. */
export const isPcOnly = (platforms: Platform[] | undefined) => !!platforms?.length && platforms.every((p) => p === 'pc')

/** The kind of change a section lists, from its title. Fixes win over new when a title says both ("Fixes and additions"). */
export const categoryOf = (title: string): NoteCategory =>
  /\b(fix(es|ed)?|bug\s*fix(es)?|bugs?|crash(es)?|stability|resolved)\b/i.test(title)
    ? 'fixed'
    : /\b(balanc\w*|tuning|tweaks?|nerfs?|buffs?|adjustments?|difficulty)\b/i.test(title)
      ? 'balance'
      : /\b(new|added|additions?|features?|content|introduc\w*|improvements?|enhancements?|highlights?)\b/i.test(title)
        ? 'new'
        : 'other'

/** A section titled "Changes" or "Patch Notes" says nothing about its items, so an item whose own first words name the kind of change decides for itself. */
export const itemCategoryOf = (text: string, section: NoteCategory): NoteCategory => {
  if (section !== 'other') return section
  if (/^(fix(ed|es)?|resolved|corrected|addressed|prevented)\b/i.test(text)) return 'fixed'
  if (/^(added|adds|new|introduced|implemented|improved|enhanced|now (supports?|includes?|has))\b/i.test(text)) return 'new'
  if (/^(adjusted|increased|decreased|reduced|reworked|tuned|nerfed|buffed|rebalanced|lowered|raised)\b/i.test(text)) return 'balance'
  return 'other'
}

const sectionPlatforms = (title: string): Platform[] | undefined => {
  const t = title.trim()
  if (/^(PS5|PlayStation\s*®?\s*5)( Pro)?( specific| fixes| changes)?:?$/i.test(t)) return ['ps5']
  if (/^PC( specific| fixes| changes)?:?$/i.test(t)) return ['pc']
  if (/^Xbox( Series X\|?S)?( specific| fixes| changes)?:?$/i.test(t)) return ['xboxSeries']
  // "Steam Deck", "Find your best Steam Deck settings": a heading about one platform covers its items.
  const named = platformsFor(t)
  return named?.length === 1 ? named : undefined
}

export const extractNotes = (body: string, fallbackTitle = 'Changes'): NoteSection[] => {
  const sections: NoteSection[] = []
  let current: NoteSection | null = null
  let currentPlatforms: Platform[] | undefined
  let currentPro = false
  const open = (title: string) => {
    current = { title, items: [] }
    currentPlatforms = sectionPlatforms(title)
    currentPro = PRO.test(title)
    sections.push(current)
  }
  let inList = false
  let lastItem: NoteItem | null = null
  for (const line of toLines(body)) {
    if (line === '§end') {
      inList = false
      lastItem = null
      continue
    }
    const heading = line.startsWith('## ') ? line.slice(3).trim() : !line.startsWith('- ') && line.length <= 60 && line.endsWith(':') ? line.slice(0, -1).trim() : null
    if (heading) {
      lastItem = null
      open(heading.replace(/:$/, ''))
      continue
    }
    const bullet = line.startsWith('- ') || line === '-'
    const text = line.replace(/^-( |$)/, '').trim()
    if (!text) continue
    // A plain line right after an item inside a list describes that item.
    if (!bullet && inList && lastItem) {
      lastItem.text = `${lastItem.text.replace(/:$/, '')}: ${text}`
      continue
    }
    if (bullet) inList = true
    if (!current) open(fallbackTitle)
    const item: NoteItem = { text, ps5ProOnly: currentPro || PRO.test(text), pcOnly: false, category: itemCategoryOf(text, categoryOf(current!.title)) }
    const platforms = platformsFor(text, currentPlatforms)
    if (platforms) item.platforms = platforms
    item.pcOnly = isPcOnly(platforms)
    current!.items.push(item)
    lastItem = bullet ? item : null
  }
  return sections.filter((s) => s.items.length)
}

/**
 * Re-applies the platform rules to notes stored earlier, so a rule change reaches old releases. Also keeps source
 * names out of the notes (Terry's rule): a line that names one (a quoted review in a studio's post, say) is dropped,
 * a heading that names one becomes "Changes", and a section left empty goes.
 */
export const tagNotes = (sections: NoteSection[]): NoteSection[] =>
  sections.map((s) => {
    const section = sectionPlatforms(s.title)
    return {
      ...s,
      title: SOURCE_NAMES.test(s.title) ? 'Changes' : s.title,
      items: s.items.filter((i) => !SOURCE_NAMES.test(i.text)).map(({ platforms: _old, ...i }) => {
        const platforms = platformsFor(i.text, section)
        const category = itemCategoryOf(i.text, categoryOf(s.title))
        return platforms ? { ...i, platforms, pcOnly: isPcOnly(platforms), category } : { ...i, pcOnly: false, category }
      }),
    }
  }).filter((s) => s.items.length)

export const mentionsPs5 = (text: string) => PS5.test(text)
export const mentionsXbox = (text: string) => XBOX.test(text)

// Hosts that are never a studio's PS5 update page: Steam itself, stores, video and social sites, image CDNs.
const NOT_A_PS5_PAGE = /(^|\.)(steampowered\.com|steamcommunity\.com|steamstatic\.com|akamaihd\.net|store\.playstation\.com|youtube\.com|youtu\.be|twitter\.com|x\.com|discord\.gg|discord\.com|reddit\.com|facebook\.com|instagram\.com|tiktok\.com|twitch\.tv|bsky\.app)$/i

/** The first link in a post to a studio page about this update on PS5 or consoles, judged by its address or link text. */
export const ps5PageOf = (body: string): string | null => {
  const links: { url: string; text: string }[] = []
  for (const m of body.matchAll(/\[url=["']?(https?:\/\/[^\]"'\s]+)["']?\]([\s\S]*?)\[\/url\]/gi)) links.push({ url: m[1]!, text: m[2]! })
  for (const m of body.matchAll(/<a\s[^>]*href=["'](https?:\/\/[^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi)) links.push({ url: m[1]!, text: m[2]! })
  // A bare address counts with the line it sits on as its text ("PS5 patch notes: https://…").
  for (const line of body.split('\n')) for (const m of line.matchAll(/(?<![=["'])\bhttps?:\/\/[^\s\]\[<>"']+/gi)) links.push({ url: m[0], text: line })
  for (const { url, text } of links) {
    let host: string
    try {
      host = new URL(url).hostname
    } catch {
      continue
    }
    if (NOT_A_PS5_PAGE.test(host)) continue
    if (/ps5|playstation|console/i.test(`${url} ${text.replace(/<[^>]+>/g, ' ')}`)) return url
  }
  return null
}
