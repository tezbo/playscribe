#!/bin/zsh
# D-2 / D-9: Terry's path. Opens a game, drives the hinge through
#   Closed → Book → Closed → Open → Tabletop → Closed
# with Duo Pose Driver, and after every pose checks the persisted state still has that game open,
# and captures the active panel. Run from the Library too with GAME=library.
# Usage: tools/qa/posepath.sh <out-dir> [game-id]

export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
out=${1:?out dir}; game=${2:-kcd2}
dev=${DEVICE:-01725EFD-2D6E-423D-B367-C5155D7E6623}; app=co.codeconnectors.playscribe
source ${0:A:h}/poselib.sh
mkdir -p $out
state() { cat "$(xcrun simctl get_app_container $dev $app data)/Library/Application Support/playscribe-state.json" 2>/dev/null; }
open_game() { python3 -c 'import json,sys; print(json.load(sys.stdin).get("nav",{}).get("gameID") or "library")'; }

set_pose closed
if [[ $game == library ]]; then route=library; else route="chapter/$game/updates"; fi
xcrun simctl launch --terminate-running-process $dev $app -qaRoute $route >/dev/null; sleep 3
fail=0; step=0
for p in closed book closed open tabletop closed; do
  step=$((step+1))
  set_pose $p; sleep 2
  got=$(state | open_game)
  [[ $game == library && $got == library ]] && got=library
  xcrun simctl io $dev screenshot --display=$(panel) "$out/$step-$p.png" >/dev/null 2>&1
  if [[ $got == $game ]]; then echo "ok   $step $p: $got"; else echo "FAIL $step $p: expected $game, got $got"; fail=1; fi
done
exit $fail
