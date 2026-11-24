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
LIM="npx -y lim"; mkdir -p "$OUT"
ID=$($LIM ios create --model iphone-duo --os-version 27 --inactivity-timeout 10m --hard-timeout 30m --json \
  | python3 -c 'import json,sys;print(json.load(sys.stdin)["metadata"]["id"])')
X=$($LIM xcode create --json | python3 -c 'import json,sys;print(json.load(sys.stdin)["metadata"]["id"])')
trap '$LIM ios delete "$ID" >/dev/null 2>&1; $LIM xcode delete "$X" >/dev/null 2>&1' EXIT
$LIM xcode attach-simulator "$ID" --id "$X" >/dev/null
$LIM xcode build . --id "$X" --scheme Playscribe --xcodegen-spec project.yml --xcode-version 27.1 | tail -2
[ -n "${RECORD:-}" ] && $LIM ios record start --id "$ID" >/dev/null 2>&1 || true
# NOTE: `lim ios launch-app` (24 Nov) has no launch-argument option, only --env, so -qaRoute and the other
# -qa flags cannot be passed here and the first-run tour shows. Use duo-poses.yml (sim-use on CI) for routes.
$LIM ios launch-app co.codeconnectors.playscribe --detach --id "$ID" >/dev/null
sleep 6; n=0
for s in $STEPS; do
  n=$((n+1)); ang=${s%%:*}; ori=${s#*:}; [ "$ori" = "$s" ] && ori=portrait
  $LIM ios fold "$ang" --orientation "$ori" --id "$ID" | tail -1; sleep 4
  act=$($LIM ios fold --json --id "$ID" | python3 -c 'import json,sys;d=json.load(sys.stdin);print([x["id"] for x in d["displays"] if x["active"]][0])')
  $LIM ios screenshot "$OUT/$(printf %02d $n)-$ang-$ori-$act.png" --display "$act" --format png --size full --id "$ID" | tail -1
done
[ -n "${RECORD:-}" ] && $LIM ios record stop --output "$OUT/run.mp4" --id "$ID" || true
