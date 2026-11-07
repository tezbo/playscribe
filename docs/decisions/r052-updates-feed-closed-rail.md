# r052-updates-feed-closed-rail

Short form. Goal: in Closed portrait the Updates rows card, separators and tap frames stop running under the clock ring and the nav rail (Nadia, Iris).

- Cause: `.contentMargins(.trailing, railWidth, for: .scrollContent)` insets only the content; List row backgrounds and separators span the container.
- Chosen: pad the List itself by `railWidth` plus the badge occlusion extra (same measure Search uses). Tabletop keeps the rail only.
- Alternative: hide separators and draw custom cards (bigger change, rejected). Doing nothing leaves tap frames under reserved regions (breaks the Duo rule).
- Weighed in: Iris and Nadia via the card; stills pending (harness, Closed portrait std and ax5).

Update (Iris, Quinn): the unread dot now hangs in the gutter between the cover and the text (12 pt clear of the first letter, centred on the title's first line), so read and unread titles share one left edge. The cover-to-text gap is 28 pt in the standard layout (8 clear of the cover, 8 dot, 12 to the text) for every row; at accessibility sizes the dot hangs in the row's leading inset.

Update (Mac, 18c34a3): in Book at AX5 the hung dot landed 6 pt outside the card, because the card pads 12 and the dot hangs 20. Book cards now pad 32 on the leading side at accessibility sizes so the dot stays on the card; lists keep the row inset (20), which already holds the dot. Open AX5 uses the list branch.

Update (Mac, 99a1f3b): Closed and Open AX5 had the dot flush with the card edge, because the list row begins at the card edge and the dot hangs 20 pt left of the text. One rule now in FeedRow, for every pose: at accessibility sizes the row pads 32 pt before its content (12 margin, 8 dot, 12 clearance), so the dot sits 12 pt inside the card everywhere. Book's own AX padding is gone (a per-pose patch). Cost: 32 pt of AX text width in Closed and Open; the AX5 wrap checks (whole words, 4-line headline) are part of the reshoot.
