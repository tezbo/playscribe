# Decision note: News headlines at accessibility text sizes (short form)

Date 2026-11-07 / owner: News thread / card: #232 (N-9), defect from Iris (AX5 stills show "Game of the Ye…").

1. **Why:** at AX sizes SwiftUI cut headlines mid-word; the AX headline rule is word-boundary ends, at most 4 lines.
3. **Value/cost:** small (one helper, four call sites). Headlines stay readable for AX players; no layout change at normal sizes. WholeWordText fits by measuring, so no guessed budget.
4. **Alternatives:** (a) `minimumScaleFactor`: shrinks text at AX sizes, defeats the purpose. (b) Show the full title with no line limit: breaks the Tabletop band and stage geometry. A fixed character budget was tried first and dropped: it cannot adapt to the real width.
5. **Decision:** Do it. All News headlines (rows, stage captions, Library strip) use `WholeWordText`: whole words then "…", 4 lines at AX sizes, 3 for rows and 2 for captions otherwise. The full headline opens on tap.
6. **Learning:** never rely on SwiftUI tail truncation for headlines; cut at a word before layout and test at AX5.
