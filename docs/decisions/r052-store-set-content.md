# r052-store-set-content: store screenshot library

- Goal: five invented games in mixed states, so store frames never show real names or marks (asked by Nadia).
- Worth: a repeatable set the Mac loads with `-qaRoute store-set`; cost is about 600 KB of art in the asset catalogue, which also ships in release builds (the route is guarded by `showsInternalTools`, the art is not).
- Alternative: reuse the demo library with renamed games. Smaller, but it keeps real-game updates and cannot show a wishlist, a long title or an unread update by design.
- Alternative: do nothing. Store frames would need real titles.
- Decision: ship the set. Unit tests cover that distribution builds ignore the route and internal builds load all five.
- Follow-up (7 Nov, Mara): the PS Plus card showed real covers in store frames. `store-set` now sets a Plus lineup of three invented titles (plates, no cover match); a unit test checks none resolves to a game.
- Follow-up (7 Nov, Mara): hero first. `store-set` now turns the PS Plus card off and treats alerts as decided (card hidden); `store-set/plus` brings the Plus card back with its invented plates. Hero fold and tab bar overlap should clear with the cards gone; the Mac confirms on reshoot.
- Follow-up (7 Nov, Quinn): the Lantern Reach sun sat under the caption (cream on orange). Art only: the sun and glow now end above 40% of the hero height and sit at 65% of its width, clear of the caption and of the top-left chips in the wide Closed card, independent of any scrim (#348).
- Follow-up (7 Nov, Iris on #361): Hollow Meridian sun moved to the top right (same move as Lantern Reach); the three Plus titles now have designed covers (muted gradient, serif initial, title below) as untracked custom games; the Lantern Reach and Long Quiet Orchard summaries reworded so they add to the headline.
