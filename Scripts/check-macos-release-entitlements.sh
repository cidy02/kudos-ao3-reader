#!/bin/sh
# M13 / M18: fail if a macOS Release product (or this tree's Release config)
# is still an ad-hoc debug-shaped sign.
#
#   Scripts/check-macos-release-entitlements.sh              # pbxproj only
#   Scripts/check-macos-release-entitlements.sh /path/Kudos.app
#
# The pbxproj half is what CI can run (GitHub runners cannot build this
# SDK). The product half dumps `codesign -d --entitlements -` and fails if
# `get-task-allow` is present or the hardened-runtime flag is missing.
#
# A passing local product still is not a distribution sign: this machine
# has Apple Development, not Developer ID Application. Notarization and
# off-team distribution still need a Developer ID identity. Do not invent
# one; do not force CODE_SIGN_IDENTITY to "-" to make Release green.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PBXPROJ="$ROOT/AO3_App_OpenSource.xcodeproj/project.pbxproj"
FAIL=0

fail() {
    FAIL=1
    printf 'FAIL: %s\n' "$1" >&2
}

# --- pbxproj: Release target must not ad-hoc-sign macOS, and must enable HR ---
# Extract the AO3_App_OpenSource Release XCBuildConfiguration block only.
# The Debug target still ad-hoc-signs macOS on purpose (local debugging).
awk '
    /Release configuration for PBXNativeTarget "AO3_App_OpenSource"/ { in_block = 1 }
    in_block { print }
    in_block && /name = Release;/ { exit }
' "$PBXPROJ" > /tmp/kudos-macos-release-xcconfig.txt

if grep -q 'CODE_SIGN_IDENTITY\[sdk=macosx\*\]" = "-"' /tmp/kudos-macos-release-xcconfig.txt; then
    fail "Release still sets CODE_SIGN_IDENTITY[sdk=macosx*] = \"-\" (ad-hoc)."
fi
if ! grep -q 'ENABLE_HARDENED_RUNTIME = YES' /tmp/kudos-macos-release-xcconfig.txt; then
    fail "Release is missing ENABLE_HARDENED_RUNTIME = YES."
fi
if ! grep -q 'CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO' /tmp/kudos-macos-release-xcconfig.txt; then
    fail "Release is missing CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO (Apple Development injects get-task-allow otherwise)."
fi
if ! grep -q 'CODE_SIGN_ENTITLEMENTS' /tmp/kudos-macos-release-xcconfig.txt; then
    fail "Release is missing CODE_SIGN_ENTITLEMENTS (INJECT_BASE=NO without a file drops the sandbox too)."
fi

# --- optional product dump ---
APP="${1:-}"
if [ -n "$APP" ]; then
    if [ ! -d "$APP" ]; then
        fail "No app bundle at $APP"
    else
        echo "== codesign -d --entitlements - =="
        ENTITLEMENTS="$(codesign -d --entitlements - "$APP" 2>&1)" || {
            fail "codesign -d --entitlements failed for $APP"
            ENTITLEMENTS=""
        }
        printf '%s\n' "$ENTITLEMENTS"

        echo "== codesign -d -vv (flags / signature) =="
        DETAILS="$(codesign -d -vv "$APP" 2>&1)" || true
        printf '%s\n' "$DETAILS" | grep -E 'Identifier=|Format=|CodeDirectory|Signature=|Authority=|TeamIdentifier=|flags='

        printf '%s\n' "$ENTITLEMENTS" | grep -q 'com.apple.security.get-task-allow' && \
            fail "Release product still has com.apple.security.get-task-allow."

        printf '%s\n' "$ENTITLEMENTS" | grep -q 'com.apple.security.app-sandbox' || \
            fail "Release product is missing com.apple.security.app-sandbox (empty entitlements is not a pass)."

        printf '%s\n' "$DETAILS" | grep -Eq 'flags=.*runtime' || \
            fail "Release product is missing the hardened-runtime flag (codesign flags should include runtime)."

        printf '%s\n' "$DETAILS" | grep -Eq 'Signature=adhoc|flags=.*adhoc' && \
            fail "Release product is still ad-hoc signed."
    fi
fi

if [ "$FAIL" -ne 0 ]; then
    echo "check-macos-release-entitlements: FAILED" >&2
    exit 1
fi
echo "check-macos-release-entitlements: OK"
exit 0
