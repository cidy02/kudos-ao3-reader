#!/bin/sh
# Runs the KudosTests unit tests on an iOS Simulator.
#
#   Scripts/test.sh                                   # default simulator
#   Scripts/test.sh 'platform=iOS Simulator,name=iPhone 16'   # pick a device
#
# Code signing is disabled for the simulator (Readium resource bundles carry
# xattrs that block signing on the readium-migration branch).
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-platform=iOS Simulator,name=iPhone 17}"

xcodebuild test \
  -project "$ROOT/kudos-ao3-reader.xcodeproj" \
  -scheme kudos-ao3-reader \
  -destination "$DEST" \
  CODE_SIGNING_ALLOWED=NO
