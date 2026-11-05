# Shipping 0.5.0 backend changes to main

The feed is built by `.github/workflows/feed.yml` from **main**, so a backend change reaches installed apps (0.2.0 now) only when it is on main. The feed is published to the `feed` branch as one commit that is replaced on every run, with the SQLite state (`state/playscribe.db`) inside it. That means **the feed branch has no history**: a bad run overwrites the only copy. Everything below is built around that.

## Before any step

1. 0.2.0 is tagged and the Mac gate has run on the exact SHA. Backend-only changes do not change the app SHA, but never move main while the gate is running.
2. **Snapshot the feed.** This is the rollback point.
   ```sh
   git fetch origin feed
   git push origin FETCH_HEAD:refs/heads/backup/feed-$(date -u +%Y%m%d-%H%M)
   ```
3. On the branch to ship: `cd backend && npm test && npm run -s typecheck`.
4. **Dry-run the publish.** Build the feed from a copy of the live state and diff it against the live feed:
   ```sh
   git fetch --depth 1 origin feed && mkdir -p /tmp/new && git --work-tree=/tmp/new checkout FETCH_HEAD -- . && git reset -q && cd backend
   DATABASE_PATH=/tmp/new/state/playscribe.db npm run ingest -- --export /tmp/new
   npm run publish-diff -- /tmp/new
   ```
   Exit 0 and "no removed or retyped fields" is the gate. Added fields are fine (0.2.0 ignores unknown keys). Attach the output to the PR. The dry run **must start from the live state** (the checkout above): a fresh database has no IGDB covers or artwork and shows them as removed. It exits 2 if it compared nothing.

   Result on release/0.5.0 at the time of writing (21:40 UTC 3 Nov): 171 files compared, 50 fields added (`digest`, `category`, `pcOnly`, `issues`, and more), one removed: `alert.tag`, the "Unconfirmed" tag of the press-only `quiet` alert. 0.2.0 reads `tag` as optional, so nothing breaks, but those releases lose their quiet alert. That is a behaviour change, so it belongs to step 7.

## Order

One PR to main per step, each merged on its own, verified on the live feed (next section) before the next. Steps are ordered by risk, lowest first, and every step is additive for the 0.2.0 app unless marked.

| # | Ship | Why this order | Data effect |
|---|---|---|---|
| 1 | Info URL fix (#87, done) and the contract check (`src/contract.ts`) | Fixes a live decode break; the check then guards every later step | None |
| 2 | Feed health and quality checks, registry `links`, PlayStation Blog set to manual | Only guards and new links; nothing the app reads changes shape | None |
| 3 | `dropPreLaunchPs5` and the duplicate fold (`versionIdentity`, `mergeSilentDuplicates`) | Repairs live data: removes 20 pre-launch assumed PS5 rows, folds press-only duplicates | **Deletes rows.** Not undone by reverting code; roll back from the snapshot |
| 4 | Note `category`, `pcOnly`, `digest` | Additive note and release fields | None |
| 5 | Steam backfill paging, then one `action=backfill` from the PS5 launch (`2020-11-01`) | Full history per game; slow (see below) | Adds releases |
| 6 | Hot-set schedule, `alert.from`, news and issues files, upcoming shards (#83), `similar` | New files and schedule; the app ignores them until 0.5.0 | New files |
| 7 | Anything that changes what 0.2.0 shows (an `alert` rule that hides or shows a release) | Behaviour change for installed apps | Decide with Theo case by case |

## Verify each step on the live feed

After the merge, run the workflow (`gh workflow run feed.yml` or the Actions tab, `action=poll`), wait for it to finish, then:

1. The run is green and its summary lists no "Data quality" or "Source failing" section.
2. `cd backend && npm run publish-diff -- <fresh checkout of the feed branch>` against the previous snapshot base: `npm run publish-diff -- /tmp/live https://raw.githubusercontent.com/tezbo/playscribe/backup/feed-<stamp>/v1`. No removed or retyped fields.
3. The contract check: fetch the feed branch and run `feedContractProblems` (it runs inside the ingest on every run; a failure stops the publish, so a green run means it passed). Open `info/38.json` and confirm it parses.
4. Spot-check three games the step touched in the feed (`games/<id>.json`): counts, the fields that step adds, and one release page in the app against the Duo or simulator if the gate machine is free.
5. Wait for the next scheduled run (:17) and confirm it is green too; a state problem often shows on the second run.

## Rollback

A revert alone does not undo data the new code wrote into the state database, and the feed branch keeps no history, so roll back in this order:

1. Stop the schedule: Actions tab, Feed workflow, disable.
2. Restore the snapshot: `git push -f origin refs/heads/backup/feed-<stamp>:refs/heads/feed` (this restores the feed files **and** the state database).
3. `git revert -m 1 <merge commit>` on main through a PR (never force-push main), merge it.
4. Re-enable the workflow and run `action=poll`. It rebuilds from the restored state with the reverted code. Verify as above.
5. A step that only added guards or files (steps 1, 2, 4, 6) is also safe to revert without restoring: the next poll republishes without the new fields. Steps 3 and 5 changed data and must be rolled back from the snapshot.

Keep the last three `backup/feed-*` branches and delete older ones once a step has been green for a day.

## Notes

- **Backfill (step 5).** `--backfill` re-reads every source back to the date, and the press list is read page by page at the site's 5 second Crawl-delay, so allow up to the 180 minute job limit. Steam now pages back with `enddate`, so busy games (Apex, Dead by Daylight, Rainbow Six Siege, The Finals, GT7 had nothing before 2024 to 2026 in the live feed) get their full history. Run it once with since `2020-11-01` (PS5 launch is 2020-11-12), then check the games in `docs/ps5-patch-data.md`.
- **Keys.** The Twitch keys exist only in the Actions "development" environment. `action=info` and the upcoming step need them; a local dry run does not (it skips IGDB).
- **Quality failures stop the publish by design.** If a run fails on "Data quality", the live feed stays as it was; fix forward rather than bypass the check.
