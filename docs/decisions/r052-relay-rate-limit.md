# Decision note: per-address limit on relay registration (short form)

Date / owner / card: 2026-11-07 / Priya / r052-relay-rate-limit (PR #402). Weighed with Nadia (ask) and Quinn (review).

1. **Why.** The relay's register POST is unauthenticated and free KV allows 1,000 writes a day; one noisy client could spend them. The 150-new-devices-a-day cap (#310) protects the budget but lets one address take the whole day's allowance from real players.
3. **Worth.** Worth = a single address cannot lock everyone else out, at no KV cost and no upkeep, with nothing for Terry to click. Cost: one binding, about ten lines, one test. Guess: 5 a minute per address is far above any household behind one connection (marked as a guess; adjust from the 429 count).
4. **Alternatives.** (a) Cloudflare dashboard rate-limit rule, as the card first said: no code, but agents cannot reach the dashboard so it waits on Terry, and it is invisible in the repo. (b) A KV counter per address: simple, but every attempt costs a write and it burns the budget it protects. (c) Do nothing: the global cap already stops runaway spend; the lock-out risk is small before a public launch. Chosen: the Workers Rate Limiting binding.
5. **Decision.** Changed: the goal stands, the way changes from a dashboard rule to a code binding in `relay/deploy.sh` and `worker.js`.
6. **Learning.** Prefer a limit that lives in the repo and costs no storage over a dashboard rule only one person can set.
