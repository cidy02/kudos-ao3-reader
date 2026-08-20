#!/bin/sh
# Builds MuPDF as a static library for Android (arm64-v8a), plus the Kudos JNI
# shim, producing app/src/main/jniLibs/<abi>/libkudosmupdf.so.
#
#   android/Scripts/build-mupdf.sh [output-dir]     # default: ./build-mupdf
#
# Android counterpart of the iOS Scripts/build-mupdf.sh — same library, same
# stripping, same reasons. See docs/PDF_ENGINE_MUPDF.md (iOS) for the evidence:
# `PDFPage.string`/`characterBounds` is a *text* API, not a *layout* one, and
# reconstructing paragraphs from it produced five separate defects, the worst
# being prose silently relocated into the wrong paragraph. MuPDF's structured
# text ("stext") emits ordered blocks with reliable bounding boxes, which is the
# data the converter actually needs.
#
# ⚠️ LICENCE: MuPDF is AGPL-3.0. GPL-3 §13 permits the combination, so this is
# legal for Kudos (GPL-3.0), but the combined work carries AGPL terms — including
# the obligation to offer complete corresponding source. Adding this dependency
# is a distribution decision, not just a technical one. iOS already made it.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/build-mupdf}"
SRC="$OUT/mupdf"
ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"

# arm64 only, deliberately: it covers every current physical device and the
# Apple-silicon emulator, and each extra ABI is another full copy of the .so in
# the APK. Add armeabi-v7a here if a 32-bit device ever needs supporting.
ABI="arm64-v8a"
TRIPLE="aarch64-linux-android"
API=26   # matches minSdk

NDK_DIR="$(ls -d "$ANDROID_HOME"/ndk/* 2>/dev/null | sort -V | tail -1)"
[ -n "$NDK_DIR" ] || { echo "No NDK under $ANDROID_HOME/ndk — install one with sdkmanager 'ndk;<version>'" >&2; exit 1; }
TOOLCHAIN="$NDK_DIR/toolchains/llvm/prebuilt/darwin-x86_64"
[ -d "$TOOLCHAIN" ] || TOOLCHAIN="$NDK_DIR/toolchains/llvm/prebuilt/$(uname -s | tr 'A-Z' 'a-z')-x86_64"

mkdir -p "$OUT"

# Pinned, not `master`: two checkouts of the same Kudos commit must link the
# same MuPDF (reproducibility, and so a MuPDF-side regression/CVE doesn't
# silently change under us). This is the commit build-mupdf.sh was last
# actually built and tested against.
MUPDF_COMMIT="9ef7ec2a6e469471f5f74a9af3896c3340c25b9c"

if [ ! -d "$SRC" ]; then
  echo "== cloning MuPDF @ $MUPDF_COMMIT (shallow, with submodules) =="
  # Shallow for the main repo, but NOT --shallow-submodules: MuPDF's submodules
  # have submodules of their own (freetype -> subprojects/dlg), and a shallow
  # fetch there fails with "shallow file has changed since we read it".
  git init -q "$SRC"
  git -C "$SRC" remote add origin https://github.com/ArtifexSoftware/mupdf.git
  git -C "$SRC" fetch --depth 1 origin "$MUPDF_COMMIT"
  git -C "$SRC" checkout -q FETCH_HEAD
  git -C "$SRC" submodule update --init --recursive
fi

# Features Kudos does not use. Dropping them keeps the static library smaller and
# avoids dragging X11/GL/curl into an app that has no business linking them.
FEATURES="HAVE_X11=no HAVE_GLUT=no HAVE_CURL=no HAVE_LEPTONICA=no HAVE_TESSERACT=no"

