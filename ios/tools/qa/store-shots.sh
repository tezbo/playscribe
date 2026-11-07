#!/bin/zsh
# App Store capture set (r052-store-set-content): the story shots on the invented store set, one SHA, one pose.
# Usage: tools/qa/store-shots.sh <pose-name> <out-dir> <device-udid>
# Clock is frozen at 9:41 with full bars and battery; the Wi-Fi ring is given time to settle before each shot.
set -e
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
pose=$1; out=$2; dev=${3:?device udid}; app=co.codeconnectors.playscribe
mkdir -p $out
xcrun simctl status_bar $dev override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode notSupported --batteryState discharging --batteryLevel 100 >/dev/null 2>&1 || echo "status_bar override unavailable: freeze the clock by hand"
route() { xcrun simctl launch --terminate-running-process $dev $app -qaRoute "$1" ${=poseargs} >/dev/null; sleep ${2:-6}; }
panel() { xcrun devicectl device info displays --device $dev 2>/dev/null | grep -q "LCD-1 (active)" && echo LCD-1 || echo LCD; }
shot() { xcrun simctl io $dev screenshot --display=$(panel) "$out/$1-$pose.png" >/dev/null 2>&1; echo "$out/$1-$pose.png"; }
route store-set;                                        shot 1-library
route store-set/end;                                    shot 1b-library-last-row
if [[ $pose == *landscape* ]]; then route reader/store-lantern-reach/store-lantern-reach@update-1.3/320; else route release/store-lantern-reach/store-lantern-reach@update-1.3; fi; shot 2-reader
# Shot 3 is a different update from shot 2 (1.2, not the newest 1.3), so Book's right page differs and the left page lists three.
route release/store-lantern-reach/store-lantern-reach@update-1.2; shot 3-book-update
route store-set/since;                                  shot 6-since-you-last-opened
route add/photo;                                             shot 5-add-from-photo
route library/upcoming;                                 shot 7-upcoming
route release/store-hollow-meridian/store-hollow-meridian@hotfix-1.1.2; shot 8-known-issue
# 9 (Closed landscape) is the same store-set shots in the closed-landscape pose: run this script again in that pose.
