# TTS Improvement Plan — flow, inflection, pronunciation

Working checklist for Read Aloud quality after T-208. Ordered so each phase
unblocks the next; within a phase, order is by payoff over effort.

Architecture context: [`TTS_KOKORO_ARCHITECTURE.md`](TTS_KOKORO_ARCHITECTURE.md).
Naturalness/packing rationale: [`TTS_KOKORO_NATURALNESS.md`](TTS_KOKORO_NATURALNESS.md).

**Everything here is judged by ear.** Phase 0 exists because right now there is
no way to compare two settings without rebuilding and listening to a whole
chapter — which means the ordering below is reasoned from Kokoro's design, not
measured, and may need revising once anyone actually listens.

---

## Phase 0 — make quality judgeable

Nothing else on this list can be evaluated honestly until this exists.

- [ ] **Audition harness.** A settings screen that speaks a fixed sample
      paragraph on demand, with the current voice / speed / pause settings, and
      ideally A/B against the previous setting. Cheapest item here and it gates
      every other one. Include a dialogue-heavy sample and a
      numbers/names-heavy sample, not just clean prose.

---

## Phase 1 — near-free defects

Small, self-contained, each affects every sentence. Do with Phase 0 in place so
the effect is audible.

- [ ] **Pauses ignore speed.** `KokoroPauseAssembler.assemble` inserts
      `pauseSeconds × sampleRate` samples with no `speed` parameter, while
      `speed` *is* passed to the synthesizer. At 1.5× the speech compresses and
      the silence does not, so gaps run ~50% long; at 0.75× they run short.
      Straight defect — anyone who touches the speed slider hears it.
      Fix: thread `speed` in, divide `pauseSeconds` by it.

- [ ] **Curly quotes are collapsed, losing open/close.** Kokoro's `vocab.json`
      carries `“` (U+201C), `”` (U+201D) **and** `"` as three distinct tokens —
      opening and closing quotes cue different intonation.
      `KokoroSpeechNormalizer` maps all of them to `"`, so the model cannot tell
      a line opening from a line closing. In fanfic that is the most common
      prosodic cue in the text.
      Fix: map `“`→`“`, `”`→`”`. Two dependents need updating —
      `KokoroSemanticDocument.classify`'s `normalized.first == "\""` dialogue
      test, and `KokoroUtterancePacker.splitKeepingDelimiter`'s `inQuote`
      toggle (becomes open/close tracking, which is more correct anyway).
      Verify by ear before/after on a dialogue exchange.

- [ ] **Shouted words get spelled out letter-by-letter.** After a lexicon
      miss, `EnglishInitialisms.isCandidate` spells any strict-ASCII all-caps
      token of **2–5 characters** as letter names (`FBI` → `ˈɛf bˈi ˈI`). That
      is right for initialisms and wrong for fanfic: `NOOO` becomes
      "N-O-O-O", and a shouted character name `DRACO!` becomes "D-R-A-C-O".
      Words whose lower-case form *is* in the lexicon (`STOP`, `WHAT`) are
      safe — only misses reach the rule, which is exactly where names and
      stretched interjections live.
      Fix in our layer: down-case an all-caps token before G2P unless it is a
      known initialism. Costs nothing expressively — Kokoro **ignores
      capitalization for emphasis entirely** (see Prior art), so there is no
      loudness being preserved by leaving it upper-case.

- [ ] **AO3 boilerplate is read aloud.** "Chapter Text" headers, author's
      pre/post notes, endnotes, tag dumps, and bare URLs all get spoken. A URL
      spelled out letter-by-letter mid-chapter is the worst of these. Cheap to
      filter, disproportionately noticeable.

---

## Phase 2 — pronunciation

Fanfic's hardest speech problem, and the one place this app has an advantage no
general-purpose TTS can have: **AO3 tags every work with its characters,
relationships, and fandoms** (`AO3Models.swift` — `characters: [String]`,
`relationships: [String]`, `fandoms: [String]`). That is a curated list of
exactly the proper nouns BART G2P will butcher, available *before* playback
starts.

