# Decision note: Skippable intro tour (TipKit, opt-in)
Date / owner / card: 6 Nov 2026, Ezra (draft for Nadia), r060-intro-tour (0.6.0, approved by Terry)

1. **Why.** Terry asked for a short tour after the welcome so a new player learns the three things that matter before they get lost on a fold-and-pose app. Spec: handoff/0.6.0-intro-tour.md. Copy: handoff/0.6.0/intro-tour-copy.md.
2. **Still needed?** Yes, probably. A Duo app has poses a player cannot guess, and a first Library can be empty. Guess, not evidence: no data on where new players stall (a drop-off research thread exists; read it before building).
3. **Value and cost.** Value: medium if it lifts first-day understanding, low if players skip it. Cost: moderate. Three TipKit steps across 5 poses and empty and full Library means about 10 stills to review and many edge cases (anchors missing, sheets, mid-tour adds). Upkeep: every layout change can break an anchor.
4. **Alternatives.** (a) Welcome only plus contextual tips on first use, no sequenced tour: much cheaper and never blocks. (b) Make the empty Library itself the teacher, with one clear "Add a game" and a Popular row: cheapest, no new code path. (c) Short silent preview video on the welcome: art cost, no anchor problems, but it goes stale.
5. **Decision.** Change: keep Terry's three-step tour, but ship the cheapest slice first, steps 1 and 2 plus the text-only fallback, and only add step 3 if testers say they still miss the spoiler toggle. Scrap nothing now. Revisit after one TestFlight round: if most testers skip it, fall back to alternative (b).
6. **Learning.** Opt-in tours need a skip-rate target before they are built, so we know when to stop.
