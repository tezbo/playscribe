# Decision note: AX5 Closed fixes, Updates rows and Add entry

Date / owner / card: 2026-11-07 AEDT, iOS engineer, Quinn's AX5 Closed fails at 32380a7 (G-8, A-1).

**Updates rows**
1. Why: at AX5 the game name sat beside the date in one HStack, so words split mid-word ("Dawn / walker", "CONTR / OL").
3. Value: no source reads a title split mid-word as a bug; cost is one layout switch at accessibility sizes only (guess: low risk, standard sizes untouched).
5. Decision: change it. At AX sizes the name takes the full row and the date sits under it.

**Add entry footer and icon**
1. Why: the pinned note took about 57% of the screen at AX5 and the keyboard icon overlapped "Search by name".
3. Value: the entry list is the way into the library, so it must stay usable; cost is a footer moved into the list at AX sizes only (guess: low risk).
5. Decision: change it. At AX sizes the note scrolls with the list as its footer; other sizes keep the pinned note. The icon column scales with the text (ScaledMetric).

Learning: a pinned note that takes more than half the screen at AX sizes belongs in the list as its footer; sizes below keep it pinned.
