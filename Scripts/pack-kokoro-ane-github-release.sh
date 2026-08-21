#!/bin/sh
# Build the English Neural Engine Kokoro zip that Kudos downloads from GitHub
# Releases (not Hugging Face). Layout matches FluidAudio's cache:
#
#   kokoro-82m-coreml/ANE/<7 mlmodelc bundles + vocab.json + af_heart.bin>
#   kokoro-82m-coreml/G2PEncoder.mlmodelc
#   kokoro-82m-coreml/G2PDecoder.mlmodelc
#   kokoro-82m-coreml/g2p_vocab.json
#   kokoro-82m-coreml/us_lexicon_cache.json
#
# Usage:
#   Scripts/pack-kokoro-ane-github-release.sh [/tmp/kokoro-ane-coreml.zip]
#   gh release create kokoro-ane-coreml-1 /tmp/kokoro-ane-coreml.zip \
#     --repo cidy02/kudos-ao3-reader --title "Kokoro Neural Engine pack" \
#     --notes "English ANE Core ML graphs + G2P for Kudos TTS."
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-${TMPDIR:-/tmp}/kokoro-ane-coreml.zip}"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/kokoro-ane-pack.XXXXXX")"
HF="https://huggingface.co/FluidInference/kokoro-82m-coreml/resolve/main"

cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

fetch() {
  rel="$1"
  dest="$WORKDIR/kokoro-82m-coreml/$rel"
  mkdir -p "$(dirname "$dest")"
  echo "GET $rel"
  curl -fsSL --retry 3 -o "$dest" "$HF/$rel"
}

for bundle in \
  ANE/KokoroAlbert.mlmodelc \
  ANE/KokoroPostAlbert.mlmodelc \
  ANE/KokoroAlignment.mlmodelc \
  ANE/KokoroProsody.mlmodelc \
  ANE/KokoroNoise_v2.mlmodelc \
  ANE/KokoroVocoder.mlmodelc \
  ANE/KokoroTail.mlmodelc \
  G2PEncoder.mlmodelc \
  G2PDecoder.mlmodelc
do
  for name in coremldata.bin metadata.json model.mil weights/weight.bin
  do
    fetch "$bundle/$name"
  done
  curl -fsSL --retry 3 -o "$WORKDIR/kokoro-82m-coreml/$bundle/analytics/coremldata.bin" \
    "$HF/$bundle/analytics/coremldata.bin" || true
done

for rel in ANE/vocab.json ANE/af_heart.bin g2p_vocab.json us_lexicon_cache.json
do
  fetch "$rel"
done

(
  cd "$WORKDIR"
  ditto -c -k --keepParent kokoro-82m-coreml "$OUT"
)

shasum -a 256 "$OUT"
ls -lh "$OUT"
echo "Upload with:"
echo "  gh release create kokoro-ane-coreml-1 '$OUT' --repo cidy02/kudos-ao3-reader --title 'Kokoro Neural Engine pack'"
