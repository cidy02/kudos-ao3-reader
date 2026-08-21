# Kokoro TTS Architecture (iOS)

Read Aloud on iOS uses Apple `AVSpeechSynthesizer` until the optional Neural
Engine pack is installed, then FluidAudio's staged Core ML Kokoro 82M.

Sherpa/ONNX is not used for playback. The old 345 MB FP32 `model.onnx` path
could jetsam, and ONNX Runtime's Core ML execution provider never guaranteed
Neural Engine placement.

## Engines

| Engine | Type | When |
|---|---|---|
| `SystemTTSService` | Apple `AVSpeechSynthesizer` | Default; also when the pack is missing |
| `CoreMLKokoroTTSService` | FluidAudio `KokoroAneManager` | Pack installed |

Selection is `ReaderTTSEngineKind.effective` + `ensureEngineForPlayback()` on
every start, so a finished install is used without relaunching.

Readium emits a content element per HTML block **and** each `<br>`. Fanfic
often breaks a sentence across those elements. Neural Engine playback uses
`TTSSpeechUnit.kokoroUtterances`: semantic blocks (heading / paragraph /
dialogue / scene break), conservative apostrophe normalization, phoneme-aware
packing toward ~175 IPA characters, and structure-based pauses after Kokoro's
edge silence is trimmed. Apple TTS still uses `packedChunks`. See
`docs/TTS_KOKORO_NATURALNESS.md`.

## Neural Engine routing

On iOS 27+: `KokoroAneComputeUnits.default` (FluidAudio):

- Albert, PostAlbert, Alignment, Vocoder → `cpuAndNeuralEngine`
- Noise, Tail (iSTFT) → GPU (iOS 26) or CPU (iOS 27)

On **iOS 26.4–26.6** Core ML still dispatches some ops to `libBNNS`
(`BnnsCpuInferenceOperation`, FluidAudio #844) even with `.cpuAndGpu` on
the seven stages — G2P BART was hardcoded `.cpuOnly` (pure BNNS). Device
crashes after GPU routing still faulted in `BNNSGraphContextExecute_v2`
with **no** ANEServices loaded.

Kudos now vendors FluidAudio 0.15.6 (`Packages/FluidAudio`) and:
- loads G2P on `.cpuAndGPU`
- uses synchronous `MLModel.prediction`
- sets `reshapeFrequency = .infrequent`

Seven-stage graphs still use `.cpuAndGpu` on this OS. First load recompiles.
Not Int8. Not a feature gate.

Output is 24 kHz mono Float32 PCM, played through `AVAudioEngine`.

First install downloads the dense FP16 pack
`https://github.com/cidy02/kudos-ao3-reader/releases/download/kokoro-ane-coreml-fp16-1/kokoro-ane-coreml-fp16.zip`
(SHA-256 pinned). ANE stages store dense Float16 (no 8-bit palettes); Noise
and Tail store dense Float32. Unpacks into FluidAudio's Application Support
cache, then compiles for ANE (~20 s cold, ~0.3 s warm). FluidAudio is not
pointed at Hugging Face. A previous palettized pack is not reused — the
install marker is versioned to this tag.

## Apple BNNS (not an app gate)

FluidAudio documents an Apple BNNS `EXC_BAD_ACCESS` on iOS 26.4–26.6
regardless of compute-unit routing (issues #667 / #817 / #844). macOS 26.6 is
verified fixed. **No iOS 26.x build is confirmed fixed; iOS 27 is the first
iOS line FluidAudio does not flag.** Kudos does not hide Kokoro behind that
OS check. Foreground ANE needs no extra entitlement. Background ANE on iOS 27
needs `com.apple.developer.background-tasks.continued-processing.inference`
(not added; provisioning-gated). Audio background mode still keeps playback
alive.

## Settings

Settings offers one optional download: "Kokoro (Neural Engine)". There is no
Int8/FP32 ONNX picker and no experimental ORT Core ML provider toggle.
