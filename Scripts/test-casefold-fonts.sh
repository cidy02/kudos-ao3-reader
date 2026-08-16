#!/bin/sh
# Runs the full iOS Simulator test target with a genuinely case-sensitive APFS
# volume mounted inside the installed Kudos app container. The case-fold tests
# fail loudly if this harness is bypassed; they never fall back to the host volume.
set -eu

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 /absolute/path/to/result.xcresult" >&2
  exit 64
fi

RESULT_BUNDLE_PATH=$1
if [ -e "$RESULT_BUNDLE_PATH" ]; then
  echo "Refusing to overwrite existing result bundle: $RESULT_BUNDLE_PATH" >&2
  exit 65
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "${KUDOS_CASEFOLD_SIMULATOR_UDID:-}" ]; then
  echo "Set KUDOS_CASEFOLD_SIMULATOR_UDID to an available booted iOS Simulator UDID." >&2
  exit 64
fi
SIMULATOR_UDID="$KUDOS_CASEFOLD_SIMULATOR_UDID"
CASE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/kudos-casefold.XXXXXX")"
# Keep compiled products outside the per-run image directory so mutation runs can
# reuse them. This path is deliberately never deleted by the harness.
BUILD_ROOT="${KUDOS_CASEFOLD_DERIVED_DATA:-${TMPDIR:-/tmp}/kudos-casefold-derived-data-$SIMULATOR_UDID}"
IMAGE_PATH="$CASE_ROOT/fonts.dmg"
SUMMARY_PATH="$CASE_ROOT/summary.json"
TESTS_PATH="$CASE_ROOT/tests.json"
MOUNT_POINT=
ATTACHING=false
ATTACHED=false
MOUNT_POINT_CREATED=false

