#!/usr/bin/env bash
# Shoot the real app on a Limrun iPhone Duo (real hinge, native-scale stills, optional video).
# Needs LIM_API_KEY in the environment (never in a file or the command line). Costs trial/plan credits
# (~2 per simulator minute): the instance is deleted on exit.
#
#   LIM_API_KEY=... ios/tools/qa/limrun-duo.sh OUTDIR "ROUTE" "ANGLE[:ORIENTATION] ..." [extra launch args]
#   e.g. ios/tools/qa/limrun-duo.sh /tmp/shots gamepage/dawnwalker "0 180 90:landscape-left" -qaAppearance dark
#
# Per step it saves NN-<angle>-<orientation>-<display>.png (full resolution) and the active displays.
# Record motion with RECORD=1 (one mp4 for the whole run).
set -euo pipefail
OUT=${1:?outdir}; ROUTE=${2:?route}; STEPS=${3:?steps}; shift 3 || true
: "${LIM_API_KEY:?set LIM_API_KEY}"
cd "$(dirname "$0")/../.."          # ios/
# `lim` is Limrun's official CLI (docs.limrun.com: npm install -g lim; repo limrun-inc/typescript-sdk). Pinned to the version tested
# on 24 Nov 2026; bump deliberately after checking its release notes.
LIM_VERSION=0.63.0
LIM_X="npx -y lim@$LIM_VERSION xcode"
LIM="npx -y lim@$LIM_VERSION ios"; mkdir -p "$OUT"
ID=$($LIM create --model iphone-duo --os-version 27 --inactivity-timeout 10m --hard-timeout 30m --json \
  | python3 -c 'import json,sys;print(json.load(sys.stdin)["metadata"]["id"])')
X=$($LIM_X create --json | python3 -c 'import json,sys;print(json.load(sys.stdin)["metadata"]["id"])')
trap '$LIM delete "$ID" >/dev/null 2>&1; $LIM_X delete "$X" >/dev/null 2>&1' EXIT
$LIM_X attach-simulator "$ID" --id "$X" >/dev/null
$LIM_X build . --id "$X" --scheme Playscribe --xcodegen-spec project.yml --xcode-version 27.1 | tail -2
[ -n "${RECORD:-}" ] && $LIM record start --id "$ID" >/dev/null 2>&1 || true
# `lim ios launch-app` has no launch-argument option (only --env), so the app is launched through lim's simctl pass-through,
# which takes -qaRoute and any extra -qa flags (lim 0.63.0 `ios simctl --help`).
$LIM simctl --id "$ID" -- launch booted co.codeconnectors.playscribe -qaRoute "$ROUTE" "$@" >/dev/null
sleep 6; n=0
for s in $STEPS; do
  n=$((n+1)); ang=${s%%:*}; ori=${s#*:}; [ "$ori" = "$s" ] && ori=portrait
  $LIM fold "$ang" --orientation "$ori" --id "$ID" | tail -1; sleep 4
  act=$($LIM fold --json --id "$ID" | python3 -c 'import json,sys;d=json.load(sys.stdin);print([x["id"] for x in d["displays"] if x["active"]][0])')
  $LIM screenshot "$OUT/$(printf %02d $n)-$ang-$ori-$act.png" --display "$act" --format png --size full --id "$ID" | tail -1
done
[ -n "${RECORD:-}" ] && $LIM record stop --output "$OUT/run.mp4" --id "$ID" || true
