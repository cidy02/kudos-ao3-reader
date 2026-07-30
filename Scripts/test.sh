#!/bin/sh
# Runs the KudosTests unit tests on an iOS Simulator.
#
#   Scripts/test.sh                                   # default simulator
#   Scripts/test.sh 'platform=iOS Simulator,name=iPhone 16'   # pick a device
#
# Code signing is disabled for the simulator (Readium resource bundles carry
# xattrs that block signing on the readium-migration branch).
#
# Parallel testing is disabled: PersistenceOperationGate is a process-wide
# static lock (intentionally global in the real app, since only one instance
# ever runs) that several PersistenceSyncTests/KudosBackupTests/FolderSyncTests
# exercise directly — running suites in separate concurrent simulator clones
# lets them spuriously contend the same gate and fail non-deterministically.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# The OS is pinned deliberately. Without it xcodebuild resolves `OS:latest`, and
# once an iOS 27 runtime is installed `latest` means 27 — where no plain
# "iPhone 17" device exists (only Pro Max / 17e / Air), so the run dies with
# "Unable to find a device matching the provided destination" instead of testing
# anything. Same pin as `verify.sh`; pass an explicit destination to override.
DEST="${1:-platform=iOS Simulator,name=iPhone 17,OS=26.5}"

xcodebuild test \
  -project "$ROOT/AO3_App_OpenSource.xcodeproj" \
  -scheme AO3_App_OpenSource \
  -destination "$DEST" \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO
