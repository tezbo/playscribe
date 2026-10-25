#!/bin/zsh
# tools/posedriver/pose.sh <command…>: runs Duo Pose Driver and prints its output.
rm -f /tmp/posedriver.txt; open -W -a ~/Applications/"Duo Pose Driver.app" --args "$@"; cat /tmp/posedriver.txt
