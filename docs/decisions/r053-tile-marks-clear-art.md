# r053-tile-marks-clear-art (Iris, tag blocker)

On main (0a9fa7e, 21e75c4) the Library tile's marks covered cover lettering: the grey check, top-right, hid the "d" in BG3's logo ("Bal( Gate"), and the date chip, bottom-leading, hid "BLOOD OF" on Dawnwalker.

**Change (GameTile).** The status circle moves to the bottom-trailing corner, 8 pt in, with a 1.5 pt dark ring (as the first-run covers in #431). The date pill moves to the top-leading corner. Both are capped at the largest standard Dynamic Type size (this folds in the 0.5.4 tile-chip cap card); at accessibility sizes the pill is still hidden and the date sits under the cover.

**Not solved by position alone.** Art lettering can be anywhere: Dawnwalker's title runs along the bottom, so a bottom-trailing check can touch its last letter. Iris's spec is followed; the ring keeps the check legible over it. Stills decide.

**Learning.** A mark on art needs a ring and a corner chosen against real covers, not one cover.
