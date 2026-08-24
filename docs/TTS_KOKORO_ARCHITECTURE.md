# Kokoro TTS Architecture (iOS)

Read Aloud degrades **Core ML Kokoro → Sherpa/ONNX Kokoro → Apple
`AVSpeechSynthesizer`**, and which Kokoro engine is eligible depends on the OS
line.

## Engines

| Engine | Type | When |
|---|---|---|
| `CoreMLKokoroTTSService` | FluidAudio `KokoroAneManager` | **iOS 27+**, Core ML pack installed, no recorded crash |
| `SherpaKokoroTTSService` | sherpa-onnx | **iOS 26.x**, or iOS 27+ after repeated Core ML crashes |
| `SystemTTSService` | Apple `AVSpeechSynthesizer` | Default, and whenever no Kokoro pack is installed |

Selection is `ReaderTTSEngineKind.effective` + `ensureEngineForPlayback()` on
every start, so a finished install is used without relaunching.

### Why iOS 26 does not use Core ML

Core ML Kokoro faults with a `SIGSEGV` inside `libBNNS`
(`BNNSGraphContextExecute_v2`) on the 26.x line — FluidAudio #817 / #844.
Three properties make it undefendable in-process:

- It is **time/environment-gated, not input-gated**: #817 reports the same
  binary going 40/40 pass in the morning to 0/15 crash the same evening on one
  iPhone 17e running iOS 26.5.
- **`cpuOnly` does not avoid it**, because `cpuOnly` *is* BNNS.
- A `SIGSEGV` **cannot be caught**, so there is no `do/catch` and no runtime
  degradation — the app simply dies mid-sentence.

Upstream scopes the bug to 26.x (`KokoroAneComputeUnits.aneTailCpu`: "the
libBNNS segfault is a 26.x-line bug"). So Kudos does not gamble a hard app
kill: on iOS 26 Kokoro means sherpa-onnx, which is why that engine and its
voice-pack download are still first-class and not dead weight.

## Neural Engine routing (iOS 27+)

`KokoroAneComputeUnits.default` — upstream's own measured, OS-aware placement:

- Albert, PostAlbert, Alignment, Prosody, Vocoder → `cpuAndNeuralEngine`
- Noise, Tail (iSTFT) → `cpuOnly` on iOS 27

Noise and Tail are **fp32-only** graphs (the `sin(cumsum)` phase math collapses
in fp16), so the fp16 ANE can take none of them regardless; on iOS 27 they use
CPU rather than GPU because Metal aborts intermittently inside MPSGraph under
Core ML (#843, FB24243070). This is already "the ANE for every workload the ANE
is better at" — Kudos does not second-guess it per stage.

### Degradation after a crash

`KokoroAneHealth` writes a marker file immediately before each synthesis and
removes it immediately after. A marker still present at the next launch means
the process died mid-synthesis — the only available signal, given the fault is
uncatchable. Escalation is per-device and permanent:

| strikes | behaviour |
|---|---|
| 0 | `KokoroAneComputeUnits.default` — ANE per stage |
| 1 | Core ML, every stage `cpuOnly` |
| 2+ | Core ML abandoned; Sherpa/ONNX takes over |

`KokoroAneHealth.reset()` clears the record.

## Text handling

Readium emits a content element per HTML block **and** each `<br>`. Units
split by a `<br>` share a `cssSelector` and become a `.line` pause (0.22 s)
rather than running prose; adjacent `<p>`s do not share a selector and keep
`.paragraph`. Core ML playback uses `TTSSpeechUnit.kokoroUtterances`:
semantic blocks (heading / paragraph / dialogue / scene break), conservative
apostrophe normalization, phoneme-aware packing toward ~175 IPA characters,
and structure-based pauses after Kokoro's edge silence is trimmed. Apple TTS
still uses `packedChunks`. See `docs/TTS_KOKORO_NATURALNESS.md`.

A phoneme string over `KokoroAneConstants.maxPhonemeLength` (510) makes
`KokoroAneVocab.encode` throw, which would end Read Aloud for the whole
chapter. `prepareClip` splits by sentence, then by word, then — for an
unspaced CJK run, a long URL, or a keysmash — halves the raw text.

Output is 24 kHz mono Float32 PCM, played through `AVAudioEngine`.

## The pack

First install downloads
`https://github.com/cidy02/kudos-ao3-reader/releases/download/<tag>/kokoro-ane-coreml-fp16.zip`
(SHA-256 pinned in `KokoroGitHubPack`), verified in bounded chunks and
extracted memory-mapped so a ~180 MB archive does not sit in RAM twice. It
unpacks into FluidAudio's **Application Support** cache (not Caches, which the
system can reclaim), then compiles for ANE (~20 s cold, ~0.3 s warm).
FluidAudio is never pointed at Hugging Face. The install marker is versioned to
the release tag, so bumping the tag re-installs everywhere.

### Voices

A voice pack is a flat `[510, 256]` little-endian fp32 style-vector blob
(522,240 bytes) — **not** precision-dependent. fp16 vs int8 describes the
*model weights*; these vectors are identical either way, so the fp16 Core ML
pack can carry exactly the voice set the int8 Sherpa pack had.

FluidInference publishes only `af_heart.bin` for the ANE variant, but
hexgrad/Kokoro-82M ships every voice as a `.pt` whose `<name>/data/0` zip
member is precisely that raw payload — verified byte-identical to
FluidInference's published `af_heart.bin`. So
`Scripts/pack-kokoro-ane-github-release.sh` builds all **28 English voices**
(`af_*`, `am_*`, `bf_*`, `bm_*`) with the Python stdlib alone, no torch and no
numpy. Other locales are excluded: they need a G2P frontend the English variant
does not have.

`KokoroVoiceCatalog` reads whatever `.bin` files the installed pack actually
contains and derives locale and gender from the identifier (`a` American, `b`
British; `f` female, `m` male). Republishing the pack with more voices
therefore needs **no app change** beyond the tag and SHA in `KokoroGitHubPack`.

## FluidAudio

`Packages/FluidAudio` is **gitignored**, like `Vendor/` (MuPDF). The repo
tracks the pinned upstream revision plus a 106-line patch, not the 6.4 MB tree.
Run `Scripts/fetch-fluidaudio.sh` on a fresh clone; the four patches are
documented in the generated `KUDOS_PATCHES.md`.

Foreground ANE needs no extra entitlement. Background ANE on iOS 27 would need
`com.apple.developer.background-tasks.continued-processing.inference` (not
added; provisioning-gated). The audio background mode still keeps playback
alive.

## Settings

The Read Aloud section offers the one download the device can actually use:
"Kokoro (Neural Engine)" on iOS 27+, or the sherpa-onnx voice pack (with its
Int8/FP32 model and execution-provider pickers) on iOS 26.x. Offering both
would invite a ~180 MB download that will never be loaded.
