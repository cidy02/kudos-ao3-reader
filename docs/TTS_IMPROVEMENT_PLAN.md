# Read Aloud quality — findings report and work checklist

Status: **investigation complete, no items implemented.** Follows T-208
(Core ML Kokoro on iOS 27+, Sherpa/ONNX on iOS 26). Tracked as T-209.

Architecture: [`TTS_KOKORO_ARCHITECTURE.md`](TTS_KOKORO_ARCHITECTURE.md) ·
Packing rationale: [`TTS_KOKORO_NATURALNESS.md`](TTS_KOKORO_NATURALNESS.md)

---

## 1. Summary

Three findings are load-bearing, and only one of them was predicted:

1. **The packer emits ~24% of utterances below its own minimum** — every work
   measured, range 17.7–29.8% over 7 fandoms, and it *increases* unit count
   (64,355 blocks → 84,116 utterances). It is net-splitting, not packing.
   Structural, not stylistic. (§4, Phase 2)
2. **The voice pack's style vector is indexed by phoneme count**, so utterance
   length selects the voice's prosodic character. That turns (1) from an
   efficiency issue into a quality one, and makes chunking decisions audible
   rather than merely tidy. (§4, Phase 2)
3. **Pauses ignore the speed setting** — a plain defect that anyone who moves
   the speed slider is already hearing. (§4, Phase 1)

Everything else is smaller, style-dependent, or a proposal.

**The biggest gap is not a defect at all:** there is no way to hear two
settings side by side. Every item here is judged by ear and the only current
method is rebuild-and-listen to a whole chapter. That is why Phase 0 exists and
why the ordering below is provisional.

---

## 2. How these findings were established

Each item is tagged with the strength of its evidence. **Do not promote an item
across tiers without doing the work that tier requires.**

| Tag | Means | Established by |
|---|---|---|
| `[code]` | Read in the source; behaviour is certain | Reading Kudos and FluidAudio source directly |
| `[measured]` | Observed running real code over real input | `KokoroCorpusDiagnosticTests` over a real work |
| `[prior-art]` | Multiple external sources agree | Licence-checked survey of other Kokoro apps (§6) |
| `[proposal]` | Design idea, not validated | Reasoning from the above; **may be wrong** |

Nothing here has been validated by listening. No audio has been produced from
either engine on this branch.

### 2.1 Corpus method

`Scripts/epub-to-corpus.py` converts an EPUB to a `tag<TAB>text` TSV in spine
order. `KokoroCorpusDiagnosticTests` runs the **real** `KokoroUtterancePacker`
over a directory of those and writes `REPORT.txt`. Diagnostic only — skipped
unless `TEST_RUNNER_KOKORO_CORPUS_DIR` is set, so it costs nothing normally.

```
Scripts/epub-to-corpus.py ~/Downloads/Work.epub corpus/
TEST_RUNNER_KOKORO_CORPUS_DIR=$PWD/corpus xcodebuild test \
  -project AO3_App_OpenSource.xcodeproj -scheme AO3_App_OpenSource \
  -destination 'id=<sim-udid>' \
  -only-testing:KudosTests/KokoroCorpusDiagnosticTests
```

Corpora are third-party fiction and stay local. Only the script is tracked.

### 2.2 Limits of the current evidence — read before citing any number

- **One work, one author, one fandom.** Prose style varies enormously and each
  style exercises a different part of the pipeline. A measurement showing some
  feature "isn't a problem" is a statement about the works measured so far and
  **never** a verdict on the item. §5 lists what this work left untested.
- **The harness has no CSS selector.** The TSV carries a tag but
  `TTSSpeechUnit.locator` is `nil`, so `KokoroSemanticDocument.classify` fell
  back to its text-only heading regex, which matched **74 of 104** headings.
  The real app receives `locator.locations.cssSelector` from Readium and
  detects `h2` directly. **Pause counts in §3 are therefore harness-specific.**
  The size distribution is unaffected.
- **No phoneme ground truth.** Sizes are `KokoroPhonemeEstimator` estimates,
  not real IPA counts, because running G2P needs the model pack. The estimator
  under-counts expanded numbers (Phase 2), so real counts will differ, most
  likely upward.
- **Prior art is documentation, not measurement.** The token bands and
  punctuation effects in §6 are what other projects publish. They have not been
  reproduced here.

