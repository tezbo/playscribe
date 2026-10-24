# Playscribe backend

Polls official patch sources, keeps releases in the model from [docs/ps5-patch-data.md](../docs/ps5-patch-data.md), holds a review queue where a person confirms PS5 releases, and sends APNs pushes. API: [docs/api.md](../docs/api.md).

TypeScript on Node 22, run directly with `tsx`. Storage is one SQLite file (`node:sqlite`, no native modules). Hosting is one Fly.io machine with a volume.

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
```

## Configuration

| Variable | |
|---|---|
| `TWITCH_CLIENT_ID`, `TWITCH_CLIENT_SECRET` | IGDB (Twitch Confidential app). Without them search and IGDB lookups are off; polling still works. |
| `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_KEY_P8` | APNs token auth. `APNS_KEY_P8` is the .p8 file as base64 (`base64 -i AuthKey_X.p8`). |
| `APNS_TOPIC` | Bundle id, default `co.codeconnectors.playscribe` |
| `ADMIN_TOKEN` | Bearer token for `/v1/admin` (`openssl rand -base64 32`) |
| `DATABASE_PATH` | Default `./data/playscribe.db`; `/data/playscribe.db` on Fly |
| `INGEST_INTERVAL_MINUTES` | Default 30 locally, 60 on Fly. Each source is polled at most hourly whatever this says. |
| `PUSH_MAX_AGE_HOURS` | Default 72 |

## Deploy (Fly.io)

One-time, from `backend/`:

```sh
fly launch --no-deploy --copy-config --name playscribe-api
fly volumes create playscribe_data --size 1 --region lhr
fly secrets set ADMIN_TOKEN=... TWITCH_CLIENT_ID=... TWITCH_CLIENT_SECRET=... APNS_KEY_ID=... APNS_TEAM_ID=... APNS_KEY_P8="$(base64 -i AuthKey_X.p8)"
fly tokens create deploy -x 999999h        # put this in the GitHub secret FLY_API_TOKEN
```

After that every merge to main that touches `backend/` deploys through `.github/workflows/backend.yml`, then checks `/v1/health`.

## Rules the code keeps

- Only an official source that names PS5 creates a PS5 row, and only as `pending`. Press creates `reported` facts. Steam never touches PS5; a PS5 mention there becomes a review item.
- Confirmation by a person is the only way to `official`, and the only thing that pushes. A release pushes once, ever.
- Each source is polled at most hourly with a descriptive User-Agent. robots.txt and 403/401 switch a source off until the registry says otherwise; nothing works around a block.
- Sony patch servers, PS Store APIs and PSN are not used.
