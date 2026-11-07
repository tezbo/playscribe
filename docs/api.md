# Playscribe API v1

Everything is free for now. There are two ways to read the same data:

1. **Static feed (what the app uses).** An hourly GitHub Actions job (`.github/workflows/feed.yml`) polls the sources and publishes JSON to the `feed` branch:
   - Base URL: `https://raw.githubusercontent.com/tezbo/playscribe/feed/v1/`
   - Responses can be up to about 5 minutes stale (GitHub's cache).
2. **Local server (development on the Mac).** `cd backend && npm ci && ADMIN_TOKEN=dev npm start` serves the dynamic API below on `http://localhost:8080`. The simulator can reach it.

Every type below is defined in [ps5-patch-data.md](ps5-patch-data.md). The server adds `revision` and `updatedAt` to `Release`. The app-only fields on `Release` (`headline`, `summary`, `keyChanges`, `video`, `videoNote`) and `NoteItem.spoiler` are not sent yet, so decode them as optional.

`Game` is `{ id, igdbId, name, cover: { imageId, url } | null, artwork: { imageId, url } | null, squareCover: { imageId, url } | null, ps5Release, ps5ReleasePrecision?, ps5TitleIds }`. For the square game tile, use `squareCover` when present: the studio's own square cover from IGDB (`t_720p`), shown as it is. It is rare. Otherwise `artwork` is the studio's official landscape key art from IGDB (textless key art first, then key art with a logo, then plain artwork; never concept art, logos, icons or alternative covers), 1920×1080 `t_1080p`, for the app to centre-crop. When both are null the app fits the portrait cover over a blurred fill. The bundled PS5 index carries them as `s` and `a` (IGDB image ids; build `https://images.igdb.com/igdb/image/upload/t_720p/<s>.jpg` and `…/t_1080p/<a>.jpg`, or `t_720p` for smaller tiles). There is no store tile art: Sony store data is out of bounds. `ps5ReleasePrecision` is `month`, `quarter`, `year` or `tbd` when IGDB has only that (a year-only date is stored as 31 Dec), and is absent for an exact day. The bundled PS5 index carries the same thing as `q` on each game. **Early Access before a later 1.0:** when IGDB lists a PS5 row with status Early Access ahead of a later Full Release row (Advanced Access, Beta and Alpha do not count), `ps5Release` is the first playable day, not the 1.0 day. While the 1.0 is still ahead `Game` also carries `eaSince` (the first playable day, same as `ps5Release`) and `fullRelease` (the 1.0 day); both are absent once the 1.0 day arrives or when there is no such pair. The app shows them on separate lines, "Early access since 22 Jan 2024" and "Full release 3 Mar 2027", never "TBA", and the game sits in Playing, not Upcoming, because its PS5 row is live. The bundled index carries the same pair as `ea` and `fr` on each game, with `d` the first playable day; the index is static, so the app treats `ea`/`fr` as live only while `fr` is after today. Dates are UTC days. Hand-set dates in `scripts/ps5-date-overrides.json` win (Minecraft and MultiVersus are set there because their IGDB Early Access rows are a console announcement and a 2022 beta of a rebuilt game).

A release is **On PS5** only when its `ps5` platform row has `status == "live"` and `verification == "official"`. This rule comes from the app rules in ps5-patch-data.md.

## Static feed

| File | Contents |
|---|---|
| `index.json` | `{ version: 1, updatedAt, games: [Game & { latestReleaseId, releaseCount, updatedAt }] }`. Fetch this first. If `updatedAt` hasn't changed, nothing has. |
| `games/<id>.json` | `{ game: Game, releases: Release[], issues: KnownIssue[] }`, releases newest announcement first. `KnownIssue` is `{ id, text, status: open\|addressed, firstReleaseId, addressedBy?, addressedAt? }`: lines from a "Known issues" section (or a "Known issue:" line) in a release's notes, PC-only lines left out. `id` is a stable hash of the game and the text, so the app can follow it across releases. When a later release lists the same thing among its fixes, `status` becomes `addressed` and `addressedBy`/`addressedAt` name that release: the event for a followed issue (the app alerts once, with the same 72 h guard, using `addressedAt`). A later release that lists it as known again keeps it open. |
| `latest.json` | `{ updatedAt, releases: Release[] }`. The 100 most recently changed releases, for a background refresh check. |
| `news/<id>.json` | `{ items: [{ gameId, title, date, url, verification }] }`, newest first, at most 20, for one tracked game. Headlines only: title, date and a link that opens in the browser. Never article text, and never a source name or credit (the UI shows none). Official non-patch posts from the game's own Steam news (`verification: official`), plus headlines from Push Square's public RSS that name a tracked game (`verification: reported`, Terry's yes 2026-11-05); no other press site and not the PlayStation Blog. Show Reported items with the Reported tag; the title, date and link are all we keep. |
| `info/<n>.json` | `{ games: { [igdbId]: { summary?, storyline?, genres?, firstRelease?, videos?: [{ youtubeId, name }], links?: { official?, patchNotes? }, similar?: [{ igdbId, name, coverId? }] } } }`, where `n` is `igdbId % 100`. The basics for every game in the bundled PS5 catalogue, tracked or not, so no game page is ever blank: description, genres, first release, and YouTube videos with the launch trailer first. `links.official` is the game's official website; `links.patchNotes` is the page its patch notes are posted on (the studio's PS5 news page where we have one, else its Steam news, never for a separate PC port). Both open in the default browser. `similar` is IGDB's similar games for the "Similar games" row: at most 8, never the game itself; `coverId` is an IGDB image id (`t_720p`). Refreshed weekly. With no patch history, a game page leads with its release (date from the PS5 index) and these. |
| `upcoming/<n>.json` | `{ games: { [igdbId]: { igdbId, name, date?, datePrecision: day\|month\|quarter\|year\|tbd, status: announced\|dated\|released, coverId? } } }`, where `n` is `igdbId % 10`. PS5 games with an upcoming (or just-released) PS5 date, from IGDB's PS5 release dates only, for the watchlist. `date` is the last day of the period for month, quarter and year, and absent for tbd; a vague date is never turned into a day. `status`: `dated` (exact day ahead), `released` (exact day reached; kept 3 days), `announced` (vague or no date). Refreshed daily. |
| `upcoming/events.json` | `{ today, releaseDay: [{ igdbId, name, date }] }`. The release-day event: games whose exact day came in the last 72 hours. The app alerts once per followed game (its local alert follows the same 72 h guard as other alerts); there is no server push for upcoming games, since follows are held on the device. |
| `review.json` | `{ items }`. Open review items (see Admin). This is for people, not the app. |

Without push (it needs the paid Apple Developer Program), the app tells players itself:
1. On launch and in a `BGAppRefreshTask`, it fetches `latest.json`.
2. It posts a local notification for each release of a followed game whose PS5 `PlatformRelease` has an `alert` it has not alerted for yet. `alert.style` is `standard` for every update live on PS5, including a Steam patch taken as out on PS5 (verification `assumed`). A release only the press reports (no Steam post or studio page in `links`) has no `alert`, is not shown, and alerts once Steam or the studio has it. One alert per release id, ever. Like the server, it skips releases whose `alert.from` (when absent, `liveAt`) is more than 72 hours old. `alert.from` is the moment a console-later update went live on PS5, so such an update alerts when it goes live even though Steam posted it a week earlier.
3. That notification uses the same content and `userInfo` (`gameId`, `releaseId`, `verification`, `tag`) as the push payloads below.

To test the notification UI in the simulator: `xcrun simctl push booted co.codeconnectors.playscribe docs/sample-push.apns`.

Games covered: the registry games (`backend/src/sources/registry.json`). Covering a new game takes one entry added to the registry.

## Local server: reading

| Call | Returns |
|---|---|
| `GET /v1/health` | `{ ok, time }` |
| `GET /v1/feed?games=dawnwalker,kcd2&since=<cursor>` | `{ releases: Release[], cursor }`. Releases that changed after `since`, newest announcement first, at most 200. |
| `GET /v1/games/:id` | `Game` |
| `GET /v1/games/:id/releases?limit=50` | `{ releases: Release[] }` |
| `GET /v1/releases/:id` | `Release` (ids look like `dawnwalker@1.1`) |
| `GET /v1/games/search?q=dawn` | `{ games: [{ igdbId, name, cover, ps5Release }] }`. Returns 503 without Twitch keys. The app searches its bundled PS5 index instead. |

## Device and follows (parked until push is paid for)

These only matter once APNs is on. For now the app keeps follows on the device.


1. `POST /v1/devices` with
   ```json
   { "apnsToken": "<hex>", "environment": "sandbox", "locale": "en-GB",
     "follows": [{ "gameId": "dawnwalker", "notify": "all" }, { "igdbId": 119171, "notify": "major" }] }
   ```
   `environment` is `sandbox` for Xcode debug builds and `production` for TestFlight and the App Store. `apnsToken` may be left out until the user allows notifications. A follow names our `gameId` or an `igdbId` from the app's PS5 index; the server adds unknown IGDB games on the fly. `notify` is `all`, `major` (major updates only) or `off`.
   Response `201`: `{ deviceId, deviceKey, follows, unknown }`. Keep `deviceKey` in the Keychain; it is shown once.
2. Every later call sends `Authorization: Bearer <deviceKey>`.
   - `PATCH /v1/devices/me` `{ apnsToken?, environment?, locale?, quietHours? }` when the token changes (call it on every launch after `didRegisterForRemoteNotificationsWithDeviceToken`). `apnsToken: null` stops pushes.
   - `quietHours` is `{ from, until, timeZone }` (minutes since midnight, `from` may be after `until` to cross midnight, IANA zone) or `null` for none. Inside the window the relay sends `interruption-level: passive` and no `sound`; outside it, or when absent, nothing changes. The app sends it on every change, on launch and after registering.
   - `GET /v1/devices/me/follows` → `{ follows: [{ gameId, notify }] }`
   - `PUT /v1/devices/me/follows` `{ follows: [...] }` replaces the whole list. → `{ follows, unknown }`
   - `DELETE /v1/devices/me` → `204`. Forgets this device: the relay removes the record, APNs token, key and team entry, so the Feed job no longer sees it. Call it when the player switches update alerts off for good or resets the app, then drop the stored `deviceKey`. On the relay a key it no longer knows is also `204` (already gone), so any `204` means done; a missing Authorization header is `401`. Registering again later creates a new device.

Errors are `{ error: "<message>" }` with 400, 401 (bad or missing device key), 404 or 503.

## Push (parked)

Sent once per release, when its PS5 row becomes live, to followers whose `notify` allows it. Releases more than 72 hours old by then do not push. Every live row gets the same push; `verification` says what told us (`official`, `reported`, `pending` or `assumed`):

```json
{
  "aps": {
    "alert": { "title": "The Blood of Dawnwalker: 4 new, 9 fixed", "body": "Update 1.1: Added photo mode" },
    "sound": "default", "thread-id": "dawnwalker", "interruption-level": "active", "relevance-score": 1
  },
  "gameId": "dawnwalker", "releaseId": "dawnwalker@1.1", "kind": "major", "verification": "official"
}
```

A release only the press reports (no Steam post, no studio page) gets no push and no `alert`; there is no Unconfirmed state. It alerts, once, if Steam or the studio later has it.

A later confirmation does not push again.

`apns-collapse-id` is the release id. Topic: `co.codeconnectors.playscribe`.

## Admin (review queue)

On the free setup, people work the review queue from GitHub. Go to Actions → Feed → Run workflow and pick an action:
- `confirm` with a release id and the official source you checked. This makes it official.
- `dismiss` with a review item id from `review.json`.
- `backfill` with a since date reads each source's history: the last 100 Steam posts per game and the press update list back to that date. It runs for up to three hours because the press site asks for 5 seconds between requests.

The local server has the same operations under `/v1/admin`, with `Authorization: Bearer <ADMIN_TOKEN>`.

| Call | What it does |
|---|---|
| `GET /review` | Open review items: official posts awaiting confirmation, Steam posts that mention PS5, and patch links found on news pages. Each carries its release. |
| `POST /releases/:id/platforms/:platform/confirm` | `{ sourceId, status?, version?, sizeBytes?, liveAt?, bundles?, push? }`. A person has checked the official post. Makes the row and its pending facts official, closes the release's review items and, for `ps5`, sends the push (`push: false` marks it sent without sending). `version` must be the console form `XX.YYY.ZZZ`. |
| `POST /review/:id/dismiss` | Closes an item that isn't a PS5 release. |
| `POST /releases` | `{ gameId, title, announcedAt, sourceId, url?, body?, platforms? }`. Manual entry for sources the registry marks `fetch: manual`, such as Dawnwalker's site. Rows start `pending`. |
| `POST /ingest?force=1` | Polls now. Sources still honour robots.txt and stay off after a 403. |
| `GET /sources` | Last poll time, status and error per source. |

## 0.5.0 additions: notes lines and checked date

- `NoteItem.category: new|fixed|balance|other` is the kind of change a notes line is, derived from its Steam section title ("New Features", "Bug Fixes", "Balance Changes"…); `other` when the title says nothing. Missing in older data: treat as `other`. Fixes win when a title says both.
- `Release.ps4: true` (optional, absent otherwise) marks a PS4 patch for a game that plays on PS5 through backward compatibility. Label it "PS4 update"; the release still has a PS5 row (live, reported) with no version. Older apps ignore the key.
- `NoteItem.pcOnly: boolean` marks a notes line that is only about PC. The app may fold these lines into a group; it never turns a release into "PC only".
- `Field.checkedAt` is the time of the latest fetch that read the fact. PS5 `version` is never a PC number.

## Feed health and data quality (0.5.0)

Each ingest run reports a source that has failed three polls in a row (`source_state.fail_streak`) as an error annotation and in the workflow summary. After export it checks the feed: a PC version is never the PS5 version, no source names appear in user-facing text, and every game in `v1/index.json` has a release or an official link. A failed check fails the run before the feed is published. Games with no readable official source carry `links` in `sources/registry.json` (official site, patch-notes page), which overrides IGDB's in `info/<n>.json`.

## Release digest: "Since you last looked" (0.5.0, roadmap item 6)

Every `Release` in `latest.json` and `games/<id>.json` carries `digest: { new, fixed, balance, other, ps5, topNew? }`, derived from its notes on read. The counts cover lines a PS5 player can use (PC-only lines are left out); `ps5` is how many name PS5 or PS5 Pro. `topNew` (at most 3 lines, each 120 characters or fewer) is present only when the headings are clean: the lines sit under a heading that names new content and make up most of the release's new lines. Otherwise show counts only. There is no download size (too few releases carry one). The catch-up screen sums `digest` over the releases newer than the player's last visit. Additive: the 0.2.0 app ignores it.

## Every event the feed can raise (0.5.0)

The app holds follows on the device and reads static JSON, so an "event" is a change it detects in a file it already fetches. Nothing is pushed from the server while push is parked.

| Event | Where it appears | Fields the app reads | When it fires | 72 h rule |
|---|---|---|---|---|
| **Update live on PS5** | `latest.json`, `games/<id>.json`: a release whose PS5 `PlatformRelease` has `alert` | `alert.style` (`standard`), `alert.from`, `liveAt`, `verification` (`official`, `assumed`, `reported`), release `id`, `gameId`, `kind`, `displayName`, `notes` | A followed game gains a PS5 row with `status: live` and an `alert` the device has not alerted for. One alert per release id, ever. A press-only report has no `alert`. | Skipped when `alert.from` (else `liveAt`) is over 72 h old. The release is then marked read. |
| **Console-later update goes live** | Same release, later: PS5 `status` moves `announced` to `live`, `alert` appears | `alert.from` = the moment it went live (about a week after Steam), `liveAt` stays Steam's date | A Steam post said consoles get it later; a week on the backend takes it as live | Counted from `alert.from`, so it alerts once, on time, though Steam posted it earlier. |
| **Notes revised** | Same release `id`, higher `revision` and new `updatedAt` | `revision`, `notes` | A source edits its post | No alert. The app refreshes the page. |
| **PS5 fact confirmed** | Same release: PS5 `verification` moves to `official` or `reported` | `version`, `sizeBytes`, `verification` | A studio post or person confirms | No alert (the update alerted when it went live). |
| **Known issue opened or addressed** | `games/<id>.json` `issues[]` | `id` (stable), `text`, `status` (`open`, `addressed`), `firstReleaseId`, `addressedBy`, `addressedAt` | An issue appears in a release's "Known issues"; a later release's fixes mention it | Proposed for the app (not built yet): alert a followed issue once when `addressedAt` is within 72 h; an older one just shows as addressed. |
| **Release day** | `upcoming/events.json` `releaseDay[]` (and `upcoming/<n>.json` `status: released`) | `igdbId`, `name`, `date` | A followed upcoming game's exact PS5 date has come | Listed while the date is within 72 h (kept 3 days); the app should alert once per game (not built yet). |
| **Release date firmed or moved** | `upcoming/<n>.json` entry changes `datePrecision` or `date` | `date`, `datePrecision` (`day`, `month`, `quarter`, `year`, `tbd`), `status` (`announced`, `dated`, `released`) | IGDB's PS5 date gains or changes precision | No alert; shown on the watchlist. A vague date is never turned into a day. |
| **News headline** | `news/<id>.json` | `title`, `date`, `url` (opens in the browser) | A new item for a tracked game | Headlines only, no alert. |

`checkedAt` on every `Field` moves whenever a fetch re-reads the same fact, so "checked <date>" advances without any of the events above.

## Contract with the 0.2.0 app

`src/contract.ts` encodes every place the 0.2.0 Swift decoders throw (unknown `Platform`, `ReleaseKind`, `KindBasis`, `PlatformStatus`; wrong types; missing `id`, `gameId`, `displayName`, `kind`, `announcedAt`, `notes`, `sourceIds`, `platforms`; unparseable dates or URLs; a null `latest.json` `updatedAt`). Unknown extra keys are safe. After export, `latest.json` and `games/<id>.json` are checked and a failure stops the run before publish; `info/<n>.json` problems are warnings, since one bad URL stops the app decoding that whole shard. Rules are refreshed from the Swift models when the oldest app in use changes. It found a live bad URL in `info/38.json` (an IGDB website with a space), now filtered when the shard is built.

## Upcoming entries: never blank, and date moves (0.5.0)

Each `upcoming/<n>.json` entry also carries, when IGDB has them: `summary` (cut to 300 characters at a word, ends with an ellipsis), `genres` (at most 3), `trailerId` (a YouTube id; a video named like a trailer, else the first), and `hypes` (IGDB's count of people waiting; a sort key for "Coming to PS5", never shown). A game that is not in the bundled catalogue therefore opens with a description and a trailer, not a blank page.

`move`, `{ kind: delayed|earlier|dated, previousDate?, previousPrecision, movedAt }`, is present for 14 days after a real change in the date, found by comparing with the previous run: a later day, or an exact day that became vague or tbd, is `delayed`; an earlier exact day is `earlier`; a vague or tbd date that became an exact day is `dated`. A vague date that only narrows ("Q4" to "November") is not a move. Show it as "Delayed from March" or "Now dated"; the app has no need to store anything.

### Push alert payload: digest counts (r050-richer-alerts)

Alert copy (Iris): counts in the title, body `Update <version>: <headline>`, where `<version>` is the release's display name ("Update 1.1"), the same label the app's local alert uses, never a PC version, and `<headline>` is the digest's first `topNew` line: text before any colon, at most 60 characters, cut at a word boundary with an ellipsis only when cut. Title is `<Game>: 3 new, 12 fixed, 2 balance, 1 PS5-only` (zero counts left out), or just the game name when there is nothing to count. The headline is the digest's first `topNew` line. When it is missing (poor headings), the body is the counts line (`3 new, 12 fixed.`), or `A new update is out` when there is nothing to count. The payload also carries `digest: {new, fixed, balance, ps5}` beside `gameId`, `releaseId`, `kind`, `verification`. The 72-hour guard and once-only claim are unchanged.

### Quiet hours on the relay (r050-quiet-hours-push)

`POST /v1/devices` and `PATCH /v1/devices/me` accept `quietHours: { from, until, timeZone } | null` (whole minutes after local midnight, `from` may be after `until` to cross midnight, IANA zone; `from == until` or an unknown zone is a 400; `null` clears; an absent field leaves it as is). Stored as three columns on the device: a window and a zone, no identity, and the zone (not an offset) so daylight saving is right. When a push is sent, a device whose local time is inside `[from, until)` gets `interruption-level: passive` and no `sound`; the copy, `thread-id`, 72-hour guard and once-only claim are unchanged. A device with no window behaves as before.

### PS Plus monthly games: `v1/plus.json` (r050-plus-card)

Hand-curated, never fetched: playstation.com's terms bar automated access, so a person (Ezra) types the month's lineup from Sony's public announcement into `backend/src/sources/plus.json` once a month. Names and dates only, no copied text. The export validates it (a bad file fails the run) and publishes it unchanged:

```json
{ "version": 1, "months": [
  { "month": "2026-11", "from": "2026-11-04", "until": "2026-12-01",
    "games": [ { "name": "Some Game" }, { "name": "Another", "gameId": "kcd2" } ] } ] }
```

`months` is newest first. `from` and `until` are the first and last day the lineup can be claimed (dates, inclusive). `gameId` is set only when the game is one the app tracks, so the card can link to its page. `coverId` (optional) is an IGDB image id for a title the app's bundled PS5 index has no cover for; the card shows it as the game's cover, and shows the name plate when there is none. **A cover must match the exact product, or the field is empty and the app draws the name plate** (Iris): never a nearby game's art, so a bundle like "Tomb Raider 4-6 Remastered", which IGDB lists only as three separate games, has no `coverId` until official bundle art exists. A title in the index always uses the index's cover. The export fills `coverId` itself for any lineup game without one (typed or auto-read months), by exact title match against IGDB's PS5 games (roman numerals count as digits, so "Resident Evil 4" matches an IGDB entry named "Resident Evil IV"); the answer is remembered, and a title IGDB cannot match keeps the name plate. The app shows the card for the month whose window contains today (or the newest month inside its last 3 days as "Last chance") and hides it when `months` is empty or none matches. Decoders must ignore unknown keys.
