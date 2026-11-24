#!/usr/bin/env bash
# Quinn's five cloud runs on a booted, app-installed iPhone Duo (hosted runner or Mac). Needs sim-use.
#   ios/tools/qa/duo-ci-scenarios.sh UDID OUTDIR [scenario ...]    (default: all)   scenarios: continuity trailer closedax5 schemes video
# Every step saves <sha>-<scenario>-<step>-<display>-shot.png and -ui.txt (outline with frames, ids and the pose line).
set -uo pipefail
UDID=$1; OUT=$2; shift 2; SCEN=${*:-continuity trailer closedax5 schemes video}
SHA=$(git rev-parse --short HEAD 2>/dev/null || echo nosha); B=co.codeconnectors.playscribe; mkdir -p "$OUT"
AX5=UICTContentSizeCategoryAccessibilityXXXL
# Rotate first, fold second, then check the active display matches the angle (inner for any open angle, outer for 0); redo once if not.
fold() {
  for try in 1 2; do
    sim-use ios rotate "${2:-portrait}" --device "$UDID" >/dev/null 2>&1; sim-use ios fold "$1" --device "$UDID" >/dev/null 2>&1; sleep 5
    local d; d=$(did); { [ "$1" = 0 ] && [ "$d" = 1 ]; } || { [ "$1" != 0 ] && [ "$d" = 3 ]; } && return 0
    echo "fold $1 ${2:-portrait}: active display $d is wrong, retry $try"
  done; }
did() { sim-use ios fold --json --device "$UDID" 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["data"]["posture"]["activeDisplay"]["id"])' 2>/dev/null || echo 1; }
snap() { # scenario step
  local d; d=$(did); local n; [ "$d" = 3 ] && n=inner || n=outer
  local f="$OUT/$SHA-$1-$2-$n"
  xcrun simctl io "$UDID" screenshot --display=$d "$f-shot.png" >/dev/null 2>&1
  sim-use ui --device "$UDID" > "$f-ui.txt" 2>&1; echo "$f: $(head -1 "$f-ui.txt" | cut -c1-80) | $(grep -o 'pose: [a-z]*[^"]*' "$f-ui.txt" | head -1)"; }
launch() { xcrun simctl terminate "$UDID" $B >/dev/null 2>&1; fold 0 portrait; xcrun simctl launch "$UDID" $B "$@" >/dev/null; sleep 8; }
for s in $SCEN; do echo "##### $s"; case $s in
continuity) # row 8: open game scrolled mid-update, fold 0, 90, 180, 120, 0
  launch -qaRoute gamepage/dawnwalker -qaOverlay YES
  sim-use swipe --from 233,520 --to 233,220 --duration 0.6 --device "$UDID" >/dev/null 2>&1; sleep 2
  echo "scroll check: $(sim-use ui --device "$UDID" 2>/dev/null | grep -o "qa-page: [^\"]*" | head -1)"; snap continuity 1-closed-scrolled
  fold 90 landscape-left; snap continuity 2-a90-landscape; fold 180 landscape-left; snap continuity 3-a180
  fold 120 portrait; snap continuity 4-a120-portrait; fold 0 portrait; snap continuity 5-closed-again ;;
trailer) # row 3: reflection element + 3 taps in the upper half, portrait Tabletop
  launch -qaRoute trailer/dQw4w9WgXcQ/dawnwalker -qaOverlay YES
  fold 90 portrait; snap trailer 1-tabletop-before
  for y in 60 200 330; do sim-use tap -x 335 -y $y --device "$UDID" >/dev/null 2>&1; sleep 1; done
  snap trailer 2-tabletop-after-3-upper-taps ;;
closedax5) # row 1: Closed outer landscape at AX5
  launch -qaRoute library/playing -qaOrientation landscape -qaOverlay YES -UIPreferredContentSizeCategoryName $AX5
  snap closedax5 1-closed-landscape-ax5
  for i in 1 2 3 4 5 6 7 8; do sim-use swipe --from 339,380 --to 339,60 --duration 0.5 --device "$UDID" >/dev/null 2>&1; done; sleep 2; snap closedax5 1b-closed-landscape-ax5-scrolled-end
  launch -qaRoute library/playing -UIPreferredContentSizeCategoryName $AX5; snap closedax5 2-closed-portrait-ax5
  for i in 1 2 3 4 5 6 7 8; do sim-use swipe --from 233,560 --to 233,120 --duration 0.5 --device "$UDID" >/dev/null 2>&1; done; sleep 2; snap closedax5 2b-closed-portrait-ax5-scrolled-end ;;
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
