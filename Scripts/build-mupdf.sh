#!/bin/sh
# Builds MuPDF as an xcframework for Kudos (iOS device + simulator + macOS).
#
#   Scripts/build-mupdf.sh [output-dir]      # default: ./build-mupdf
#
# Why MuPDF: `PDFPage.string` + `characterBounds` is a *text* API, not a *layout*
# API — it does not guarantee reading order and its glyph boxes are frequently
# degenerate. Five separate paragraph bugs came out of reconstructing layout from
# it. MuPDF's structured text ("stext") emits ordered paragraph blocks with
# reliable bounding boxes, which is the data the converter actually needs. See
# docs/PDF_ENGINE_MUPDF.md for the evidence and the licence obligations.
#
# ⚠️ LICENCE: MuPDF is AGPL-3.0. GPL-3 §13 permits the combination, so this is
# legal for Kudos (GPL-3.0), but the combined work carries AGPL terms — including
# the obligation to offer complete corresponding source. Adding this dependency is
# a distribution decision, not just a technical one.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/build-mupdf}"
SRC="$OUT/mupdf"
MIN_IOS=17.0
MIN_MACOS=14.0

mkdir -p "$OUT"

if [ ! -d "$SRC" ]; then
  echo "== cloning MuPDF (shallow, with submodules) =="
  git clone --depth 1 --recurse-submodules --shallow-submodules \
    https://github.com/ArtifexSoftware/mupdf.git "$SRC"
fi

# Features Kudos does not use. Dropping them keeps the static library smaller and
# avoids pulling X11/GL/curl into an app that has no business linking them.
FEATURES="HAVE_X11=no HAVE_GLUT=no HAVE_CURL=no HAVE_LEPTONICA=no HAVE_TESSERACT=no"

# Each slice builds from a *pristine* tree.
#
# This is not belt-and-braces: building slices in sequence into different `OUT`
# directories still produced a mixed-platform archive. A HarfBuzz object
# (`VARC.o`) kept its MACOS build tag inside the simulator's
# `libmupdf-third.a`, because some third-party objects are written outside `OUT`,
# and `xcodebuild -create-xcframework` then rejects the library with "binaries
# with multiple platforms are not supported". `git clean -xfd` between slices is
# what makes each archive single-platform.
build_slice() {
  slice_name="$1"; sdk="$2"; min_flag="$3"
  echo "== building $slice_name =="
  git -C "$SRC" clean -xfdq
  git -C "$SRC" submodule foreach --quiet 'git clean -xfdq' || true

  sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"
  make -C "$SRC" -j"$(sysctl -n hw.ncpu)" libs \
    $FEATURES \
    build=release \
    OUT="build/$slice_name" \
    CC="$(xcrun -f clang) -arch arm64 -isysroot $sysroot $min_flag" \
    AR="$(xcrun -f ar)" RANLIB="$(xcrun -f ranlib)" >"$OUT/$slice_name.log" 2>&1

  # One archive per slice: -create-xcframework takes a single library per platform.
  libtool -static -o "$OUT/libmupdf-$slice_name.a" \
    "$SRC/build/$slice_name/libmupdf.a" \
    "$SRC/build/$slice_name/libmupdf-third.a"
  echo "   $(du -h "$OUT/libmupdf-$slice_name.a" | cut -f1) $OUT/libmupdf-$slice_name.a"
}

build_slice ios-sim    iphonesimulator "-mios-simulator-version-min=$MIN_IOS"
build_slice ios-device iphoneos        "-miphoneos-version-min=$MIN_IOS"
build_slice macos      macosx          "-mmacosx-version-min=$MIN_MACOS"

echo "== packaging MuPDF.xcframework =="
rm -rf "$OUT/MuPDF.xcframework"
xcodebuild -create-xcframework \
  -library "$OUT/libmupdf-ios-sim.a"    -headers "$SRC/include" \
  -library "$OUT/libmupdf-ios-device.a" -headers "$SRC/include" \
  -library "$OUT/libmupdf-macos.a"      -headers "$SRC/include" \
  -output "$OUT/MuPDF.xcframework"

echo
echo "Built $OUT/MuPDF.xcframework"
echo "The xcframework is deliberately NOT committed — it is ~190 MB. Build it"
echo "locally, or attach it to a release, and reference it from the project."
