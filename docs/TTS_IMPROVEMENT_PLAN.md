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