# Size flags, and they matter more than anything else here: a default MuPDF build
# is tens of MB of static library, the great majority of it **bundled CJK/Noto
# fonts** compiled in as byte arrays, plus parsers for formats Kudos never opens.
#
# The dropped fonts are only needed to *render* glyphs; extraction reads the
# PDF's own encoding and ToUnicode tables. Base-14 fonts are deliberately kept,
# since some documents lean on their metrics.
#
# FZ_ENABLE_* removes whole document handlers. Kudos reads PDF here and nothing
# else — EPUB is Readium's job, exactly as on iOS — so XPS/SVG/HTML/EPUB, the JS
# engine and the OCR path all go.
SIZE_FLAGS="-DTOFU_CJK -DTOFU_CJK_EXT -DTOFU_CJK_LANG -DTOFU_NOTO -DTOFU_SIL -DTOFU_SYMBOL \
 -DFZ_ENABLE_XPS=0 -DFZ_ENABLE_SVG=0 -DFZ_ENABLE_HTML=0 -DFZ_ENABLE_EPUB=0 \
 -DFZ_ENABLE_JS=0 -DFZ_ENABLE_OCR=0"

# -ffunction-sections/-fdata-sections + --gc-sections matter more on Android than
# on iOS: iOS links a static lib and dead-strips into the app binary, so it only
# pays for objects the linker keeps. Android ships the .so itself, so unused code
# must be dropped at link time or it rides along in the APK.
# -fPIC is required: this static library gets linked into a shared object, and
# without it lld rejects the AArch64 absolute relocations ("cannot be used
# against symbol 'TT_RunIns'; recompile with -fPIC").
CFLAGS="$SIZE_FLAGS -Os -fPIC -ffunction-sections -fdata-sections -fvisibility=hidden"

echo "== building MuPDF for $ABI (API $API) =="
# Clean first, then re-materialise the submodules. Cleaning *after* checkout
# empties submodule working trees (mujs vanishes and source/fitz/regexp.c, which
# #includes it unconditionally regardless of FZ_ENABLE_JS, then fails to build).
git -C "$SRC" clean -xfdq
git -C "$SRC" submodule foreach --quiet --recursive 'git clean -xfdq' || true
git -C "$SRC" submodule update --init --recursive --force

make -C "$SRC" -j"$(sysctl -n hw.ncpu)" libs \
  $FEATURES \
  build=release \
  OUT="build/android-$ABI" \
  XCFLAGS="$CFLAGS" \
  CC="$TOOLCHAIN/bin/${TRIPLE}${API}-clang" \
  CXX="$TOOLCHAIN/bin/${TRIPLE}${API}-clang++" \
  AR="$TOOLCHAIN/bin/llvm-ar" \
  RANLIB="$TOOLCHAIN/bin/llvm-ranlib" \
  >"$OUT/mupdf-$ABI.log" 2>&1 || { echo "== MuPDF build failed, tail of $OUT/mupdf-$ABI.log: ==" >&2; tail -n 80 "$OUT/mupdf-$ABI.log" >&2; exit 1; }

echo "   $(du -h "$SRC/build/android-$ABI/libmupdf.a" | cut -f1) libmupdf.a"

echo "== building the Kudos JNI shim =="
JNI_OUT="$ROOT/app/src/main/jniLibs/$ABI"
mkdir -p "$JNI_OUT"

"$TOOLCHAIN/bin/${TRIPLE}${API}-clang" \
  -shared -fPIC -Os -fvisibility=hidden \
  -ffunction-sections -fdata-sections -Wl,--gc-sections -Wl,--strip-all \
  -I"$SRC/include" \
  -o "$JNI_OUT/libkudosmupdf.so" \
  "$ROOT/app/src/main/cpp/kudos_mupdf.c" \
  "$SRC/build/android-$ABI/libmupdf.a" \
  "$SRC/build/android-$ABI/libmupdf-third.a" \
  -lm -llog

echo
echo "Built $JNI_OUT/libkudosmupdf.so ($(du -h "$JNI_OUT/libkudosmupdf.so" | cut -f1))"
echo "jniLibs/ is deliberately NOT committed — build locally, or attach to a release."
