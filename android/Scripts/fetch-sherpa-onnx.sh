#!/bin/sh
# Fetches the sherpa-onnx Android AAR (Kokoro TTS engine) into app/libs/.
#
# Not on Maven Central (checked: no com.k2fsa.sherpa.onnx group there) — the
# project only publishes prebuilt AARs as GitHub release assets. Not
# committed to git either (~47 MB binary); this script + app/libs/*.aar in
# .gitignore is the Android counterpart of Scripts/build-mupdf.sh's "fetch a
# vendored binary locally, verify it, don't commit it" pattern.
set -eu

VERSION="1.13.6"
URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/v${VERSION}/sherpa-onnx-${VERSION}.aar"
SHA256="0012d9a28f15bd6fb966b62b70a75da3990512fdccce28b83098248ce4be1698"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/app/libs/sherpa-onnx-${VERSION}.aar"

mkdir -p "$ROOT/app/libs"

if [ -f "$OUT" ] && echo "$SHA256  $OUT" | shasum -a 256 -c - >/dev/null 2>&1; then
  echo "sherpa-onnx-${VERSION}.aar already present and verified."
  exit 0
fi

echo "== fetching sherpa-onnx ${VERSION} AAR =="
curl -fL --progress-bar -o "$OUT.tmp" "$URL"

if ! echo "$SHA256  $OUT.tmp" | shasum -a 256 -c - >/dev/null 2>&1; then
  echo "Checksum mismatch for $OUT.tmp — aborting, not installing." >&2
  rm -f "$OUT.tmp"
  exit 1
fi

mv "$OUT.tmp" "$OUT"
echo "Verified and installed $OUT ($(du -h "$OUT" | cut -f1))"
