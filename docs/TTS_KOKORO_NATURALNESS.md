# Kokoro EPUB TTS Naturalness (iOS)

Long-form Read Aloud for Neural Engine Kokoro. The hypothesis is that
**segmentation, phoneme-aware packing, punctuation, and pauses** move
perceived naturalness more than FP16 vs palettized INT8.

No cloud TTS, no LLM, no upload of book text. The synthesizer is still
FluidAudio `KokoroAneManager` on the dense FP16 pack
`kokoro-ane-coreml-fp16-1`.

## 1. Existing architecture (before)

1. `ReaderSpeechController` walks Readium `publication.content(from:)` for
   the current spine resource only (streaming, not the whole book).
2. Each HTML block **and** each `<br>` becomes a `TTSSpeechUnit`.
3. `TTSSpeechUnit.sentenceChunks` concatenates the chapter, then
   `NLTokenizer` emits **one sentence per inference** (max 250 characters).
4. `CoreMLKokoroTTSService` calls `synthesizeDetailed(text:)` per sentence
   and plays the raw 24 kHz PCM with one-chunk lookahead.
5. No pause model, no pronunciation overrides, no phoneme cache.

Readium's HTML iterator always sets `TextContentElement.role = .body`, so
headings, quotes, and empty `<hr>` are not typed. CSS selectors on the
locator (`h2`, `blockquote`, `hr`) plus text heuristics are the remaining
structure.

## 2. Problems found

| Issue | Effect |
|---|---|
| Sentence-at-a-time inference | Isolated `"No."` / `"Home."` sound like citation clips |
| Character cap 250, not IPA length | Too short for Kokoro's 100–200 token sweet spot; never used the real G2P length |
| Flattened chapter | Paragraph and scene pauses were whatever Kokoro put at the clip edge |
| Curly apostrophes | Misaki `#774`: `wasn’t` can tokenize as `was` if not folded to `'` |
| No pronunciation layer | Fanfic names always go through BART G2P |
| MiniZip `unzip` | Nested `.mlmodelc/...` paths on iOS failed with `pathTraversal`, so the Neural Engine pack would not install |

G2P happens inside FluidAudio (`phonemes(for:)` → Misaki lexicon + BART
fallback). PCM was concatenated as generated. The Core ML graphs are
**dynamic** `[1, T_enc]`, not static 64/128/256 buckets.

## 3. Changes made

- Conservative `KokoroSpeechNormalizer` (apostrophes, ellipses, dashes,
  quotes, whitespace). Does not rewrite prose.
- `KokoroSemanticDocument` groups Readium units into heading / paragraph /
  dialogue / blockquote / scene-break using CSS selectors + text. Units that
  share a `cssSelector` are a `<br>` seam, not a merge. `.dialogue` does
  not join adjacent non-dialogue; adjacent dialogue still may.
- `KokoroUtterancePacker` packs those blocks to ~110–220 IPA characters,
  merges short fragments, balances long-paragraph leftovers.
- `KokoroPauseAssembler` trims edge silence (zero-crossing) and inserts
  structure-based pauses.
- `KokoroPronunciationStore` JSON (global / fandom / work). Empty by
  default; wired into `setEnglishCustomLexicon`.
- Session phoneme cache (128 entries, revision-keyed).
- MiniZip: component-wise extract paths, symlink-resolved staging root,
  directory-entry trailing slash, skip `__MACOSX` / `._*`.

Apple TTS uses `packedChunks`, partitioned on a shared `cssSelector` so a
`<br>` is a new `AVSpeechUtterance` rather than running prose. Sherpa's
`sentenceChunks` path still concatenates for G2P context.

## 4. Chunking algorithm

| Knob | Value | Role |
|---|---|---|
| Preferred target | 175 IPA chars | Group **whole sentences** together; never a cut point |
| Preferred range | 110–220 | Same grouping band |
| Soft upper | 250 | Extra room when merging short dialogue |
| Model limit | 510 | Only size that may split a complete sentence |
| Core ML buckets | none | Albert input is `[1, T_enc]` |

A complete NLTokenizer sentence is atomic. 175/220 only decides whether the
*next* sentence joins this inference. A 300-token sentence is sent whole.
`;` `:` `—` / comma / words run only if that one sentence would exceed 510.
Playback uses the same rule on the real G2P string.

