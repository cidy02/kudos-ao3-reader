#!/bin/sh
# G8: archive, export with Developer ID, notarize, and staple the macOS Release build.
#
#   Scripts/notarize-macos.sh
#
# arm64 only — this project does not support Intel Macs (Vendor/MuPDF.xcframework
# has no x86_64 slice for macOS, and that's expected, not a bug).
#
# Four real Apple steps, and they are NOT interchangeable or reorderable:
#
#   1. xcodebuild archive       — uses whatever identity Automatic signing
#                                  resolves to at archive time. This is NOT
#                                  Developer ID Application even with
#                                  DEVELOPMENT_TEAM set correctly — forcing
#                                  CODE_SIGN_IDENTITY="Developer ID Application"
#                                  at archive time fails with "conflicting
#                                  provisioning settings" (confirmed). Let
#                                  Automatic signing do whatever it does here;
#                                  it gets thrown away at step 2.
#   2. xcodebuild -exportArchive — THIS is the step that actually re-signs
#                                  with Developer ID Application, driven by
#                                  -exportOptionsPlist method=developer-id.
#                                  Verified end to end 2026-08-16: the export
#                                  succeeds, `codesign -dv` on the result shows
#                                  Authority=Developer ID Application: Yan Cid
#                                  (NQH85H7343) -> Developer ID Certification
#                                  Authority -> Apple Root CA, and
#                                  check-macos-release-entitlements.sh passes
#                                  against it.
#   3. xcrun notarytool submit   — needs a ONE-TIME credential setup this
#                                  script cannot do for you (see below). Fails
#                                  with a clear, actionable message if the
#                                  keychain profile doesn't exist yet, rather
#                                  than a confusing auth error.
#   4. xcrun stapler staple      — attaches the notarization ticket so the app
#                                  opens offline without a Gatekeeper network
#                                  check.
#
# One-time setup the owner must do interactively (this script cannot do it —
# it needs an Apple ID password and there is no way to do that non-interactively
# without you supplying a plaintext credential, which we don't):
#
#   1. Generate an app-specific password at https://appleid.apple.com
#      (Sign-In and Security -> App-Specific Passwords).
#   2. Store it in this Mac's keychain, once, ever:
#
#        xcrun notarytool store-credentials "AC_NOTARIZE" \
#          --apple-id "yan.cid@icloud.com" \
#          --team-id "NQH85H7343" \
#          --password "<the app-specific password from step 1>"
#
#      This prompts interactively and writes to the login keychain; it is not
#      stored in this repo or by this script. "AC_NOTARIZE" is the keychain
#      profile name this script expects (KEYCHAIN_PROFILE below); use a
#      different value there if you name it something else.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STABLE_XCODE="/Applications/Xcode.app/Contents/Developer"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-AC_NOTARIZE}"
TEAM_ID="${TEAM_ID:-NQH85H7343}"

if [ -d "$STABLE_XCODE" ]; then
  export DEVELOPER_DIR="$STABLE_XCODE"
fi

# Config half first so a signing-regression fails before a multi-minute build.
"$ROOT/Scripts/check-macos-release-entitlements.sh"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/kudos-notarize.XXXXXX")"
cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT INT HUP TERM

# Only the disposable intermediates (archive, zip) live under the
# auto-cleaned WORKDIR. The exported .app is the actual deliverable, so it
# goes in the same stable, non-cleaned location build-macos.sh already uses
# for its Release build — putting it under WORKDIR would delete it via the
# EXIT trap moments after the final success message tells you to copy it
# out, which is not a real chance to do so.
ARCHIVE="$WORKDIR/Kudos.xcarchive"
EXPORT_DIR="$ROOT/.build/notarized-macos"
EXPORT_OPTIONS="$WORKDIR/export-options.plist"
ZIP_PATH="$WORKDIR/Kudos-for-notarization.zip"
rm -rf "$EXPORT_DIR"

echo "==> 1/4 Archiving (arm64, Release)"
xcodebuild archive \
  -project "$ROOT/AO3_App_OpenSource.xcodeproj" \
  -scheme AO3_App_OpenSource \
  -destination 'platform=macOS,arch=arm64' \
  -archivePath "$ARCHIVE" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  DEVELOPMENT_TEAM="$TEAM_ID"

cat > "$EXPORT_OPTIONS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>developer-id</string>
	<key>teamID</key>
	<string>$TEAM_ID</string>
	<key>signingStyle</key>
	<string>automatic</string>
</dict>
</plist>
EOF

echo "==> 2/4 Exporting with Developer ID Application"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS"

EXPORTED_APP="$EXPORT_DIR/Kudos.app"
if [ ! -d "$EXPORTED_APP" ]; then
  echo "FAIL: export succeeded but $EXPORTED_APP does not exist." >&2
  exit 1
fi

# Same product-half check WPD-2 already runs after a plain Release build —
# notarization does not change entitlements, so this should still pass.
"$ROOT/Scripts/check-macos-release-entitlements.sh" "$EXPORTED_APP"

# notarytool needs a zip/dmg/pkg, not a raw .app bundle.
/usr/bin/ditto -c -k --keepParent "$EXPORTED_APP" "$ZIP_PATH"

echo "==> 3/4 Submitting to notarytool (profile: $KEYCHAIN_PROFILE)"
if ! xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" >/dev/null 2>&1; then
  cat >&2 <<EOF
FAIL: no notarytool credentials found under keychain profile "$KEYCHAIN_PROFILE".

This is a one-time setup only you can do (needs your Apple ID password):

  1. Generate an app-specific password: https://appleid.apple.com
     (Sign-In and Security -> App-Specific Passwords)
  2. Run once:
       xcrun notarytool store-credentials "$KEYCHAIN_PROFILE" \\
         --apple-id "yan.cid@icloud.com" \\
         --team-id "$TEAM_ID" \\
         --password "<app-specific password>"

Then re-run this script.
EOF
  exit 1
fi

xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$KEYCHAIN_PROFILE" --wait

echo "==> 4/4 Stapling"
xcrun stapler staple "$EXPORTED_APP"

echo ""
echo "notarize-macos: OK — notarized and stapled: $EXPORTED_APP"
