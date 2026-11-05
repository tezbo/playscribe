#!/bin/zsh
# Proves the fold harness would have caught the two 0.5.0 gate bugs: put each bug back (a mutant of the fixed code), run
# the harness, and require it to FAIL. Then restore and require it to PASS. Usage: tools/qa/prove_harness.sh [toolbar|deck|all]
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
cd ${0:A:h:h:h} || exit 1   # ios/
which=${1:-all}; dest=${DEST:-"platform=iOS Simulator,name=iPhone Duo"}
xcodegen generate >/dev/null || exit 1
run() { xcodebuild test -scheme Playscribe -destination $dest -only-testing:PlayscribeTests/FoldHarnessTests 2>&1 | tee /tmp/harness-$1.log | grep -E '\*\* TEST|✘|error:' | head -12; grep -q 'TEST FAILED' /tmp/harness-$1.log; }
mutate() { python3 tools/qa/mutants.py $1 apply; }
fails=0
for m in toolbar deck; do
  [[ $which == all || $which == $m ]] || continue
  echo "== mutant: $m (bug put back; the harness must fail)"
  mutate $m || exit 1
  if run $m; then echo "OK: harness caught $m"; else echo "MISS: harness did not catch $m"; ((fails++)); fi
  python3 tools/qa/mutants.py $m restore
done
echo "== clean (the harness must pass)"
run clean && { echo "FAIL: harness fails on the fixed code"; ((fails++)); } || echo "OK: clean passes"
exit $(( fails > 0 ))
