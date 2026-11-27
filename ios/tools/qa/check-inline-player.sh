#!/bin/bash
# bug-inline-video-voiceover-stray-iframe: in each given sim-use tree of the inline player (playing), VoiceOver gets our one
# player element (#inlinePlayer, with the transport as actions) and none of YouTube's iframe pieces. Exit 1 on any miss.
bad=0
for f in "$@"; do
  if grep -q 'Show player controls' "$f"; then echo "FAIL $(basename "$f"): YouTube's Show player controls is exposed"; bad=1
  elif ! grep -q '#inlinePlayer' "$f"; then echo "FAIL $(basename "$f"): no #inlinePlayer element"; bad=1
  else echo "ok $(basename "$f"): $(grep '#inlinePlayer' "$f" | sed -E 's/^ *@[0-9]+ +//' | cut -c1-100)"; fi
done
exit $bad
