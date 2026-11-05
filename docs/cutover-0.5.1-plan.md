# 0.5.1 backend cutover plan (draft, Priya, 2026-11-05)

Status: **draft, nothing live has been changed.** 0.5.0 build 6 is on TestFlight (tag v0.5.0). The cutover waits for Terry's device pass. Extends docs/cutover-0.5.0.md (read it for commands); this page is the order, owners, rollback times and the push question.

Terms: *main* is what the feed workflow runs; *feed branch* is the one-commit published feed plus `state/playscribe.db` (no history); *snapshot* is `backup/feed-<UTC stamp>`.

## 0. Before any step (owner: Priya, Theo watches)

1. Terry has finished the device pass and said go. Nothing moves before that.
2. Snapshot: `git fetch origin feed && git push origin FETCH_HEAD:refs/heads/backup/feed-$(date -u +%Y%m%d-%H%M)`. Record the stamp in the PR. (1 minute.)
3. On the branch to ship: `cd backend && npm test && npm run -s typecheck`.
4. Dry run from the live state (cutover-0.5.0.md step 4): exit 0, "no removed or retyped fields" except the known `alert.tag` (step 7). Last run 2026-11-04: 171 files, 49 added, 1 removed (`alert.tag`), green.
5. Pause point: do not run the schedule disable/enable unless rolling back.

## 1. Order (one PR to main per step, each verified before the next)

| # | PR content | Data effect | Verified by |
|---|---|---|---|
| 1 | Contract check (`src/contract.ts`), info URL fix | none | Priya: run green, `info/38.json` parses |
| 2 | Feed health and quality checks, registry `links`, PlayStation Blog set to manual | none | Priya |
| 3 | `dropPreLaunchPs5`, duplicate fold, **#152** (earliest PS5 live date, repairs 87 drifted dates) | **deletes 32 rows, edits dates** | Priya (counts), Quinn (spot-check 3 games), Theo |
| 4 | Note `category`, `pcOnly`, `digest` | additive | Priya, Quinn (catch-up screen on a TestFlight device) |
| 5 | Steam backfill paging, then one `action=backfill` from 2020-11-01 | **adds releases**, up to 180 min | Priya (counts per game), Quinn |
| 6 | Hot-set schedule, `alert.from`, news, issues, upcoming (#83), similar, **plus.json (#204, #207, #213)** | new files | Priya; Iris/engineer check Plus card on device |
| 7 | Anything that changes what 0.2.0/0.5.0 shows: the `alert.tag` removal on press-only alerts | behaviour | Theo decides case by case |

Per step, after merge: run `feed.yml` (`action=poll`), then cutover-0.5.0.md "Verify" 1 to 5, including the next :17 run being green. Steps are separated by at least one green scheduled run.

## 2. The pre-publish gate

Every run (not only the cutover) fails before publishing if the contract check (`feedContractProblems`: kind and platform enums, dates, Field shape, `alert.style`, link URLs, `latest.updatedAt` never null) or the quality checks (no PC version as PS5 version, no source names, link and release coverage) fail. A red run leaves the live feed as it was; fix forward. Info-shard problems are warnings. `publish-diff` against the live feed is the human gate: any removed or retyped field blocks the step.

## 3. Rollback and time to recover

| Step | Rollback | Time |
|---|---|---|
| 1, 2, 4, 6 (additive) | Revert PR on main; next poll republishes without the new fields | about 10 min (merge + one run) |
| 3 and 5 (change data) | Disable the Feed workflow, `git push -f origin refs/heads/backup/feed-<stamp>:refs/heads/feed` (restores files and DB), revert PR on main, re-enable, `action=poll`, verify | about 20 min; backfill is the same restore, the 180 min job is not repeated |
| 7 | Revert PR | about 10 min |

The `feed` branch force-push is the one forceful action, only for a data-changing step (3, 5), and only after Theo says so. Keep the last three snapshots; delete older ones a day after a step is green.

## 4. What the 0.5.0 app already tolerates (TestFlight devices cannot break)

Read from the decoders on release/0.5.0 (full list: /mnt/project-files/gamebook/qa/0.5.0-feed-required-fields.md). Everything the steps add is optional or lenient: `digest` (a bad one is ignored), `issues` (bad ones drop to none), `category`, `pcOnly`, `news`, `similar`, upcoming extras, and `plus.json` (not read until the Plus card ships; its loader ignores unknown keys). What can break the app is only a bad value inside `latest.json`/`games/*.json` releases (unknown `kind` or platform, malformed `links` URL, bad date, `alert` without `style`), which the contract check blocks before publish. The one visible change for installed apps is step 7 (`alert.tag`).

## 5. Pushes: can they be switched on safely?

**Not yet, and flipping `PUSH_ENABLED` is not enough.** Findings (2026-11-05):

- The app's `PlayscribeAPIBaseURL` is `https://raw.githubusercontent.com/tezbo/playscribe/feed/v1/`, a static file host. `PushRegistrar` posts to `v1/devices` and `v1/devices/me` there, which cannot accept a POST. There is **no hosted relay** today: the Hono server in `backend/src/server.ts` only runs locally. So no device token, follow or quiet-hours window is stored anywhere; the hourly job sends to nobody.
- To get server pushes we need (a) a free host for `server.ts` that persists SQLite (or a move of the device table to something the Actions job can read), (b) the app's API base URL split into feed URL and relay URL (an app change, so 0.5.2 at the earliest for TestFlight), (c) APNs secrets and `PUSH_ENABLED=1`. (a) and (b) are design decisions for Theo and Terry.
- #198 (quiet hours relay) and #162 (alert copy) are code-ready and tested but only matter once (a) and (b) exist. They can ride step 6 harmlessly.
- Until then the app's own local alerts do the work (they honour quiet hours).

## 6. Steps that need Terry

- Go after his device pass (step 0.1).
- **APNs secrets** (`APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_KEY_P8`) and the **repo variable** `PUSH_ENABLED`: only Terry can add them, and only once a relay host exists (section 5).
- Twitch keys already live in the Actions "development" environment; the upcoming shard (#83, step 6) needs nothing new.
- Anything Apple-side (App Group and widget App ID for the 0.5.0 widget are already in docs/release.md).
- Force-push to `feed` in a rollback of step 3 or 5: Theo's call, not Priya's.

## 7. Open before step 3

- #152 is green but unreviewed; it is part of step 3.
- #162 (alert copy) and #213 (parser fix, draft) are still open on release/0.5.0.
