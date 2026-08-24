# Read Aloud quality — findings report and work checklist

Status: **investigation complete; implementation in progress, and four
external reviews verified against primary sources (§6).** Follows T-208
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

- [x] **Audition harness — done 2026-08-23.** `ReaderSpeechAuditionHarness` +
      `ReaderSpeechController.audition(text:)`. Three original samples
      (dialogue / numbers+names / narration), play-stop, shows the engine
      actually resolved. Deliberately does *not* install remote commands: a
      Settings preview must not take over Lock Screen transport. `[proposal]` Speak a fixed sample on demand under
      current settings, ideally A/B against the previous setting. Include a
      dialogue-heavy and a numbers/names-heavy sample, not just clean prose.
      Cheapest item here; gates every other one.

### Phase 1 — defects

- [x] **Pauses ignore speed — fixed 2026-08-22.** `[code]` `KokoroPauseAssembler.assemble` inserts
      `pauseSeconds × sampleRate` samples and takes no `speed` parameter, while
      `speed` *is* passed to the synthesizer. At 1.5× the speech compresses and
      the silence does not, so gaps run ~50% long; at 0.75× they run short.
      Fix: thread `speed` through, divide `pauseSeconds` by it.

- [x] **Curly quotes collapsed — fixed 2026-08-23** (`31f8ea05`). Preserves
      `“`/`”`, promotes straight by *position* (whitespace-before means open;
      a toggle inverts after any unclosed speech, which is normal in fiction).
      Guillemets mapped — and they had to be: `vocab.encode` **silently drops**
      unknown characters, so left alone they vanished before the model. `[code]` `[measured]`
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

- [x] **Shouted words — fixed 2026-08-23. The proposed fix was wrong.**
      Two recoveries in `KokoroAneEnglishPhonemizer.resolveWord`, placed after
      a complete lexicon miss and before `EnglishInitialisms.isCandidate`:
      apostrophe reinsertion (169 occurrences) and de-elongation (31). Both
      carry a guard found by replaying the algorithm against the real lexicon:
      a one-letter stem plus `'s` is a letter *plural*, not a contraction
      (`PS` was reading as "peas"), and a token spelled only from `ivxlcdm` is
      a numeral, not an elongated word (`XXXII` was collapsing to `xi`). The
      second guard removed **42 of 73** de-elongation hits — unguarded, that
      rule did more harm than good.
      An adversarial review then found four more defects, every one by
      replaying the **real** lexicon rather than reading the code:
      collapsing *every* repeated run flattened a word's own spelling
      (`GOODD` → `god`, `SOONN` → `son`, `ALLL` → `al`); `normalizeKey` keeps
      `'` and drops `-`, so `P-S` became `p'-s` → `p's` → "peas" past a raw
      length check; the numeral guard tested the whole token, so `XXX-II`
      (32) collapsed to `xi` (11); and apostrophe reinsertion was quadratic
      with no length cap, so an unbroken keysmash paid for a search that
      cannot succeed.

      The elongation fix is the one worth remembering: collapse only the
      **trailing** run, because that is where written elongation lands — a
      writer holds the last sound — and try a native double before a single
      so `ALLL` is `all`. A 60,000-word collision scan then found no wrong
      recoveries.

      The logic lives in gitignored `Packages/`, so it survives only through
      `Scripts/fluidaudio-kudos.patch`; the patch was regenerated and verified
      to apply to a fresh pinned clone with the result byte-matching.

      **Method note.** Three rounds of defects, none found by inspection —
      the spec was wrong, then the guards were wrong, then the guards had
      holes. Every one surfaced by replaying the algorithm against real
      lexicon data. For anything that consults a large external dictionary,
      replaying it is the review; reading the diff is not.
      `[measured]` `[code]` After a lexicon miss,
      `EnglishInitialisms.isCandidate` spells any strict-ASCII all-caps token
      of **2–5 characters** as letter names (`FBI` → `ˈɛf bˈi ˈI`). The rule
      only fires on tokens that *miss* the lexicon, and the lexicon is consulted
      **lower-cased** (`wordToPhonemes[lowered]`), so the discriminator is
      exactly "is the lower-cased token in the Misaki lexicon".

      This item was blocked on being unable to ask that question. It is no
      longer: running the real Misaki lexicon (178,646 gold + 186,722 silver)
      against the corpus answers it directly.

      **The examples in the original write-up were wrong.** `draco`, `newt` and
      `roy` are all *in* the gold lexicon, so `DRACO!` resolves normally and is
      never letter-spelled. Of 9,748 all-caps tokens, 1,913 (19.6%) miss and get
      spelled out, 403 distinct. Classified:

      | share | class | examples |
      |---|---|---|
      | 41.7% | no vowel — genuine initialism | `PDF` `TG` `GC` `TV` `WTF` |
      | 26.2% | initialisms and numerals | `DNA` `UK` `ASL` `AKA` `VII` |
      | 17.3% | acronyms *and* shouted names | `UNSC` `ODST` `DMLE`; `TOBIO` `LANDO` |
      | 10.0% | contraction, apostrophe stripped | `IM` `DONT` `YOURE` `HES` `CMON` |
      | 3.8% | resolves once de-elongated | `YESSS` `YAYYY` `HIMMM` `YOUU` `MEE` |

      **So roughly 68% of these letter-spellings are correct**, and the fix
      this item proposed — "down-case an all-caps token before G2P unless it is
      a known initialism" — would break the majority case. Down-casing `PDF`,
      `DNA`, `UNSC` or Homestuck's `TG`/`GC` makes them worse, not better.

      What is actually broken is two small deterministic classes, both fixable
      without a heuristic:

      1. **Contractions typed without the apostrophe** (191 occurrences, 15
         distinct). Try inserting `'` at each interior position and keep a form
         the lexicon knows.
      2. **Elongated words** (93 occurrences). Collapse repeated-letter runs
         and retry. This is also Gemini's "condense prolonged vocalisations"
         suggestion, arriving from the opposite direction.

      Both are safe *because of where they sit*: they run only after a complete
      lexicon miss, so `cant` (a real word) resolves first and is never turned
      into `can't`, and `beer` never reaches de-elongation. Genuine initialisms
      match neither and fall through to letter-spelling unchanged.

      Shouted **names** are the residue and stay open — they need Phase 3's
      name discovery, not a spelling rule.

      Caveat: measured against Python Misaki's lexicon, which should match the
      pack FluidAudio downloads but was not byte-compared.

