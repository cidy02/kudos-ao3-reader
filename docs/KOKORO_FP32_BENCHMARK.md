# Kokoro FP32 benchmark pack

This is a developer-only, offline A/B path for the existing Sherpa Kokoro
engine. It does not add a network call to the app: the ordinary Int8 pack keeps
using its existing download flow, while FP32 is prepared on a Mac and copied
into the app container for a controlled benchmark.

## Official source

- Archive: <https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-en-v0_19.tar.bz2>
- Archive SHA-256: `912804855a04745fa77a30be545b3f9a5d15c4d66db00b88cbcd4921df605ac7`
- Required extracted directory: `kokoro-en-v0_19/`
- Required runtime files: `model.onnx`, `voices.bin`, `tokens.txt`, and the
  complete `espeak-ng-data/` directory.

The app verifies the side-load before it becomes selectable. Its runtime
content fingerprint is
`57dbaeaaab06ab7a813a996be93f0c9c9a1ccb45ef0d9921bc09e0f559cbce6a`,
covering the three root runtime files and every regular file in
`espeak-ng-data/`. It writes its verification marker only after that check
succeeds. Until then, the reader uses the installed Int8 pack or Apple TTS.

## Prepare and test

1. Download the archive above on the Mac and verify its archive SHA-256.
2. Extract it on disk; do not use the app's current BZip2/TAR extractor, which
   intentionally avoids the roughly 320 MB compressed FP32 archive.
3. Copy the complete `kokoro-en-v0_19` directory into the app container at
   `Library/Application Support/TTS_Models/`.
4. In Read Aloud settings, select **Full precision (FP32)** and tap
   **Verify Side-Loaded FP32 Pack**. The app creates its marker locally only
   after the complete runtime fingerprint matches.
5. Compare Int8/CPU, Int8/Core ML request, FP32/CPU, and FP32/Core ML request
   on the same passage. Record cold load, real-time factor, audible gaps,
   thermals, and battery. Core ML is an ONNX Runtime execution-provider request
   and does not prove Neural Engine-only execution; confirm actual placement
   with device logs/Instruments.

## Why FP16 is not listed

There is no official Sherpa-compatible Kokoro v0.19 FP16 pack. A standalone or
third-party FP16 ONNX file must not be dropped into this runtime: it has not
been packaged and validated with Sherpa's required model metadata, compatible
`voices.bin`, `tokens.txt`, and complete `espeak-ng-data` layout. A future FP16
option needs a reproducible conversion of the official FP32 pack plus device
validation before it can be offered.
