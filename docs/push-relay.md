# Push relay

Server push needs something always on to receive each phone's APNs token and followed games. GitHub Actions cannot, so a
small Cloudflare Worker (`relay/worker.js`, free plan, one KV namespace) holds them. Nothing else about the architecture
changes: the Feed job still polls the sources and sends the pushes itself. The APNs key lives in GitHub secrets and, for one
purpose only, in the Worker (see Team alerts).

```
phone ──POST /v1/devices──▶ relay (KV)          Feed job (GitHub Actions, :17 and :47)
                               ▲                  1. relay-sync   GET /admin/devices ─┐ loads devices into the run's database
                               └──────────────────────────────────────────────────────┘
                                                  2. ingest       polls sources, notify.ts sends APNs, once per release
                                                  3. relay-scrub  deletes every device, VACUUMs, fails if a token is left
                                                  4. Publish      state database goes to the public `feed` branch
```

## Rules the code keeps
- **A token never reaches the public `feed` branch.** The state database is published, so devices exist in it only between
  steps 1 and 3. The scrub step runs even when an earlier step failed, deletes with `secure_delete`, rewrites the file, then searches
  the file's bytes for every token it loaded; Publish does not run if one is found or any device row is left. Logs hold counts only.
- **Switched off by default.** The Load and push steps run only when the repository variable `PUSH_ENABLED` is `1`, which
  is Terry's switch. With it off, `ingest` marks releases alerted without sending (unchanged behaviour).
- **APNs topic** is the TestFlight bundle id `tezbo.Playscribe` (set in feed.yml; the code default is the simulator id).
- **Secrets:** `APNS_KEY_P8`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `CLOUDFLARE_API_TOKEN` (Workers Scripts and KV edit). The relay's
  admin token is derived from the Cloudflare token in `relay/deploy.sh` and feed.yml, so there is no extra secret.
- **Relaunching spends no KV writes** (registration is idempotent per token and writes only on a change), because the free
  plan allows 1,000 writes a day. Sized for hundreds of devices, not thousands; past that, upgrade the plan or batch.
- **Never blocks the feed.** If the relay cannot be reached (down, not deployed, token rotated: the admin token is derived from
  `CLOUDFLARE_API_TOKEN`, so a new token needs a redeploy), the Load step fails without failing the job, push is deferred
  (`PUSH_DEFER=1`: no release is claimed as pushed, so nothing is lost) and polling and publishing carry on.
- A deferred alert is still subject to `PUSH_MAX_AGE_HOURS` (72): after a relay outage longer than that, the old releases are
  correctly not pushed.
- **Ceilings (free plan):** 1,000 KV writes a day; about 2,000 devices before the Feed job's reads (48 runs a day, one read per
  device) pass 100,000 a day. `POST /v1/devices` is unauthenticated, so someone could burn the daily writes; the Worker therefore
  accepts at most 150 new devices a day (the count resets at 00:00 UTC, which is 11:00 AEDT; 429 with Retry-After after that; relaunches of known devices are never refused).
  A new device must also pass a per-address limit of 5 a minute (the `REGISTER_LIMIT` Workers Rate Limiting binding, keyed on `cf-connecting-ip`, set up by `relay/deploy.sh`; 429 with Retry-After 60). It spends no KV writes, and known devices relaunching are never limited. Without the binding the check is skipped.
- The relay stores follows as sent (`gameId` or `igdbId`); the Feed job resolves them and counts follows for games it does
  not track. A dead token (410) is only dropped for the run, since the relay's copy is the source; a push to it fails again, harmlessly.

## Follow list without alerts (0.5.4)
`POST /v1/follows` (docs/api.md "Follow list without alerts") stores a record with no token: ids and a key only, `hourly: true`.
The Worker refuses any other field, so the app's promise ("ids and a random code, nothing else") is enforced on both ends. Such a
record is written with a 90-day `expirationTtl` (record and key entry) that every write renews; an unchanged `PUT` of the list
is written again only once the record is seven days old (the weekly "still here"), so idle devices cost nothing and a live one
costs two writes a week. `GET /admin/devices` lists these records with `token: null`; relay-sync loads them (no token to scrub,
`devices.hourly = 1`), and `trackedGames` polls a non-registry game hourly only while an `hourly` device follows it. A push-only
device's follows address alerts and do not widen the hourly tier. Budget: about 0.3 KV writes a device a day, against 1,000.

## Feed cron (GitHub's schedule as the fallback)

GitHub runs scheduled workflows from a shared queue and, when it is busy, fires them hours late or not at all: on 11 Nov 2026 the
Feed workflow had one full poll between 18:31 and 23:04 UTC and no :47 hot run. Hourly currency is the app's value, so the Worker
holds the clock too. Two cron triggers (`22 * * * *` full, `52 * * * *` hot; `FEED_FULL_CRON`, `FEED_HOT_CRON` in worker.js,
registered by deploy.sh) call `dispatchFeed`: it reads the workflow's latest run and, when none was created in the last 10 minutes,
POSTs a `workflow_dispatch` (`action: poll`, `hot: true` on the :52 tick) to `feed.yml` on main. Five minutes after GitHub's own
:17 and :47 so a run GitHub did start is seen and not doubled; `concurrency: feed` serialises any race. The token is
`FEED_DISPATCH_TOKEN`: a fine-grained GitHub token for this repository only, permission Actions read and write, stored as a
repository secret and bound to the Worker by deploy.sh (relay-deploy.yml passes it). Without it the handler logs
"no FEED_DISPATCH_TOKEN" and does nothing, so the old schedule keeps working. Blast radius of the token: starting, cancelling or
re-running this repository's workflows; no code or secrets access. Decision: docs/decisions/feed-cron-worker.md.

## Forgetting a device
`DELETE /v1/devices/me` (device key as Bearer) deletes `d:`, `k:`, `t:` (only if it still points at this device) and `tm:`. It is idempotent: an unknown key is `204`, no key is `401`. It spends up to 4 KV deletes, which count against the 1,000 writes a day.

## Deploy
`Relay deploy` workflow (on a change to `relay/**` on main, or by hand): runs the Worker tests, creates the KV namespace and the
workers.dev subdomain if missing, uploads the Worker with its binding, smoke-tests `/health` and the admin route's auth. The
URL goes in `relay/url.txt` (read by feed.yml) and in the app's `PlayscribeRelayURL` (Info.plist).

## App
Builds up to 0.5.1 build 7 use `PlayscribeAPIBaseURL` (the static feed on raw.githubusercontent.com) for the device routes too, so
they cannot register anywhere. The next build adds a separate `PlayscribeRelayURL`; only builds with it can receive push.

## Team alerts (TestFlight feedback)

Apple's App Store Connect webhook posts to `POST /v1/webhooks/asc` when a tester sends feedback or a crash report. The Worker
checks an HMAC-SHA256 signature (secret derived from the Cloudflare token in `relay/deploy.sh`; no signature, no secret or a
mismatch is a 401), then sends one fixed-text push ("New TestFlight feedback" or "New TestFlight crash report") to devices that
set `team: true`, which only internal builds do. The push never carries tester text.

**Trust model change (Terry approved 2026-11-07 AEDT):** this is the one place the APNs key is held by the Worker. Deploy binds
`APNS_KEY`, `APNS_KEY_ID`, `APNS_TEAM_ID` from the existing GitHub secrets (nothing is pasted). Blast radius: someone who could
read Worker secrets could push to this app's devices. The Feed job's own sending is unchanged. Delivery is capped at 20 team
devices a send (`tm:<id>` index keys) to stay inside the free plan's 50 subrequests per request.
