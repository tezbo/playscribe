# Playscribe API v1

Everything is free for now. There are two ways to read the same data:

1. **Static feed (what the app uses).** An hourly GitHub Actions job (`.github/workflows/feed.yml`) polls the sources and publishes JSON to the `feed` branch:
   - Base URL: `https://raw.githubusercontent.com/tezbo/playscribe/feed/v1/`
   - Responses can be up to about 5 minutes stale (GitHub's cache).
2. **Local server (development on the Mac).** `cd backend && npm ci && ADMIN_TOKEN=dev npm start` serves the dynamic API below on `http://localhost:8080`. The simulator can reach it.

Every type below is defined in [ps5-patch-data.md](ps5-patch-data.md). The server adds `revision` and `updatedAt` to `Release`. The app-only fields on `Release` (`headline`, `summary`, `keyChanges`, `video`, `videoNote`) and `NoteItem.spoiler` are not sent yet, so decode them as optional.

`Game` is `{ id, igdbId, name, cover: { imageId, url } | null, artwork: { imageId, url } | null, squareCover: { imageId, url } | null, ps5Release, ps5ReleasePrecision?, ps5TitleIds }`. For the square game tile, use `squareCover` when present: the studio's own square cover from IGDB (`t_720p`), shown as it is. It is rare. Otherwise `artwork` is the studio's official landscape key art from IGDB (textless key art first, then key art with a logo, then plain artwork; never concept art, logos, icons or alternative covers), 1920×1080 `t_1080p`, for the app to centre-crop. When both are null the app fits the portrait cover over a blurred fill. The bundled PS5 index carries them as `s` and `a` (IGDB image ids; build `https://images.igdb.com/igdb/image/upload/t_720p/<s>.jpg` and `…/t_1080p/<a>.jpg`, or `t_720p` for smaller tiles). There is no store tile art: Sony store data is out of bounds. `ps5ReleasePrecision` is `month`, `quarter`, `year` or `tbd` when IGDB has only that (a year-only date is stored as 31 Dec), and is absent for an exact day. The bundled PS5 index carries the same thing as `q` on each game.

A release is **On PS5** only when its `ps5` platform row has `status == "live"` and `verification == "official"`. This rule comes from the app rules in ps5-patch-data.md.

## Static feed

| File | Contents |
|---|---|
| `index.json` | `{ version: 1, updatedAt, games: [Game & { latestReleaseId, releaseCount, updatedAt }] }`. Fetch this first. If `updatedAt` hasn't changed, nothing has. |
| `games/<id>.json` | `{ game: Game, releases: Release[], issues: KnownIssue[] }`, releases newest announcement first. `KnownIssue` is `{ id, text, status: open\|addressed, firstReleaseId, addressedBy?, addressedAt? }`: lines from a "Known issues" section (or a "Known issue:" line) in a release's notes, PC-only lines left out. `id` is a stable hash of the game and the text, so the app can follow it across releases. When a later release lists the same thing among its fixes, `status` becomes `addressed` and `addressedBy`/`addressedAt` name that release: the event for a followed issue (the app alerts once, with the same 72 h guard, using `addressedAt`). A later release that lists it as known again keeps it open. |
| `latest.json` | `{ updatedAt, releases: Release[] }`. The 100 most recently changed releases, for a background refresh check. |
| `info/<n>.json` | `{ games: { [igdbId]: { summary?, storyline?, genres?, firstRelease?, videos?: [{ youtubeId, name }], links?: { official?, patchNotes? } } } }`, where `n` is `igdbId % 100`. The basics for every game in the bundled PS5 catalogue, tracked or not, so no game page is ever blank: description, genres, first release, and YouTube videos with the launch trailer first. `links.official` is the game's official website; `links.patchNotes` is the page its patch notes are posted on (the studio's PS5 news page where we have one, else its Steam news, never for a separate PC port). Both open in the default browser. Refreshed weekly. With no patch history, a game page leads with its release (date from the PS5 index) and these. |
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
   - `PATCH /v1/devices/me` `{ apnsToken?, environment?, locale? }` when the token changes (call it on every launch after `didRegisterForRemoteNotificationsWithDeviceToken`). `apnsToken: null` stops pushes.
   - `GET /v1/devices/me/follows` → `{ follows: [{ gameId, notify }] }`
   - `PUT /v1/devices/me/follows` `{ follows: [...] }` replaces the whole list. → `{ follows, unknown }`
   - `DELETE /v1/devices/me` → `204`

Errors are `{ error: "<message>" }` with 400, 401 (bad or missing device key), 404 or 503.

## Push (parked)

Sent once per release, when its PS5 row becomes live, to followers whose `notify` allows it. Releases more than 72 hours old by then do not push. Every live row gets the same push; `verification` says what told us (`official`, `reported`, `pending` or `assumed`):

```json
{
  "aps": {
    "alert": { "title": "The Blood of Dawnwalker", "body": "Update 1.1 is out on PS5 (version 01.004.000). See what changed." },
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

- `NoteItem.pcOnly: boolean` marks a notes line that is only about PC. The app may fold these lines into a group; it never turns a release into "PC only".
- `Field.checkedAt` is the time of the latest fetch that read the fact. PS5 `version` is never a PC number.