---

## 3. Corpus measurements

### Run 1 — 2026-08-22 · 1 work

Frozen (2013), 2020, 433k words / 11,960 blocks / 103 chapters.

| Metric | Value |
|---|---|
| blocks → utterances | 11,960 → **20,230** |
| est. IPA length | min 4 · p25 103 · med 143 · p75 179 · p95 215 · max 407 |
| below `preferredMin` 110 | **5,648 (27.9%)** |
| above `preferredMax` 220 | 505 (2.5%) |
| above 400 (rushing zone) | 1 |
| above 510 (would throw) | 0 |
| pauses † | cont 9,171 · para 10,911 · scene **0** · chapter 148 |
| quotes | straight 14,273 · curly 719 |
| all-caps 2–5 tokens | 22 distinct, ~54 uses |
| blocks opening with a quote | 3,319 (27.7%) |

† harness-specific, see §2.2.

`scene=0` says nothing about the detector — this work is chapter-per-scene and
contains no markers. `epub-to-corpus.py` now emits `***` for `<hr>` so a work
that uses them will exercise `looksLikeSceneBreak`.

### Run 2 — 2026-08-22 · 7 works, 7 fandoms

Harvested with `KokoroCorpusHarvestTests`, which drives the app's own
`AO3Client` (§2.1). Top complete English work over 150k words by kudos, per
fandom: Harry Potter, Bleach, Supernatural, Frozen, Naruto, Supergirl,
Criminal Minds. 64,355 blocks total.

| Work (fandom) | blocks → utt. | med | max | < 110 | > 400 | straight q | curly q | caps |
|---|---|---|---|---|---|---|---|---|
| Harry Potter | 22,841 → 23,778 | 152 | **510** | 24.1% | 35 | 608 | 39,711 | **222** |
| Bleach | 3,974 → 7,028 | 164 | 462 | 17.7% | 7 | 2 | 8,748 | 25 |
| Supernatural | 9,182 → 9,261 | 145 | 382 | 29.8% | 0 | 8 | 14,298 | 26 |
| Frozen | 11,960 → 20,230 | 143 | 407 | 27.9% | 1 | 14,273 | 719 | 22 |
| Naruto | 3,296 → 6,962 | 155 | 470 | 18.0% | 1 | 2,615 | **0** | 23 |
| Supergirl | 7,470 → 9,211 | 155 | 439 | 20.5% | 9 | 29 | 11,580 | 51 |
| Criminal Minds | 5,632 → 7,646 | 152 | 496 | 25.8% | 10 | 56 | 11,188 | 31 |
| **ALL** | **64,355 → 84,116** | **151** | **510** | **24.3%** | **63** | **17,591** | **86,244** | **336** |

Scene breaks fired **409** times (283 / 68 / 33 / 25 across four works), so
`looksLikeSceneBreak` is exercised and working — Run 1's `scene=0` was
genuinely an absent feature, not a broken detector.

### Run 3 — 2026-08-22 · 12 works, formatting-diverse

Sorting by kudos finds well-liked work, which is reliably *cleanly typeset*
work — it selects against exactly the formatting a reader app must survive. So
Run 3 samples two ways: by fandom for specific conventions (quirk typing,
transcript framing, broadcast script, multilingual dialogue, footnotes,
military acronyms, unusual typography), and by AO3's **own convention tags**
sorted by date rather than kudos — `Not Beta Read` (the archive's marker for
unedited prose), `Chat Fic`, `Epistolary`, `Social Media`, `Texting`.

