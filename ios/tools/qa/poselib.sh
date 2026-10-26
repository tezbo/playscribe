# Sourced by the QA scripts: sets the iPhone Duo simulator's pose through Duo Pose Driver.
# Device Hub has Closed, Partially Open and Open presets plus Rotate Right; the orientation of the
# panel in use tells book from tabletop (rot90 landscape, rot0 portrait).
dev=${DEVICE:-01725EFD-2D6E-423D-B367-C5155D7E6623}
_qa=${0:A:h}
press() { ($_qa/../posedriver/pose.sh press "$1" >/dev/null 2>&1 & q=$!; sleep 12; kill $q 2>/dev/null || true); sleep 2; }
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
