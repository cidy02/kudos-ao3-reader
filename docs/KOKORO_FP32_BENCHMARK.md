# Kokoro FP32 pack

Official Kokoro English v0.19 FP32 can be installed in-app. The app never
unpacks the ~320 MB `kokoro-en-v0_19.tar.bz2` archive in memory. It downloads
only the immutable official `model.onnx` and copies compatible support files
from the already-installed Int8 Voice Pack.

## Official sources

- Int8 Voice Pack (required first):
  <https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-int8-en-v0_19.tar.bz2>
- Int8 archive SHA-256: `c9f0dd393615805b0bab050c340834d5e684e732aec91c0e860cd30e982c08bd`
- FP32 model only (Hugging Face, pinned revision):
  <https://huggingface.co/csukuangfj/kokoro-en-v0_19/resolve/92805c485745946a0d945562d3aba19e7cbb2104/model.onnx?download=true>
- Model size: `345555491` bytes
- Model SHA-256: `10ff414106a038ce7e9e0126c6461e4dc8a86efaa89dc91d2009d69fe635e339`
- Installed directory: `TTS_Models/kokoro-en-v0_19/`
- Required runtime files: `model.onnx`, `voices.bin`, `tokens.txt`, and the
  complete `espeak-ng-data/` directory (the last three come from Int8).

The app verifies the Int8 archive SHA-256 before extraction. The FP32 installer
copies Int8's `voices.bin`, `tokens.txt`, and `espeak-ng-data/` into a staging
directory, verifies the downloaded model size and SHA-256, then fingerprints the
assembled runtime. Root files are hashed in pack order (`model.onnx`,
`voices.bin`, `tokens.txt`) followed by sorted eSpeak files. They are never
lexically reordered. The pinned runtime fingerprint is
`57dbaeaaab06ab7a813a996be93f0c9c9a1ccb45ef0d9921bc09e0f559cbce6a`. The marker
is written only after that check succeeds, and the staged directory atomically
replaces the destination. Until then, the reader uses the installed Int8 pack
or Apple TTS.

Both Voice Pack downloads are explicit user actions: Int8 uses GitHub and FP32
uses Hugging Face (`csukuangfj/kokoro-en-v0_19`). Kudos does not send book text,
generated audio, AO3 credentials, saved works, reading history, analytics, or
an app-account identifier. However, the selected host or its CDN necessarily
receives an IP address and ordinary connection/request metadata; the consent
sheet says so before either request starts. See [Hugging Face's privacy policy](https://huggingface.co/privacy).

A conservative storage check reserves two copies of `model.onnx` plus support
and filesystem slack (~883 MB) using
`volumeAvailableCapacityForImportantUsage` when the volume reports it.
The shared background manager persists the tagged download or preserved local
file before processing it, rebinds callbacks after relaunch, and defers the
system background-session completion until extraction/install verification
reaches a terminal state.

## Core ML

Playback no longer uses Sherpa or ONNX Runtime's experimental Core ML EP.
iOS Read Aloud uses FluidAudio `KokoroAneManager` (`CoreMLKokoroTTSService`)
with default per-stage compute units so Albert / PostAlbert / Alignment /
Vocoder stay on the Neural Engine. The FP32 ONNX installer in this document
is historical: it is not wired for playback.

FluidAudio still documents a BNNS `EXC_BAD_ACCESS` on iOS 26.4–26.6 (no
confirmed iOS 26.x fix; iOS 27 is the first unflagged iOS line). Kudos does
not hide Kokoro behind that check. See `docs/TTS_KOKORO_ARCHITECTURE.md`.

## Why FP16 is not listed

There is no official Sherpa-compatible Kokoro v0.19 FP16 pack. A standalone or
third-party FP16 ONNX file must not be dropped into this runtime: it has not
been packaged and validated with Sherpa's required model metadata, compatible
`voices.bin`, `tokens.txt`, and complete `espeak-ng-data` layout. A future FP16
option needs a reproducible conversion of the official FP32 pack plus device
validation before it can be offered.

## Residual constraints

- FP32 installation is disk-backed, but the prerequisite Int8 installer still
  uses the legacy BZip2/TAR extraction path and materializes that smaller
  archive in memory. A one-tap, memory-safe first install needs a separately
  pinned support-file distribution.
- Native Core ML / ANE: FluidAudio KokoroAne is now the iOS playback backend
  (`CoreMLKokoroTTSService`). It cannot consume the Sherpa v0.19 `model.onnx`
  + Int8 support layout. Four stages run on the Neural Engine by default; Noise
  and Tail stay on GPU.
- Licensing remains a release review item: Kokoro and Sherpa are Apache-2.0;
  the packaged eSpeak NG data needs its GPL-3.0-or-later attribution and source
  offer handled in the app's third-party notices before a public release.
- The published combined runtime fingerprint was produced for the official
  v0.19 runtime tree. If a future Int8 Voice Pack ships support files that
  differ byte-for-byte from that tree, in-app FP32 install fails closed until
  the pin is recomputed from the assembled files.
