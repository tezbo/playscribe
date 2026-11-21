#!/bin/zsh
# Puts the booted iPhone Duo simulator in a pose on a GitHub runner, without a person: pose-stills.yml.
# Usage: tools/qa/ci-pose.sh <udid> <pose>   (closed, closedLandscape, open, openPortrait, book, tabletop)
# Closed poses need nothing (the sim boots closed, on the outer panel). Open, Book and Tabletop need the inner panel, which only
# Device Hub's "Open" control selects. On the Mac, Duo Pose Driver presses it through the Accessibility API with a stable,
# trusted signature (poselib.sh). Here the same driver is built unsigned and run from the job's shell, which works only if the
# runner trusts that shell for Accessibility. Whatever happens, the last line says which panel is active, so the pilot can
# answer "can CI select the inner panel?" from the log.
udid=${1:?udid}; pose=${2:?pose}
here=${0:A:h}
panel() { xcrun devicectl device info displays --device $udid 2>/dev/null | grep -q "LCD-1 (active)" && echo LCD-1 || echo LCD; }
echo "displays before:"; xcrun devicectl device info displays --device $udid 2>&1 | grep -E "LCD|active|Orientation" | head -12
case $pose in
  closed|closedLandscape) echo "pose $pose: outer panel, nothing to press" ;;
  *)
    # Run 1 (88f02f7): the runner trusted the driver for Accessibility and Device Hub was running, but it had no windows, so
    # "Open" was never found. Show the device first (Simulator.app, then Device Hub), and dump the tree before pressing.
    label=Open; [[ $pose == book || $pose == tabletop ]] && label="Partially Open"
    hub=$(xcode-select -p)/../Applications/DeviceHub.app
    [[ -d $hub ]] || hub=$(mdfind "kMDItemCFBundleIdentifier == '*DeviceHub*'" 2>/dev/null | head -1)
    sim=$(xcode-select -p)/Applications/Simulator.app
    echo "device hub: ${hub:-not found}; simulator app: $([[ -d $sim ]] && echo $sim || echo none)"
    [[ -d $sim ]] && { open -a "$sim" --args -CurrentDeviceUDID $udid 2>&1; sleep 10; }
    open -a "$hub" 2>&1; sleep 15
    swiftc -O $here/../posedriver/main.swift -o /tmp/posedriver 2>&1 | grep -E "error" | head -3
    (/tmp/posedriver tree 8 400 >/dev/null 2>&1 & q=$!; sleep 40; kill $q 2>/dev/null); echo "tree:"; head -60 /tmp/posedriver.txt 2>/dev/null
    for i in 1 2 3; do
      /tmp/posedriver press "$label" >/dev/null 2>&1 & q=$!; sleep 15; kill $q 2>/dev/null
      echo "press $label: $(cat /tmp/posedriver.txt 2>/dev/null | tail -2)"
      [[ $(panel) == LCD-1 ]] && break
      open -a "$hub" 2>&1; sleep 5
    done
    [[ $(panel) == LCD-1 ]] || echo "inner panel not selected"
    ;;
esac
echo "displays after:"; xcrun devicectl device info displays --device $udid 2>&1 | grep -E "LCD|active|Orientation" | head -12
echo "panel=$(panel)"
