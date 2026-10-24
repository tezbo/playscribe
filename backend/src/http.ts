// Outbound HTTP for source polling: one descriptive User-Agent, a timeout, and robots.txt.
export const USER_AGENT = 'PlayscribeBot/0.1 (+https://github.com/tezbo/playscribe; patch notes reader)'

export type FetchFn = typeof fetch

export class Blocked extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message)
  }
}

export const getText = async (fetchFn: FetchFn, url: string, headers: Record<string, string> = {}) => {
  const r = await fetchFn(url, { headers: { 'user-agent': USER_AGENT, ...headers }, signal: AbortSignal.timeout(20_000) })
  if (r.status === 403 || r.status === 401) throw new Blocked(r.status, `${r.status} from ${url}`)
  if (!r.ok) throw new Error(`${r.status} from ${url}`)
  return r.text()
}

export const getJson = async <T>(fetchFn: FetchFn, url: string, headers: Record<string, string> = {}) =>
  JSON.parse(await getText(fetchFn, url, { accept: 'application/json', ...headers })) as T

// robots.txt: the rules for our agent if it is named, else for *. Longest match wins, Allow beats
// Disallow on a tie, as in RFC 9309.
const robotsCache = new Map<string, { at: number; rules: { allow: boolean; path: string }[] }>()

export const parseRobots = (txt: string, agent = 'playscribebot') => {
  const groups: { agents: string[]; rules: { allow: boolean; path: string }[] }[] = []
  let cur: (typeof groups)[number] | null = null
  let lastWasAgent = false
  for (const raw of txt.split('\n')) {
    const line = raw.replace(/#.*/, '').trim()
    const m = line.match(/^([a-z-]+)\s*:\s*(.*)$/i)
    if (!m) continue
    const key = m[1]!.toLowerCase()
    const val = m[2]!.trim()
    if (key === 'user-agent') {
      if (!cur || !lastWasAgent) groups.push((cur = { agents: [], rules: [] }))
      cur.agents.push(val.toLowerCase())
      lastWasAgent = true
    } else {
      lastWasAgent = false
      if (cur && (key === 'allow' || key === 'disallow') && val) cur.rules.push({ allow: key === 'allow', path: val })
    }
  }
  const mine = groups.filter((g) => g.agents.some((a) => a !== '*' && agent.includes(a)))
  const chosen = mine.length ? mine : groups.filter((g) => g.agents.includes('*'))
  return chosen.flatMap((g) => g.rules)
}

export const robotsAllows = (rules: { allow: boolean; path: string }[], path: string) => {
  let best: { allow: boolean; path: string } | null = null
  for (const r of rules) {
    const re = new RegExp('^' + r.path.replace(/[.+?^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*').replace(/\\\$$/, '$'))
    if (!re.test(path)) continue
    if (!best || r.path.length > best.path.length || (r.path.length === best.path.length && r.allow)) best = r
  }
  return best ? best.allow : true
}

export const allowedByRobots = async (fetchFn: FetchFn, url: string) => {
  const u = new URL(url)
  const cached = robotsCache.get(u.origin)
  let rules = cached && Date.now() - cached.at < 24 * 3600_000 ? cached.rules : null
  if (!rules) {
    try {
      const r = await fetchFn(`${u.origin}/robots.txt`, { headers: { 'user-agent': USER_AGENT }, signal: AbortSignal.timeout(10_000) })
      rules = r.ok ? parseRobots(await r.text()) : []
    } catch {
      rules = []
    }
    robotsCache.set(u.origin, { at: Date.now(), rules })
  }
  return robotsAllows(rules, u.pathname + u.search)
}
