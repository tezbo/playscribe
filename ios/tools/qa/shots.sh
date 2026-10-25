#!/bin/zsh
# Captures the QA screen set in the simulator's current pose (docs/ux-acceptance.md §9).
# Usage: tools/qa/shots.sh <pose-name> <out-dir> [device]
set -e
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
pose=$1; out=$2; dev=${3:?device udid}; app=co.codeconnectors.playscribe
here=${0:A:h}
mkdir -p $out
route() { xcrun simctl launch --terminate-running-process $dev $app -qaRoute "$1" >/dev/null; sleep ${2:-2.5}; }
# The Duo has two panels: LCD (outer) and LCD-1 (inner). Capture whichever is active.
panel() { xcrun devicectl device info displays --device $dev 2>/dev/null | grep -q "LCD-1 (active)" && echo LCD-1 || echo LCD; }
shot() { xcrun simctl io $dev screenshot --display=$(panel) "$out/$1-$pose.png" >/dev/null 2>&1; echo "$out/$1-$pose.png"; }
route library; shot library
route add; shot add-game
route release/dawnwalker/dawnwalker@1.1; shot game-book
route video/dawnwalker/dawnwalker@1.1 5; shot video
route library; xcrun simctl push $dev $app $here/release.apns >/dev/null; sleep 1; shot notification
