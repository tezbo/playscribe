#!/bin/bash
# Screenshots of every 0.5.0 surface in the simulator's default (Closed) pose, for CI: no Mac
# needed. Usage: tools/qa/ci-shots.sh <udid> <out-dir>. The Duo pose driver is Mac-only, so the
# other four poses stay with the Mac gate (docs/release-0.5.0-gate.md).
set -u
dev=${1:?simulator udid}; out=${2:?output dir}; app=co.codeconnectors.playscribe
mkdir -p "$out"
xcrun simctl boot "$dev" 2>/dev/null || true
xcrun simctl bootstatus "$dev" -b >/dev/null 2>&1 || true
shot() { # name route [seconds]
  xcrun simctl launch --terminate-running-process "$dev" "$app" -qaRoute "$2" >/dev/null 2>&1 || { echo "launch failed: $2"; return; }
  sleep "${3:-4}"
  xcrun simctl io "$dev" screenshot "$out/$1-closed.png" >/dev/null 2>&1 && echo "$out/$1-closed.png" || echo "no screenshot: $1"
}
shot first-run first-run
shot library library
shot demo-library demo
shot add-game add
shot settings settings
shot updates updates
shot release release/dawnwalker/dawnwalker@1.1
shot news chapter/dawnwalker/news 6
shot overlay overlay
