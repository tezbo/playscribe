#!/bin/bash
# bug-071 / #655 (Iris; Quinn's conditions): in full screen VoiceOver gets our picture element, never YouTube's iframe
# buttons. sim-use's tree honours hidden flags as VoiceOver does; XCUITest's snapshot does not (see FullScreenVideoTests).
# Usage: check-no-youtube-buttons.sh <sim-use -ui.txt>...  Exits 1 if any given tree exposes "Show player controls".
bad=0
for f in "$@"; do
  if grep -q 'Show player controls' "$f"; then echo "FAIL $(basename "$f"): YouTube's Show player controls is exposed"; bad=1
  else echo "ok $(basename "$f")"; fi
done
exit $bad
