#!/bin/zsh
# Five-pose gate in one run, built once. Usage: tools/qa/gate.sh <out-dir> [poses…]
#
#  1. Build once per SHA (build-for-testing). Every later step is test-without-building.
#  2. Pose-independent suites run once, in Closed: unit tests, ReleaseRow, Journey, Capture stills.
#  3. Pose-sensitive suites (fold audit, layout, accessibility audit, deck, 0.5.0 sheets) run in each pose.
#  4. Each pose is verified (panel and orientation) before any test runs; a wrong pose fails the gate.
#  5. Every step logs its seconds and appends to <out>/summary.txt, so a dropped session loses nothing.
# Poses are set through Duo Pose Driver (a GUI press on one Device Hub window), so poses stay serial.
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
out=${1:?out dir}; shift; mkdir -p $out
# TIER=pr (PRs, docs/ci.md): Closed and Tabletop only (the two layouts that differ most), no stills, no once-suites. TIER=full (default,
# release sign-off): all five poses, with stills. Poses named on the command line win.
TIER=${TIER:-full}
poses=(${=@})
if (( ! $#poses )); then
  [[ $TIER == pr ]] && poses=(closed tabletop) || poses=(closed book open open-portrait tabletop)
fi
[[ $TIER == pr ]] && : ${STILLS:=0} ${ONCE:=0}   # the pose-independent suites and unit tests run in TIER=full; GitHub CI runs the unit tests on every PR
here=${0:A:h}; cd ${here:h:h} || exit 1   # ios/: xcodebuild and xcodegen run from here
source $here/poselib.sh
app=co.codeconnectors.playscribe
sha=$(git rev-parse --short HEAD); sum=$out/summary.txt; : > $sum
dd=~/Library/Developer/Xcode/DerivedData/Playscribe-gate
dest="platform=iOS Simulator,id=$dev"
note() { echo "$*" | tee -a $sum; }
timed() { local t=$SECONDS; "$@"; local rc=$?; note "  ($(( SECONDS - t )) s)"; return $rc; }
ui() { echo "-only-testing:PlayscribeUITests/$1"; }

# Pose-sensitive: these look at fold, reserved regions, layout and sheets, so they run in every pose.
POSE_SUITES=(FoldAuditTests LibraryLayoutTests LatestUpdatesDeckTests Release050Tests ReleaseFeatureTests
  PlayscribeUITests/testAccessibilityAudit PlayscribeUITests/testTabletopSheetsKeepControlsInTheLowerHalf
  PlayscribeUITests/testScanFitsThePanel)
# Only meaningful when two pages are side by side.
TWO_PAGE_SUITES=(SwapSidesTests)
# Pose-independent: logic, data, navigation. Once, in Closed. (JourneyTests is not here: it needs the device
# unfolded mid-test, which only tools/qa/journey.sh does.)
ONCE_SUITES=(ReleaseRowTests ReviewFixUITests DisplayChoiceTests CaptureTests ReaderPerformanceTests
  PlayscribeUITests/testNotificationTapOpensRelease)

note "gate $sha $(date '+%F %T')"
note "== build once"
(cd $here/../.. && xcodegen generate >/dev/null) || { note "FAIL xcodegen"; exit 1; }
timed xcodebuild -scheme PlayscribeUI -destination $dest -derivedDataPath $dd build-for-testing \
  > $out/build.log 2>&1 || { note "FAIL build-for-testing (see build.log)"; exit 1; }
xctestrun=$(ls -t $dd/Build/Products/*.xctestrun | head -1)

run() {  # run <label> <only-testing…>
  local label=$1; shift
  xcrun simctl spawn $dev defaults write $app pageOnLeft -bool NO
  rm -rf $out/$label.xcresult   # xcodebuild refuses an existing result bundle
  xcodebuild test-without-building -xctestrun $xctestrun -destination $dest \
    "$@" -resultBundlePath $out/$label.xcresult > $out/$label.log 2>&1
  local r=$(grep -E '\*\* TEST (EXECUTE )?(SUCCEEDED|FAILED)' $out/$label.log)
  note "$label: ${r:-NO RESULT}"
  # Every error, never a capped list (the old head -8 hid most of the e869273 failures), then the failing-test count.
  grep -E "error:" $out/$label.log | sed 's/.*error: -\[/  [/' | tee -a $sum
  note "$label: $(grep -E "^Test Case .* failed" $out/$label.log | sort -u | wc -l | tr -d ' ') failing test(s)"
  grep -E "^Test Case .* failed" $out/$label.log | sort -u | sed 's/^Test Case .-\[/  FAILED [/;s/. failed.*//' | tee -a $sum
  [[ $r == *SUCCEEDED* ]]
}
verify_pose() {  # verify_pose <pose>: panel and orientation must match, or the run is void.
  local want_panel want_or
  case $1 in
    closed) want_panel=LCD; want_or=rot0 ;;
    book|open) want_panel=LCD-1; want_or=rot90 ;;
    open-portrait|tabletop) want_panel=LCD-1; want_or=rot0 ;;
  esac
  local got_or=$(orientation $want_panel)
  [[ $(panel) == $want_panel && $got_or == $want_or ]] && { note "pose $1 ok ($want_panel $got_or)"; return 0; }
  note "FAIL pose $1: wanted $want_panel $want_or, got $(panel) $got_or"; return 1
}

fails=0
note "== once, in closed"
set_pose closed; verify_pose closed || exit 1
if [[ ${ONCE:-1} == 1 ]]; then
# Unit tests live in the Playscribe scheme (PlayscribeUI's xctestrun has only the UI target).
timed xcodebuild -scheme Playscribe -destination $dest -derivedDataPath $dd test > $out/unit.log 2>&1
unit=$(grep -E '\*\* TEST (EXECUTE )?(SUCCEEDED|FAILED)' $out/unit.log); note "unit: ${unit:-NO RESULT}"; [[ $unit == *SUCCEEDED* ]] || ((fails++))
timed run once $(for s in $ONCE_SUITES; do ui $s; done) || ((fails++))
fi

for p in $poses; do
  note "== $p"
  set_pose $p; verify_pose $p || { ((fails++)); continue; }
  suites=($POSE_SUITES); [[ $p == book || $p == open ]] && suites+=($TWO_PAGE_SUITES)
  timed run $p $(for s in $suites; do ui $s; done) || ((fails++))
  # Stills (library, game book, video) in this pose; allposes.sh re-presses the pose, ~15 s. STILLS=0 skips.
  [[ ${STILLS:-1} == 1 ]] && timed env POSES=$p $here/allposes.sh $out/stills $sha >/dev/null 2>&1
done
note "== done: $fails failing step(s), $SECONDS s total"
exit $(( fails > 0 ))
