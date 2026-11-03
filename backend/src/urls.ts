// A website URL the app can open. IGDB sometimes holds junk (spaces, a second host); the app decodes
// `links.official` as a URL, and one bad value stops it decoding the whole info/<n>.json shard (seen live in info/38).
export const isUrl = (v: unknown): v is string => typeof v === 'string' && /^https?:\/\/[^\s]+$/.test(v)