| target | blocks → utt | med | max | < 110 | > 400 | straight | curly | caps |
|---|---|---|---|---|---|---|---|---|
| goodomens-footnotes | 9,454 → 11,440 | 147 | **510** | 26.6% | 30 | 834 | 12,676 | 213 |
| halo-acronyms | 2,299 → **11,351** | 175 | 509 | 16.0% | **234** | 4,014 | 2,423 | 164 |
| hetalia-multilingual | 6,194 → 6,372 | 153 | **510** | 25.7% | 121 | 299 | 573 | **637** |
| homestuck-quirk | 3,516 → 6,523 | 146 | 493 | 26.4% | 3 | 3,980 | **0** | 86 |
| magnus-transcript | 3,958 → 4,771 | 156 | 493 | 22.6% | 4 | 269 | 6,364 | 19 |
| messy-chat-fic | 16,266 → 3,479 | 97 | **510** | **55.6%** | 121 | **0** | 2,232 | 570 |
| messy-epistolary | 4,130 → 4,734 | 103 | 503 | **53.0%** | 18 | 752 | **0** | 68 |
| messy-not-beta-read | 1,858 → 3,331 | 154 | 507 | 23.6% | 1 | 3,568 | 767 | 194 |
| messy-social-media | 6,241 → 2,542 | 103 | 498 | **52.7%** | 5 | 8 | 4,016 | 211 |
| messy-texting | 2,874 → 2,759 | **42** | 492 | **78.4%** | 4 | 1,374 | **0** | 5 |
| nightvale-broadcast | 2,324 → 4,342 | 161 | 508 | 21.1% | 15 | 2,343 | 2,232 | 30 |
| undertale-typography | 3,488 → 4,739 | 154 | 471 | 21.6% | 2 | 433 | 5,783 | 30 |
| **ALL** | **62,602 → 66,383** | 148 | **510** | **30.1%** | **558** | 17,874 | 37,066 | **1,308** |

Every headline number gets worse on formatting-diverse input:

- **Short utterances 17.7–29.8% → up to 78.4%.** Non-prose layouts (texting,
  chat, epistolary, social media) are *majority* runts. The packer's band is
  not merely missed there, it is meaningless.
- **Rushing zone 63 → 558.** `halo-acronyms` alone contributes 234, and four
  works touch **510 — the exact cap where `vocab.encode` throws.** Splitting at
  the model limit rather than below it is now clearly wrong.
- **All-caps 336 → 1,308 distinct.** Hetalia 637, chat fic 570.
- **`halo-acronyms` expands 2,299 blocks into 11,351 utterances — 4.9×.**
  The most extreme splitting seen; worth understanding before tuning the band.
- **Quote convention is bimodal, not a spectrum.** Three works have *zero*
  curly quotes; two have *zero* straight. Any fix must handle both, and must
  not assume a work is internally consistent.

### Run 4 — 2026-08-23 · 20 works, gap-fill

Nine targets added specifically to exercise the five predictions Runs 1–3 left
untested. 20 of 21 harvested (`voltron-spanish` returned no AO3 results).

| | Run 3 (12 works) | Run 4 (20 works) |
|---|---|---|
| blocks → utterances | 62,602 → 65,303 | **102,780 → 111,485** |
| median est. IPA | 153 | 147 |
| below `preferredMin` | 28.5% | 31.7% |
| **above 400 (rushing)** | **0** | **0** |
| **above 510 (throws)** | **0** | **0** |
| all-caps distinct | 1,308 | 1,519 |
| quotes straight / curly | 17,874 / 37,066 | 24,299 / 75,837 |

**The `splitThreshold` fix holds on every new convention** — quirk typing,
honorific-dense sports banter, chat/Twitter/Tumblr formats, stardates. Nothing
crossed 400 or 510 anywhere in 111,485 utterances.

#### Verdict on the five predictions

1. **Quirk typing — exercised, confirmed.** Tagging by *format*
   (`Pesterlog(s) (Homestuck)`) rather than fandom found 186 distinct all-caps
   tokens against the fandom-only sample's 86, plus heavy digit-substitution
   typing. Sampling by fandom alone undersampled this.
2. **Honorifics — the premise was WRONG, and the gap never existed.** This
   document previously asserted the Naruto and Bleach works were "plain English
   prose". Re-measuring them directly: the Bleach work carries **208**
   honorific-suffix tokens and the Naruto work **68** (`-san`, `-kun`,
   `-chan`, `-sama`, `-sensei`, `-nii`), verified against raw text, not regex
   false positives. The convention was in the corpus from Run 2 onward and the
   claim of no signal was simply not checked.
3. **URLs — still uncovered; the hedge failed.** `Twitter` and `Tumblr` tags
   contributed **zero** organic URLs — those tags mark *subject matter*, not
   format-with-links. The aggregate rise (28 → 35) came entirely from an
   unrelated work's repeated credit-header links. Needs a different approach.
