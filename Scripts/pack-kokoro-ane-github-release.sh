#!/bin/sh
# Build the English Neural Engine Kokoro zip that Kudos downloads from GitHub
# Releases (not Hugging Face). Layout matches FluidAudio's cache:
#
#   kokoro-82m-coreml/ANE/<7 mlmodelc bundles + vocab.json + 28 <voice>.bin>
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

for rel in ANE/vocab.json g2p_vocab.json us_lexicon_cache.json
do
  fetch "$rel"
done

# Voice packs. FluidInference publishes only af_heart.bin for the ANE variant,
# but a voice pack is not precision-dependent at all: it is a flat [510, 256]
# little-endian fp32 style-vector blob (522,240 bytes), and fp16-vs-int8 is a
# property of the *model weights*, not of these vectors.
#
# hexgrad/Kokoro-82M ships each voice as a `.pt`, which is a zip whose
# `<name>/data/0` member is exactly that raw fp32 payload. Verified: the
# extracted af_heart payload is byte-identical to FluidInference's published
# af_heart.bin. So every voice can be produced with the Python stdlib, no
# torch and no numpy.
#
# Only the American (a*) and British (b*) English voices are packed — the
# other locales need a G2P frontend the English variant does not have.
KOKORO_HF="https://huggingface.co/hexgrad/Kokoro-82M/resolve/main/voices"
VOICES="af_alloy af_aoede af_bella af_heart af_jessica af_kore af_nicole \
af_nova af_river af_sarah af_sky am_adam am_echo am_eric am_fenrir am_liam \
am_michael am_onyx am_puck am_santa bf_alice bf_emma bf_isabella bf_lily \
bm_daniel bm_fable bm_george bm_lewis"

for voice in $VOICES
do
  echo "GET voices/$voice.pt"
  curl -fsSL --retry 3 -o "$WORKDIR/$voice.pt" "$KOKORO_HF/$voice.pt"
  python3 - "$WORKDIR/$voice.pt" "$WORKDIR/kokoro-82m-coreml/ANE/$voice.bin" <<'PYEOF'
import sys, zipfile
src, dst = sys.argv[1], sys.argv[2]
name = src.split("/")[-1][: -len(".pt")]
with zipfile.ZipFile(src) as z:
    member = next(n for n in z.namelist() if n.endswith("/data/0"))
    payload = z.read(member)
expected = 510 * 256 * 4
if len(payload) != expected:
    raise SystemExit(f"{name}: expected {expected} bytes, got {len(payload)}")
with open(dst, "wb") as out:
    out.write(payload)
PYEOF
  rm -f "$WORKDIR/$voice.pt"
done
echo "packed $(printf '%s\n' $VOICES | wc -l | tr -d ' ') English voices"

(
  cd "$WORKDIR"
  ditto -c -k --keepParent kokoro-82m-coreml "$OUT"
)

shasum -a 256 "$OUT"
ls -lh "$OUT"
echo "Upload with:"
echo "  gh release create kokoro-ane-coreml-1 '$OUT' --repo cidy02/kudos-ao3-reader --title 'Kokoro Neural Engine pack'"
