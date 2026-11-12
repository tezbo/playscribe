# Decision note: the relay Worker's cron starts the Feed when GitHub's schedule does not

Date / owner / card: 2026-11-11 / Theo / currency (auto-onboarding follow-up; Sam asked for it now, 11 Nov 23:07 UTC)

1. **Why.** The Feed workflow is scheduled hourly (:17 full, :47 hot) but GitHub fires scheduled workflows from a shared queue:
   on 11 Nov 2026 one full poll ran between 18:31 and 23:04 UTC and no hot run at all. Terry (8 Nov): "the value of this app
   hinges on the currency of game update information". Auto-onboarding's 9-run cycle and the followed games' hot cadence both
   assume the hour is real.
2. **Still needed?** Yes. Every alert, the follow list's "checks them every hour" promise and the 14 h worst case rest on it.
3. **Value vs cost.** Polls fire on the hour again, for about 40 lines in the Worker that already runs for the relay, two cron
   triggers, four tests, and one new secret (a fine-grained GitHub token, this repository, Actions read and write) that Terry
   creates once. Cost of the token: whoever reads Worker secrets could start or cancel this repository's workflows; nothing else.
4. **Alternatives.** (a) Do nothing and accept GitHub's drift: free, but hourly is a promise we then do not keep. (b) Move the
   Feed job off GitHub Actions to a Worker or a VPS: real hourly, but the job needs Node, SQLite and 3 to 4 minutes of CPU, so a
   rewrite and a bill. (c) Keep GitHub's schedule and add a second clock that only fills gaps (this): small, reversible, the
   old schedule stays as fallback and the dispatch is skipped when GitHub did fire.
5. **Decision.** Do (c). Until the secret exists the Worker logs and does nothing, so the change is safe to merge first.
   Review after a week of runs: if GitHub's own fires only ever double up, drop the `schedule` block from feed.yml.
6. **Learning.** A cron you do not own is a wish, not a clock; put the clock where you can see it fire (Worker log, run list).