- [x] **AO3 boilerplate — fixed 2026-08-23** (`cbb234c6`). Whole-block
      equality only. 909 label blocks + AO3's closing plug (19/19 works).
      URLs become their bare host, not deleted — nearly every hit is
      mid-sentence and deletion leaves a dangling "at .". `[proposal]` "Chapter Text" headers,
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

- [x] **Split before the rushing zone — fixed 2026-08-22.** 558 → **0** above
      400; max 510 → 400. Holds across 111,485 utterances in Run 4. `[prior-art]`
      Kokoro is reported to rush beyond ~400 tokens, and Kokoro-FastAPI sets
      `ABSOLUTE_MAX_TOKENS = 450` against the same 510 model limit. Our
      `KokoroPhonemeBudget.modelLimit = 510` doubles as the split trigger, so a
      long sentence can synthesize at ~500 and rush. Separate the constants:
      keep 510 as the hard `vocab.encode` cap, add a ~400 split threshold.
      `[measured]` **63 utterances above 400 across 7 works, and the Harry
      Potter work hits exactly 510** — the model cap — so this is not
      hypothetical. Rare per work, but a single rushed sentence is audible.

- [x] **Estimator: digit term added 2026-08-23. Full replacement dropped.**
      `[measured]` The number prediction above was right and understated. Real
      Misaki G2P (espeak fallback for OOV names) over 7,000 grouped corpus
      utterances puts a **digit at ~10.3 phoneme characters against a letter's
      ~0.92**, and digit density was by far the strongest predictor of an
      under-estimate — the worst-undercounting groups carried roughly **500x**
      the digit density of median text. Measured single cases: a two-year
      sentence estimated **43 against a real 64**; a stardate line estimated
      **52 against a real 102**, under by half.

      `KokoroPhonemeEstimator.digitPhonemeBonus = 9` is a *tail* fix by design:
      p99 ratio 1.04 → 1.00, median untouched at 0.866 → 0.865, because most
      prose holds no digits. Moving the median would move every chunk boundary
      in the app, which is a tuning change and needs ears.

      **Replacing the estimator outright is now not worth doing.** It would
      make the whole packer async and re-run G2P on every candidate grouping it
      considers and discards, and `prepareClip` already enforces the true count
      against `splitThreshold`. The estimator's job is to be cheap and roughly
      right, and with the digit term it is.