4. **Number/date density — still uncovered; both hedges underperformed.**
   `time-travel-dates` (0.042/block) and `startrek-stardates` (0.024/block)
   came in *below* the corpus average (0.064–0.079) — the opposite of the
   hypothesis. The architectural concern is nonetheless confirmed by reading
   the code: there is **no digit-expansion logic anywhere in
   `KokoroSpeechNormalizer`**, so numeric text is genuinely under-counted by
   the estimator whenever it occurs.
5. **Non-English — exercised modestly.** A French work adds 19 distinct
   foreign words. `voltron-spanish` found nothing and was a genuine miss.

#### Two measurement contaminations found — both invalidate earlier counts

- **Decorative Unicode is not foreign text.** Python's `unicodedata` classifies
  Mathematical Alphanumeric Symbols and Letterlike Symbols — the stylised
  fancy-font AO3 authors use for *English* headers — as letters. Earlier
  non-ASCII counts conflated those with genuine diacritics. The "14 accented
  characters total" figure from Run 1 is unreliable for this reason: one
  existing work alone carries 127 genuine foreign letters (Spanish, French,
  Portuguese, German) mixed with 288 decorative characters.
- **Leetspeak is not numbers.** Quirk typing substitutes digits for letters
  (`TH3`, `4ND`), which a bare `\d+` counts as numeric. Requiring no adjacent
  letter dropped the Homestuck work's apparent numeric density from 1.13/block
  to 0.07/block.

**Lesson, consistent with §5:** three of the five "uncovered" predictions were
wrong about their own premise — one had signal all along, two had hedges that
measured the opposite of what was expected. A prediction is not evidence, and
neither is a plan to test it.

---

## 4. Findings and checklist

### Phase 0 — make quality judgeable

Nothing below can be evaluated honestly until this exists, and the ordering of
everything below is provisional without it.

- [ ] **Audition harness.** `[proposal]` Speak a fixed sample on demand under
      current settings, ideally A/B against the previous setting. Include a
      dialogue-heavy and a numbers/names-heavy sample, not just clean prose.
      Cheapest item here; gates every other one.

### Phase 1 — defects

- [ ] **Pauses ignore speed.** `[code]` `KokoroPauseAssembler.assemble` inserts
      `pauseSeconds × sampleRate` samples and takes no `speed` parameter, while
      `speed` *is* passed to the synthesizer. At 1.5× the speech compresses and
      the silence does not, so gaps run ~50% long; at 0.75× they run short.
      Fix: thread `speed` through, divide `pauseSeconds` by it.

- [ ] **Curly quotes are collapsed, losing open/close.** `[code]` `[measured]`
      Kokoro's vocab holds `“` (U+201C), `”` (U+201D) **and** `"` as three
      distinct tokens — opening and closing cue different intonation, which is
      the most common prosodic signal in dialogue. `KokoroSpeechNormalizer`
      maps all of them to `"`, discarding it.
      **Corpus says this matters: curly outnumbers straight 86,244 to 17,591**
      across 7 works, and 5 of 7 are overwhelmingly curly. Two works (Frozen,
      Naruto) are straight-dominant, one with *zero* curly quotes — so the fix
      has to handle both directions: **preserve curly where present, and
      promote straight to curly open/close by position where it is not.**
      Dependents: `KokoroSemanticDocument.classify`'s `normalized.first == "\""`
      dialogue test, and `KokoroUtterancePacker.splitKeepingDelimiter`'s
      `inQuote` toggle (becomes open/close tracking, which is more correct).

- [ ] **Shouted words are spelled out letter by letter.** `[code]` After a
      lexicon miss, `EnglishInitialisms.isCandidate` spells any strict-ASCII
      all-caps token of **2–5 characters** as letter names (`FBI` →
      `ˈɛf bˈi ˈI`). Right for initialisms, wrong for fiction: `NOOO` becomes
      "N-O-O-O", a shouted `DRACO!` becomes "D-R-A-C-O". Only *misses* reach
      the rule — `STOP`/`WHAT` resolve normally — which is exactly where names
      and interjections live.
      Fix in our layer: down-case an all-caps token before G2P unless it is a
      known initialism. Costs nothing expressively; Kokoro ignores
      capitalization for emphasis entirely `[prior-art]`.
      `[measured]` Run 1 saw 22 distinct tokens; Runs 2–3 found **336 then
      1,308 distinct** (Hetalia 637, chat fic 570). But **the magnitude that
      matters is still unmeasured, and this item is blocked on it.**
      The rule only fires on tokens that *miss* the Misaki lexicon. Splitting
      the corpus by whether a token's lower-case form appears elsewhere in the
      same work gives 8,065 "shouted" against 1,872 "initialism-ish" — but that
      over-counts enormously, because the shouted set is dominated by `THE`,
      `YOU`, `TO`, `NOT`, `WHAT`, which all resolve at lexicon tier 5 and never
      reach the rule. The genuinely affected set is shouted **proper nouns**
      (`NEWT`, `ROY`, `GIZA`, `SANAZ`, `NARA`, `NANI` in the corpus) — small,
      but they are character names, and they recur.
      **Do not blunt-force down-case.** 1,872 initialism-ish uses include real
      acronyms where letter-spelling is *correct*, 262 of them in the Halo work
      alone. The discriminator needed is "is this in the Misaki lexicon", which
      is precisely what the phonemizer already knows and our layer does not —
      so the clean fix is to ask it, which needs the model pack installed.
      Blocked on a device/pack run, not on design.

