# r053-tile-marks-clear-art (Iris, tag blocker)

On main (0a9fa7e, 21e75c4) the Library tile's marks covered cover lettering: the grey check, top-right, hid the "d" in BG3's logo ("Bal( Gate"), and the date chip, bottom-leading, hid "BLOOD OF" on Dawnwalker.

**Change (GameTile).** First try: check bottom-trailing with a ring, pill top-leading. Iris: the bottom-trailing check can still touch "WALKER" on Dawnwalker. Final: the status mark (check, bookmark or eye) becomes the first glyph of the date pill ("check 22 Oct"), top-leading, and the circle is gone, so nothing else is over the art. The mark is inert and part of the tile's label. The pill is capped at the largest standard Dynamic Type size (this folds in the 0.5.4 tile-chip cap card); at accessibility sizes the pill is still hidden and the mark and date sit under the cover.

**Learning.** Art lettering can be anywhere, so a second mark on the art moves the problem. One pill, one corner.