`KokoroPronunciationStore` already persists global / fandom / work layers and
is already wired as tier 1 of the phonemizer's resolution order — it beats the
Misaki lexicon and the BART fallback. **It has no UI at all**, so today a
mispronounced name is permanent.

- [ ] **Pronunciation-fix UI.** Long-press a word while reading →
      "Fix pronunciation". The reader already has text selection.

- [ ] **Respelling input, not IPA.** Nobody types `hɜːrˈmaɪəni`. Accept
      `her-MY-oh-nee` and convert using the lexicon already on disk —
      phonemize each chunk, concatenate, take stress from the capitalised
      syllable. Without this the store is unusable by real users.

- [ ] **"Words I guessed at."** Log BART fallbacks locally during a chapter and
      offer them as a review list. Turns an invisible failure into a fixable
      one, and costs almost nothing given the fallback path is already a
      distinct branch in `KokoroAneEnglishPhonemizer`.

- [ ] **Adopt the established inline override syntax.** Kokoro-FastAPI and
      MisakiSwift both use a markdown-shaped form —
      `[Worcester](/wˈʊstər/)`. Reusing it rather than inventing one means
      power users can paste overrides they already have, and it gives the
      respelling UI an obvious serialized form.

- [ ] **Cast pre-flight.** On opening a work, run the character/relationship
      tags through `manager.phonemes(for:)`, detect which missed the Misaki
      lexicon and fell through to BART, and prompt once: "Before we start, how
      do you say *Aziraphale*?" One prompt per work fixes words that would
      otherwise be mangled hundreds of times.

- [ ] **Fandom seed dictionaries.** The `fandoms` layer exists and is unused.
      Once one person fixes *Hermione* it should be right for every Potter fic
      they open. Ship a seed set for the largest fandoms so most users never
      see a prompt.

---

## Phase 3 — packing and style-row correctness

These two compose: exact phoneme counts are what make dialogue-boundary
splitting land on the right style rows.

Background: `KokoroAneVoicePack.slice(for:)` computes
`row = min(max(phonemeCount - 1, 0), 509)` — **the style vector is indexed by
phoneme count**, so utterance length literally selects the voice's prosodic
character. This is upstream Kokoro's design (`ref_s = voicepack[len(ps)-1]`),
not a quirk.

- [ ] **Replace the estimator with real phoneme counts.**
      `KokoroPhonemeEstimator` guesses IPA length as graphemes × 1.15, but the
      NeMo normalizer expands numbers before G2P ("2024" → 4 graphemes → ~20
      IPA characters), so a date-heavy paragraph can estimate ~200 and actually
      exceed the 510 cap. `prepareClip`'s runtime re-check catches it and
      splits, so it is correct but wasteful — G2P re-runs on the halves. Pack
      against `manager.phonemes(for:)` instead; it is already cached per
      session, so the synthesis call gets it free. Deletes the estimator
      entirely.

- [ ] **Split before the rushing zone, not at the model cap.** Kokoro is
      reported to *rush* on utterances beyond ~400 tokens, and Kokoro-FastAPI
      sets `ABSOLUTE_MAX_TOKENS = 450` despite the same 510 model limit. Our
      `KokoroPhonemeBudget.modelLimit = 510` doubles as the split trigger, so
      a long sentence can legitimately synthesize at ~500 tokens and rush.
      Separate the two constants: keep 510 as the hard `vocab.encode` cap,
      add a ~400 split threshold.

- [ ] **Revisit the packing band (A/B).** Ours is min 110 / target 175 / max
      220. Kokoro-FastAPI ships min **175** / max **250** — their *minimum* is
      our *target*. Worth hearing both.
      Note this pulls against the dialogue item below: their band is tuned for
      continuous narration, whereas a standalone line of dialogue should stay
      short on purpose. Likely answer is a narration band and a dialogue
      exception, not one global band.