- [ ] **AO3 boilerplate is read aloud.** `[proposal]` "Chapter Text" headers,
      author's notes, endnotes, tag dumps, bare URLs. A URL spelled out
      mid-chapter is the worst of them. Cheap, disproportionately noticeable.

### Phase 2 — packing and style-row correctness

**Background** `[code]`: `KokoroAneVoicePack.slice(for:)` computes
`row = min(max(phonemeCount - 1, 0), 509)` — the style vector is indexed by
phoneme count, so **utterance length selects the voice's prosodic character**.
Upstream Kokoro's design (`ref_s = voicepack[len(ps)-1]`), not a quirk. It is
why this phase is about quality and not tidiness.

- [x] **Orphaned block tails — partially fixed 2026-08-22.** `[measured]`
      `[code]` Measuring tails (`pauseAfter != .continuation`) against
      mid-block pieces showed the real shape: **block tails are 2–3× more
      likely to be short than mid-block pieces, in every one of 12 works**
      (prose 30–37% vs 11–18%; texting 83% vs 25%). A block's last group is
      whatever the loop could not place, so it is systematically the runt.
      `packWholeSentences` now absorbs a sub-`preferredMin` tail into the
      previous group when the pair fits `softUpper`, instead of only
      *stealing* one sentence back — stealing needed the previous group to
      hold ≥2 sentences and could leave a fresh runt behind.
      Measured before/after on identical input: **66,915 → 65,303 utterances**
      (−1,612 independent synthesis units), tails 44.5% → 42.2% short, median
      148 → 153. **Trade-off:** above `preferredMax` rose 9.2% → 11.8%, bounded
      by `softUpper` (250) and far under the 400 split threshold.
      **Deliberately not fixed further:** the dominant remaining case is a
      block that yields a *single* short group, where there is nothing
      in-block to merge with. Per the texting / chat / social-media data those
      blocks are genuinely short — a text message, a line of dialogue — and
      Kokoro handles short utterances well. Merging across blocks would buy
      length at the cost of the paragraph pause, which is a real prosodic
      boundary. The residue is correct content, not a defect.

      *Note on the original framing:* this was first written up as "28% voiced
      with style rows the prose never implied". That was wrong — the style row
      for a short utterance *is* the right row for its length; that is the
      design. The cost is **fragmentation**: every extra utterance is another
      independent synthesis with its own prosody reset (see Phase 5).

- [ ] **~~28% of utterances fall below the packer's own minimum.~~** superseded `[measured]`
      `[code]` Structural, not stylistic. `packBlock` runs **per block** and
      `packWholeSentences` can only group sentences *within* one block, so
      every paragraph's remainder is emitted alone however short it is;
      `mergeShort` only rescues fragments under `shortFragment` (40). One block
      per paragraph means ~12,000 chances to emit a runt. It is also why unit
      count *rises* 69% — the packer is net-splitting.
      Fix: merge across adjacent same-kind blocks up to `preferredMax`, or pull
      the next block's opening sentence forward to meet a floor.
      Interacts with the dialogue item below — a short line of *dialogue*
      should stay short deliberately; a short line of narration should not.

