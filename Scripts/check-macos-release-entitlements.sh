#!/bin/sh
# M13 / M18: fail if a macOS Release product (or this tree's Release config)
# is still an ad-hoc debug-shaped sign.
#
#   Scripts/check-macos-release-entitlements.sh              # pbxproj + entitlements file
#   Scripts/check-macos-release-entitlements.sh /path/Kudos.app
#
# The pbxproj + entitlements-file half is what CI can run (GitHub runners
# cannot build this SDK). INJECT_BASE=NO means Kudos.entitlements IS the
# whole macOS Release entitlement set — this script reads that file.
# The optional product half dumps `codesign -d --entitlements -` and fails
# if `get-task-allow` is present or the hardened-runtime flag is missing.
#
# Both CODE_SIGN_ENTITLEMENTS and CODE_SIGN_INJECT_BASE_ENTITLEMENTS must
# be [sdk=macosx*] qualified. Unqualified, they apply to the five-platform
# target and strip iOS Release of its Keychain entitlements (WPD-3).
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

# WPD-7: do not write the extracted block to a predictable /tmp path.
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/kudos-macos-entitlements.XXXXXX")"
cleanup() {
    rm -rf "$WORKDIR"
}
trap cleanup EXIT INT HUP TERM

RELEASE_BLOCK="$WORKDIR/release-xcconfig.txt"

# Extract the AO3_App_OpenSource Release XCBuildConfiguration block only.
# The Debug target still ad-hoc-signs macOS on purpose (local debugging).
awk '
    /Release configuration for PBXNativeTarget "AO3_App_OpenSource"/ { in_block = 1 }
    in_block { print }
    in_block && /name = Release;/ { exit }
' "$PBXPROJ" > "$RELEASE_BLOCK"

# WPD-4: any ad-hoc identity in Release, qualified or not.
# `.*=` (not `[^=]*=`) because an [sdk=macosx*] qualifier itself contains `=`.
if grep -qE 'CODE_SIGN_IDENTITY.*= *"?-"?;' "$RELEASE_BLOCK"; then
    fail "Release sets a CODE_SIGN_IDENTITY of \"-\" (ad-hoc), qualified or not."
fi

# WPD-4: a later SDK-qualified NO beats an unqualified YES.
# Same `=`-inside-qualifier trap as CODE_SIGN_IDENTITY above.
if grep -qE 'ENABLE_HARDENED_RUNTIME.*= *NO;' "$RELEASE_BLOCK"; then
    fail "Release has an ENABLE_HARDENED_RUNTIME override set to NO."
fi
if ! grep -q 'ENABLE_HARDENED_RUNTIME = YES' "$RELEASE_BLOCK"; then
    fail "Release is missing ENABLE_HARDENED_RUNTIME = YES."
fi

# WPD-3: INJECT_BASE=NO is a macOS-only pin. Unqualified, iOS Release loses
# application-identifier / keychain-access-groups and AO3SessionVault falls
# through to the plaintext file vault.
if grep 'CODE_SIGN_INJECT_BASE_ENTITLEMENTS' "$RELEASE_BLOCK" | grep -vq 'sdk=macosx'; then
    fail "Release CODE_SIGN_INJECT_BASE_ENTITLEMENTS is not confined to [sdk=macosx*] (unqualified NO drops iOS Keychain entitlements)."
fi
if ! grep -qE 'CODE_SIGN_INJECT_BASE_ENTITLEMENTS\[sdk=macosx\*\]" = NO;' "$RELEASE_BLOCK"; then
    fail "Release is missing CODE_SIGN_INJECT_BASE_ENTITLEMENTS[sdk=macosx*] = NO (Apple Development injects get-task-allow otherwise)."
fi

# WPD-3: the entitlements file is macOS-shaped (app-sandbox, user-selected
# files). Applying it to iOS replaces Keychain entitlements.
if grep 'CODE_SIGN_ENTITLEMENTS' "$RELEASE_BLOCK" | grep -vq 'sdk=macosx'; then
    fail "Release CODE_SIGN_ENTITLEMENTS is not confined to [sdk=macosx*] (unqualified pin applies to iOS and drops Keychain)."
