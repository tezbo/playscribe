import type { NoteItem, NoteSection, Platform } from '../types.ts'

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

const platformsFor = (text: string, section?: Platform[]): Platform[] | undefined => {
  if (section) return section
  const p: Platform[] = []
  if (/^\s*(\[PS5\]|PS5:|\(PS5\))|\(PS5( Pro)?\)|PS5 only/i.test(text)) p.push('ps5')
  if (PC.test(text)) p.push('pc')
  if (/^\s*(\[Xbox[^\]]*\]|Xbox[^:]*:)|Xbox only/i.test(text)) p.push('xboxSeries')
  return p.length ? p : undefined
}

const sectionPlatforms = (title: string): Platform[] | undefined => {
  const t = title.trim()
  if (/^(PS5|PlayStation\s*®?\s*5)( Pro)?( specific| fixes| changes)?:?$/i.test(t)) return ['ps5']
  if (/^PC( specific| fixes| changes)?:?$/i.test(t)) return ['pc']
  if (/^Xbox( Series X\|?S)?( specific| fixes| changes)?:?$/i.test(t)) return ['xboxSeries']
  return undefined
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
    const item: NoteItem = { text, ps5ProOnly: currentPro || PRO.test(text) }
    const platforms = platformsFor(text, currentPlatforms)
    if (platforms) item.platforms = platforms
    current!.items.push(item)
    lastItem = bullet ? item : null
  }
  return sections.filter((s) => s.items.length)
}

export const mentionsPs5 = (text: string) => PS5.test(text)
export const mentionsXbox = (text: string) => XBOX.test(text)