- [ ] **The estimator over-estimates by 15%, and that is currently correct.**
      `[measured]` Real phoneme length is **0.866x the estimate** (p5 0.79,
      p95 0.94), stable across all 20 works (0.850–0.891). So the budget
      constants do not mean what they say — `preferredTarget 175` really lands
      at **~152** phonemes, `splitThreshold 400` at **~346**.

      This was worth checking and is worth *not* changing. Upstream `VOICES.md`
      puts the sweet spot at 100–200 phonemes, whose midpoint is 150; the real
      centre of ~152 sits on it. Removing the bias would move the real centre
      to 175 and off that midpoint. The open question is only whether
      `splitThreshold`'s real ~346 should be raised toward a real ~400 to cut
      the number of prosody resets — the one change here with a plausible
      audible upside, and it needs Phase 0.

      Cause: English IPA is *shorter* than English spelling (`through` is seven
      letters and three phonemes), so a 1.15x grapheme factor over-shoots even
      though stress marks — a measured **12.8%** of a real phoneme string — are
      not modelled at all. GPT predicted the mismatch and got the sign
      backwards; the missing stress term is real but far too small to overcome
      the grapheme factor.

- [ ] **Do not merge across dialogue boundaries.** `[code]` `[proposal]`
      A standalone `"Don't."` glued into surrounding narration is voiced with a
      long-form style row instead of its own. `KokoroSemanticDocument` already
      classifies `.dialogue` and **that classification is dead** — the only
      place it or `.blockquote` is consulted is `isBody()`, which treats them
      exactly like `.paragraph`. hexgrad specifically improved Kokoro's short
      utterances `[prior-art]`, so short lines are a strength to use.

- [ ] **Preserve `<br>` as an audible boundary.** `[measured]` `[code]`
      Same defect as the item above, from the other direction: the document
      hands us a boundary and we glue over it. Chain verified end to end in
      §6.3.1 — AO3 stores a single author newline as `<br>`, Readium's
      `HTMLResourceContentIterator` calls `flushText()` on it so each line
      arrives as its own unit, and `concatenateForSentenceContext` space-joins
      them straight back together. 15,133 breaks across the corpus, and the
      hard-wrapped prose that would justify the join **does not exist here**
      (0 of 1,180 candidate runs, against a passing positive control).

      The join is not pointless — G2P is per-word and an isolated `read` gets
      the citation form — so the fix is GPT's split: let phonemes see across
      the break, let the listener hear it. Discriminator needs no new parsing:
      units split by `<br>` share a `cssSelector`, units from adjacent
      paragraphs do not. Needs a boundary shorter than `.paragraph`'s 0.32 s.

      Worth doing with the dialogue item above, not separately — both are
      "stop merging across a boundary the document already gave us", and they
      touch the same two functions.

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
- [ ] **Contextual pronunciation: `the` sandhi.** `[code]` `/ðə/` before a
      consonant, `/ði/` before a vowel — and the rule is **phonological, not
      orthographic**, so it must run on phonemes: *the hour* takes `/ði/`
      (silent h), *the university* takes `/ðə/` (`/j/` glide), *the FBI* takes
      `/ði/`. A letter-based rule gets all three wrong; a phoneme-based one
      gets all three free, because G2P has already resolved them.
      `wordToPhonemes` is `[String: [String]]` — a flat map with no context
      parameter — so today `the` has exactly one pronunciation everywhere.
      Feasible because `phonemize` joins words with `parts.joined(separator: " ")`,
      so word boundaries survive into the IPA string: split on spaces, find the
      weak form, inspect the next token's first phoneme, swap. Deterministic,
      no model, no POS. Highest-frequency word in English.

- [ ] **Contextual pronunciation: possessives.** `[code]` `splitWords` keeps
      `'` inside a word (which is what saves `wasn't`) and `normalizeKey` keeps
      it in the lookup key, so `Anna's` is looked up as the literal key
      `anna's`. Contractions are in the Misaki lexicon; **possessives of proper
      nouns are not**, so they miss every tier and land on BART with the
      apostrophe attached.
      English possessive `-s` is regular, picked by the preceding phoneme:
      `/ɪz/` after a sibilant (Alice's), `/s/` after voiceless (Pat's), `/z/`
      otherwise (Anna's, Harold's). Derive it rather than guess it.
      **This also breaks the pronunciation UI and cast pre-flight below**, and
      that is the bigger problem: a user correcting `Aziraphale` does *not* fix
      `Aziraphale's` — different key, tier-1 override never matches — and AO3
      tags supply `Aziraphale`, never the possessive. Fix by emitting a derived
      companion entry for every correction, which needs only the final phoneme
      of the base IPA. Plural possessives (`the Winchesters'`) fall out of the
      same rule.

