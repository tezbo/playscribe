# r053-tile-marks-clear-art (Iris, tag blocker)

On main (0a9fa7e, 21e75c4) the Library tile's marks covered cover lettering: the grey check, top-right, hid the "d" in BG3's logo ("Bal( Gate"), and the date chip, bottom-leading, hid "BLOOD OF" on Dawnwalker.

**Change (GameTile).** First try: check bottom-trailing with a ring, pill top-leading. Iris: the bottom-trailing check can still touch "WALKER" on Dawnwalker. Final: the status mark (check, bookmark or eye) becomes the first glyph of the date pill ("check 22 Oct"), top-leading, and the circle is gone, so nothing else is over the art. The mark is inert and part of the tile's label. The pill is capped at the largest standard Dynamic Type size (this folds in the 0.5.4 tile-chip cap card); at accessibility sizes the pill is still hidden and the mark and date sit under the cover.

**Learning.** Art lettering can be anywhere, so a second mark on the art moves the problem. One pill, one corner.


Iris's spec for the pill: one pill, top-leading, 8 pt in; a dark ground of 72% (the unread pill stays solid ember); text 11 pt (caption2) or larger, capped at the largest standard size; at AX the date sits under the cover with the mark as its first glyph; VoiceOver reads the tile as one element ("<game>, in your library, <date>" is the existing tile label). If stills show the pill covering more than one letter of the Roblox or MINECRAFT logo, it moves under the cover at every size.

Iris, final: no disc and no new yellow. The Wishlist mark is the filled bookmark in the pill's text colour; the shape tells the states apart (check, filled bookmark, eye).

Quinn's findings on the pill: it must fit the narrowest tile (a Closed 3-column tile is about 95 pt). The pill now takes the tile's width less its 8 pt insets as its maximum, shrinks its text to 75% before it truncates, and drops the glyph when the tile is narrower than 100 pt and the words are long ("Plays on PS5", "Not on PS5"); the tile's label still carries the status. The dark ground is 72% (ffff58e). An unread Wishlist pill uses onAccent on ember. At AX the under-cover text carries the glyph, and that text is hidden from VoiceOver (the tile is one element, with its own label).

Iris's ruling on the narrow tile: the glyph never drops and the text never ends in an ellipsis. The pill takes the tile's width less its insets as its maximum; the text wraps to two whole-word lines ("Plays on / PS5") and the pill grows taller, not wider. The copy is unchanged (wording goes through Ezra). The earlier minimum-scale and glyph-drop rule is removed.
