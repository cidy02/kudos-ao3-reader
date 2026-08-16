#!/bin/sh
# Runs the KudosTests unit tests on a booted iOS Simulator.
#
#   KUDOS_CASEFOLD_SIMULATOR_UDID=<udid> Scripts/test.sh
#   Scripts/test.sh <udid>
#
# The complete target includes tests that require a case-sensitive APFS image.
# Delegate to the case-fold harness so the normal test gate cannot silently run
# those tests on the host's case-insensitive filesystem.
#
# Parallel testing is disabled: PersistenceOperationGate is a process-wide
# static lock (intentionally global in the real app, since only one instance
# ever runs) that several PersistenceSyncTests/KudosBackupTests/FolderSyncTests
# exercise directly — running suites in separate concurrent simulator clones
# lets them spuriously contend the same gate and fail non-deterministically.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIMULATOR_UDID="${1:-${KUDOS_CASEFOLD_SIMULATOR_UDID:-}}"
if [ -z "$SIMULATOR_UDID" ]; then
  echo "Usage: KUDOS_CASEFOLD_SIMULATOR_UDID=<udid> $0 [udid]" >&2
  exit 64
fi
export KUDOS_CASEFOLD_SIMULATOR_UDID="$SIMULATOR_UDID"
RESULT_BUNDLE_PATH="${KUDOS_TEST_RESULT_BUNDLE:-${TMPDIR:-/tmp}/kudos-tests-$(uuidgen).xcresult}"
exec "$ROOT/Scripts/test-casefold-fonts.sh" "$RESULT_BUNDLE_PATH"