- [ ] **Cast pre-flight — as ranked, multi-source discovery.** `[proposal]`
      Originally scoped as "phonemize the AO3 character tags". **Tags are a
      good seed and a bad set**: they miss Original Characters — often the
      most-spoken name in the work — along with minor characters the author
      never tagged, and every place name, invented term, spell, ship and
      organisation, none of which are ever tagged.
      Three sources that fail in different directions:
      | Source | Finds | Misses |
      |---|---|---|
      | AO3 tags | canonical cast, free, before playback | OCs, minor names, non-person nouns |
      | `NLTagger` `.nameType` over the text | untagged people, places, organisations | invented words NER has no prior for |
      | BART-fallback log | *exactly* what actually missed every tier | only known after it is spoken once |
      **Frequency is what makes it tractable.** Nobody wants a 200-name prompt,
      but an OC named every third paragraph and a spear-carrier named twice are
      not comparable — rank by occurrences × missed-the-lexicon and the top few
      are worth one prompt each. The whole EPUB is on disk before playback, so
      the scan can cover the entire work rather than discovering names
      chapter by chapter.
      **Caveat:** for an OC there is no correct answer to discover — no
      lexicon, no authority, only what the reader thinks it sounds like. That
      argues for making the fix cheap rather than the guess clever, and it is
      why the possessive derivation above matters more here, not less: an OC's
      name is exactly the word that recurs as `Rhiannon's`.
- [ ] **Fandom seed dictionaries.** `[proposal]` The `fandoms` layer exists and
      is unused. Fixing *Hermione* once should hold for every Potter fic.

### Phase 4 — expressiveness

- [ ] **Emphasis via stress promotion — the only in-vocabulary lever left.**
      `[code]` `[proposal]` With the arrows gone (Phase 5) there is no proposal
      for `<em>`/`<i>`, which fic uses heavily and we currently parse and throw
      away. DeepSeek's replacement suggestion is the one surviving idea, and
      unlike the arrows it is **in distribution**: `ˈ` and `ˌ` are both in
      Misaki's `US_VOCAB`, so promoting secondary stress to primary on an
      emphasised word emits nothing the English G2P would not itself emit.

      Its proposed implementation is wrong twice and must not be copied:
      `replacingOccurrences(of: "ˌ", with: "ˈ")` promotes *every* secondary
      stress in the whole string, giving words several primary stresses and
      hitting every word rather than the emphasised one. Promotion has to be
      scoped to one word and to one mark.

      Its own example also argues against it: `/ˈrɛkərd/` → `/rɪˈkɔrd/` is a
      heteronym whose **vowels** change with the stress, which is a
      demonstration that stress is not separable from segmental content — the
      exact hazard it warns about elsewhere. So: promote an existing `ˌ` to
      `ˈ` only, never add stress to an unstressed syllable, and never touch a
      function word. Needs Phase 0 and a fixed paragraph.

- [x] **Voice blending — done 2026-08-23.** Half-row SLERP (the granularity
      the model actually reads: timbre → Noise+Vocoder, style_s →
      PostAlbert+Prosody). Direction slerped, magnitude lerped separately.
      Content-addressed `.bin` cache. Marked ceiling: sequential fold is not a
      true Karcher barycentre for n>2. `[prior-art]` A voice pack is a `[510, 256]` fp32
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

### Phase 4b — on-device LLM as an oracle for the ambiguous residue

The device runs iOS 27, so Apple's **Foundation Models** framework is
available: an on-device model with no download, no memory management to own,
and guided generation for structured output. That last part is the crux.

**Use it to *choose*, not to *generate*.** Asking a small model for IPA is
asking for confident, unverifiable, occasionally-wrong phoneme strings, and we
would have no way to tell a good answer from a bad one. Asking it *"in this
sentence, is `read` past or present?"* is a two-way classification we can
constrain, cache, and sanity-check. Everything below is framed that way.

**Run it once, at download, never at playback.** The whole EPUB is on disk
before a word is spoken; results cache alongside the work. Synthesis latency
must not depend on a language model.

