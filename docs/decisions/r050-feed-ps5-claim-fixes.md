# Decision note: fix the feed's PS5 claims found in the r050 spot-check (short form)

Date / owner / card: 2026-11-12 / Priya / r050-feed-ps5-claim-fixes (Nadia's scope). Reviews: Quinn (rerun of the same 25 rows).

1. **Why.** Quinn's spot-check of 25 rows found PS5 rows the posts do not support: official dates before the studio's stated time, PTB and test builds counted as releases, PS5 assumed from posts that list only PC and Mac builds, and a version letter dropped.
3. **Worth.** A wrong official date is worse than none (Nadia). Worth = the same 25 rows pass on rerun and no row claims more than its post says. Cost: one new module, small changes in the ingest path, one repair pass inside the existing backfill.
4. **Alternatives.** (a) Only hold the two wrong official rows by hand: fast, but the next such post repeats the mistake. (b) Rewrite stored rows with a one-off script: needs a person to run it, and cannot be re-run safely. (c) Do nothing: leaves wrong official dates in the app. Chosen: rules in ingest, repair by backfill (re-reads the post, corrects only the row that post made).
5. **Decision.** See "What a post claims about PS5" in docs/ps5-patch-data.md. Held rows stay `announced`, which never alerts.
6. **Learning.** An "official" row needs the post's own time, not the time the post was written.
