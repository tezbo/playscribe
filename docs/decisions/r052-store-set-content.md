# r052-store-set-content: store screenshot library

- Goal: five invented games in mixed states, so store frames never show real names or marks (asked by Nadia).
- Worth: a repeatable set the Mac loads with `-qaRoute store-set`; cost is about 600 KB of art in the asset catalogue, which also ships in release builds (the route is guarded by `showsInternalTools`, the art is not).
- Alternative: reuse the demo library with renamed games. Smaller, but it keeps real-game updates and cannot show a wishlist, a long title or an unread update by design.
- Alternative: do nothing. Store frames would need real titles.
- Decision: ship the set. Unit tests cover that distribution builds ignore the route and internal builds load all five.
