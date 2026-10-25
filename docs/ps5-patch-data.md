# PS5 patch data: sourcing and data model

Decided 2026-10-24 by the PS5 patching lead. This is the contract for the iOS app and the backend.

## Sourcing decision

1. **Official sources only can mark something "On PS5".** Per game, keep a registry of the official channels: studio or publisher patch posts that name PS5, studio support centres, publisher newsrooms, and PlayStation Blog.
2. **PlayStation press (Push Square, PlayStation LifeStyle) is secondary.** It is often first with a PS5 version and download size. A press-only fact shows as "Reported", never as confirmed.
3. **Steam news stays as the PC signal only.** A PC post never sets PS5 status, and a PC version number is never copied to PS5. PS5 builds carry their own version numbers.
4. **Sony's patch servers: not used.** The title-update lookup needs a request signature derived from a key taken out of console firmware. PlayStation's Software Usage Terms forbid getting around authentication safeguards and gaining unauthorised access to PSN services. This is closed and is not a question for Terry. Revisit only if Sony offers a partner programme.
5. **Also not used:** ProsperoPatches and similar trackers (private, bot-protected API), PlayStation Store pages (they have no game version), PSN APIs (they need NPSSO, which is ruled out), and any scraping that playstation.com terms s.10 bans.

**Fetching rules for the backend:** prefer RSS, Atom or JSON feeds. Respect robots.txt and each site's terms. Poll each source at most once an hour, with a descriptive User-Agent. If a site returns 403 to automated fetches, mark the source `manual` and don't work around the block.

**Verification:** extraction can be automated, with Claude summarising the post into notes. A release only reaches `official` after a person confirms that the post names PS5. Until then it is `pending` and hidden from push notifications.

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

- **On PS5** (counts as new, raises the badge, can push): the PS5 `PlatformRelease` has `status == .live` and its verification is `official`.
- `PlatformRelease.verification` is about the status only. A press-only size or version on an officially confirmed release does not downgrade it: the release stays On PS5 and that field shows a "Reported" tag. Example: Dawnwalker 1.1 is On PS5, and its size is tagged Reported.
- **Reported on PS5** (shown, no push): the status verification is `reported`. Show a "Reported" tag and no version unless the press gave one.
- **PC only so far** (collapsed group, keep the current prototype copy): no PS5 `PlatformRelease`, or one with `status` of `announced` or `unknown`.
- **Not coming to PS5**: `status == .notPlanned`, and only when an official post says so.
- Sources stay in the data and out of the UI, as Terry asked. The verification tag is the only signal shown.
- Push notifications fire only when a release reaches `official` on the user's platform. A release that later upgrades from `reported` to `official` does not push a second time.

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