- [ ] **Do not merge across dialogue boundaries.** The packer merges whole
      sentences up to 220 IPA chars, so a standalone `"Don't."` gets glued into
      surrounding narration and voiced with a long-form style row instead of
      its own short-utterance row — losing both the delivery and the beat
      around it. `KokoroSemanticDocument` already classifies `.dialogue`, and
      **that classification is currently dead** — the only place it or
      `.blockquote` is consulted is `isBody()`, which treats them exactly like
      `.paragraph`.

---

## Phase 4 — expressiveness

- [ ] **Multi-voice dialogue.** The biggest single upgrade available, and going
      from 1 voice to 28 is what unlocked it. Fic is overwhelmingly dialogue.
      Parse attribution (`"…," said Draco`), assign a voice per character —
      seeded from the character tags already in hand — and keep the narrator
      distinct. Largest piece of work on this list; also the difference between
      "a screen reader" and "an audiobook".

- [ ] **Voice blending — unlimited voices from the 28 we ship.** A voice pack
      is a `[510, 256]` fp32 tensor (`KokoroAneVoicePack.storage`), so mixing
      two voices is a weighted combination of those vectors — Kokoro-FastAPI
      exposes exactly this as `af_bella(2)+af_heart(1)`, normalized to 100%.
      Use **SLERP, not a naive average**: averaging two vectors that point in
      different directions shrinks the result's magnitude and audibly flattens
      the voice.
      This makes the multi-voice item above far more valuable — a large cast
      stops requiring a larger pack, and blends give related-but-distinct
      voices (useful for siblings, or for keeping a narrator adjacent to a POV
      character). Cheap to implement; verify by ear.

- [ ] **Emphasis from EPUB markup.** `<em>`/`<i>`/`<strong>`/`<b>` is authorial
      stress, and in fic italics also mark internal thought. `KokoroSemanticBlock`
      already carries `selector`, but it is only ever tested for `h1-6`,
      `blockquote`, and `hr` — the inline emphasis signal is discarded. Map to
      IPA stress marks or a distinct delivery.

- [ ] **Fanfic's own conventions.** ALL-CAPS shouting, `*asterisk emphasis*`,
      stretched vowels (`noooooo` → lengthened IPA `ː`), interrobangs, trailing
      `…`. These currently reach BART as OOV garbage.

---

## Phase 5 — hard or experimental

- [ ] **Cross-chunk prosody context.** Every chunk is synthesized with no
      knowledge of the chunk before it, so prosody resets at every boundary —
      this is the "reading a list of sentences" quality that separates chunked
      TTS from continuous, and it is the real ceiling on flow. No amount of
      pause tuning reaches it. Standard fix: carry a few words of context into
      each chunk and trim the overlap from the rendered audio. Costs synthesis
      time and is fiddly.

- [ ] **Non-English passages.** Fic drops in Japanese, French, Spanish
      constantly and English G2P mangles it. The pack now ships English voices
      only and the English variant has no other G2P frontend. At minimum
      detect and handle gracefully rather than sounding out romaji; the Kokoro
      model itself does support other locales if a frontend is added.

- [ ] **Intonation arrows — A/B only, do not ship blind.** The vocab also
      carries `→ ↓ ↗ ↘` (level, downstep, rising, falling pitch markers) and we
      emit none of them. Tempting to inject `↗` on questions and `↘` on
      sentence-final falls. **The tokens are verified to exist; the model's
      response to them in arbitrary positions is not.** Feeding a model tokens
      outside its training distribution usually degrades. Requires Phase 0 and
      a fixed test paragraph.

---

## Corpus measurements

`Scripts/epub-to-corpus.py` + `KokoroCorpusDiagnosticTests` run the **real
packer** over real works and report what it does to them. Diagnostic only —
skipped unless `TEST_RUNNER_KOKORO_CORPUS_DIR` is set.

**One work characterises its own author and nothing else.** Prose style varies
enormously between fandoms and writers, and each style stresses a different
part of the pipeline. A measurement showing some feature "isn't a problem" is
only a statement about the works measured so far, never a verdict on the item.
Add works from different fandoms and authors as they come.

### Measured 2026-08-22 — 1 work

