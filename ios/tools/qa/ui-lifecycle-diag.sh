#!/bin/bash
# bug-ui-runner-terminate-flake: what the runner looked like after a UI run failed, so a "Failed to terminate", "does not
# have a process ID" or "Timed out while evaluating UI query" can be traced to its cause next time instead of retried blind.
# Usage: ui-lifecycle-diag.sh <udid> <out dir>. Never fails the caller.
udid=$1; out=$2
mkdir -p "$out"
{
  echo "== uptime"; uptime
  echo "== top CPU (host)"; ps -Ao pid,pcpu,pmem,etime,stat,comm -r | head -25
  echo "== app and test processes"; ps -Ao pid,ppid,pcpu,pmem,etime,stat,command | grep -E 'Playscribe|XCTRunner|testmanagerd|WebContent|backboardd|SpringBoard' | grep -v grep
  echo "== memory"; vm_stat | head -12
} > "$out/processes.txt" 2>&1
# A Playscribe process still alive after XCTest gave up on it: where is its main thread?
for pid in $(pgrep -f 'Playscribe.app/Playscribe' 2>/dev/null); do
  sample "$pid" 3 -file "$out/sample-$pid.txt" > /dev/null 2>&1 || true
done
# Crash or hang reports written during the run.
find ~/Library/Logs/DiagnosticReports -newer build.log \( -iname '*Playscribe*' -o -iname '*XCTRunner*' -o -iname '*testmanagerd*' \) \
  -exec cp {} "$out/" \; 2>/dev/null || true
# The simulator's own log for the app and XCTest around the failure.
xcrun simctl spawn "$udid" log show --last 15m --style compact \
  --predicate 'process == "Playscribe" OR process CONTAINS "XCTRunner" OR process == "testmanagerd" OR (process == "SpringBoard" AND eventMessage CONTAINS[c] "playscribe")' \
  2>/dev/null | tail -3000 > "$out/simulator.log" || true
ls -la "$out" | tee -a "$out/index.txt"
exit 0
