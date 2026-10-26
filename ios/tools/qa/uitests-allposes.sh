#!/bin/zsh
# D-9: runs the pose-sensitive UI tests (fold audit, accessibility audit, Swap sides, D-13) in
# every pose. Usage: tools/qa/uitests-allposes.sh <out-dir>
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
out=${1:?out dir}; mkdir -p $out
source ${0:A:h}/poselib.sh
app=co.codeconnectors.playscribe
for p in ${=${POSES:-closed book open open-portrait tabletop}}; do
  set_pose $p
  xcrun simctl spawn $dev defaults write $app pageOnLeft -bool NO
  tests=(-only-testing:PlayscribeUITests/FoldAuditTests -only-testing:PlayscribeUITests/PlayscribeUITests/testAccessibilityAudit)
  [[ $p == book || $p == open ]] && tests+=(-only-testing:PlayscribeUITests/SwapSidesTests)
  [[ $p == book || $p == open ]] && xcrun simctl io $dev recordVideo --display=LCD-1 --force $out/swap-$p.mov >/dev/null 2>&1 &
  xcodebuild -scheme PlayscribeUI -destination "platform=iOS Simulator,id=$dev" \
    -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Playscribe-cli test $tests \
    -resultBundlePath $out/$p.xcresult > $out/$p.log 2>&1
  echo "$p: $(grep -E '\*\* TEST (SUCCEEDED|FAILED)' $out/$p.log)"
  grep -E "error:" $out/$p.log | sed 's/.*error: -\[/  [/' | head -8
  pkill -INT -f recordVideo 2>/dev/null; sleep 2
done
