# Decision note: Closed landscape AX5 hero chips (#292)

Date / owner / card: 2026-11-07 AEDT, iOS engineer, #292 (G-4, G-8).

1. Why: Iris and Quinn saw the "New update" chip's descender cross its bottom edge at AX5, and no "v1.1".
3. Value: v1.1 never shows in the compact band at any size (Mac, standard-size still), so there was nothing to restore. Moving both chips into the caption (ec38209) made the card taller than the viewport and clipped it (Mac). Cost with no gain.
5. Decision: scrap the chips-in-caption change. Keep "New update" only, in a chip that grows with its text (minHeight 22, 2 pt vertical padding). The version is in the VoiceOver label.
6. Learning: check what a pose shows at standard size before treating a missing element at AX as a regression.
