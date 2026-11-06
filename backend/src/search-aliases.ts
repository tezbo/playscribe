// Search aliases for the bundled PS5 index (field k): the short names players type. "GTA" finds Grand Theft Auto,
// "RDR2" finds Red Dead Redemption 2. The app folds and matches them like the name (case, accents and punctuation ignored).

/** Franchise names players shorten. A title starting with the long form also answers to the short form ("COD Modern Warfare"). */
export const FRANCHISE_ABBREVIATIONS: [string, string][] = [
  ['Grand Theft Auto', 'GTA'],
  ['Call of Duty', 'COD'],
  ["Assassin's Creed", 'AC'],
  ['Final Fantasy', 'FF'],
  ['Red Dead Redemption', 'RDR'],
  ['Resident Evil', 'RE'],
  ['Kingdom Hearts', 'KH'],
  ['Monster Hunter', 'MH'],
  ['Dragon Ball', 'DB'],
  ['Dragon Quest', 'DQ'],
  ['The Elder Scrolls', 'TES'],
  ['The Witcher', 'TW'],
  ['Mortal Kombat', 'MK'],
  ['Need for Speed', 'NFS'],
  ['Battlefield', 'BF'],
  ['Tom Clancy’s', 'TC'],
  ['The Last of Us', 'TLOU'],
  ['God of War', 'GOW'],
  ['Horizon Zero Dawn', 'HZD'],
  ['Horizon Forbidden West', 'HFW'],
  ['Ghost of Tsushima', 'GOT'],
  ['Marvel’s Spider-Man', 'Spider-Man'],
  ['Counter-Strike', 'CS'],
  ['League of Legends', 'LOL'],
  ['Elden Ring', 'ER'],
  ['Cyberpunk 2077', 'CP2077'],
  ['Baldur’s Gate', 'BG'],
  ['Persona', 'P'],
  ['Street Fighter', 'SF'],
  ['Pro Evolution Soccer', 'PES'],
  ['Football Manager', 'FM'],
  ['EA Sports FC', 'FC'],
  ['Hogwarts Legacy', 'HL'],
  ['Genshin Impact', 'Genshin'],
]

const SMALL = new Set(['the', 'of', 'a', 'an', 'and', 'for', 'to', 'in', 'on', 'at'])
const fold = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim()
const ROMAN: Record<string, string> = { ii: '2', iii: '3', iv: '4', v: '5', vi: '6', vii: '7', viii: '8', ix: '9', x: '10' }

/** Initials of a title's significant words with any number kept: "Red Dead Redemption 2" gives "RDR2", "Baldur's Gate 3" gives "BG3". */
export const initialism = (name: string): string | null => {
  const sig = fold(name.split(/[:\u2013\u2014]\s?|\s-\s/)[0]!).split(' ').filter((w) => w && !SMALL.has(w))
  const isNum = (w: string) => /^\d+$/.test(w) || !!ROMAN[w]
  const letters = sig.filter((w) => !isNum(w))
  const num = sig.find(isNum)
  if (letters.length < (num ? 2 : 3)) return null
  const base = letters.map((w) => w[0]).join('').toUpperCase()
  return num ? base + (ROMAN[num] ?? num) : base
}

/** Up to `max` aliases for one game: IGDB's alternative names, the franchise short forms, and the initialism. */
export const searchAliases = (name: string, alternative: string[] = [], max = 5): string[] => {
  const own = fold(name)
  const out = new Map<string, string>()
  const add = (a: string | null | undefined) => {
    const f = a ? fold(a) : ''
    // Latin text only, and never a file name (IGDB alternative names include "bootstrapper.exe").
    if (f.length >= 2 && f !== own && !out.has(f) && a!.length <= 40 && /^[\x20-\x7e\u00c0-\u024f\u2019\u00ae\u2122]+$/.test(a!) && !/\.[a-z0-9]{2,4}$/i.test(a!)) out.set(f, a!)
  }
  let franchise = false
  const nameFold = name.replace(/’/g, "'")
  for (const [long, short] of FRANCHISE_ABBREVIATIONS) {
    const l = long.replace(/’/g, "'")
    if (nameFold.toLowerCase().startsWith(l.toLowerCase()) && (nameFold.length === l.length || /[\s:]/.test(nameFold[l.length]!))) {
      franchise = true
      add(short + nameFold.slice(l.length))
      // "GTAV": the short form with the number joined on
      const rest = fold(nameFold.slice(l.length))
      const first = rest.split(' ')[0] ?? ''
      if (/^(\d+|ii|iii|iv|v|vi|vii|viii|ix|x)$/.test(first)) add(short + (ROMAN[first] ?? first))
    }
  }
  if (!franchise) add(initialism(name))
  for (const a of alternative) add(a)
  return [...out.values()].slice(0, max)
}
