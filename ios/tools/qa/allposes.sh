#!/bin/zsh
# D-9: captures the Library and the game book in every pose, driving the hinge with Duo Pose
# Driver. Usage: tools/qa/allposes.sh <out-dir> [build]
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
out=${1:?out dir}; build=${2:-$(git rev-parse --short HEAD)}
dev=${DEVICE:-01725EFD-2D6E-423D-B367-C5155D7E6623}; app=co.codeconnectors.playscribe
here=${0:A:h}; mkdir -p $out
source ${0:A:h}/poselib.sh
route() { xcrun simctl launch --terminate-running-process $dev $app -qaRoute "$1" >/dev/null; sleep ${2:-4}; }
shot() { xcrun simctl io $dev screenshot --display=$(panel) "$out/$build-$1.png" >/dev/null 2>&1; echo "$out/$build-$1.png"; }
side() { xcrun simctl openurl $dev "playscribe://side/$([[ $1 == YES ]] && echo left || echo right)"; sleep 2; }
for p in ${=${POSES:-closed book open open-portrait tabletop}}; do
  set_pose $p
  side NO
  route library; shot "$p-library"
  route release/dawnwalker/dawnwalker@1.1; shot "$p-gamebook"
  if [[ $p == book || $p == open ]]; then side YES; route release/dawnwalker/dawnwalker@1.1; shot "$p-gamebook-swapped"; side NO; fi
  route video/dawnwalker/dawnwalker@1.1 12; shot "$p-video"
done
