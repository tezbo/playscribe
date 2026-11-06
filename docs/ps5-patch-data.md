# PS5 patch data: sourcing and data model

Decided 2026-10-24 by the PS5 patching lead. This is the contract for the iOS app and the backend.

**Changed 2026-10-27 (Terry): Steam is the source of truth for updates.** Every patch or update a game posts on Steam is taken as released on PS5 too, unless we can confirm otherwise. The app shows such an update as "Released", alerts for it as soon as it lands, and links back to the Steam notes and, when one exists, the studio's PS5 page for that update. This replaces rule 3 below and the no-source-credits rule (links are now shown). "Unconfirmed" is kept only for a release the press reports and neither Steam nor the studio has. A PC version number is still never shown as a PS5 version.

## Sourcing decision

1. **Official sources only can mark something "On PS5".** Per game, keep a registry of the official channels: studio or publisher patch posts that name PS5, studio support centres, publisher newsrooms, and PlayStation Blog.
2. **PlayStation press (Push Square, PlayStation LifeStyle) is secondary.** It is often first with a PS5 version and download size. A press-only fact shows as "Reported", never as confirmed.
3. **Steam news is the source of truth for updates** (since 2026-10-27). A Steam patch post creates the PS5 row as `live` with verification `assumed`, unless the post says consoles get it later (`announced`, taken as `live` a week after the Steam post, dated from Steam, with no alert if that is over 72 h ago) or not at all (`notPlanned`), the game's Steam version is a separate PC port (`steamIsPcPort` in the registry: Sony and Square Enix ports such as Ghost of Tsushima), or the post predates the PS5 release. A PC version number or download size is never copied to PS5. PS5 builds carry their own version numbers.
4. **Sony's patch servers: not used.** The title-update lookup needs a request signature derived from a key taken out of console firmware. PlayStation's Software Usage Terms forbid getting around authentication safeguards and gaining unauthorised access to PSN services. This is closed and is not a question for Terry. Revisit only if Sony offers a partner programme.
5. **Also not used:** ProsperoPatches and similar trackers (private, bot-protected API), PlayStation Store pages (they have no game version), PSN APIs (they need NPSSO, which is ruled out), and any scraping that playstation.com terms s.10 bans.

**Fetching rules for the backend:** prefer RSS, Atom or JSON feeds. Respect robots.txt and each site's terms. Poll each source at most once an hour, with a descriptive User-Agent. If a site returns 403 to automated fetches, mark the source `manual` and don't work around the block.