cleanup() {
  STATUS=$?
  trap - EXIT HUP INT TERM
  CAN_CLEAN=true
  if [ "$ATTACHED" = true ] || [ "$ATTACHING" = true ]; then
    hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 \
      || hdiutil detach -force "$MOUNT_POINT" >/dev/null 2>&1 \
      || true
    if mount | grep -F " on $MOUNT_POINT (" >/dev/null 2>&1; then
      echo "Could not detach case-sensitive test volume: $MOUNT_POINT" >&2
      CAN_CLEAN=false
      STATUS=1
    fi
  fi
  if [ "$CAN_CLEAN" = true ]; then
    if [ "$MOUNT_POINT_CREATED" = true ] && [ -d "$MOUNT_POINT" ] && ! rmdir "$MOUNT_POINT"; then
      echo "Could not remove case-sensitive test mount point: $MOUNT_POINT" >&2
      STATUS=1
    fi
  fi
  if [ "$CAN_CLEAN" = true ]; then
    for CLEANUP_FILE in "$IMAGE_PATH" "$SUMMARY_PATH" "$TESTS_PATH"; do
      if [ -e "$CLEANUP_FILE" ] && ! unlink "$CLEANUP_FILE"; then
        echo "Could not remove case-sensitive test file: $CLEANUP_FILE" >&2
        STATUS=1
      fi
    done
    if [ -d "$CASE_ROOT" ] && ! rmdir "$CASE_ROOT"; then
      echo "Could not remove case-sensitive test directory: $CASE_ROOT" >&2
      STATUS=1
    fi
  fi
  exit "$STATUS"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT TERM

xcrun simctl bootstatus "$SIMULATOR_UDID" -b
echo "Building test-for-testing bundle for $SIMULATOR_UDID..."
xcodebuild build-for-testing \
  -project "$ROOT/AO3_App_OpenSource.xcodeproj" \
  -scheme AO3_App_OpenSource \
  -destination "id=$SIMULATOR_UDID" \
  -derivedDataPath "$BUILD_ROOT" \
  CODE_SIGNING_ALLOWED=NO

APP_PATH="$BUILD_ROOT/Build/Products/Debug-iphonesimulator/Kudos.app"
if [ ! -d "$APP_PATH" ]; then
  echo "Build-for-testing did not produce the expected app: $APP_PATH" >&2
  exit 67
fi
echo "Installing test host in the simulator..."
xcrun simctl install "$SIMULATOR_UDID" "$APP_PATH"
APP_CONTAINER="$(xcrun simctl get_app_container "$SIMULATOR_UDID" com.cidy02.Kudos data)"
CONTAINER_ROOT="$APP_CONTAINER/Library/Application Support"
MOUNT_POINT="$CONTAINER_ROOT/KudosCaseSensitiveFonts"
mkdir -p "$CONTAINER_ROOT"
# Idempotence. macOS fseventsd opens any mounted volume and holds it, so the
# cleanup detach below can fail with "Resource busy" even with -force and the
# simulator shut down — the mount then survives the run. Refusing outright made
# this harness single-use, which is useless for mutation testing (it needs one
# run per mutant). If a previous run left a volume here, adopt it after proving
# it is genuinely case-sensitive; only refuse a path that is NOT a live volume.
REUSED_EXISTING_MOUNT=false
if [ -e "$MOUNT_POINT" ]; then
  if mount | grep -F " on $MOUNT_POINT (" >/dev/null 2>&1; then
    PROBE="$MOUNT_POINT/.kudos-case-probe-$$"
    if : > "${PROBE}.UP" 2>/dev/null && : > "${PROBE}.up" 2>/dev/null \
       && [ -e "${PROBE}.UP" ] && [ -e "${PROBE}.up" ]; then
      rm -f "${PROBE}.UP" "${PROBE}.up"
      touch "$MOUNT_POINT/.kudos-case-sensitive-fonts"
      REUSED_EXISTING_MOUNT=true
      echo "Reusing the case-sensitive volume already mounted at $MOUNT_POINT"
    else
      rm -f "${PROBE}.UP" "${PROBE}.up" 2>/dev/null || true
      echo "Existing mount at $MOUNT_POINT is not case-sensitive." >&2
      exit 66
    fi
  else
    echo "Refusing to mount over existing non-volume path: $MOUNT_POINT" >&2
    exit 66
  fi
fi
if [ "$REUSED_EXISTING_MOUNT" = false ]; then
  mkdir "$MOUNT_POINT"
  MOUNT_POINT_CREATED=true
  echo "Creating and mounting case-sensitive APFS volume..."
  hdiutil create -quiet -size 64m -fs 'Case-sensitive APFS' \
    -volname KudosCaseSensitiveFonts -type UDIF "$IMAGE_PATH"
  ATTACHING=true
  hdiutil attach -quiet -noverify -nobrowse -mountpoint "$MOUNT_POINT" "$IMAGE_PATH"
  ATTACHED=true
  ATTACHING=false
  # Keep fseventsd and Spotlight off the volume so the cleanup detach can succeed.
  mkdir -p "$MOUNT_POINT/.fseventsd" 2>/dev/null || true
  : > "$MOUNT_POINT/.fseventsd/no_log" 2>/dev/null || true
  : > "$MOUNT_POINT/.metadata_never_index" 2>/dev/null || true
  touch "$MOUNT_POINT/.kudos-case-sensitive-fonts"
fi

echo "Running the complete simulator test target..."
xcodebuild test-without-building \
  -project "$ROOT/AO3_App_OpenSource.xcodeproj" \
  -scheme AO3_App_OpenSource \
  -destination "id=$SIMULATOR_UDID" \
  -derivedDataPath "$BUILD_ROOT" \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO \
  -resultBundlePath "$RESULT_BUNDLE_PATH" || true

if ! xcrun xcresulttool get test-results summary \
  --path "$RESULT_BUNDLE_PATH" --format json > "$SUMMARY_PATH"; then
  echo "Could not read the case-fold test result bundle." >&2
  exit 68
fi
TOTAL_TESTS="$(jq -r '.totalTestCount // 0' "$SUMMARY_PATH")"
PASSED_TESTS="$(jq -r '.passedTests // 0' "$SUMMARY_PATH")"
FAILED_TESTS="$(jq -r '.failedTests // 0' "$SUMMARY_PATH")"
printf 'Case-fold result bundle: %s\nTests: total=%s passed=%s failed=%s\n' \
  "$RESULT_BUNDLE_PATH" "$TOTAL_TESTS" "$PASSED_TESTS" "$FAILED_TESTS"
if [ "$TOTAL_TESTS" -le 0 ]; then
  echo "Case-fold test harness ran zero tests." >&2
  exit 69
fi
if ! xcrun xcresulttool get test-results tests \
  --path "$RESULT_BUNDLE_PATH" --format json > "$TESTS_PATH"; then
  echo "Could not read test names from the case-fold result bundle." >&2
  exit 70
fi
for CASE_TEST_NAME in \
  'zipRestorePreservesAmbiguousCaseFoldedRowsAndFiles' \
  'restorePreservesOneRowAndTwoCaseVariantFilesWhenIncomingMatchesOrphan' \
  'restoreTreatsTwoLocalFilesAsAmbiguousWhenIncomingMatchesDatabaseFile' \
  'legacyDirectoryRestorePreservesAmbiguousCaseFoldedRowsAndFiles' \
  'zipRestoreTreatsTwoLocalFilesAsAmbiguousWhenIncomingMatchesDatabaseFile' \
  'legacyDirectoryRestoreTreatsTwoLocalFilesAsAmbiguousWhenIncomingMatchesDatabaseFile' \
  'syncDownPreservesEveryCaseFoldedDatabaseRow' \
  'syncDownTreatsTwoLocalFilesAsAmbiguousWhenIncomingMatchesDatabaseFile'
do
  if ! jq -e --arg case_test "$CASE_TEST_NAME" \
    '.. | objects
      | select((.name? // "") | contains($case_test))
      | select((.result? // "") == "Passed")' \
    "$TESTS_PATH" >/dev/null; then
    echo "Result bundle did not pass required case-fold test: $CASE_TEST_NAME" >&2
    exit 71
  fi
done
if [ "$FAILED_TESTS" -gt 0 ]; then
  echo "Case-fold test result bundle contains failed tests." >&2
  exit 1
fi
