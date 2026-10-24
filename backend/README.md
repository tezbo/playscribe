# Playscribe backend

Polls official patch sources, keeps releases in the model from [docs/ps5-patch-data.md](../docs/ps5-patch-data.md), holds a review queue where a person confirms PS5 releases, and sends APNs pushes. API: [docs/api.md](../docs/api.md).

TypeScript on Node 22, run directly with `tsx`. Storage is one SQLite file (`node:sqlite`, no native modules). It costs nothing to run. An hourly GitHub Actions job polls the sources and publishes a static JSON feed to the `feed` branch (see [docs/api.md](../docs/api.md)). The same code also runs as a local server for development.

```
src/
  sources/registry.json   per-game official sources (hand-edited)
  ingest/adapters.ts      Steam news, RSS/Atom feeds, news-page links
  ingest/classify.ts      release names, kinds (dayOne/hotfix/patch/major/silent), console version and size
  ingest/notes.ts         post body → NoteSection[]
  ingest/pipeline.ts      the poll job and its PS5 rules
  ingest/igdb.ts          catalogue and search (server-side only)
  confirm.ts              the person-confirm step
  push/apns.ts            HTTP/2 + ES256 token auth
  push/notify.ts          who gets a push, once per release
  server.ts               HTTP API
```

## Run locally

```sh
npm ci
npm test
NODE_USE_ENV_PROXY=1 npm run ingest        # one poll into ./data/playscribe.db
ADMIN_TOKEN=dev npm start                  # API on :8080, polls hourly
npm run confirm -- dawnwalker@1.1 --source dawnwalker-news --version 01.004.000
```

## Configuration

| Variable | |
|---|---|
| `TWITCH_CLIENT_ID`, `TWITCH_CLIENT_SECRET` | IGDB (Twitch Confidential app). Without them search and IGDB lookups are off; polling still works. |
| `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_KEY_P8` | APNs token auth. `APNS_KEY_P8` is the .p8 file as base64 (`base64 -i AuthKey_X.p8`). |
| `APNS_TOPIC` | Bundle id, default `co.codeconnectors.playscribe` |
| `ADMIN_TOKEN` | Bearer token for `/v1/admin` (`openssl rand -base64 32`) |
| `DATABASE_PATH` | Default `./data/playscribe.db`. The feed job keeps it at `state/playscribe.db` on the `feed` branch. |
| `INGEST_INTERVAL_MINUTES` | Local server only, default 30. Each source is polled at most once an hour, whatever this is set to. |
| `PUSH_ENABLED` | `1` turns APNs on. Off by default, because APNs needs the paid Apple Developer Program. |
| `PUSH_MAX_AGE_HOURS` | Default 72 |

## The free feed

`.github/workflows/feed.yml` runs at 17 minutes past every hour. Each run:
1. Restores `state/playscribe.db` from the `feed` branch.
2. Polls the sources.
3. Writes `v1/*.json`.
4. Force-pushes the branch as a single commit, so it never grows.

Running it by hand (Actions → Feed → Run workflow) gives three actions: `poll`, `confirm` (the person-confirm step) and `dismiss`.

Optional repository secrets:
- `TWITCH_CLIENT_ID` and `TWITCH_CLIENT_SECRET` add covers and PS5 release dates from IGDB.
- When the Apple Developer Program is paid for, set `PUSH_ENABLED=1` (repository variable) and the `APNS_*` secrets.

GitHub turns off scheduled workflows after 60 days without repository activity. If the feed goes quiet, re-enable it from the Actions tab.

## Rules the code keeps

- Only an official source that names PS5 creates a PS5 row, and only as `pending`. Press creates `reported` facts. Steam never touches PS5; a PS5 mention there becomes a review item.
- Confirmation by a person is the only way to `official`, and the only thing that pushes. A release pushes once, ever.
- Each source is polled at most hourly with a descriptive User-Agent. robots.txt and 403/401 switch a source off until the registry says otherwise; nothing works around a block.
- Sony patch servers, PS Store APIs and PSN are not used.
