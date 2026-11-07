# r052-updates-feed-closed-rail

Short form. Goal: in Closed portrait the Updates rows card, separators and tap frames stop running under the clock ring and the nav rail (Nadia, Iris).

- Cause: `.contentMargins(.trailing, railWidth, for: .scrollContent)` insets only the content; List row backgrounds and separators span the container.
- Chosen: pad the List itself by `railWidth` plus the badge occlusion extra (same measure Search uses). Tabletop keeps the rail only.
- Alternative: hide separators and draw custom cards (bigger change, rejected). Doing nothing leaves tap frames under reserved regions (breaks the Duo rule).
- Weighed in: Iris and Nadia via the card; stills pending (harness, Closed portrait std and ax5).

Update (Iris, Quinn): the unread dot now hangs in the gutter between the cover and the text (12 pt clear of the first letter, centred on the title's first line), so read and unread titles share one left edge. The cover-to-text gap is 28 pt in the standard layout (8 clear of the cover, 8 dot, 12 to the text) for every row; at accessibility sizes the dot hangs in the row's leading inset.
