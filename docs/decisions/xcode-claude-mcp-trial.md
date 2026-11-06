# Decision note: Claude inside Xcode (MCP and Previews) for the stills loop (short form)
Date / owner / card: 6 Nov 2026 (23:36 UTC), Theo, no card (tooling; Terry's question after connecting Claude to Xcode)

1. **Why.** Terry connected Claude to Xcode and asked whether it makes testing much faster; today's bottleneck is the Mac stills loop (Device Hub poses, serial, steals focus).
2. **Still needed?** The goal (shorter fix cycle for layout bugs, fewer Mac shoots) stands; it serves "award-worthy made for iPhone Duo" by finding fold and AX bugs earlier.
3. **Value and cost.** Xcode's MCP (`xcrun mcpbridge`, Xcode 26.3+; third-party write-ups, not Apple docs) gives build, tests, `RenderPreview`, docs search. No documented simulator control or screenshots; needs Xcode open on the Mac, so cloud engineers cannot use it; the app has zero `#Preview` blocks. Value over what we have (gate scripts, fold harness): low. Time saved per fix is an estimate, not measured: Mac shoot about 15 to 30 min with queueing against a few minutes for a CI harness render.
4. **Alternatives.** (a) Harness PNG artifacts in CI (reuses `FoldHost.render`, which already loops AX3 and AX5): cheap, no Mac. (b) `-qaPose` launch argument (docs/ci.md item 6): headless poses, ends Device Hub focus theft, needs Terry's yes. (c) One `#Preview` of the Tabletop deck at AX5 as a one-hour trial. (d) Do nothing.
5. **Decision.** Changed: do not adopt Xcode's Claude as a process dependency; pursue (a), ask Terry for (b), and run (c) once. Scrap (c) if it does not reproduce the #292 hang. Product and design not consulted: no screen changes.
6. **Learning.** Check what the existing harness already covers before adding a tool; "the harness loops AX5 yet missed the #292 hang" is the open question to answer first.
