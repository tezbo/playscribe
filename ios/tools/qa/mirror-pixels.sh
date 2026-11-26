#!/bin/zsh
# R-11: runs ReflectionTests in Tabletop and measures the mirror in real screenshots (an XCUITest screenshot of the inner display
# is black on the Duo simulator). Passes when, on a bright frame (video peak >= 80), the band's brightest pixels reach 25% of the
# video's. Frames that are not the app (the home screen) make the numbers meaningless: check mirror-*.png. Usage: tools/qa/mirror-pixels.sh <device-udid> <out-dir>   (run from ios/, simulator already in Tabletop)
set -u
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
dev=${1:?device udid}; out=${2:?out dir}; here=${0:A:h}
mkdir -p $out; log=$out/reflection-test.log
panel() { xcrun devicectl device info displays --device $dev 2>/dev/null | grep -q "LCD-1 (active)" && echo LCD-1 || echo LCD; }
xcodebuild test -scheme PlayscribeUI -destination "platform=iOS Simulator,id=$dev" -only-testing:PlayscribeUITests/ReflectionTests > $log 2>&1 &
test=$!
for i in {1..900}; do grep -q "^MIRROR_GEOMETRY window" $log && break; kill -0 $test 2>/dev/null || break; sleep 1; done
geo=$(grep -m1 "^MIRROR_GEOMETRY window" $log)
if [[ -z $geo ]]; then wait $test; grep -E "error:|ReflectionTests" $log | tail -5; echo "MIRROR FAIL: the test never reached the mirror"; exit 1; fi
g=(${=geo}) # MIRROR_GEOMETRY window W H video x y w h band top height
best=0
for i in {1..6}; do
  png=$out/mirror-$i.png
  xcrun simctl io $dev screenshot --display=$(panel) $png >/dev/null 2>&1
  r=(${=$(swift $here/mirror_pixels.swift $png $g[3] $g[6] $g[7] $g[8] $g[9] $g[11] $g[12])})
  echo "frame $i: video $r[2] mirror $r[4]"
  if (( r[2] >= 80 )); then best=$(( r[4] * 100 / r[2] > best ? r[4] * 100 / r[2] : best )); fi
  sleep 1.5
done
wait $test; status=$?
echo "best mirror/video ${best}%  (xcodebuild exit $status)"
(( best >= 25 && status == 0 )) && { echo "MIRROR PASS"; exit 0; } || { echo "MIRROR FAIL"; exit 1; }