**Verification** (still recorded, no longer shown as a tag): extraction can be automated, with Claude summarising the post into notes. A release reaches `official` when an official post (the studio's site, its Steam post, or the PlayStation Blog) says in so many words that the update is live on PS5, such as "now live on PC, PS5 and Xbox" (Terry, 2026-10-26: Unconfirmed should be the rare exception). A post that only names PS5, or says the PS5 version follows later, stays `pending` until a person confirms it, and is hidden from push notifications until then. A "PS5 controller" mention is not evidence. A backfill re-reads official posts already seen, so the rule also applies to old releases.

## How console patching works, and what the model has to handle

- Every PS5 patch goes through Sony certification, so the console usually trails PC by days, sometimes by weeks. A PC hotfix often never ships on PS5 on its own. It is folded into the next console patch. So one PS5 release can bundle several PC releases, and the model links them.
- The PS5 shows a game version in the form `XX.YYY.ZZZ`, for example `01.004.000`. Store that string exactly as the console shows it. Studio names like "Update 1.1" or "Patch 3" are display names, kept separately.
- Some games have a separate PS5 Pro build or Pro-only fixes. Treat these as notes flagged `ps5ProOnly` on a PS5 release, not as a separate platform.
- Silent updates exist: a version change with no announcement. Without Sony's servers we only catch them when the press reports them. Show them as `Reported`, with "No official notes" as their notes.
- Day-one patches are their own kind, because players on disc install them before they first play.

## Release kinds

| kind | What it means | How we classify it |
|---|---|---|
| `dayOne` | Patch that ships at or before launch | Published within 1 day of the platform release date |
| `hotfix` | Small, urgent fix with no new features | Studio says "hotfix", or fixes only, at most 7 days after the previous release |
| `patch` | Planned fix and balance release | Studio says "patch" or uses a numbered patch, with fixes and tuning only |
| `major` | Content or feature update | Studio calls it an update or expansion, or it adds content, modes or features |
| `silent` | Version changed with no announcement | Press reports it and no official post exists |

The studio's own label always wins. Store `kindBasis: "studio" | "inferred"` so we can audit the inferred ones.

## Data model

```swift
enum Platform: String, Codable { case ps5, xboxSeries, switch2, pc }

enum ReleaseKind: String, Codable { case dayOne, hotfix, patch, major, silent }

enum Trust: String, Codable { case official, secondary }

enum Verification: String, Codable {
    case official     // a person confirmed it against an official post that names this platform
    case reported     // press only
    case pending      // extracted automatically, not confirmed yet
    case assumed      // a Steam patch with no word on PS5, taken as out on PS5 too (2026-10-27)
}

struct Source: Codable, Identifiable {
    let id: String                 // "rebelwolves-news"
    let kind: Kind                 // studioSite, supportCentre, publisherNews, playstationBlog, steamNews, press
    let url: URL
    let feedURL: URL?
    let platforms: [Platform]      // what this channel covers
    let trust: Trust
    let fetch: FetchMode           // auto, manual
}

struct Game: Codable, Identifiable {
    let id: String                 // our slug
    let igdbID: Int
    let ps5TitleIDs: [String]      // "PPSA01234", one per region; stored for later, never queried
    let sourceIDs: [String]        // registry for this game
}

/// One update as the studio announces it (for example "Update 1.1").
struct Release: Codable, Identifiable {
    let id: String
    let gameID: String
    let displayName: String        // "Update 1.1"
    let kind: ReleaseKind
    let kindBasis: KindBasis       // studio, inferred
    let announcedAt: Date
    let notes: [NoteSection]       // grouped change list
    let sourceIDs: [String]
    let links: ReleaseLinks        // { steamNotes?: URL, ps5Page?: URL }: the Steam post, and the studio's PS5 page for this update
    let platforms: [PlatformRelease]
    // App-facing editorial fields, all optional. The backend may fill them; the app must cope with nil.
    let headline: String?
    let summary: String?
    let keyChanges: [String]?
    let video: URL?
    let videoNote: String?
}

/// Where and when that update is live on one platform.
struct PlatformRelease: Codable {
    let platform: Platform
    let status: Status             // live, announced, notPlanned, unknown
    let version: Field<String>?    // as the platform shows it: "01.004.000"
    let sizeBytes: Field<Int64>?
    let liveAt: Field<Date>?
    let bundles: [String]          // ids of PC-side releases folded into this console patch
    let verification: Verification // confirms the status (that the update is live on this platform); each Field keeps its own tag
}

/// Every fact carries where it came from.
struct Field<T: Codable>: Codable {
    let value: T
    let verification: Verification
    let sourceID: String
    let checkedAt: Date
}

struct NoteSection: Codable {
    let title: String              // "Combat", "Performance", "PS5"
    let items: [NoteItem]
}

struct NoteItem: Codable {
    let text: String
    let platforms: [Platform]?     // nil means every platform; set when an item is console-only or PC-only
    let ps5ProOnly: Bool
    let spoiler: Bool?             // hide behind a tap
}
```

## App rules

- **Released** (counts as new, raises the badge, alerts once): the PS5 `PlatformRelease` has `status == .live` and its `alert.style` is `standard` (verification `official`, `pending`, `assumed`, or `reported` on a release Steam or the studio has). Since 2026-10-27 the app shows no Unconfirmed, "Not confirmed on PS5", "Live on PC" or "PC only so far" wording for these.
- `PlatformRelease.verification` is about the status only. A press-only size or version on an officially confirmed release does not downgrade it: the release stays On PS5 and that field shows a "Reported" tag. Example: Dawnwalker 1.1 is On PS5, and its size is tagged Reported.
- **Press only (no Unconfirmed state)**: live, verification `reported`, and the release has no `links`. The feed gives it no `alert`, the app does not show it, and no push is sent. If Steam or the studio later has it, it is Released and alerts once. Removed in 0.5.0 (Terry's data rule).
- **Coming to PS5**: a PS5 `PlatformRelease` with `status` of `announced` (the studio said consoles get it later). Releases with no PS5 row at all (PC ports, posts before the PS5 release) are not PS5 updates.
- **Not coming to PS5**: `status == .notPlanned`, and only when an official post says so.
- Each release links back to where its notes came from: `links.steamNotes` (the Steam post) and `links.ps5Page` (the studio's own PS5 page for that update, when one is found: an official post that names PS5, or a PS5 or console link in the Steam post). Terry, 2026-10-27; this replaces the earlier no-source-credits rule.
- A release alerts at most once on the user's platform: the standard alert as soon as its PS5 row is live, including a Steam patch taken as out on PS5. A press-only report earns none. A later confirmation does not alert a second time. The feed's `PlatformRelease.alert` says which alert a PS5 row earns.

## Registry file

`registry.json` (next to this spec, and in the repo as `backend/src/sources/registry.json`) holds the shared feeds (PlayStation Blog and the press) and a source list for each game. Each source has `kind` (`rss`, `html`, `steamNews` or `pressIndex`, a press site's paged list of update articles whose matching articles are opened for their facts), `url`, `platforms`, `trust`, `fetch` (`auto` or `manual`) and `ps5Signal`. A `ps5Signal` of `always` means everything in the feed is about PS5, though shared feeds still have to match the game by name. A value of `explicit` means a post counts for PS5 only when its text names "PS5" or "PlayStation 5". The `igdbId` and `ps5TitleIds` fields are filled from the catalogue. Dawnwalker's site blocks automated fetches, so it is `manual`. A game's `aliases` are the other names the press uses ("GTA 5", "Dawnwalker"), and `exclude` lists names that contain it but are other games ("Minecraft Dungeons").

Press articles are read for facts only: the PS5 version, the download size, whether it is live, and when. Their text is never stored or shown. Requests to a site are spaced by its robots.txt `Crawl-delay`.

## Note platforms

Each note item is tagged with the platforms it is about (`NoteItem.platforms`), with the shared rules in `backend/src/ingest/platform-terms.json`. An item that names a PC-only thing (FrameGen, DLSS, AMD or NVIDIA GPUs, Steam Deck, Steam Controller, mouse and keyboard, ultrawide…) is tagged `pc` unless it also names a console. A heading about one platform ("PC", "Steam Deck", "PS5") tags its items. PS5 pages leave out items whose platforms don't include `ps5`. Headlines, summaries, key changes and push lines are shown on PS5 pages and in pushes, so they never carry a PC-only line; the fixture builder fails if one does.

## PS5 version

The PS5 version is the console's `XX.YYY.ZZZ` string. A studio's "Ver. 1.005.000" is the same build with the leading zero dropped, so it is stored as `01.005.000`. In a post that covers several platforms, only a version written next to "PS5" counts. A studio display name ("Update 1.1") or a PC build number is never stored as the PS5 version.

## Backend jobs

1. `registry`: the per-game sources, edited by hand and stored in the repo for now.
2. `poll`: fetches each auto source at most hourly and creates `pending` releases with the extracted notes.
3. `confirm`: a review queue where a person approves a release, which moves it to `official` and triggers push.
4. `press`: matches press reports to existing releases and fills `version` and `sizeBytes` as `reported` when no official value exists.
5. Steam news keeps feeding the PC platform rows, using the existing `fetch-catalog.mjs` logic.

## 0.5.0 guards and alerts (roadmap 11)

- **72-hour guard.** An alert is raised only if its guard date is under 72 h old. A release that is already older is stored as pushed (`pushed_at` set) and sends nothing, for the push job and the app alike. This holds for press-only (`quiet`) reports and every other style.
- **Guard date.** `alert.from` in the feed: the moment a console-later update went live on PS5 (`alert_from`), else the PS5 row's `liveAt`.
- **Consoles later.** A Steam patch whose post says consoles get it later is `announced`; a week after the Steam post the backend takes it as `live` (liveAt stays Steam's date) and sets `alert_from` to that moment, so it earns its one standard alert, once. A rerun does not alert again (the row is no longer `announced`, and `pushed_at` claims the push).
- **Before PS5 launch.** A Steam patch dated before the game's PS5 release creates no PS5 row; it is not released on PS5.

## 0.5.0 upcoming games (roadmap 14)

- Source: IGDB PS5 `release_dates` rows (same date rules and overrides as the PS5 index). `scripts/upcoming.ts` writes `v1/upcoming/<igdbId % 10>.json` and `events.json` daily. Rules live in `src/upcoming.ts`.
- No invented dates: month, quarter and year dates keep their precision, tbd has no date. A game with no PS5 date row at all is not listed.
- A game stays listed 3 days after an exact release date so the release-day event reaches offline devices; older ones drop out, as do vague dates that have passed.

## 0.5.0 PS5 version, checked date, PC-only lines (roadmap 4, 9)

- **PS5 version.** `PlatformRelease.version` for PS5 is only ever read next to "PS5" in a post (or from a PS5-only post), never from a PC build number. A Steam post never fills it; a test covers a PC-only number.
- **Checked date.** Every `Field` carries `checkedAt`. When a fetch reads the same fact again (same value and verification), `checkedAt` moves to that fetch time, so the app can say "checked <date>".
- **PC-only lines.** `NoteItem.pcOnly` is true when a notes line is tagged for PC and no console (Steam Deck, mouse and keyboard, PC graphics, or a PC section). It is a grouping flag on the line inside the Steam notes. It is not a release status: there is still no "PC only" state for a release (Terry, 26 Oct). Lines stored before 0.5.0 are re-tagged on export; the app treats a missing `pcOnly` as false.

## 0.5.0 hot-set schedule (roadmap 11)

- Follows live on devices, so the server does not know which games are followed. The **hot set** is the games with a patch in the last 14 days plus `backend/src/sources/hot-pinned.json`, capped at 12 (`src/hot.ts`).
- A second Actions schedule at :47 runs `npm run ingest -- --hot`: it polls only the hot games' sources (25 minute minimum interval, instead of 55) and skips the shared press sources. The hourly :17 run does everything as before and also uses the 25 minute interval for hot games. Hot games are therefore checked about every 30 minutes; the rest hourly.
- Budget: each hot run takes about 1 to 2 minutes (cached install, up to 12 games), so roughly 1,000 to 1,500 extra Actions minutes a month. The repository is public, so this is free. GitHub may delay scheduled runs, so these are targets, not guarantees.

## 0.5.0 known issues (roadmap 16)

- `src/issues.ts` derives issues from stored notes at export time (no new table): a "Known issues" section or a "Known issue:" line, PC-only lines excluded. Id = hash of game and normalised text.
- A later release addresses an issue when one of its other note lines matches (one contains the other, or at least 70% of the shorter line's words are shared). Relisting it as known keeps it open. The match is a heuristic; a wrong match can be fixed by rewording, and nothing here alters the notes themselves.

## 0.5.0 similar games (roadmap 18)

- `similar[]` in the info shard comes from IGDB `similar_games` (`src/similar.ts`): `{ igdbId, name, coverId? }`, at most 8, unique, never the game itself. It is the weekly info refresh, so it costs no extra IGDB request.

## 0.5.0 news (roadmap 17)

- Allowlist: `backend/src/sources/news-sources.json`. Only the game's own Steam news feed. The PlayStation Blog is not on it (see the open check below). Press sites (Push Square, PlayStation LifeStyle) are facts-only for patches and never feed news.
- Stored: title, date, link (`news` table). Never body text. The source id stays in the database for audit and is not exported. The UI shows no source names or credits.
- Terms: Steam's `ISteamNews` is public and already used.
- Patch posts are not news; they become releases as before.

### Open check before App Store submission: PlayStation Blog terms

The PlayStation Blog's robots.txt allows `/feed/` (Crawl-delay 5), but playstation.com's website terms of use (read 2026-11-03, section on text and data mining) say users shall not use any "robot", "bot", "spider", "scraper" or other automated tool to access, obtain, copy, monitor or republish any portion of the site or its content. It is not clear that a public RSS feed is carved out, or that blog.playstation.com falls under those terms. Until Terry or Theo decides:

- The PlayStation Blog is not used for news headlines, and (below) not polled for patches either.
- It is no longer polled at all: `playstation-blog` in `src/sources/registry.json` is `fetch: manual` (Theo's call, 2026-11-03). Re-enable only with written permission from Sony. Nothing else depends on it: PS5 versions and live times come from studio posts, Steam posts and other allowed sources, and a release's `links.ps5Page` comes from the Steam post or from a studio page, or is added by hand. Data already stored from it stays; it is not refreshed.
- The same terms are why Sony's patch servers and PSN APIs are out (see the top of this file).

## Link-only games and feed health (0.5.0)

Minecraft, Rocket League, Valorant, Fortnite, Astro Bot, Gran Turismo 7, Ghost of Yotei, Wolverine, Alan Wake 2 and Genshin Impact have no readable official patch feed, so they stay link-only: registry `links` give the official site and patch-notes page. Six PS5 games with no history yet pin the official site only; their patch-notes link stays Steam news. See docs/api.md for the run checks.

## Note categories and pcOnly accuracy (0.5.0 item 4)

Checked against the latest patch posts of 22 games on Steam. A heading that names a kind of change (Fixes, Balance, New, Content) sets the category of its items. Under a generic heading ("Changes", "Patch Notes"), an item's own first word decides: Fixed/Resolved is `fixed`, Added/New/Improved/Implemented is `new`, Adjusted/Increased/Reduced/Reworked is `balance`, anything else stays `other`. `pcOnly` held up: PC-specific headings, graphics-driver versions, keybinds and Steam Controller lines tag PC; lines naming a console never do. Stray `[/*]` markup no longer becomes a note item.

## PS4 games that play on PS5 (Terry, 2026-11-06)

A PS4 game plays on PS5 through backward compatibility, so it belongs in the app and its PS4 patch history counts. Its release date line reads "Playable on PS5 since <PS4 launch>" (never "TBA" for a game that has shipped). A PS4 patch is stored on the release's PS5 row (reported, live) and the release carries an optional `ps4: true` in the feed. The app labels such a release "PS4 update"; apps that predate the field show it as an ordinary update. There is no `ps4` platform value (unknown platforms fail the whole decode).

Rule in the press matcher: a post about PS4 only counts for a game with no native PS5 release, or when the post predates that release. After a native PS5 version ships, PS4-only posts are ignored. `dropPreLaunchPs5` never removes a `ps4` release. A PC version number is still never shown as a PS5 version, and a PS4 version is not a PS5 version: the PS5 row's version stays empty for these.

## One patch, one release (0.5.0 duplicate audit)

Audit of the live feed (1,298 releases; the five games with most releases checked first, then every game): no repeated ids, and same-day pairs such as Hotfix 10.4.1 and Update 10.4.0 are distinct patches. One real duplicate: Control Resonant `1.4` (press only) and `1.4.0` (Steam), three hours apart. Cause: the version key was the literal text, so "1.4" and "1.4.0" differed. Now trailing zero parts are ignored when matching (`versionIdentity`: `1.4.0` = `1.4`, `2.0` stays `2.0`), but only within 3 days of the stored release, so Dead by Daylight "Patch 10.2" and "Patch 10.2.0", months apart, stay separate (also checked: 5 other pairs in the feed are months apart). A press report or studio post joins the stored release and adds its source and PS5 facts. `mergeSilentDuplicates` folds a press-only duplicate stored earlier into the real release on each ingest.

## Data trust audit, 2026-11-04 (Priya)

Checked every live PS5 row in the feed (1,487 rows, 1,916 releases, not just a sample of 25) for internal consistency: date against the Steam post, verification against evidence, version never copied from PC. Pattern found: 87 Steam-assumed PS5 rows carried a "went live" date later than their Steam post (Indiana Jones Update 8 by 30 days, Apex by hours). Cause: a second post for the same release replaced the date of an equal-rank non-official field, while the release kept its earliest date. Fix: `liveAt` of an equal-rank non-official field keeps the earliest value (`mergeLiveAt`), and each ingest runs `repairAssumedLiveAt` to move stored rows back to the Steam post's date. Not checked from here: comparison against each studio's own PS5 page (no readable official feed for most games; Quinn's double-check should do that on the shortlist).

**Automatic PS Plus lineup (2026-11-04).** `src/plusAuto.ts` reads Push Square's "PS Plus Essential games for <month> announced" article (found on its `/tags/ps-plus` page, spaced by its Crawl-delay) and stores month, claim window and game names in the `plus_months` table; article text is never kept. The window ends the day before the next lineup ("rotated out ... on 1st December"). `plus.json` still works and overrides a month typed in by hand. Failure leaves what is stored; run with `--hot` skips it.

## PS Plus lineup sources, checked 2026-11-04 (Priya)

Goal: fill `plus.json` automatically (see docs/api.md, PS Plus monthly games). Manual entry stays as the fallback.

| Source | Result |
| --- | --- |
| PlayStation Blog / playstation.com | Website terms bar bots and scrapers. Not used. |
| Push Square | robots.txt allows articles and the public RSS feed (`/feeds/latest`, linked in its footer; Crawl-delay 5). Its terms page (`/terms`) has no bot, scraper or feed clause apart from competition entries. Feed items are teasers; the lineup is in the article page, which robots.txt allows. Candidate, same facts-only rules as the press pipeline: names and dates, text never stored. |
| PlayStation LifeStyle | robots.txt allows everything but `/tag`; its terms not yet read. Possible second source. |
| PSU.com | Cloudflare challenge returns 403 to automated clients. Not used. |
| Wikipedia | The API rate-limited this run (429) and its list pages are not a monthly feed. Not used. |
| IGDB | No PS Plus data. |

Next step: parse the monthly "PS Plus Essential games for <month>" article from Push Square when one is published, fill `plus.json` from it, and keep manual entry as the override. Not built yet: the month's article was not in the feed during this check, so there is no real sample to parse against.

### Push Square patch tag (2026-11-06)

`pushsquare-patches` reads Push Square's `/tags/Patches` list beside `/tags/updates`. The older list is where its PS4-era patch articles live (Assassin's Creed Odyssey 1.0.3 to 1.50, 2018 to 2019), tagged PS4. Same rules as the updates list: facts only, reported, one request per page at the site's Crawl-delay. PS4 posts in it count only for a game that plays on PS5 (no native PS5 release, or the post predates it) and are labelled `ps4`.

### Search aliases in the PS5 index (field `k`, #298)

Each index entry may carry `k`, a list of up to 5 aliases players type: IGDB alternative names plus franchise short forms ("GTA V", "GTA5", "COD: Modern Warfare II", "RDR2", "AC Odyssey", "FF7", "BG3"); built by `src/search-aliases.ts`. The app folds them like the name and matches them after every name match, so a real title always outranks an alias.
