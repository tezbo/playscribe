# Decision note: opt-in follow list to the relay (auto-onboarding step 3)

Date / owner / card: 2026-11-11 / Theo / r054 (auto-onboarding, step 3)

1. **Why.** A game outside the hand registry waits up to about 14 h on the rotating slice. Terry (8 Nov): the app's value is the
   currency of update information, and yes to sending the follow list "as long as we are explicit". Nadia: opt-in, off by default.
2. **Still needed?** Yes: with ~5,300 auto games on a 600-a-run slice, a followed game is the one that must be hourly.
3. **Value vs cost.** Hourly for the games a player actually follows, at the cost of one relay route, a flag, two KV writes a week
   per device, and the privacy promise to keep: ids and a random key, nothing else, 90-day expiry, deleted on switch-off.
4. **Alternatives.** (a) Poll everything hourly: 5,300 Steam requests an hour, past the 20 min job limit; no. (b) Keep the
   rotation only: simple, no data leaves the phone, but 14 h latency for the games people care about; kept as the off state.
   (c) Infer hot games from the public feed's reads: no per-device data, but raw.githubusercontent gives no reads; no.
5. **Decision.** Do (opt-in). Relay: `POST /v1/follows` refuses any field beyond ids; token-less records expire; `hourly` flag.
   Feed: only `hourly` follows widen the tracked set. App: Settings switch and one-time card with Ezra's copy, body-shape test.
6. **Learning.** Enforce a privacy promise at both ends: the app's test stops a field being added, the relay's 400 stops it arriving.
