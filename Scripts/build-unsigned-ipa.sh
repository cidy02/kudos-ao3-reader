#!/bin/sh
# Builds an UNSIGNED .ipa of the iOS app, for sideloading.
#
#   Scripts/build-unsigned-ipa.sh [output-dir]
#
# Output defaults to .build/ipa/Kudos-<short-sha>.ipa (gitignored).
#
# "Unsigned" here means exactly what sideloaders expect: a normal .ipa whose
# Payload/Kudos.app carries no _CodeSignature and no embedded provisioning
# profile, so AltStore / Sideloadly / SideStore / TrollStore can sign it with
# the user's own certificate. It is NOT installable as-is on a stock device.
#
# This is a device (iphoneos) build, not a simulator one — a simulator .app is
# x86_64/arm64-sim and will not run on hardware. It builds with
# CODE_SIGNING_ALLOWED=NO so no developer account or DEVELOPMENT_TEAM is
# needed; AGENTS.md requires DEVELOPMENT_TEAM to stay empty in the committed
# pbxproj, and this script never writes it.
#
# Prerequisites, both gitignored and both fetched/built by their own scripts:
#   Vendor/MuPDF.xcframework   → Scripts/build-mupdf.sh
#   Packages/FluidAudio        → Scripts/fetch-fluidaudio.sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${1:-$ROOT/.build/ipa}"
DERIVED="$ROOT/.build/ipa-derived"
SCHEME="AO3_App_OpenSource"
APP_NAME="Kudos"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "build-unsigned-ipa: xcodebuild not found — this needs macOS with Xcode." >&2
  exit 1
fi

if [ ! -d "$ROOT/Vendor/MuPDF.xcframework" ]; then
  echo "build-unsigned-ipa: missing Vendor/MuPDF.xcframework (gitignored — it is built, not cloned)." >&2
  echo "                    Build it once with:  Scripts/build-mupdf.sh" >&2
  exit 1
fi

if [ ! -d "$ROOT/Packages/FluidAudio" ]; then
  echo "build-unsigned-ipa: missing Packages/FluidAudio — run Scripts/fetch-fluidaudio.sh first." >&2
  exit 1
fi

rm -rf "$DERIVED"
mkdir -p "$OUT_DIR"

# Stamp the build so "which build am I running?" has an answer.
#
# The committed pbxproj pins CURRENT_PROJECT_VERSION = 1 and MARKETING_VERSION =
# 1.0, so every build reported itself as "1.0 (1)" — installing a new IPA over
# an old one looked identical from inside the app, which is exactly the question
# a sideloader needs answered. The commit count is monotonic and numeric, which
# is what CFBundleVersion requires; the short SHA goes in a custom key below,
# since CFBundleVersion cannot hold hex.
#
# Passed on the command line rather than written into the pbxproj: AGENTS.md
# keeps that file low-churn, and a build stamp is a property of the build, not
# of the project.
BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
BUILD_COMMIT="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
BUILD_BRANCH="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"

# Release, so what ships to a sideloader is what a release build does —
# whole-module optimisation included. Signing is off rather than ad-hoc: an
# ad-hoc signature would have to be stripped again before the sideloader could
# apply its own, and Scripts/check-macos-release-entitlements.sh exists
# precisely because a reintroduced ad-hoc sign has bitten this repo before.
xcodebuild build \
  -project "$ROOT/AO3_App_OpenSource.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="" \
  DEVELOPMENT_TEAM="" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

APP="$DERIVED/Build/Products/Release-iphoneos/$APP_NAME.app"
if [ ! -d "$APP" ]; then
  echo "build-unsigned-ipa: expected $APP but the build produced nothing there." >&2
  exit 1
fi

# Written into the built bundle rather than passed as a build setting: these are
# not Xcode-known keys, and adding them to the project would mean editing the
# pbxproj for something only this script cares about. Safe to do post-build
# because the bundle is unsigned — the sideloader signs it afterwards, over this.
plutil -replace KudosBuildCommit -string "$BUILD_COMMIT" "$APP/Info.plist"
plutil -replace KudosBuildBranch -string "$BUILD_BRANCH" "$APP/Info.plist"

# An .ipa is a zip with the .app under Payload/ and nothing else required.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/"

# Belt and braces: strip anything that would make a sideloader's re-sign fail.
# CODE_SIGNING_ALLOWED=NO should leave none of these behind, but a stale
# DerivedData or a future build-setting change could, and a half-signed bundle
# fails at install time with an error that names none of this.
rm -rf "$STAGE/Payload/$APP_NAME.app/_CodeSignature"
rm -f  "$STAGE/Payload/$APP_NAME.app/embedded.mobileprovision"
find "$STAGE/Payload/$APP_NAME.app" -name '_CodeSignature' -type d -prune -exec rm -rf {} + 2>/dev/null || true

SHA="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo nogit)"
IPA="$OUT_DIR/$APP_NAME-$SHA.ipa"
rm -f "$IPA"
# -y keeps symlinks as symlinks: frameworks inside the bundle rely on them, and
# following them instead both bloats the archive and breaks the bundle layout.
( cd "$STAGE" && zip -qry "$IPA" Payload )

echo "build-unsigned-ipa: wrote $IPA (build $BUILD_NUMBER, $BUILD_COMMIT on $BUILD_BRANCH)"
echo "build-unsigned-ipa: unsigned — sign it with AltStore/Sideloadly/SideStore before installing."