- [ ] **Split before the rushing zone, not at the model cap.** `[prior-art]`
      Kokoro is reported to rush beyond ~400 tokens, and Kokoro-FastAPI sets
      `ABSOLUTE_MAX_TOKENS = 450` against the same 510 model limit. Our
      `KokoroPhonemeBudget.modelLimit = 510` doubles as the split trigger, so a
      long sentence can synthesize at ~500 and rush. Separate the constants:
      keep 510 as the hard `vocab.encode` cap, add a ~400 split threshold.
      `[measured]` **63 utterances above 400 across 7 works, and the Harry
      Potter work hits exactly 510** — the model cap — so this is not
      hypothetical. Rare per work, but a single rushed sentence is audible.

- [ ] **Replace the estimator with real phoneme counts.** `[code]`
      `KokoroPhonemeEstimator` guesses IPA length as graphemes × 1.15, but the
      NeMo normalizer expands numbers before G2P ("2024" → 4 graphemes → ~20
      IPA), so a date-heavy paragraph can estimate ~200 and exceed the cap.
      `prepareClip`'s runtime re-check catches it and splits, so it is correct
      but wasteful — G2P re-runs on the halves. Pack against
      `manager.phonemes(for:)`, already cached per session. Deletes the
      estimator, and makes every number in §3 exact.

- [ ] **Do not merge across dialogue boundaries.** `[code]` `[proposal]`
      A standalone `"Don't."` glued into surrounding narration is voiced with a
      long-form style row instead of its own. `KokoroSemanticDocument` already
      classifies `.dialogue` and **that classification is dead** — the only
      place it or `.blockquote` is consulted is `isBody()`, which treats them
      exactly like `.paragraph`. hexgrad specifically improved Kokoro's short
      utterances `[prior-art]`, so short lines are a strength to use.

- [ ] **Revisit the packing band (A/B).** `[prior-art]` Ours is min 110 /
      target 175 / max 220; Kokoro-FastAPI ships min **175** / max **250** —
      their minimum is our target. Their band is tuned for continuous
      narration, so the answer is probably a narration band plus a dialogue
      exception, not one global band.

### Phase 3 — pronunciation

Fanfic's hardest speech problem, and the one place this app has an advantage no
general-purpose engine can have: **AO3 tags every work with its characters,
relationships and fandoms** (`AO3Models.swift`). That is a curated list of
exactly the proper nouns BART G2P will mispronounce, available *before*
playback starts.

`KokoroPronunciationStore` already persists global / fandom / work layers and
is already tier 1 of the phonemizer's resolution order — it beats the Misaki
lexicon and the BART fallback `[code]`. **It has no UI at all**, so today a
mispronounced name is permanent.

- [ ] **Pronunciation-fix UI.** `[proposal]` Long-press a word while reading →
      "Fix pronunciation". The reader already has selection.
- [ ] **Respelling input, not IPA.** `[proposal]` Nobody types `hɜːrˈmaɪəni`.
      Accept `her-MY-oh-nee`, convert with the lexicon already on disk, take
      stress from the capitalised syllable. Without this the store is unusable.
- [ ] **"Words I guessed at."** `[proposal]` Log BART fallbacks locally and
      offer them as a review list. The fallback is already a distinct branch in
      `KokoroAneEnglishPhonemizer`, so this is nearly free.
- [ ] **Adopt the established inline syntax.** `[prior-art]` Kokoro-FastAPI and
      MisakiSwift both use `[Worcester](/wˈʊstər/)`. Reuse rather than invent —
      it gives the respelling UI a serialized form and lets power users paste
      overrides they already have.
- [ ] **Cast pre-flight.** `[proposal]` On opening a work, phonemize the
      character/relationship tags, detect which fell through to BART, prompt
      once. One prompt fixes words that would otherwise be mangled hundreds of
      times.
- [ ] **Fandom seed dictionaries.** `[proposal]` The `fandoms` layer exists and
      is unused. Fixing *Hermione* once should hold for every Potter fic.

### Phase 4 — expressiveness

- [ ] **Voice blending.** `[prior-art]` A voice pack is a `[510, 256]` fp32
      tensor, so mixing two voices is a weighted combination —
      Kokoro-FastAPI exposes it as `af_bella(2)+af_heart(1)`. Use **SLERP, not
      a naive average**: averaging vectors pointing different directions
      shrinks magnitude and audibly flattens the voice. Turns 28 voices into an
      unbounded set and makes the next item far cheaper.