| | |
|---|---|
| Corpus | 1 work, Frozen, 2020, 433k words / 11,960 blocks / 103 chapters |
| blocks → utterances | 11,960 → **20,230** |
| est. IPA length | min 4 · p25 103 · med 143 · p75 179 · p95 215 · max 407 |
| below `preferredMin` 110 | **5,648 (27.9%)** |
| above `preferredMax` 220 | 505 (2.5%) |
| above 400 (rushing) | 1 |
| above 510 (throws) | 0 |
| pauses | cont 9,171 · para 10,911 · scene **0** · chapter 148 |

**Caveat on this run:** the corpus TSV carries no CSS selector, so
`KokoroSemanticDocument.classify` fell back to its text-only heading regex,
which matched 74 of 104 headings. The real app gets `locator.locations.cssSelector`
from Readium and detects `h2` directly, so the pause counts above are
harness-specific. The size distribution is not affected.

- [ ] **The packer emits 28% of utterances below its own minimum.** Not
      style-dependent — structural. `packBlock` runs **per block**, and
      `packWholeSentences` can only group sentences *within* one block, so
      every paragraph's remainder is emitted alone however short it is.
      `mergeShort` only rescues fragments under `shortFragment` (40). With one
      block per paragraph, that is ~12,000 chances to emit a runt.
      This is also why the "packer" **increases** unit count by 69% — it is
      net-splitting, not packing.
      Given the style vector is indexed by phoneme count, 28% of the work is
      being voiced with short-utterance style rows the author never implied.
      Fix: allow merging across adjacent same-kind blocks up to
      `preferredMax`, or enforce a floor by pulling the next block's opening
      sentence forward. Interacts with the dialogue item — a short line of
      *dialogue* should stay short deliberately; a short line of narration
      should not.

- [ ] **`<hr>` scene breaks are unexercised.** The measured work uses
      chapter-per-scene and contains no `***`-style markers, so `scene=0` says
      nothing about the detector. `epub-to-corpus.py` now emits `***` for
      `<hr>` so a work that uses them will exercise
      `KokoroSemanticDocument.looksLikeSceneBreak`. Needs a work that has them.

### Predictions this work did not exercise

Recorded so they are not mistaken for resolved. This author writes with
straight quotes, almost no ALL-CAPS, and almost no non-English — so the
corresponding items got no signal, not a negative result:

| Item | This work | Still open because |
|---|---|---|
| Curly-quote open/close | straight 14,273 · curly 719 | **Inverts the fix**: the opportunity is *promoting* straight quotes to curly open/close by position, giving Kokoro the distinction on all 14k rather than preserving 719. Other authors do post curly. |
| All-caps letter-spelling | 22 distinct, ~54 uses; most lowercase to lexicon hits so never reach the rule | Fandoms with quirk typing or heavy caps emphasis would hit it hard |
| Stretched vowels | 9 total | Style-dependent; `AAAAAAH` (7 chars) exceeds the 2–5 window and goes to BART anyway |
| Non-English | `é` ×14 only | Anime/manga fandoms carry romaji and honorifics throughout |
| URLs | 3 | Epistolary and social-media-format works are full of them |
| Numbers | 142, mostly small integers | Estimator under-count needs date/time-heavy prose to show |

## Prior art — what other Kokoro apps do

License check done because this project is **AGPL-3.0**; Apache-2.0, MIT, BSD
and ISC are all one-way compatible *into* AGPL-3.0.

