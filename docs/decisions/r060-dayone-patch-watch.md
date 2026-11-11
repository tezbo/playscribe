# Decision note: release-day and day-one patch watch, backend half (short form)

Date / owner / card: 2026-11-11 / Priya / r060-dayone-patch-watch (0.6.0, approved by Nadia). App half: iOS engineer.

1. **Why.** On release day the day-one patch is what a player on disc installs first, and a watched upcoming game has no recent patch, so it sits outside the hot set and, if it is a derived game, waits for the auto slice (up to nine hourly runs). The alert pipeline (N-3) already pushes `dayOne` as major; the gap is polling.
3. **Worth.** Worth = a day-one patch for a launching game is seen within about 30 minutes, like any hot game, at no new source and no new file. Cost: one query in `hot.ts`, one clause in `trackedGames`, three tests. Guess: a window of 2 days before to 7 days after the exact PS5 day (marked as a guess; a day-one patch is "within a day of the platform release" in ps5-patch-data.md, and a week covers the first hotfix).
4. **Alternatives.** (a) Pin launching games by hand in `hot-pinned.json`: no code, but someone has to watch the calendar. (b) Make the hot set read device follows: follows are per device and push-only follows do not grant hourly polling (by design), so a watched game would still be missed. (c) Do nothing: the hourly run catches registry games anyway; only derived games wait. Chosen: a launch window from the stored exact PS5 day, which the index already keeps fresh while the date is ahead.
5. **Decision.** Added: launch window in `hot.ts` and `trackedGames`. Unchanged: HOT_MAX 12, the 14-day patch window, the app's release-day alert from `upcoming/events.json`.
6. **Learning.** When a feature "reuses the alert pipeline", check what feeds the pipeline first: the miss was in polling, not alerts.
