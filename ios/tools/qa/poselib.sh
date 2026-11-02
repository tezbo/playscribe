# Sourced by the QA scripts: sets the iPhone Duo simulator's pose through Duo Pose Driver.
# Device Hub has Closed, Partially Open and Open presets plus Rotate Right; the orientation of the
# panel in use tells book from tabletop (rot90 landscape, rot0 portrait).
dev=${DEVICE:-01725EFD-2D6E-423D-B367-C5155D7E6623}
_qa=${0:A:h}
# Device Hub answers Accessibility reads reliably only when it's the active app.
open -a /Applications/Xcode.app/Contents/Applications/DeviceHub.app 2>/dev/null; sleep 2
press() {
  # Device Hub sometimes hides its toolbar until the window is active; retry, waking it with a tree read.
  for i in 1 2 3; do
    open -a /Applications/Xcode.app/Contents/Applications/DeviceHub.app 2>/dev/null; sleep 1
    ($_qa/../posedriver/pose.sh press "$1" >/dev/null 2>&1 & q=$!; sleep 12; kill $q 2>/dev/null || true)
    grep -q "→ 0" /tmp/posedriver.txt 2>/dev/null && { sleep 2; return; }
    ($_qa/../posedriver/pose.sh tree 3 50 >/dev/null 2>&1 & q=$!; sleep 8; kill $q 2>/dev/null || true)
  done
  echo "pose: could not press $1" >&2
}
orientation() { xcrun devicectl device info displays --device $dev 2>/dev/null | awk -v d="$1" '($3==d || $3==d":"){f=1} f&&/currentOrientation/{print $NF; exit}'; }
orient() { for i in 1 2 3 4; do [[ $(orientation $1) == $2 ]] && return; press "Rotate Right"; done; }
panel() { xcrun devicectl device info displays --device $dev 2>/dev/null | grep -q "LCD-1 (active)" && echo LCD-1 || echo LCD; }
set_pose() {
  case $1 in
    closed) press Closed; orient LCD rot0 ;;
    book) press "Partially Open"; orient LCD-1 rot90 ;;
    open) press Open; orient LCD-1 rot90 ;;
    open-portrait) press Open; orient LCD-1 rot0 ;;
    tabletop) press "Partially Open"; orient LCD-1 rot0 ;;
  esac
}
