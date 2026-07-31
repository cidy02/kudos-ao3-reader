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

# Size flags, and they matter more than anything else here: a default MuPDF build is
# 54 MB of static library, of which the great majority is **bundled CJK/Noto fonts**
# compiled in as byte arrays, plus parsers for formats Kudos never opens.
#
# Measured on this tree: libmupdf.a 54 MB -> 6.4 MB, and a dead-stripped executable
# that opens a PDF and walks its structured text links at **6.1 MB** total. That is
# the number that matters — a static library is linked, not embedded, so the app pays
# for the objects the linker keeps, not for the archive on disk.
#
# Verified after stripping: structured-text extraction returns byte-identical
# paragraph blocks on the reference PDF. The dropped fonts are only needed to *render*
# glyphs; extraction reads the PDF's own encoding and ToUnicode tables. Base-14 fonts
# are deliberately kept, since some documents lean on their metrics.
#
# FZ_ENABLE_* removes whole document handlers: Kudos reads PDF here and nothing else
# (EPUB is handled by Readium), so XPS/SVG/HTML/EPUB, the JS engine and the OCR path
# all go.
SIZE_FLAGS="-DTOFU_CJK -DTOFU_CJK_EXT -DTOFU_CJK_LANG -DTOFU_NOTO -DTOFU_SIL -DTOFU_SYMBOL \
 -DFZ_ENABLE_XPS=0 -DFZ_ENABLE_SVG=0 -DFZ_ENABLE_HTML=0 -DFZ_ENABLE_EPUB=0 \
 -DFZ_ENABLE_JS=0 -DFZ_ENABLE_OCR=0"

# Each slice overrides **both** CC and CXX, and builds from a pristine tree.
#
# CXX is the one that actually matters, and it cost two failed attempts to find.
# Overriding only CC leaves MuPDF's C++ third-party sources — HarfBuzz is C++ — to be
# compiled by the *host* compiler, so `libmupdf-third.a` ends up holding
# macOS-tagged objects (`VARC.o` was the tell) inside an iOS archive, and
# `xcodebuild -create-xcframework` rejects it with "binaries with multiple platforms
# are not supported". The first theory — stale objects surviving between builds — was
# wrong: the contamination is produced fresh every time by the unset CXX.
#
# `git clean -xfd` stays anyway, because a tree that has already built one platform
# should not be trusted to rebuild another.
build_slice() {
  slice_name="$1"; sdk="$2"; min_flag="$3"
  echo "== building $slice_name =="
  git -C "$SRC" clean -xfdq
  git -C "$SRC" submodule foreach --quiet 'git clean -xfdq' || true

  sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"
  make -C "$SRC" -j"$(sysctl -n hw.ncpu)" libs \
    $FEATURES \
    XCFLAGS="$SIZE_FLAGS" \
    build=release \
    OUT="build/$slice_name" \
    CC="$(xcrun -f clang) -arch arm64 -isysroot $sysroot $min_flag" \
    CXX="$(xcrun -f clang++) -arch arm64 -isysroot $sysroot $min_flag" \
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
echo "Slices are ~16 MB each with the size flags above (~64 MB without). The app"
echo "binary grows by roughly 6 MB once linked and dead-stripped."
echo "The xcframework is deliberately NOT committed — build it locally, or attach it"
echo "to a release, and reference it from the project."
