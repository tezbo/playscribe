import { mkdirSync } from 'node:fs'
import { dirname } from 'node:path'
import { DatabaseSync } from 'node:sqlite'

// One SQLite file on the host's volume. node:sqlite keeps the image free of native modules.
export type DB = DatabaseSync

const SCHEMA = `
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;

-- Model follows docs/ps5-patch-data.md. JSON columns hold the spec's nested types as-is.
CREATE TABLE IF NOT EXISTS games (
  id TEXT PRIMARY KEY,               -- our slug: registry key, else the IGDB slug
  igdb_id INTEGER UNIQUE,
  name TEXT NOT NULL,
  cover_image_id TEXT,
  artwork_image_id TEXT,             -- IGDB key art for the square tile; '' when IGDB has none
  square_cover_image_id TEXT,        -- IGDB square cover, when the studio supplied one
  steam_app_id INTEGER,
  ps5_release TEXT,                  -- YYYY-MM-DD, earliest PS5 release date
  ps5_release_precision TEXT,        -- month | quarter | year | tbd; NULL is a day
  first_release TEXT,
  ps5_title_ids TEXT NOT NULL DEFAULT '[]',
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS releases (
  id TEXT PRIMARY KEY,               -- "<gameId>@<versionKey>"
  game_id TEXT NOT NULL REFERENCES games(id),
  version_key TEXT NOT NULL,
  display_name TEXT NOT NULL,
  kind TEXT NOT NULL,                -- dayOne | hotfix | patch | major | silent
  kind_basis TEXT NOT NULL,          -- studio | inferred
  announced_at TEXT NOT NULL,
  notes TEXT NOT NULL,               -- JSON NoteSection[]
  source_ids TEXT NOT NULL,          -- JSON string[]
  content_hash TEXT NOT NULL,
  revision INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE (game_id, version_key)
);
CREATE INDEX IF NOT EXISTS releases_by_game ON releases (game_id, announced_at DESC);

CREATE TABLE IF NOT EXISTS platform_releases (
  release_id TEXT NOT NULL REFERENCES releases(id),
  platform TEXT NOT NULL,            -- ps5 | xboxSeries | switch2 | pc
  status TEXT NOT NULL,              -- live | announced | notPlanned | unknown
  version TEXT,                      -- JSON Field<string>
  size_bytes TEXT,                   -- JSON Field<number>
  live_at TEXT,                      -- JSON Field<string>
  bundles TEXT NOT NULL DEFAULT '[]',
  verification TEXT NOT NULL,        -- official | reported | pending
  pushed_at TEXT,                    -- set once; a release never pushes twice
  updated_at TEXT NOT NULL,
  PRIMARY KEY (release_id, platform)
);

-- Posts already read, so a feed item is processed once.
CREATE TABLE IF NOT EXISTS seen_posts (
  source_id TEXT NOT NULL,
  post_id TEXT NOT NULL,
  release_id TEXT,
  seen_at TEXT NOT NULL,
  PRIMARY KEY (source_id, post_id)
);

-- Review queue: things a person has to look at before PS5 can become official.
CREATE TABLE IF NOT EXISTS review_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  release_id TEXT REFERENCES releases(id),
  game_id TEXT NOT NULL,
  platform TEXT NOT NULL,
  reason TEXT NOT NULL,              -- officialPost | steamMentionsPs5 | sourceLink
  source_id TEXT NOT NULL,
  url TEXT NOT NULL,
  title TEXT NOT NULL,
  created_at TEXT NOT NULL,
  resolved_at TEXT,
  resolution TEXT,                   -- confirmed | dismissed
  UNIQUE (source_id, url)
);

CREATE TABLE IF NOT EXISTS source_state (
  source_id TEXT PRIMARY KEY,
  last_fetched_at TEXT,
  last_status INTEGER,
  last_error TEXT,
  blocked INTEGER NOT NULL DEFAULT 0 -- 403 or robots.txt: stays off until a person changes the registry
);

CREATE TABLE IF NOT EXISTS devices (
  id TEXT PRIMARY KEY,
  key_hash TEXT NOT NULL UNIQUE,
  apns_token TEXT UNIQUE,
  environment TEXT NOT NULL,         -- sandbox | production
  locale TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS follows (
  device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  game_id TEXT NOT NULL REFERENCES games(id),
  notify TEXT NOT NULL,              -- all | major | off
  PRIMARY KEY (device_id, game_id)
);

CREATE TABLE IF NOT EXISTS push_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  release_id TEXT NOT NULL,
  device_id TEXT NOT NULL,
  status INTEGER NOT NULL,
  reason TEXT,
  sent_at TEXT NOT NULL
);
`

export const openDb = (path: string): DB => {
  if (path !== ':memory:') mkdirSync(dirname(path), { recursive: true })
  const db = new DatabaseSync(path)
  db.exec(SCHEMA)
  // Columns added after the first feed went out; CREATE TABLE IF NOT EXISTS leaves old tables as they were.
  const has = (table: string, col: string) => (db.prepare(`PRAGMA table_info(${table})`).all() as { name: string }[]).some((c) => c.name === col)
  if (!has('games', 'ps5_release_precision')) db.exec('ALTER TABLE games ADD COLUMN ps5_release_precision TEXT')
  if (!has('games', 'artwork_image_id')) db.exec('ALTER TABLE games ADD COLUMN artwork_image_id TEXT')
  if (!has('games', 'square_cover_image_id')) db.exec('ALTER TABLE games ADD COLUMN square_cover_image_id TEXT')
  return db
}

export const now = () => new Date().toISOString()

export const tx = <T>(db: DB, fn: () => T): T => {
  db.exec('BEGIN')
  try {
    const out = fn()
    db.exec('COMMIT')
    return out
  } catch (e) {
    db.exec('ROLLBACK')
    throw e
  }
}
