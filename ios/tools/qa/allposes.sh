#!/bin/zsh
# D-9: captures the Library and the game book in every pose, driving the hinge with Duo Pose
# Driver. Usage: tools/qa/allposes.sh <out-dir> [build]
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
out=${1:?out dir}; build=${2:-$(git rev-parse --short HEAD)}
dev=${DEVICE:-01725EFD-2D6E-423D-B367-C5155D7E6623}; app=co.codeconnectors.playscribe
here=${0:A:h}; mkdir -p $out
press() { ($here/../posedriver/pose.sh press "$1" >/dev/null 2>&1 & q=$!; sleep 12; kill $q 2>/dev/null); sleep 2; }
panel() { xcrun devicectl device info displays --device $dev 2>/dev/null | grep -q "LCD-1 (active)" && echo LCD-1 || echo LCD; }
route() { xcrun simctl launch --terminate-running-process $dev $app -qaRoute "$1" >/dev/null; sleep ${2:-4}; }
shot() { xcrun simctl io $dev screenshot --display=$(panel) "$out/$build-$1.png" >/dev/null 2>&1; echo "$out/$build-$1.png"; }
side() { xcrun simctl spawn $dev defaults write $app pageOnLeft -bool $1; }
# The inner panel's orientation: rot90 is landscape (book, open), rot0 portrait (tabletop, open
# portrait). Rotate Right steps 90°, so rotate until it matches.
inner() { xcrun devicectl device info displays --device $dev 2>/dev/null | awk '/LCD-1/{f=1} f&&/currentOrientation/{print $NF; exit}'; }
orient() { for i in 1 2 3 4; do [[ $(inner) == $1 ]] && return; press "Rotate Right"; done; }
set_pose() {
  case $1 in
    closed) press Closed ;;
    book) press "Partially Open"; orient rot90 ;;
    open) press Open; orient rot90 ;;
    open-portrait) press Open; orient rot0 ;;
    tabletop) press "Partially Open"; orient rot0 ;;
  esac
}
for p in ${POSES:-closed book open open-portrait tabletop}; do
  set_pose $p
  side NO
  route library; shot "$p-library"
  route release/dawnwalker/dawnwalker@1.1; shot "$p-gamebook"
  if [[ $p == book || $p == open ]]; then side YES; route release/dawnwalker/dawnwalker@1.1; shot "$p-gamebook-swapped"; side NO; fi
  route video/dawnwalker/dawnwalker@1.1 6; shot "$p-video"
done
