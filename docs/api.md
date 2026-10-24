# Playscribe API v1

Base URL: `https://playscribe-api.fly.dev` (once deployed). JSON in and out. Times are ISO 8601 UTC. Every type below is the one in [ps5-patch-data.md](ps5-patch-data.md); the server adds `revision` and `updatedAt` to `Release`. The app-only fields on `Release` (`headline`, `summary`, `keyChanges`, `video`, `videoNote`) and `NoteItem.spoiler` are not sent yet, so decode them as optional.

## Reading

| Call | Returns |
|---|---|
| `GET /v1/health` | `{ ok, time }` |
| `GET /v1/feed?games=dawnwalker,kcd2&since=<cursor>` | `{ releases: Release[], cursor }`. Releases that changed after `since`, newest announcement first, at most 200. Store `cursor` and send it next time. Leave `since` out for a full sync. |
| `GET /v1/games/:id` | `Game` |
| `GET /v1/games/:id/releases?limit=50` | `{ releases: Release[] }` |
| `GET /v1/releases/:id` | `Release` (ids look like `dawnwalker@1.1`) |
| `GET /v1/games/search?q=dawn` | `{ games: [{ igdbId, name, cover, ps5Release }] }`, PS5 games from IGDB. 503 until IGDB keys are set on the server. |

`Game` is `{ id, igdbId, name, cover: { imageId, url } | null, ps5Release, ps5TitleIds }`.

What the app shows follows the app rules in ps5-patch-data.md: a release is **On PS5** only when its `ps5` platform row has `status == "live"` and `verification == "official"`.

## Device and follows

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

## Push

Sent once per release, when its PS5 row becomes live and official, to followers whose `notify` allows it. Releases more than 72 hours old by the time they are confirmed do not push.

```json
{
  "aps": {
    "alert": { "title": "The Blood of Dawnwalker", "body": "Update 1.1 is out on PS5 (version 01.004.000). See what changed." },
    "sound": "default", "thread-id": "dawnwalker", "interruption-level": "active", "relevance-score": 1
  },
  "gameId": "dawnwalker", "releaseId": "dawnwalker@1.1", "kind": "major"
}
```

`apns-collapse-id` is the release id. Topic: `co.codeconnectors.playscribe`.

## Admin (review queue)

All under `/v1/admin`, with `Authorization: Bearer <ADMIN_TOKEN>`.

| Call | What it does |
|---|---|
| `GET /review` | Open review items: official posts awaiting confirmation, Steam posts that mention PS5, and patch links found on news pages. Each carries its release. |
| `POST /releases/:id/platforms/:platform/confirm` | `{ sourceId, status?, version?, sizeBytes?, liveAt?, bundles?, push? }`. A person has checked the official post. Makes the row and its pending facts official, closes the release's review items and, for `ps5`, sends the push (`push: false` marks it sent without sending). `version` must be the console form `XX.YYY.ZZZ`. |
| `POST /review/:id/dismiss` | Closes an item that isn't a PS5 release. |
| `POST /releases` | `{ gameId, title, announcedAt, sourceId, url?, body?, platforms? }`. Manual entry for sources the registry marks `fetch: manual`, such as Dawnwalker's site. Rows start `pending`. |
| `POST /ingest?force=1` | Polls now. Sources still honour robots.txt and stay off after a 403. |
| `GET /sources` | Last poll time, status and error per source. |
