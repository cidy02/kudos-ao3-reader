#!/bin/sh
# Builds the macOS target.
#
#   Scripts/build-macos.sh
#
# Pins DEVELOPER_DIR to a stable (non-beta) Xcode install if one is found.
# Reason: building the macOS scheme's x86_64 slice against a beta Xcode/SDK
# (e.g. Xcode-beta's MacOSX27.0.sdk) triggers a deterministic Swift compiler
# crash ("Found ownership error?!") in vendored SwiftSoup's
# Element.appendNormalisedText — a SIL ownership-verifier bug in the beta
# toolchain itself, not app or SwiftSoup code. The app's actual deployment
# target (see MACOSX_DEPLOYMENT_TARGET in project.pbxproj) is already covered
# by the stable SDK, so pinning here costs nothing.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STABLE_XCODE="/Applications/Xcode.app/Contents/Developer"

if [ -d "$STABLE_XCODE" ]; then
  export DEVELOPER_DIR="$STABLE_XCODE"
else
  echo "warning: $STABLE_XCODE not found; building with the active DEVELOPER_DIR." >&2
  echo "warning: if that's a beta Xcode, the macOS build may hit a SwiftSoup SIL-verifier crash." >&2
fi

# Config half first so a signing-regression fails before a multi-minute build.
"$ROOT/Scripts/check-macos-release-entitlements.sh"

xcodebuild build \
  -project "$ROOT/AO3_App_OpenSource.xcodeproj" \
  -scheme AO3_App_OpenSource \
  -destination 'platform=macOS'

# WPD-2: nothing in the repo previously built Release, so the product half
# of the entitlement guard (get-task-allow / sandbox / hardened runtime)
# never ran. Build Release and hand the .app to the same script.
RELEASE_DD="$ROOT/.build/release-macos"
xcodebuild build \
  -project "$ROOT/AO3_App_OpenSource.xcodeproj" \
  -scheme AO3_App_OpenSource \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$RELEASE_DD"

RELEASE_APP="$RELEASE_DD/Build/Products/Release/Kudos.app"
"$ROOT/Scripts/check-macos-release-entitlements.sh" "$RELEASE_APP"