| Project | License | Usable? | Worth taking |
|---|---|---|---|
| [hexgrad/kokoro](https://github.com/hexgrad/kokoro) | Apache-2.0 | ✅ | Reference pipeline — the authority on what the model expects |
| [remsky/Kokoro-FastAPI](https://github.com/remsky/Kokoro-FastAPI) | Apache-2.0 | ✅ | Token band (175/250/450), voice blending, inline IPA syntax |
| [thewh1teagle/kokoro-onnx](https://github.com/thewh1teagle/kokoro-onnx) | MIT | ✅ | Packaging; combined all-voices binary |
| [nazdridoy/kokoro-tts](https://github.com/nazdridoy/kokoro-tts) | MIT | ✅ | Closest use case — an EPUB reader with blending |
| [mlalma/MisakiSwift](https://github.com/mlalma/MisakiSwift) | Apache-2.0 | ✅ | Inline override syntax (G2P itself is redundant — FluidAudio ships one) |
| [lucasjinreal/Kokoros](https://github.com/lucasjinreal/Kokoros) | **none** | ❌ | No license file = all rights reserved. Do not read or adapt. |
| nikkoxgonzales/streaming-tts | **none** | ❌ | Same. |

**Settled by consensus across sources — do not spend time on these:**

- **Kokoro ignores capitalization, emoji, emotion markers (`[excited]`), and
  SSML tags** entirely, or misreads them. There is no markup path to emphasis;
  the levers are punctuation, the phoneme string itself, and the style vector.
- Stacking `!!!` does not increase energy over a single `!`.
- Chunking is *the* quality lever for long-form. Split on sentence and
  paragraph boundaries, never on character counts.

**Punctuation is the prosody API** (already mostly handled by preserving the
vocab's punctuation tokens, but worth knowing when tuning pause lengths — these
are the model's *own* pauses, which our structural pauses stack on top of):

| Mark | Effect |
|---|---|
| `.` | Full stop, intonation resets completely |
| `,` | Brief breath, sentence flow maintained |
| `…` | Trailing pause **0.5–1 s**, falling intonation |
| `;` | Between comma and period |
| `:` | Pause with anticipation |
| `?` | Rising intonation on yes/no questions |
| `!` | Higher energy (one is enough) |

- [ ] **Check for stacked pauses.** `…` already yields a 0.5–1 s pause from the
      model, and `KokoroPauseAssembler` then appends a structural pause on top.
      An ellipsis at a paragraph end may be getting ~1.3 s. Audible check once
      Phase 0 exists.

- [ ] **Default speed 0.9, not 1.0.** Audiobook narration is widely recommended
      at 0.9 (1.05 for ads). We default to 1.0. One-line change to
      `ReaderSpeechPreferences.defaultRate`, but it changes everyone's
      experience — A/B first.

- [ ] **Normalization escape hatch.** Kokoro-FastAPI exposes
      `normalization_options: {normalize: false}` because text normalization
      "can incorrectly remove or change some phrases". We stack two normalizers
      (`KokoroSpeechNormalizer` then NeMo `EnglishTextNormalizer`) with no way
      to inspect or disable either. At minimum a debug toggle, so a
      mispronunciation can be traced to the right stage.

## Known defects and housekeeping

- [ ] **Speed changes need a restart.** `CoreMLKokoroTTSService.speak` captures
      `currentSpeed` into a local at start, so moving the slider mid-playback
      does nothing until the next utterance batch.
- [ ] **Republish the pack with 28 voices.**
      `Scripts/pack-kokoro-ane-github-release.sh` → `gh release create` → bump
      `tag` and `expectedSHA256` in `KokoroGitHubPack`. The published release is
      still the 1-voice build.
- [ ] **Device-test both engines.** Nothing on this branch has produced audible
      audio. Core ML path needs an iOS 27 device; Sherpa path needs iOS 26.
- [ ] **Pre-existing suite failures, unrelated to TTS** — worth their own task.
      9 tests fail identically on commit `2a61aaf4` (before any TTS work, with
      the original MiniZip): `FolderSyncTests` + `KudosBackupFontRestoreTests`
      case-folding, and `WorkStatLabelTests/categoryColorMatchesAO3sOwnCoding`.
- [ ] **`ReaderSpeechSettingsSection` exceeds the SwiftLint type-body-length
      warning** (532 lines) after gaining the Core ML section. Non-blocking;
      split if it grows further.
- [ ] **x86_64 simulators no longer link** — FluidAudio ships an arm64-only
      `libtext_processing_rs.a`. Apple Silicon only, or an upstream issue.
