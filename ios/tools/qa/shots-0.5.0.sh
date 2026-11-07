#!/bin/zsh
# Captures every 0.5.0 still in the simulator's current pose, with and without the debug overlay.
# Usage: tools/qa/shots-0.5.0.sh <pose-name> <out-dir> <device-udid>
# Run once per pose (closed, flat, book, tabletop, closed-landscape); Tabletop acceptance reads the
# "-overlay" set (no tappable frame above the division). Evidence names: <screen>-<pose>[-overlay].png
set -e
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
pose=$1; out=$2; dev=${3:?device udid}; app=co.codeconnectors.playscribe
mkdir -p $out
panel() { xcrun devicectl device info displays --device $dev 2>/dev/null | grep -q "LCD-1 (active)" && echo LCD-1 || echo LCD; }
screens=(
  library first-run demo
  add add/keyboard add/scan settings settings/quiet
  tag/official tag/reported tag/pending
  links/dawnwalker release/dawnwalker/dawnwalker@1.1 updates search
)
for overlay in no yes; do
  suffix=""; extra=(); [[ $overlay == yes ]] && { suffix="-overlay"; extra=(-qaOverlay YES); }
  for route in $screens; do
    xcrun simctl launch --terminate-running-process $dev $app -qaRoute "$route" ${=poseargs} $extra >/dev/null
    # keyboard and scan need longer to settle
    case $route in add/keyboard|add/scan) sleep 5 ;; *) sleep 3 ;; esac
    name=${route//\//_}
    xcrun simctl io $dev screenshot --display=$(panel) "$out/$name-$pose$suffix.png" >/dev/null 2>&1 && echo "$out/$name-$pose$suffix.png"
  done
done
