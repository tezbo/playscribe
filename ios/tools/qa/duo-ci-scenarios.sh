#!/usr/bin/env bash
# Quinn's five cloud runs on a booted, app-installed iPhone Duo (hosted runner or Mac). Needs sim-use.
#   ios/tools/qa/duo-ci-scenarios.sh UDID OUTDIR [scenario ...]    (default: all)   scenarios: continuity trailer closedax5 schemes video axchips
# Every step saves <sha>-<scenario>-<step>-<display>-shot.png and -ui.txt (outline with frames, ids and the pose line).
set -uo pipefail
UDID=$1; OUT=$2; shift 2; SCEN=${*:-continuity trailer closedax5 schemes video}
SHA=$(git rev-parse --short HEAD 2>/dev/null || echo nosha); B=co.codeconnectors.playscribe; mkdir -p "$OUT"
AX5=UICTContentSizeCategoryAccessibilityXXXL
fold() { sim-use ios fold "$1" --device "$UDID" >/dev/null 2>&1; sim-use ios rotate "${2:-portrait}" --device "$UDID" >/dev/null 2>&1; sleep 5; }
did() { sim-use ios fold --json --device "$UDID" 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["data"]["posture"]["activeDisplay"]["id"])' 2>/dev/null || echo 1; }
snap() { # scenario step
  local d; d=$(did); local n; [ "$d" = 3 ] && n=inner || n=outer
  local f="$OUT/$SHA-$1-$2-$n"
  xcrun simctl io "$UDID" screenshot --display=$d "$f-shot.png" >/dev/null 2>&1
  sim-use ui --device "$UDID" > "$f-ui.txt" 2>&1; echo "$f: $(head -1 "$f-ui.txt" | cut -c1-80) | $(grep -o 'pose: [a-z]*[^"]*' "$f-ui.txt" | head -1)"; }
launch() { xcrun simctl terminate "$UDID" $B >/dev/null 2>&1; fold 0 portrait; xcrun simctl launch "$UDID" $B "$@" >/dev/null; sleep 8; }
for s in $SCEN; do echo "##### $s"; case $s in
continuity) # row 8: open game scrolled mid-update, fold 0, 90, 180, 60, 0
  launch -qaRoute gamepage/dawnwalker -qaOverlay YES
  sim-use swipe --from 233,520 --to 233,220 --device "$UDID" >/dev/null 2>&1; sleep 2; snap continuity 1-closed-scrolled
  fold 90 landscape-left; snap continuity 2-a90-landscape; fold 180 landscape-left; snap continuity 3-a180
  fold 60 portrait; snap continuity 4-a60-portrait; fold 0 portrait; snap continuity 5-closed-again ;;
trailer) # row 3: reflection element + 3 taps in the upper half, portrait Tabletop
  launch -qaRoute trailer/dQw4w9WgXcQ/dawnwalker -qaOverlay YES
  fold 90 portrait; snap trailer 1-tabletop-before
  for y in 60 200 330; do sim-use tap -x 335 -y $y --device "$UDID" >/dev/null 2>&1; sleep 1; done
  snap trailer 2-tabletop-after-3-upper-taps ;;
closedax5) # row 1: Closed outer landscape at AX5
  launch -qaRoute library/playing -qaOrientation landscape -qaOverlay YES -UIPreferredContentSizeCategoryName $AX5
  snap closedax5 1-closed-landscape-ax5
  launch -qaRoute library/playing -UIPreferredContentSizeCategoryName $AX5; snap closedax5 2-closed-portrait-ax5 ;;
axchips) # bug-closed-landscape-ax5-no-games + r060-filter-pills-grid-ax5: overlay off, first screen then scrolled (chips in view)
  for ax in AX3:UICTContentSizeCategoryAccessibilityL AX5:$AX5; do n=${ax%%:*}; c=${ax#*:}
    launch -qaRoute library/playing -qaOrientation landscape -UIPreferredContentSizeCategoryName $c
    snap axchips 1-closed-landscape-$n
    sim-use swipe --from 233,450 --to 233,150 --device "$UDID" >/dev/null 2>&1; sleep 2; snap axchips 2-closed-landscape-$n-scrolled
    sim-use swipe --from 233,450 --to 233,150 --device "$UDID" >/dev/null 2>&1; sleep 2; snap axchips 2b-closed-landscape-$n-scrolled-more
    for k in $(seq 1 16); do sim-use swipe --from 233,450 --to 233,100 --device "$UDID" >/dev/null 2>&1; sleep 1
      [ $((k % 3)) = 0 ] && snap axchips 2c-closed-landscape-$n-swipe$k; done
    sleep 1; snap axchips 2c-closed-landscape-$n-end
  done
  launch -qaRoute library/playing -UIPreferredContentSizeCategoryName $AX5; snap axchips 3-closed-portrait-AX5
  sim-use swipe --from 233,560 --to 233,160 --device "$UDID" >/dev/null 2>&1; sleep 2; snap axchips 4-closed-portrait-AX5-scrolled
  launch -qaRoute library/playing -UIPreferredContentSizeCategoryName $AX5; fold 90 portrait; snap axchips 5-tabletop-AX5
  sim-use swipe --from 335,880 --to 335,560 --device "$UDID" >/dev/null 2>&1; sleep 2; snap axchips 6-tabletop-AX5-scrolled ;;
schemes) # dark and light for the pose set
  for ap in dark light; do
    launch -qaRoute library/playing -qaAppearance $ap -qaOverlay YES
    snap schemes $ap-1-closed; fold 180 landscape-left; snap schemes $ap-2-flat-landscape
    fold 90 landscape-left; snap schemes $ap-3-book; fold 90 portrait; snap schemes $ap-4-tabletop; fold 180 portrait; snap schemes $ap-5-flat-portrait
  done ;;
video) # row 9: hinge sweep recording with frame timing
  launch -qaRoute library/playing; fold 180 landscape-left
  sim-use record-video --device "$UDID" --fps 60 --output "$OUT/$SHA-video-sweep.mp4" >/dev/null 2>&1 & rp=$!
  sleep 3; for a in 180 170 160 150 140 130 120 110 100 90 80 70 60 70 80 90 100 110 120 130 140 150 160 170 180; do sim-use ios fold $a --device "$UDID" >/dev/null 2>&1; sleep 1.5; done
  sleep 2; kill -INT $rp 2>/dev/null; wait $rp 2>/dev/null
  if command -v ffprobe >/dev/null; then ffprobe -v error -select_streams v -show_entries frame=pts_time -of csv=p=0 "$OUT/$SHA-video-sweep.mp4" \
    | python3 -c 'import sys;t=[float(x) for x in sys.stdin if x.strip()];g=[(b-a)*1000 for a,b in zip(t,t[1:])];print("frames",len(t),"(frames are emitted only when the screen changes: gaps are NOT hitches; row 9 needs the app frame log) max gap ms",round(max(g),1) if g else 0,"gaps>100ms",sum(x>100 for x in g))' | tee "$OUT/$SHA-video-frame-gaps.txt"; fi ;;
esac; done