**Do not point it at the whole text.** The genuinely ambiguous cases are a
tiny fraction of any work, and the deterministic rules above already cover the
*regular* ones correctly and far more cheaply. An LLM that re-derives
possessive allomorphs is slower, less reliable, and adds nondeterminism to
something that has a rule.

- [ ] **Heteronym disambiguation.** `[proposal]` `read` / `lead` / `live` /
      `wind` / `tear` / `bow` / `close` / `record` / `present` / `object` /
      `content` / `refuse` / `produce` / `desert`. These need part of speech
      and sometimes semantics, which is exactly what rules cannot do and a
      model can. Only sentences containing one of a closed list are sent, so
      the work is bounded and small.
      Note: **Misaki upstream does POS-aware lookup via spaCy; the Swift port
      dropped it**, so this is a known gap against the reference
      implementation rather than a novel feature. `NLTagger`'s `.lexicalClass`
      is the cheaper non-LLM option and should be tried first.
- [ ] **Speaker attribution for multi-voice.** `[proposal]` Unattributed lines
      in a back-and-forth (`"Don't."` with no `said X`) are where rule-based
      attribution fails, and where a model reading a few lines of context does
      well. Feeds the multi-voice item directly.
- [ ] **Ambiguous normalisation.** `[proposal]` `St.` as Saint or Street,
      roman numerals, bare dates, and units — cases where NeMo's rules have to
      guess and the surrounding sentence resolves it.
- [ ] **Non-English passage detection.** `[proposal]` Identify language spans
      so they can at least be handled deliberately rather than sounded out as
      English.

**Blocked on / risks, to check before building:** Foundation Models needs a
supported device with Apple Intelligence enabled, so every path must degrade
to the deterministic rules when it is absent — it is a quality layer, never a
dependency. A 433k-word work is a real amount of processing at download time,
which is the main argument for bounding input to ambiguous spans. And model
output is nondeterministic, so the same work could prepare differently twice;
caching the decision with the work makes it stable after the first pass.

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

- [x] **Intonation arrows — DROPPED 2026-08-23, the premise was false.**
      `[measured]` All four external reviewers independently recommended
      emitting the vocab's `→ ↓ ↗ ↘` as English intonation. All four were
      wrong about what those glyphs are. They are **Mandarin lexical tones**:
      `misaki/zh.py` `ZHG2P.retone` maps the Chao tone letters straight onto
      them — `˥`→`→` (tone 1), `˧˥`→`↗` (tone 2), `˧˩˧`→`↓` (tone 3),
      `˥˩`→`↘` (tone 4). Misaki's English vocabulary does not contain them
      (`US_VOCAB`/`GB_VOCAB` in `misaki/en.py`; `EN_PHONES.md` lists 49
      phonemes, stress as `ˈ`/`ˌ`, no arrows), and the Japanese path has its
      arrow emission **commented out** in favour of `_ ^ -`.

      So this was never "use a token we already have". Emitting `↗` into
      English asks a model for a Mandarin tone contour on an English syllable —
      out of distribution in the strict sense, and plausibly acting on the
      adjacent segment rather than the phrase. DeepSeek's "Japanese accent
      nucleus / heiban / kaku" reading is contradicted at the source; it also
      argued that vocab membership proves the model saw them in training, which
      does not follow — the vocab is shared across every language Kokoro
      supports.

      **The lesson is worth more than the item.** Four independent reviewers
      agreeing looked like strong evidence and was not evidence at all: none of
      them had read `zh.py`. Held at `[proposal]` for exactly this reason.

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

## 6. External review — what survived verification

Four models reviewed the pipeline from
[`TTS_EXTERNAL_REVIEW_PROMPT.md`](TTS_EXTERNAL_REVIEW_PROMPT.md). Every
checkable claim was then verified against primary sources, because a
confident, well-written suggestion is not evidence. Two did not survive.

| Claim | Source | Verdict |
|---|---|---|
| Style vector splits 128 timbre / 128 prosody | GPT | **Verified** — in our own code |
| StyleTTS 2 blends style vectors across sentences | Grok | **Verified** — but paper and code disagree on direction |
| AO3 rewrites linebreaks before storing | GPT | **Verified** — and narrower than claimed, usefully |
| Thai fine-tune duration numbers | GPT | **Verified**, but mislabelled as correlation |
| Arrows are Japanese pitch accent | DeepSeek | **Contradicted** — they are Mandarin tones (§4, Phase 5) |
| Estimator undercounts phoneme length | GPT | **Contradicted** — it over-counts by 15% (§4, Phase 2) |