- [ ] **Multi-voice dialogue.** `[proposal]` The biggest single upgrade
      available, unlocked by going from 1 voice to 28. **27.7% of blocks in the
      measured work open with a quote** `[measured]`. Parse attribution, assign
      per character from the tags already in hand, keep the narrator distinct.
      Largest item on this list.

- [ ] **Emphasis from EPUB markup.** `[code]` `<em>`/`<i>`/`<strong>` is
      authorial stress, and in fic italics also mark internal thought.
      `KokoroSemanticBlock` carries `selector` but only ever tests it for
      `h1-6`, `blockquote`, `hr` — the inline signal is discarded.

- [ ] **Fanfic's own conventions.** `[proposal]` ALL-CAPS, `*asterisks*`,
      stretched vowels (`noooooo` → lengthened `ː`), interrobangs, trailing `…`.

### Phase 5 — hard or experimental

- [ ] **Cross-chunk prosody context.** `[proposal]` Every chunk is synthesized
      with no knowledge of the one before it, so prosody resets at every
      boundary. This is the "reading a list of sentences" quality that
      separates chunked TTS from continuous, and it is the real ceiling on
      flow — no amount of pause tuning reaches it. Standard fix: carry a few
      words of context into each chunk and trim the overlap from the audio.
      Costs synthesis time and is fiddly.

- [ ] **Non-English passages.** `[proposal]` English G2P mangles them. The pack
      ships English voices only and the English variant has no other frontend.
      At minimum detect and handle gracefully.

- [ ] **Intonation arrows — A/B only, do not ship blind.** `[code]`
      `[proposal]` The vocab carries `→ ↓ ↗ ↘` (level, downstep, rising,
      falling) and we emit none. **The tokens are verified to exist; the
      model's response to them in arbitrary positions is not.** Feeding a model
      tokens outside its training distribution usually degrades. Needs Phase 0
      and a fixed test paragraph.

---

## 5. Predictions the measured work did not exercise

Recorded so they are not mistaken for resolved. This author writes with
straight quotes, almost no ALL-CAPS and almost no non-English, so these got
**no signal — not a negative result**.

### Resolved by Run 2

| Item | Run 1 (1 work) | Run 2 (7 works) | Outcome |
|---|---|---|---|
| Curly-quote open/close | straight 14,273 · curly 719 | **curly 86,244 · straight 17,591** | **Run 1 was the outlier.** 5 of 7 works are overwhelmingly curly; one has *zero* curly. The fix must handle both directions — see Phase 1 |
| All-caps spelling | 22 distinct | **336 distinct**, 222 in one work | Real; Run 1 under-sold it by 10× |
| `<hr>` scene breaks | 0 — untested | **409 fired** across 4 works | Detector works |
| Rushing zone > 400 | 1 utterance | **63**, one work hits exactly 510 | Real, not hypothetical |

### Still unexercised

| Item | Why still open |
|---|---|
| Stretched vowels | Style-dependent; `AAAAAAH` (7 chars) exceeds the 2–5 window and reaches BART anyway |
| Non-English | Even the Naruto and Bleach works are English-prose; romaji-heavy works exist but were not sampled |
| URLs | Epistolary and social-media formats are full of them; none sampled |
| Numbers | Estimator under-count needs date/time-heavy prose |
| Quirk typing | Homestuck-style typing quirks would stress the caps and punctuation paths hardest |

**Next corpus additions should deliberately target these**: a quirk-typed work,
a romaji-heavy fic, and a texting or epistolary format. Halo returned no
results for the current filter — the canonical tag name needs checking.

### The methodological lesson

The curly-quote item was **predicted correctly, then wrongly reversed off a
single work, then restored by seven**. One work characterises its author, and
that cuts both ways: it can no more disprove a finding than prove one. Treat
any single-work result as a hypothesis, and note that `[measured]` is only as
strong as the corpus behind it — always cite the run.

---

## 6. Prior art

Licence-checked because this project is **AGPL-3.0**; Apache-2.0, MIT, BSD and
ISC are all one-way compatible *into* AGPL-3.0.