fi
if ! grep -q 'CODE_SIGN_ENTITLEMENTS\[sdk=macosx\*\]' "$RELEASE_BLOCK"; then
    fail "Release is missing CODE_SIGN_ENTITLEMENTS[sdk=macosx*] (INJECT_BASE=NO without a file drops the sandbox too)."
fi

# WPD-8: folder sync writes the user-selected Library Sync Folder.
if grep -qE 'ENABLE_USER_SELECTED_FILES = readonly;' "$RELEASE_BLOCK"; then
    fail "Release sets ENABLE_USER_SELECTED_FILES = readonly; folder sync writes the Library Sync Folder and needs readwrite."
fi
if ! grep -qE 'ENABLE_USER_SELECTED_FILES = readwrite;' "$RELEASE_BLOCK"; then
    fail "Release is missing ENABLE_USER_SELECTED_FILES = readwrite (folder sync writes the user-selected folder)."
fi

# WPD-1: INJECT_BASE=NO means this file IS the macOS Release entitlement set.
ENT_REL="$(awk '
    /CODE_SIGN_ENTITLEMENTS\[sdk=macosx\*\]/ {
        gsub(/;/, "")
        for (i = 1; i <= NF; i++) {
            gsub(/"/, "", $i)
            if ($i ~ /\.entitlements$/) { print $i; exit }
        }
    }
' "$RELEASE_BLOCK")"

if [ -z "$ENT_REL" ]; then
    fail "Could not parse CODE_SIGN_ENTITLEMENTS[sdk=macosx*] path."
else
    ENT_FILE="$ROOT/$ENT_REL"
    if [ ! -f "$ENT_FILE" ]; then
        fail "CODE_SIGN_ENTITLEMENTS points at $ENT_REL, which does not exist."
    else
        grep -q 'com.apple.security.get-task-allow' "$ENT_FILE" && \
            fail "$ENT_REL declares com.apple.security.get-task-allow (Release is the whole set: INJECT_BASE=NO)."
        grep -q 'com.apple.security.app-sandbox' "$ENT_FILE" || \
            fail "$ENT_REL is missing com.apple.security.app-sandbox."
        grep -qE 'com.apple.security.cs.(disable-library-validation|allow-unsigned-executable-memory|allow-jit|disable-executable-page-protection)' "$ENT_FILE" && \
            fail "$ENT_REL adds a hardened-runtime exception — that defeats ENABLE_HARDENED_RUNTIME."
        grep -q 'com.apple.security.files.bookmarks.app-scope' "$ENT_FILE" || \
            fail "$ENT_REL is missing com.apple.security.files.bookmarks.app-scope (folder sync persists a security-scoped bookmark)."
        grep -q 'com.apple.security.files.user-selected.read-write' "$ENT_FILE" || \
            fail "$ENT_REL is missing com.apple.security.files.user-selected.read-write (folder sync writes the Library Sync Folder)."
    fi
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
        # WPD-6: a bare grep miss is exit 1 and would abort under set -e
        # before the get-task-allow / sandbox / runtime assertions run.
        printf '%s\n' "$DETAILS" | grep -E 'Identifier=|Format=|CodeDirectory|Signature=|Authority=|TeamIdentifier=|flags=' || true

        printf '%s\n' "$ENTITLEMENTS" | grep -q 'com.apple.security.get-task-allow' && \
            fail "Release product still has com.apple.security.get-task-allow."

        printf '%s\n' "$ENTITLEMENTS" | grep -q 'com.apple.security.app-sandbox' || \
            fail "Release product is missing com.apple.security.app-sandbox (empty entitlements is not a pass)."

        printf '%s\n' "$ENTITLEMENTS" | grep -q 'com.apple.security.files.bookmarks.app-scope' || \
            fail "Release product is missing com.apple.security.files.bookmarks.app-scope."

        printf '%s\n' "$ENTITLEMENTS" | grep -q 'com.apple.security.files.user-selected.read-write' || \
            fail "Release product is missing com.apple.security.files.user-selected.read-write."

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