### 6.1 The style vector splits in half, and the halves do different jobs

`[code]` Verified in the vendored source, not inferred:
`KokoroAneVoicePack.slice(for:)` returns `(styleS, styleTimbre)` where
`[0..<128]` is `style_timbre` and `[128..<256]` is `style_s`. Tracing the
synthesizer inputs, they go to genuinely different stages:

* `style_s` → **PostAlbert** (duration prediction) and **Prosody** (F0/N)
* `style_timbre` → the **Noise/F0-curve** stage and the **Vocoder**

Corroborated upstream, and this is the useful part: StyleTTS 2's own LibriTTS
notebook blends the two halves with **separate weights** —
`ref = alpha * ref + (1 - alpha) * ref_s[:, :128]` against
`s = beta * s + (1 - beta) * ref_s[:, 128:]`, with `alpha = 0.3` and
`beta = 0.7`–`0.9`. Treating the 256-vector as one unit is not how its own
authors treat it.

**Consequence for any style-row experiment:** move the halves independently.
All duration risk lives in `style_s`; mismatching `style_timbre` cannot change
speaking rate because it never reaches the duration predictor. That splits one
risky experiment into a safe half and a dangerous half.

### 6.2 StyleTTS 2 style persistence — real, and the weight is a trap

`[prior-art]` arXiv:2306.07691 **Appendix B.3, "Consistent Long-Form
Generation"**, Algorithm 1. The latent style space is described as convex, so a
combination of two style vectors is another style vector, letting the current
sentence be conditioned on the previous one.

**The paper and the official code disagree about which side the weight applies
to, using the same symbol and the same value 0.7:**

| Source | Expression | α = 0.7 means |
|---|---|---|
| Paper, Algorithm 1 | `s_curr ← α·s_curr + (1−α)·s_prev` | 70% **current** |
| `Demo/Inference_LJSpeech.ipynb` | `s_pred = alpha * s_prev + (1 - alpha) * s_pred` | 70% **previous** |
| `Demo/Inference_LibriTTS.ipynb` | `s_pred = t * s_prev + (1 - t) * s_pred` | 70% **previous** |

Anyone implementing from the paper's formula while taking the constant from the
code gets the blend backwards — heavy persistence where light was intended.

**Resolved:** put to Grok, which agreed there is no reconciling definition of
`s_prev` and that the published code contradicts the published algorithm. Its
recommendation, which is the right one: follow the **code** — 70% previous, 30%
current — because the notebooks are the authors' own runnable demonstration of
Algorithm 1 and are what every public port copies. Implement it with the
discrepancy written down at the call site, or the next reader will "fix" it
back to the paper.

**Per-half persistence weights are our own idea, not prior art.** The separate
`alpha`/`beta` weights exist *only* for the reference-style interpolation; the
persistence step applies one weight to the full 256-vector, in both the paper
and every implementation. Weighting timbre persistence high (identity should
not drift) and prosody persistence low (each sentence needs its own rhythm) is
a reasonable extension, and must be labelled as an extension when tried.

**Adapting it to Kokoro is not mechanical.** StyleTTS 2 *samples* a fresh style
per sentence via diffusion conditioned on the target text, then blends it with
the previous. Kokoro has no diffusion sampler — the vector is a deterministic
lookup by phoneme count. So the analogue is blending two length-selected rows,
which is a materially weaker claim than "StyleTTS 2 does this". Worth trying,
since `KokoroVoiceBlend` already SLERPs style vectors, but the 0.7 carries no
authority here.

### 6.3 AO3 rewrites linebreaks before storing — and that *helps*

