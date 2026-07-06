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

xcodebuild build \
  -project "$ROOT/AO3_App_OpenSource.xcodeproj" \
  -scheme AO3_App_OpenSource \
  -destination 'platform=macOS'
