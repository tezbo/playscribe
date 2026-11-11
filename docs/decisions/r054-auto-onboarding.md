# Decision note: auto-onboarding of untracked games (0.5.4)

Date 2026-11-11 / owner Theo / card r054-auto-onboarding (design note: project files design/auto-onboarding-0.5.4.md)

1. **Why.** Terry, 8 Nov: "the value of this app hinges on the currency of game update information". The feed followed ~100 of 9,419 PS5 index games; Ninja Gaiden 4 showed as untracked (#425). Terry asked for coverage first after v0.5.3.
2. **Still needed?** Yes: a PS5 player's library is mostly outside the hand registry, and "we don't track this game yet" is the opposite of the north star.
3. **Worth it?** Worth = games with history in the feed per unit of job time and upkeep. Cost: one Steam request per game per cycle (about 600 a run, 9 runs a cycle, free Actions minutes on a public repo), no IGDB calls, no hand edits. Value: ~5,300 released games gain Steam-derived history (count from the dry run on 9 Nov data). Guess: a cold game's first patch can be up to a cycle (about 9 h) late until it joins the hot set.
4. **Alternatives.** (a) Keep hand-curating: zero risk, but 1% coverage and an editor's hour per 20 games. (b) Poll all 5,300 every hour: current within the hour, but 5,300 requests a run breaks the 20 min job and Steam's patience. (c) Send the device's follow list so followed games go hourly (Terry yes, opt-in with explicit transparency): built next on top of this, the rotation stays the floor for everyone else.
5. **Decision.** Do it, in two steps: this PR adds the derived registry, the rotation and the dry run, switched off by default (`AUTO_SLICE` repository variable); it goes live after the 20-game spot check is signed by Quinn. The opt-in follow list is the next PR.
6. **Learning.** A coverage gap hid behind copy ("No updates yet"); audit the data before the words.
