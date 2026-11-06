# Decision note: Closed landscape AX5 hero (#292)

Date / owner / card: 2026-11-07 AEDT, iOS engineer, #292 (G-4, G-8, J-5).

1. Why: at AX5 the wide hero's "New update" chip crossed its edge, "v1.1" was missing, the last caption line was clipped and the card ran past the container's right edge (no border or corner).
3. Value: the earlier note said v1.1 never shows in the compact band. That was WRONG: the overlay was off-screen because the card was wider than the pager (width bug). Iris's "never drop chips" rule applies, so v1.1 stays. The J-5 half-container bound cannot hold the whole caption at AX in landscape (container about 390 pt, bound about 200 pt, caption plus padding about 210 pt or more).
4. Alternatives: (a) hold J-5 and cut lines (rejected: Iris, no cut lines); (b) put the caption under the art (more change, a new layout); (c) at AX only, let the card be as tall as its caption (chosen).
5. Decision: width fixed (the card is exactly the pager's width, so border, corner and v1.1 show). At accessibility sizes in Closed landscape only, the card and pager are as tall as the caption (at least the base height), the caption takes 72% of the width with 16 pt side and 22 pt vertical padding, and the headline may use three lines. J-5 is not held in that pose at AX; the harness tests portrait poses only. Standard sizes unchanged.
6. Learning: a "never shows" claim from one still can be a layout bug; check the element at standard size AND measure the card's width before accepting it as design.