| Project | Licence | Usable | Worth taking |
|---|---|---|---|
| [hexgrad/kokoro](https://github.com/hexgrad/kokoro) | Apache-2.0 | ✅ | Reference pipeline — the authority on what the model expects |
| [remsky/Kokoro-FastAPI](https://github.com/remsky/Kokoro-FastAPI) | Apache-2.0 | ✅ | Token band 175/250/450, voice blending, inline IPA syntax |
| [thewh1teagle/kokoro-onnx](https://github.com/thewh1teagle/kokoro-onnx) | MIT | ✅ | Packaging; combined all-voices binary |
| [nazdridoy/kokoro-tts](https://github.com/nazdridoy/kokoro-tts) | MIT | ✅ | Closest use case — an EPUB reader with blending |
| [mlalma/MisakiSwift](https://github.com/mlalma/MisakiSwift) | Apache-2.0 | ✅ | Inline override syntax. G2P itself is redundant — FluidAudio ships one |
| [lucasjinreal/Kokoros](https://github.com/lucasjinreal/Kokoros) | **none** | ❌ | No licence file = all rights reserved. Do not read or adapt |
| nikkoxgonzales/streaming-tts | **none** | ❌ | Same |

### Settled — do not re-investigate

- Kokoro **ignores** capitalization, emoji, emotion markers (`[excited]`) and
  SSML tags entirely, or misreads them. There is no markup path to emphasis;
  the levers are punctuation, the phoneme string, and the style vector.
- Stacking `!!!` does not increase energy over a single `!`.
- Chunking on sentence and paragraph boundaries — never character counts — is
  *the* quality lever for long-form.

### Punctuation is the prosody API

These are the model's **own** pauses, which our structural pauses stack on top
of. Relevant when tuning pause lengths.

| Mark | Effect |
|---|---|
| `.` | Full stop, intonation resets completely |
| `,` | Brief breath, flow maintained |
| `…` | Trailing pause **0.5–1 s**, falling intonation |
| `;` | Between comma and period |
| `:` | Pause with anticipation |
| `?` | Rising intonation on yes/no questions |
| `!` | Higher energy (one is enough) |

- [ ] **Check for stacked pauses.** `[prior-art]` `…` already yields 0.5–1 s
      from the model and `KokoroPauseAssembler` then appends a structural pause
      on top — an ellipsis at a paragraph end may be getting ~1.3 s.
- [ ] **Default speed 0.9, not 1.0.** `[prior-art]` Audiobook narration is
      widely recommended at 0.9 (1.05 for ads). One line in
      `ReaderSpeechPreferences.defaultRate`, but it changes everyone's
      experience — A/B first.
- [ ] **Normalization escape hatch.** `[prior-art]` Kokoro-FastAPI exposes
      `normalization_options: {normalize: false}` because normalization "can
      incorrectly remove or change some phrases". We stack two normalizers
      (`KokoroSpeechNormalizer`, then NeMo `EnglishTextNormalizer`) with no way
      to inspect or disable either. A debug toggle at minimum, so a
      mispronunciation can be traced to the right stage.

---

## 7. Housekeeping and known defects

- [ ] **Speed changes need a restart.** `[code]` `CoreMLKokoroTTSService.speak`
      captures `currentSpeed` into a local at start, so the slider does nothing
      until the next utterance batch.
- [ ] **Republish the pack with 28 voices.**
      `Scripts/pack-kokoro-ane-github-release.sh` → `gh release create` → bump
      `tag` and `expectedSHA256` in `KokoroGitHubPack`. The published release is
      still the 1-voice build.
- [ ] **Device-test both engines.** Core ML needs an iOS 27 device; Sherpa needs
      iOS 26. **Nothing on this branch has produced audible audio.**
- [ ] **Pre-existing suite failures, unrelated to TTS.** 9 tests fail
      identically on commit `2a61aaf4` — before any TTS work and with the
      original MiniZip: `FolderSyncTests` + `KudosBackupFontRestoreTests`
      case-folding, and `WorkStatLabelTests/categoryColorMatchesAO3sOwnCoding`.
      Worth their own task.
- [ ] **Heading detection depends on the CSS selector.** `[measured]` The
      text-only regex matches 74/104 headings; "Preface" and a work's title
      match nothing. Fine while Readium supplies `cssSelector`, silent
      degradation if it ever does not.
- [ ] **`ReaderSpeechSettingsSection` exceeds the SwiftLint type-body-length
      warning** (532 lines) after gaining the Core ML section. Non-blocking.
- [ ] **x86_64 simulators no longer link** — FluidAudio ships an arm64-only
      `libtext_processing_rs.a`.