`[prior-art]` `lib/html_cleaner.rb` `add_paragraphs_to_text` ("Adding
paragraphs in place of linebreaks") runs on `content` **before**
`Sanitize.clean`, through the `sanitize_ac_params` before-action, and the
result is what gets stored and later exported. `lib/paragraph_maker.rb`
`split_text_at_newlines` maps:

| Author typed | AO3 stores |
|---|---|
| one newline | `<br>` |
| two newlines | a new `<p>` |
| three or more | a new `<p>` plus `<p>&nbsp;</p>` |
| `<br><br>` | two `<p>`s — **the `<br>`s are removed** |
| `<br>` already inside a `<p>` | kept as-is |

GPT read this as provenance being destroyed. It is closer to the opposite, and
this is the most useful thing to come out of the review: **AO3 has already
promoted every multi-line break to a paragraph.** A `<br>` surviving into our
EPUB is therefore a *single* author line break, never a paragraph the exporter
mangled. The decision we face is narrower than assumed — not "is this break
real?" but "is this single, deliberate break prosodic or cosmetic?".

That still leaves hard-wrapped prose imported from elsewhere. **Measured: it
does not occur.** `[measured]`

GPT proposed a sharper test than line-length variance, and it is a good one:
under greedy word wrap at width `W`, every non-final line must satisfy
`L_i <= W < L_i + 1 + len(firstWordOf(i+1))` — the line fits, and the next
word did not. Intersect that interval across a run of lines and a mechanical
wrap leaves a common `W`; deliberate line breaks do not.

Implemented and run over the 18 EPUBs (244,535 blocks):

| | |
|---|---|
| blocks containing `<br>` | 4,214 (1.7%) — 15,133 breaks |
| runs of 4+ consecutive broken lines | 1,180 |
| runs admitting a common `W >= 40` | **0** |
| runs admitting any common `W` at all | 10, every one at `W` 30–36 |

**Positive control passes**, which is the only reason the zero is worth
anything: real prose wrapped at 60, 72, 76 and 80 characters is detected every
time, with the true width inside the inferred interval. The detector works and
finds nothing. The ten low-`W` hits are the coincidence GPT warned about —
short line-oriented text fitting a narrow budget; a verse control lands at
`W` 9–10 the same way, which is what the width floor is for.

Caveats: these EPUBs carry Calibre's classes, so this measures what reaches
the reader rather than what AO3 emitted; and the corpus was selected *for*
messy formatting, so it is biased toward finding line-oriented content — and
still found no mechanical wrapping.

**So the detector is correct, well-designed, and unnecessary.** GPT's own
fallback is the whole answer: preserve `<br>` by default.

### 6.3.1 What we actually do to those breaks — verified end to end

`[code]` The chain from AO3's server to our audio:

1. AO3 stores a single author newline as `<br>` (`paragraph_maker.rb`), having
   already promoted every multi-line break to a `<p>`.
2. Readium's `HTMLResourceContentIterator` calls `flushText()` when it meets a
   `br` tag, so each broken line arrives as its **own** `TextualContentElement`
   and therefore its own `TTSSpeechUnit`.
3. `TTSService.concatenateForSentenceContext` space-joins adjacent units, and
   `splitIntoContextualSentences` re-splits on sentence boundaries — so a
   break that is not a sentence end is **erased**.

Every step verified in source. The join is not gratuitous: G2P is per-word, and
an isolated `read` gets the citation form rather than the verb. But the effect
is that chat fic, epistolary works, transcripts and verse — 15,133 breaks —
are flattened into running prose, and the measurement above says nothing is
gained by it.

- [ ] **Preserve `<br>` as an audible boundary while keeping lexical context.**
      `[proposal]` GPT's framing is the right one and costs nothing: decide
      *"may G2P see across this?"* separately from *"should the listener hear
      it?"*. Keep the join for phonemes, insert a short pause at the seam.

      The discriminator is already in hand and needs no new parsing: units
      split by `<br>` share a `cssSelector` (they came from one `<p>`), where
      units from adjacent paragraphs do not. Needs a boundary shorter than
      `.paragraph`'s 0.32 s — a line is not a paragraph — and it must not
      fire between two ordinary `<p>`s.

### 6.4 The Thai fine-tune numbers are real and were mislabelled

`[prior-art]` The numbers are in `kunato/wayu-kokoro-thai-v1`,
`kokoro_thai/infer.py`, in the `build_voice_pack` docstring. They are **not**
correlations, as reported to me — the docstring labels them
`(pred/true duration, 1.00 = correct)`:

* style from the clip itself — 0.96
* style from a length-matched clip — 0.97
* one fixed 4-second reference — 0.76, i.e. 1.26x too fast

So 0.76 means predicted durations are 76% of true, not r=0.76. The direction
supports length-matched rows and argues against a fixed narration row. But it
is one author-stated measurement in a docstring on a Thai fine-tune, with no
backing table found in the repo, so it is suggestive rather than decisive.

---

## 7. Prior art

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

## 8. Housekeeping and known defects

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
