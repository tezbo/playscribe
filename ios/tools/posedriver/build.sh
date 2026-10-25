#!/bin/zsh
# Rebuilds Duo Pose Driver into ~/Applications, signed with the stable "Playscribe QA Tools"
# identity in ~/Library/Keychains/posedriver.keychain-db so the Accessibility grant survives.
set -e
here=${0:A:h}; out=$(mktemp -d)/"Duo Pose Driver.app"
mkdir -p "$out/Contents/MacOS"; cp $here/Info.plist "$out/Contents/Info.plist"
swiftc -O $here/main.swift -o "$out/Contents/MacOS/posedriver"
xattr -cr "$out"; security unlock-keychain -p qa ~/Library/Keychains/posedriver.keychain-db
codesign --force --keychain ~/Library/Keychains/posedriver.keychain-db -s "Playscribe QA Tools" --identifier co.codeconnectors.playscribe.posedriver "$out"
rm -rf ~/Applications/"Duo Pose Driver.app"; ditto --norsrc "$out" ~/Applications/"Duo Pose Driver.app"