Short fragments under 40 estimated IPA chars merge with neighbors in the
**same** block. Headings and scene breaks never merge with body.

## 5. Pause strategy

1. RMS (5 ms windows, threshold 0.006) finds first/last voiced sample.
2. Keep 20 ms of original edge; snap the cut to a nearby zero crossing.
3. Append zeros:

| Boundary | Duration |
|---|---|
| Continuation in a packed paragraph | 140 ms |
| Line (`<br>` inside one `<p>`) | 220 ms |
| Paragraph | 320 ms |
| Scene break | 850 ms |
| Chapter heading | 1250 ms |

Last utterance of a chapter gets no extra tail. These are starting points
from the spec, not a listening sweep.

## 6. G2P / normalization

- Kudos folds typographic apostrophes to `'` **before** packing, matching
  `KokoroAneEnglishPhonemizer.normalizeApostrophes` (#774).
- `...` → `…`; `--` / en-dash → em-dash; curly quotes → `"`.
- FluidAudio still runs `EnglishTextNormalizer.normalizeForFrontend` (NeMo
  TN for numbers/currency) then Misaki lexicon + BART G2P.
- Custom lexicon: exact spelling, then lower-case, before Misaki. No
  invented IPA. File:
  `Application Support/TTS_Models/kokoro-pronunciations.json`.

## 7. Core ML / ANE execution

Unchanged routing (`KokoroAneComputeUnits.default`):

| Stage | Units | Why |
|---|---|---|
| Albert, PostAlbert, Alignment, Prosody, Vocoder | `cpuAndNeuralEngine` | RNN / conv stages that stay ANE-resident |
| Noise, Tail (iSTFT) | GPU on iOS 26; CPU on iOS 27+ | FP32 phase/iSTFT; ANE is FP16-only; GPU RNN JIT is unsafe for the other stages |
| G2P BART, Misaki, WAV wrap | CPU | Not part of the 7-stage chain |
| Pause insert / RMS | CPU | Tiny vs vocoder |

Pack: GitHub `kokoro-ane-coreml-fp16-1`, SHA-256
`44705ed4708d703b18e56f5761d000e183eae883db0ac0aac2d5a701bcf6f6f4`.
Vocoder `KokoroNoise_v2` is the atan2/HF-noise fix. Dense FP16 on ANE
stages, dense FP32 on Noise/Tail. Not replaced in this task.

## 8. Performance results

Measured on packing only (no device Instruments pass in this change):

Corpus paragraph
`"No." He stepped backward. "You're lying." Rain stitched the windows. She kept walking.`

| Pipeline | Utterances |
|---|---|
| A Existing `sentenceChunks` | 5 isolated sentences |
| C Semantic + phoneme packing | 1 packed utterance |

Time-to-first-audio: first packed chunk is longer than one sentence, so
TTFA can increase slightly; one-chunk lookahead still covers the next
inference. Real-time factor / ANE energy need an on-device Instruments
session after the pack installs.

## 9. Naturalness evaluation

Offline A/B of **structure**, not audio:

| Variant | What | Result |
|---|---|---|
| A Existing | One NLTokenizer sentence each | Short dialogue is its own clip |
| B Sentence | Same as A (previous Kokoro path) | — |
| C Semantic + phoneme | Packer | Short dialogue merges; headings isolated; `***` not spoken |
| D + pauses | Assembler | Edge silence stripped; paragraph/scene/chapter zeros |
| E Full | C+D+normalizer+pronunciation store | Contractions keep negation; lexicon ready |

Largest structural win is **C (short-utterance merge + paragraph packing)**.
Pause control (D) is the next audible change once the Neural Engine pack
runs on device. Live `af_heart` listening is still required; this change
does not claim a MOS score.

## 10. Remaining opportunities

- User-facing pronunciation editor (store is ready).
- Work/fandom IDs plumbed from the open `SavedWork` into the lexicon call.
- Recover empty `<hr>` that Readium drops (no text element).
- Italics as a mild emphasis hint (Readium flattens `<i>`).
- On-device A/B WAV dump of A vs E on `af_heart`.
- Tune pause ms after listening.
- Phoneme cache keyed by normalized text across chapter seeks.

Do not silently expand into those here.
