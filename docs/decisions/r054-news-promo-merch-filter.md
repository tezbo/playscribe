# Decision note: hide sale and merch headlines from News (r054-news-promo-merch-filter)

Date 2026-11-11 / owner: News thread (Fable, iOS and backend) / card r054-news-promo-merch-filter / PR #461

1. **Why.** Quinn's #443 review: Steam store posts like "Get 20% Off CONTROL Resonant", "Merch you might have Missed" and keycap
   or figure announcements showed in the News tab with the Official chip. Nadia decided (11 Nov, Iris can veto): filter them
   with the #332 promo patterns extended to titles, never touching patch notes, and log every hidden title for Quinn.
2. **Still needed?** Yes. News exists to keep PS5 players in the know about their games; a sale or a plushie is not that, and
   each one pushes a real story off a page capped at three per game.
3. **Worth it.** Cheap: one regex pair, a prune pass, tests. Risk is hiding a real story; the keep-list (update, patch, hotfix,
   out now, launch, release, servers, roadmap) and the change-word guard make the rule err towards showing. Quinn's dry run on
   the live feed: 8,036 rows, 446 hidden (5.5%), 1 of them press.
4. **Alternatives.** (a) Show everything, let the per-game cap cope: zero code, but the cap then fills with sales. (b) A
   "Promo" chip instead of hiding: honest, but adds a chip type and still spends the three slots. (c) Hide, as here.
5. **Decision.** Hide sale and merch headlines (c). Open for Nadia, cautious default until she answers: free weekends (13 rows)
   and milestone thank-yous are SHOWN; soundtrack and vinyl releases are HIDDEN as merch. Quinn signs the backend.
6. **Learning.** A filter written for one surface (note lines) hid different things when pointed at another (headlines); dry-run
   the live data and read the list before shipping a text rule.
