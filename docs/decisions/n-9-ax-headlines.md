# Decision note: News headlines at accessibility text sizes (short form)

Date 2026-11-07 / owner: News thread / card: #232 (N-9), defect from Iris (AX5 stills show "Game of the Ye…").

1. **Why:** at AX sizes SwiftUI cut headlines mid-word; the AX headline rule is word-boundary ends, at most 4 lines.
3. **Value/cost:** small (one helper, four call sites). Headlines stay readable for AX players; no layout change at normal sizes. The 40-character budget is a guess sized for a half-page column at AX5; Iris's stills confirm or tighten it.
4. **Alternatives:** (a) `minimumScaleFactor`: shrinks text at AX sizes, defeats the purpose. (b) Show the full title with no line limit: breaks the Tabletop band and stage geometry. Word-bounded budget plus `lineLimit(4)` chosen.
5. **Decision:** Do it. AX sizes use `accessibleTitle()` (word-bounded, ellipsis) with `lineLimit(4)` and `fixedSize(vertical)`; other sizes unchanged. The full headline opens on tap.
6. **Learning:** never rely on SwiftUI tail truncation for headlines; cut at a word before layout and test at AX5.
