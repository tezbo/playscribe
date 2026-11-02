#!/bin/zsh
# J-1 journey across a pose change: Closed → tap Patch 1.4 → unfold to Open → the Page shows 1.4.
# Usage: tools/qa/journey.sh <out-dir>
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
out=${1:?out dir}; mkdir -p $out
here=${0:A:h}
source $here/poselib.sh
run() { xcodebuild -project $here/../../Playscribe.xcodeproj -scheme PlayscribeUI -destination "platform=iOS Simulator,id=$dev" \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Playscribe-cli test-without-building -only-testing:PlayscribeUITests/JourneyTests/$1 \
  -resultBundlePath $out/$1.xcresult > $out/$1.log 2>&1; echo "$1: $(grep -E '\*\* TEST (SUCCEEDED|FAILED)' $out/$1.log)"; grep "error:" $out/$1.log | sed 's/.*error: //' | head -3; }
set_pose closed
xcrun simctl io $dev recordVideo --display=LCD --force $out/journey-closed.mov >/dev/null 2>&1 &
run testClosedToOpenKeepsPatch14 &
tp=$!
sleep 60
pkill -INT -f recordVideo; sleep 2
set_pose open
xcrun simctl io $dev recordVideo --display=LCD-1 --force $out/journey-open.mov >/dev/null 2>&1 &
wait $tp
pkill -INT -f recordVideo; sleep 2
