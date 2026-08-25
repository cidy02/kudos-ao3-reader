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

## 3b. Owner decisions — 2026-08-24

Recorded because they change what gets built, and because several items below
were written before they were made.

| Question | Decision |
|---|---|
| How to surface name corrections | **Both** a silent ranked list in Read Aloud settings **and** long-press-to-fix while reading. **No upfront prompt** — playback is never interrupted. |
| Multi-voice dialogue (per-character voices) | **Skip for now.** Speaker attribution is unreliable in fic and a line in the wrong voice is worse than one narrator throughout. |
| On-device LLM oracle (Phase 4b) | **Deferred** — "we will come back to that". Do not build it; leave the four items open and untouched. |
| Changes that need an ear (line pause, packing band, stress emphasis) | **Ship as defaults**, with the plan recording exactly what each value rests on and what would change it. |

The last one is a standing instruction for everything below: pick the
best-evidenced value, make it the default, write down the evidence. Do not add
a setting per tuning knob, and do not land code disabled.

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

- [x] **The other half of Phase 0 — done 2026-08-25.** The harness auditions a
      *fixed sample*, which answers "how does this setting sound" but not "how
      does this setting sound **on the work I am reading**" — and the settings
      it auditioned were compile-time constants, so A/B meant rebuilding.
      Developer Settings now exposes every unproven value (pauses, chunk band,
      split threshold, the two boundary toggles) and they change real
      playback, not the sample. Defaults are the shipped constants exactly, so
      an untouched install is unchanged, and the panel says plainly when
      anything has been moved — a listening report is worthless if it is
      unclear which build it describes.

      Reachable mid-read: long-press the Read Aloud button in the reader fan
      menu, which opens the speech options without needing playback to have
      started.

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

- [x] **~~28% of utterances fall below the packer's own minimum.~~** superseded `[measured]`
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

- [x] **The estimator over-estimates by 15%, and that is currently correct.**
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

      **Phase 0 now exists.** Developer Settings → Chunk size → *Split above*
      is that slider, and it changes real playback, not the sample. To try the
      raise: set it to **460** (≈400 real, given the 0.866 factor) and compare
      a long descriptive passage against the shipped 400. Everything else in
      this item is settled and should not be re-derived.

      Cause: English IPA is *shorter* than English spelling (`through` is seven
      letters and three phonemes), so a 1.15x grapheme factor over-shoots even
      though stress marks — a measured **12.8%** of a real phoneme string — are
      not modelled at all. GPT predicted the mismatch and got the sign
      backwards; the missing stress term is real but far too small to overcome
      the grapheme factor.

- [x] **Do not merge across dialogue boundaries.** `[code]` A standalone
      `"Don't."` glued into surrounding narration was voiced with a long-form
      style row instead of its own. `canJoin` now refuses when exactly one
      side is `.dialogue`. Adjacent dialogue still joins, so a back-and-forth
      that arrived as fragments of one paragraph does not become one inference
      per line. `<br>` seams still flush first (shared cssSelector), so quoted
      chat-fic keeps the `.line` pause. hexgrad improved Kokoro's short
      utterances `[prior-art]`; short lines are a strength to use.

- [x] **Preserve `<br>` as an audible boundary.** `[measured]` `[code]`
      Same defect as the item above, from the other direction: the document
      handed us a boundary and we glued over it. 9,681 seams across the
      corpus, and the hard-wrapped prose that would justify the join **does
      not exist here** (0 of 632 candidate runs, against a passing positive
      control). Implemented: matching `cssSelector`s flush with
      `endsAtLineBreak` and the packer emits `.line` (0.22 s). Adjacent
      `<p>`s, headings, and scene-break promotion are unchanged. See §6.3.1.

- [x] **Apple TTS still merges `<br>` seams.** `[code]` The line pause was
      Kokoro-only: `packedChunks` now partitions on the same discriminator
      (shared `cssSelector`) before concatenating, so each seam is its own
      `AVSpeechUtterance` and `postUtteranceDelay` (0.22 s, matching `.line`)
      carries the pause. Apple cannot insert silence inside an utterance.
      `sentenceChunks` still concatenates — that path is G2P context for
      Sherpa, not Apple. Adjacent `<p>`s (different selectors) still join.

- [x] **All three engines now vary the gap by structure — 2026-08-25.** Two
      engines were still flat after the item above. **Apple** gave every
      utterance the same `postUtteranceDelay`, so a chapter break sounded
      exactly like a mid-sentence split. **Sherpa** queued clips back to back,
      so its only gap was whatever the generation boundary happened to cost.
      `TTSSpeechUnit` now carries a `pauseAfter: KokoroBoundary?`; Apple reads
      it into `postUtteranceDelay`, and Sherpa appends that many zero samples
      to the clip. `nil` means unclassified and keeps the old flat behaviour,
      so a caller that builds units directly is unaffected.

      Classification is **structural, not positional**: a different source
      block is a `.paragraph`, no terminal punctuation is the length-driven
      split of one sentence (`.continuation`), a `<br>` seam is `.line`, and a
      sentence boundary *inside* one block stays `nil` — Kokoro has no
      boundary for that case because it packs those sentences into a single
      utterance. The first version labelled by position and would have made
      nearly every paragraph break a `.continuation`, **shortening** real
      breaks from 0.22 s to 0.14 s. `<br>` seams are ~1% of paragraphs, so
      position is a bad proxy for structure.

      Needs listening on a device: neither engine has been heard yet, and the
      pause values themselves are still the unproven ones Developer Settings
      exists to settle.

- [ ] **Revisit the packing band (A/B).** `[prior-art]` Ours is min 110 /
      target 175 / max 220; Kokoro-FastAPI ships min **175** / max **250** —
      their minimum is our target. Their band is tuned for continuous
      narration, so the answer is probably a narration band plus a dialogue
      exception, not one global band.

      Now A/B-able: Developer Settings → Chunk size → *Minimum* / *Maximum*.
      Remember the 0.866 factor when reading either number — the sliders are
      in estimated phonemes, so Kokoro-FastAPI's real 175/250 is about
      **202/289** on these. Chunk sizes are consumed when the chapter's plan
      is built, so change them between chapters, not mid-playback.

### Phase 3 — pronunciation

> **Implemented 2026-08-24.** The possessive item below was one third of a
> larger, cheaper win. The downloaded lexicon has **patchy regular inflection
> coverage** — `walking`, `walked`, `cats`, `asked` are present but `wanted`,
> `belongs`, `characters`, `companies`, `towards` are **absent** — and Misaki
> compensates with three stemmers (`stem_s`, `stem_ed`, `stem_ing`) that
> derive the inflected form from a base the lexicon *does* hold. All three
> now run at the same `resolveWord` gate as the possessive derivation, US-only,
> with `US_TAUS` tapping ported verbatim (`noticed` → `nˈOɾəst`, `sitting` →
> `ɾɪŋ`). Possessive `X's` is the `"'s"` branch of `stem_s`.
>
> Measured over 2.44M corpus words: **113,827 reach the G2P fallback (4.7%),
> and the three stemmers recover 49,457 of them — 43.4%**, about 2% of every
> word spoken.
>
> | branch | recovered |
> |---|---|
> | `-s` (plurals, possessives, `that's`) | 34,751 |
> | `-ed` | 14,022 |
> | `-ing` | 684 |
>
> Most frequent: `wanted` 1546, `that's` 2081 combined, `towards` 927,
> `makes` 737, `minutes` 610, `opened` 478, `characters` 423. Proper-noun
> possessives (`Jim's` 453) are a small slice of the `-s` branch.


Fanfic's hardest speech problem, and the one place this app has an advantage no
general-purpose engine can have: **AO3 tags every work with its characters,
relationships and fandoms** (`AO3Models.swift`). That is a curated list of
exactly the proper nouns BART G2P will mispronounce, available *before*
playback starts.

`KokoroPronunciationStore` already persists global / fandom / work layers and
is already tier 1 of the phonemizer's resolution order — it beats the Misaki
lexicon and the BART fallback `[code]`. **It has no UI at all**, so today a
mispronounced name is permanent.

- [x] **Pronunciation-fix UI — done 2026-08-25.** Both surfaces per §3b: a
      ranked list in Read Aloud settings and "Fix Pronunciation" in the
      reader's selection menu, no upfront prompt. Readium dispatches selection
      actions through the responder chain, so it needed the same three-part
      wiring as Highlight and Add Note. Both present the same editor and write
      through the same store.
- [x] **Respelling input — done 2026-08-25.** Accepts `her-MY-oh-nee` and
      converts by sending each syllable through the same G2P the reader uses,
      so no phoneme table is invented. Stress lands before the stressed
      syllable's **vowel** (`wˈɑnt`, not `ˈwɑnt`) — the lexicon's own
      convention, and the boundary placement I wrote first would have produced
      strings the model never saw. All-capitals means "no marked stress", since
      the capital only reads as emphasis when something else is lower-case.
- [x] **"Words I guessed at" — done 2026-08-25.** `[measured]` A word reaches
      the neural fallback only after missing the custom lexicon, the Misaki
      lexicon and every recovery, so it is a genuine guess. Observed via a new
      `setNeuralFallbackObserver` hook on `KokoroAneManager` (patch 8) — the
      fallback closure is built inside the manager, so the app could not see it
      otherwise.

      **Ranking is what makes it usable.** A work yields ~1,700 distinct
      fallbacks, which is a wall of text; the top ten cover a median **46%** of
      that work's occurrences. Measured leaders are exactly the intended
      target: `Marvolo` 570, `Purilla` 464, `Lucius` 461, `Severus` 392.

      Buffered behind a lock and flushed on stop rather than written per word —
      the observer fires inside synthesis, and disk I/O there would sit on the
      path that has to keep audio fed. Capped at 500 entries, dropping
      least-frequent: a name said once is the least worth keeping and returns
      on its own if it recurs.

      Correcting a word forgets it from the list, so it moves into Corrections
      rather than appearing in both.
- [x] **Adopt the established inline syntax.** `[prior-art]` Kokoro-FastAPI and
      MisakiSwift both use `[Worcester](/wˈʊstər/)`. Reuse rather than invent —
      it gives the respelling UI a serialized form and lets power users paste
      overrides they already have.
- [x] **Contextual pronunciation: `the` sandhi — port it, don't invent it.**
      `[measured]` `[prior-art]` Two facts found by measurement, both of which
      change this item:

      **0. Verified against the lexicon the app actually downloads**, not a
      local proxy: `us_lexicon_cache.json` from
      `FluidInference/kokoro-82m-coreml` — 10 MB, **178,546** lower-cased and
      **9,226** case-sensitive entries. Every claim below is read out of that
      file. This matters because the first pass of this measurement used
      Python Misaki's bundled lexicon, which is *similar* but not the artefact
      the app loads.

      **It is not one word — it is four, and they are the commonest words in
      English.** Every one of these is stored as its strong/citation form,
      which is wrong in running speech:

      | word | real lexicon entry | should be | corpus |
      |---|---|---|---|
      | `the` | `ði` | `ðə` / `ði` by context | 105,383 |
      | `to` | `tu` | `tə` / `tʊ` by context | 67,403 |
      | `a` | `A` — the FACE diphthong, i.e. the letter name "ay" | `ɐ` | 47,158 |
      | `am` | `æm` | `ɐm` | 1,451 |

      That is ~221,000 occurrences, close to **9% of every word spoken**. `a`
      is the most striking: `A` is the vowel in *face*, so "a book" currently
      reads as "AY book". `a` and `am` need no context at all — they are flat
      corrections. Only `the` and `to` need the neighbour.

      The in-tree comment claiming the lexicon "gives function words their
      weak forms (`to` → `tu`)" is half right: `tu` beats the stressed BART
      citation form, but it is still the strong form, not the weak `tə`.

      **1. Our lexicon's entry for `the` is `ði` — the *vowel* form.** So today
      every consonant-initial `the` is the wrong one: "thee book". At
      **105,388 occurrences** in the 20-work corpus this is plausibly the
      highest-frequency single mispronunciation in the pipeline, and it is a
      defect rather than a missing feature.

      **2. Misaki already solves this, and we can read the answer.** Python
      Misaki gets every hard case right — `the book` → `ðə`, `the apple` →
      `ði`, `the hour` → `ði` (silent h), `the university` → `ðə` (the `/j/`
      glide), `the FBI` → `ði`. `misaki/en.py`:

          elif word in ('the', 'The') or (word == 'THE' and tag == 'DT'):
              return 'ði' if ctx.future_vowel == True else 'ðə', 4

      Note `== True`, not truthiness: `future_vowel` is tri-state, so an
      **unknown** neighbour falls back to `ðə` — the opposite of our current
      constant. `future_vowel` is computed by scanning the *next* token's
      phoneme string for its first vowel / consonant / punctuation character
      (`VOWELS = frozenset('AIOQWYaiuæɑɒɔəɛɜɪʊʌᵻ')`); punctuation yields
      unknown. Misaki is MIT, so this is portable as-is.

      It is also not one word: the same context drives `to` → `tə`/`tʊ` and
      the weak form of `am`. Porting the *mechanism* gets those free.

      **Independently confirmed in three other engines**, and they agree on
      the trigger: Festival (`postlex_the_vs_thee`), Flite (`the_iy_ax`), and
      eSpeak NG — which does it not as a rule but as a *dynamic phoneme*,
      `the D@2` in `en_list`, where `@2` is documented as "schwa, changes to I
      before a vowel". Running `espeak-ng` here confirms the behaviour on the
      cases that matter: `the university` → `ðə` (the `/j/` glide counts as a
      consonant), `the one` → `ðə` (`/w/` likewise), `the hour` → `ðɪ`,
      `the house` → `ðə`. Note `/h/` is **not** special-cased anywhere — *the
      hour* only works because its lexicon entry already begins with a vowel,
      which is the whole argument for running this on phonemes.

      `g2p_en` notably does *not* implement it and emits `DH AH0` always, so
      this is a real differentiator rather than table stakes.

      **Implemented 2026-08-24 for `the`/`The` and `to`/`To` only**, as a
      post-pass over `(word, phonemes)` parts in
      `KokoroAneEnglishPhonemizer.phonemize`. `a`/`an`/`am`/`in` and
      all-caps `THE`/`TO` remain out of scope (POS-gated in Misaki; we
      have no tagger).

      **Impact, measured over the corpus with the real lexicon: 153,735 of
      168,711 `the`/`to` occurrences (91.1%) now get a different form.**

      | | count |
      |---|---|
      | `the` → `ðə` — previously "thee" | 90,456 |
      | `to` → `tə` | 56,919 |
      | `to` → `tʊ` | 6,360 |
      | already correct | 14,976 |

      Only 12,642 `the` were right before, because `ði` is only correct before
      a vowel and prose is mostly consonant-initial. That is roughly **6% of
      every word spoken** changing to the correct vowel.

      **Verified against the reference at scale, not just by unit test.**
      Replaying the ported algorithm over the real `us_lexicon_cache.json` and
      real corpus sentences, then comparing its `the`/`to` choices to Misaki's
      own output on the same text: **98.51% agreement across 2,760 tokens**.
      Every disagreement was accounted for — Misaki gluing an opening quote to
      the token, the deliberately out-of-scope all-caps `THE`/`TO`, harness
      token misalignment on things like `bit--`, and one genuine consequence
      of the scope limit below.

      **The `a` scope has a knock-on effect worth knowing.** Because we leave
      `a` as the lexicon's `A` (a vowel), `to a` comes out `tʊ`, where Misaki
      gives `tə` — Misaki resolves `a` to `ɐ` first, and `ɐ` is not in its own
      `VOWELS` set, so its scan finds nothing and falls through to unknown.
      Ours is arguably the more consistent answer, but it is a divergence
      created by not porting the POS-gated `a` rule, and it would disappear if
      that rule ever lands.

      **The architectural catch:** our `phonemize` resolves words left to
      right and independently, so nothing knows the next word's phonemes yet.
      Resolve into `(word, phonemes)` pairs first, walk backwards to compute
      the context, apply weak forms, then join — rather than restructuring the
      resolution order.

      Original note follows. `[code]` `/ðə/ before a
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

- [x] **Weak-form pass: four findings from adversarial review (2026-08-24).**
      `[code]` Two of the six checks came back sound — the tri-state genuinely
      distinguishes `nil` from `false` on every path, and the vowel /
      consonant / punctuation sets match upstream character-for-character
      (20 / 25 / 8). The rest:

      1. **Custom overrides are overwritten — the serious one.** Tier-1
         custom-lexicon entries are consulted first, then the post-pass
         rewrites `the`/`to` regardless. This contradicts the override
         contract, whose own API documentation uses `["to": "tə"]` as its
         example, and it breaks the pronunciation editor: a reader correcting
         `the` would have it silently discarded in every context. **Fix: skip
         the rewrite when the word has a custom entry.** No weak-form test
         supplies a custom lexicon, which is exactly why nothing caught it.

      2. **Quotes wrongly terminate the vowel context.** The pass treats any
         trailing punctuation on the current part as unknown, but Misaki
         excludes `"` `“` `”` from `NON_QUOTE_PUNCTS` so they stay
         transparent. `to “apple”` yields `tu` where Misaki gives `tʊ`. The
         character set is right; an earlier shortcut bypasses it. Fic is full
         of quoted titles, so this is a live path.

      3. **Two tests are vacuous.** `theAppleTakesTheVowelForm` and
         `theHourTakesTheVowelForm` pass with the feature removed, because
         `ði` is already the lexicon gold — they assert what the lexicon would
         have produced anyway. The `ðə` cases do the real work.

      4. **`an` is a second scope knock-on.** The real lexicon holds `an` as
         `æn`, not Misaki's `ɐn`, so `to an art museum` sees the vowel `æ` and
         gives `tʊ` where Misaki gives `tə`. Beyond the documented `a`
         exception, with no fixture. Deliberate-scope divergence, not a
         porting error.


- [x] **Regular inflection stemmers (`stem_s` / `stem_ed` / `stem_ing`) — implemented 2026-08-24.**
      `[measured]` `[code]` The possessive item below was the first third of
      this. All three Misaki stemmers now run at the same `resolveWord` point,
      in order `-s`, `-ed`, `-ing`, US-only. Each keeps the existing gate:
      derive only when the inflected form misses every lexicon tier AND the
      stem is a lexicon hit. `US_TAUS` tapping is ported verbatim, not
      paraphrased: `noticed` (stem `nˈOɾəs`) → `nˈOɾəst`, `sitting` → `ɾɪŋ`,
      a `t`-final stem preceded by a taut (`waited` ← `wˈAt`) → `ɾᵻd`.
      Possessive `X's` falls out of `stem_s`'s `"'s"` branch; `KokoroAneEnglishPossessiveTests`
      is unchanged.

- [x] **Contextual pronunciation: possessives — implemented 2026-08-24.**
      `[measured]` The corpus holds **5,896** proper-noun possessives
      across 462 distinct forms. **36.7% miss the lexicon entirely** (base and
      possessive both), and — the number that matters — when the base name *is*
      in the lexicon, the possessive is there only **36.6%** of the time. So
      roughly two thirds of possessives fall through even for known names.
      Most frequent misses are exactly the predicted shape: `Liv's` (360),
      `Oikawa's` (276), `Tobio's` (233), `Cecil's` (232).

      **Confirmed in the real lexicon: not one possessive is present, while
      every base is.** `anna` → `ˈɑnə` but `anna's` → absent; `alice` →
      `ˈælɪs` but `alice's` → absent; likewise `pat`, `james`. `liv` is absent
      entirely, which is why `Liv's` (360 occurrences) is the single most
      frequent miss. So the derivation has a base to work from in exactly the
      cases that matter.

      Misaki's own output confirms the target: `Anna's` → `ˈɑnəz` (/z/),
      `Pat's` → `pˈæts` (/s/), `Alice's` → `ˈælɪsᵻz` (/ɪz/ after a sibilant).
      The rule is real and the reference gets it right.

      **Implemented 2026-08-24** in `KokoroAneEnglishPhonemizer.resolveWord`,
      after the two fanfic recoveries and before letter-name initialisms,
      and **widened the same day** from possessive-only to all three stemmers.
      Apostrophe reinsertion skips any token that already contains an
      apostrophe, so `anna's` does not reach it; de-elongation wants a
      trailing letter run of two or more, so a single `s` after the
      apostrophe does not fire. The gate is the load-bearing part: derive
      only when the stem is a lexicon hit. `James'` is out of scope.

      **The reference implementation, verbatim** (`misaki/en.py`, MIT) — port
      this rather than paraphrasing the textbook rule, because the textbook
      version gets three details wrong:

          def _s(self, stem):
              if not stem: return None
              elif stem[-1] in 'ptkfθ':      return stem + 's'
              elif stem[-1] in 'szʃʒʧʤ':     return stem + 'ᵻ' + 'z'   # 'ɪ' if british
              return stem + 'z'

      1. The voiceless set is **`ptkfθ` — five phonemes**, not "all voiceless
         consonants". `s` and `ʃ` are voiceless but belong to the sibilant
         branch, and `h` is absent entirely.
      2. The epenthetic vowel is **`ᵻ`** for American English, not `ɪ`. That
         matches the observed `ˈælɪsᵻz` for *Alice's*.
      3. Order matters — `ptkfθ` is tested **before** the sibilants.

      And the gate that makes it safe, from `stem_s`: it derives **only when
      the stem is already known to the lexicon** (`is_known`). For `anna's` it
      strips `'s`, confirms `anna` resolves, looks that up, and appends the
      allomorph. That is exactly the boundary the double-clitic hazard
      requires, arrived at independently and then found in the reference.

      Note `James'` — apostrophe with no `s` — fails `stem_s`'s
      `word.endswith('s')` test and is not handled at all; it falls through to
      G2P. So the apostrophe-only plural possessive is out of scope for the
      derivation, not something to special-case.

      **The sibilant set is `/s z ʃ ʒ tʃ dʒ/`**, hardcoded in `misaki/en.py`
      as the string `szʃʒʧʤ` — note the single-codepoint affricates `ʧ`/`ʤ`,
      not the two-character digraphs, which is a real trap for a Swift port
      comparing `Character`s. Flite instead defines the set *negatively* by
      feature (fricative or affricate, excluding dental/labial/velar), which
      excludes `/θ ð f v/` structurally rather than by enumeration and is the
      more robust formulation if we ever extend it.

      **Two edge cases, verified by running `espeak-ng` here rather than taken
      on trust:**

      | input | output | reading |
      |---|---|---|
      | `James's` | `dʒˈeɪmzᵻz` | extra syllable |
      | `James'` | `dʒˈeɪmz` | **no** extra syllable |
      | `the Winchesters'` | `ðə wˈɪntʃɛstɚz` | plural possessive, no extra syllable |
      | `the FBI's` | `ðɪ ˌɛfbˌiːˈaɪz` | initialism, `/z/` after `/aɪ/` |

      So the apostrophe-only form is **not** pronounced like `'s`; the
      orthographic distinction is real and a derivation rule has to respect
      it, or every `Winchesters'` grows a syllable.

      **The hazard that must shape the spec:** `espeak-ng` handed the whole
      token `Anna's` returns `ˈænəz` — it has *already* applied the clitic. A
      G2P fallback given the full token therefore needs no help, and adding
      our own derivation on top would double it (`ˈænəzz`). The derivation is
      only correct where the **base** resolved from the lexicon and the
      possessive did not — which is exactly the 63.4% case measured above, and
      exactly what a tier-1 user correction produces. Getting this boundary
      wrong is worse than not doing it at all.

      Licences for anything reusable: Misaki Apache-2.0, Festival MIT/X11,
      g2p_en Apache-2.0, CMUdict BSD-2-Clause — all AGPL-compatible. eSpeak NG
      is GPL-3.0: compatible, but not permissive, so it constrains differently.
      Flite's "BSD-like" is unconfirmed and must be read before use.

      Original note follows. `[code]` `splitWords` keeps
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

      **Partly wired 2026-08-25 — two of three sources.** `KokoroCastDiscovery`
      was built and tested but called by nothing. The pronunciation list now
      ranks through it, and the reader passes the work's own cast: opened via
      the fan menu's long press, `ReaderSpeechSettingsSheet` forwards
      `workCharacters + workRelationships`, falling back to the flat `workTags`
      union because EPUB subjects arrive uncategorised and `workCharacters`
      stays empty until an AO3 refresh. From global Settings no tags are passed
      and the ordering degrades to plain guess count, exactly as before.

      **The pre-flight is now real — built 2026-08-25.** `rank` maps over the
      guessed log, so until now a word the engine had never guessed at could
      not appear however heavily it was tagged: the list was *retrospective*,
      and the reader had to hear a name mangled once before they could fix it.

      G2P turns out to be separable from synthesis, which is the whole reason
      this is possible: `KokoroAneManager.phonemes(for:)` runs the frontend and
      nothing else, and the fallback observer fires from that same path —
      upstream documents the observer as existing precisely so a frontend can
      offer "words I guessed at" for correction. `KokoroCastPreflight.scan`
      phonemises the chapter, records what fell through, and the list is
      populated before the first tap. Reached from *Scan this chapter* in the
      pronunciation list.

      Two things it is careful about. **There is exactly one fallback
      observer**, and `setNeuralFallbackObserver` replaces rather than adds, so
      scanning during playback would redirect the engine's own guesses into the
      scan's collector and lose the very words the reader wants — refused with
      `.playbackActive`, and the observer is always cleared afterwards.
      **`isAvailable` matches the three conditions playback uses to choose Core
      ML** (safe OS line, pack installed, engine not already abandoned on this
      device), not just the pack, so the button does not appear where it cannot
      work.

      **Core ML only, and unverified on a device.** sherpa-onnx takes text and
      returns audio with no exposed frontend, so on iOS 26 there is nothing to
      ask. The simulator has no pack, so `isAvailable` is false there and the
      button cannot be exercised — the guards are unit-tested, the scan itself
      is not.

      **All three sources are now wired.** NER was the last one, and it was
      only blocked because `recognisedNames(in:)` needs the chapter text, which
      nothing outside playback had. The pre-flight has it, so the scan runs NER
      over the same text in the same pass and hands the names back with its
      result. That is the source that finds Original Characters — often the
      most-spoken name in a work, and the one AO3 tags never carry — which the
      caveat above says matters most.

      It follows that NER names are available only *after* a scan; before one,
      ranking uses tags alone. Carried back in the result rather than cached,
      because nothing else has the text to recompute them from and a stale set
      would silently rank one chapter's names against another's.
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

- [ ] **Multi-voice dialogue — DEFERRED by owner decision (§3b).** Do not
      build. Attribution errors are more audible than the benefit.
      `[proposal]` The biggest single upgrade
      available, unlocked by going from 1 voice to 28. **27.7% of blocks in the
      measured work open with a quote** `[measured]`. Parse attribution, assign
      per character from the tags already in hand, keep the narrator distinct.
      Largest item on this list.

- [ ] **Emphasis from EPUB markup — rule built, wiring BLOCKED.**
      `[measured]` `[code]` `KokoroEmphasis` implements the rule and is tested;
      what is missing is any way to know a word was emphasised.

      **Readium discards it before we see it.** `TextContentElement` carries an
      `attributes: [ContentAttribute]` array, but
      `HTMLResourceContentIterator` only ever populates `.accessibilityLabel`
      (for images) and `.language`. There is no emphasis or style attribute,
      so `<em>`/`<i>`/`<strong>` never reaches `TTSSpeechUnit`. The plan said
      this markup was "parsed and discarded" — it is discarded by *Readium*,
      not by our layer, which is a materially harder problem.

      Readium is an SPM dependency (`readium/swift-toolkit`), not vendored the
      way FluidAudio is, so there is no patch hook equivalent to
      `fluidaudio-kudos.patch`.

      Two routes, neither cheap. **Fork or upstream a change to Readium** so
      the iterator emits an emphasis attribute — cleanest, slowest, and an
      upstream PR is plausible since the data is already in the DOM it walks.
      Or **parse the EPUB XHTML ourselves** alongside Readium's text and match
      spans by offset — we already hold the file, but aligning raw markup
      against Readium's *normalised* text is exactly the class of fragile
      matching that goes wrong silently.

      **The rule itself is measured and settled**, so whichever route lands,
      the hard part is done: an emphasised word must carry primary stress.
      15.4% of single-word spans change (5.7% promote a lone secondary, 9.6%
      stress a weak form); 68.1% already carry primary stress and correctly get
      nothing.

- [ ] **Emphasis from EPUB markup (original note).** `[code]` `<em>`/`<i>`/`<strong>` is
      authorial stress, and in fic italics also mark internal thought.
      `KokoroSemanticBlock` carries `selector` but only ever tests it for
      `h1-6`, `blockquote`, `hr` — the inline signal is discarded.

- [x] **Fanfic's own conventions — measured 2026-08-25; mostly nothing to do.**
      `[measured]` Counted across 98,384 corpus paragraphs. The honest result
      is that these either have no lever or are already handled correctly, and
      one of them would be actively wrong to implement.

      | convention | count | verdict |
      |---|---|---|
      | ALL-CAPS run (3+ words) | 1,106 | no lever |
      | `*asterisks*` | 190 | **not emphasis** — already right |
      | elongated vowels | 149 | already de-elongated |
      | `_underscores_` | 27 | negligible |
      | `~tildes~` | 9 | negligible |
      | `s p a c e d  o u t` | 2 | negligible |

      **`*asterisks*` are stage directions, not emphasis.** The corpus says so
      plainly: `*hours later*`, `*click*`, `*ahem*`, `*sighs*`. Treating them
      as emphasis — which is what this item assumed — would stress roleplay
      notation. They are already handled correctly by two mechanisms that
      happen to compose: the scene-break filter requires the *whole* line be
      decorative, so `***` becomes a scene pause while `*ahem*` does not; and
      `*` is absent from Kokoro's vocab, so `encode` drops it and the word is
      spoken bare.

      **ALL-CAPS is the common one and has no phoneme lever.** It is shouting,
      but each word resolves from the lower-cased lexicon and is spoken
      normally. Kokoro ignores capitalisation entirely, and the emphasis
      measurement above already established that 68.1% of emphasised words
      carry primary stress and therefore have nothing to promote. Adding `!`
      is the only remaining idea and is speculative — it changes punctuation
      the author did not write.

      Elongated vowels (`Noooo`) are already collapsed by the de-elongation
      stemmer, which is a deliberate trade: the lexicon form is intelligible,
      the held vowel is not reproducible without a duration lever we lack. `[proposal]` ALL-CAPS, `*asterisks*`,
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
| blocks containing `<br>` | 4,214 (1.7%) — 9,681 seams |
| runs of 4+ consecutive broken lines | 632 |
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

**Correction (2026-08-24).** The seam figures above were first computed over a
file set that globbed both `epubs/` and `epubs2/`, which share **9 duplicated
works** — 38 files for 29 distinct EPUBs. That does not merely scale the
counts, it double-weights those nine works and so biases every ratio toward
them. All numbers here are the deduplicated ones: 9,681 seams across 29 unique
works, 60.9% ending a sentence, 97 enjambment cases (1.0%), and 0 of 632 runs
matching a wrap-width signature. **Every conclusion survived the correction** —
the hard-wrap result was zero either way, and the enjambment cost moved from
0.8% to 1.0%. Caught by an adversarial review noticing that two documents in
this repo quoted different seam totals.

### 6.3.1 What we actually do to those breaks — verified end to end

`[code]` The chain from AO3's server to our audio:

1. AO3 stores a single author newline as `<br>` (`paragraph_maker.rb`), having
   already promoted every multi-line break to a `<p>`.
2. Readium's `HTMLResourceContentIterator` calls `flushText()` when it meets a
   `br` tag, so each broken line arrives as its **own** `TextualContentElement`
   and therefore its own `TTSSpeechUnit`.
3. Both engines honour the seam. Kokoro: `KokoroSemanticDocument` treats a
   shared `cssSelector` as a `<br>` seam, flushes the open block with
   `endsAtLineBreak`, and the packer emits a `.line` pause (0.22 s) rather
   than `.paragraph`. Apple: `packedChunks` partitions on the same
   discriminator before concatenating, so each seam is a separate
   `AVSpeechUtterance` and `postUtteranceDelay` (also 0.22 s) carries the
   pause. Adjacent `<p>`s (different selectors) are unchanged on both paths.

- [x] **Preserve `<br>` as an audible boundary.** Implemented as a `.line`
      pause between same-selector units, not as a G2P-cross-break join: each
      broken line is already its own `TTSSpeechUnit`, and packing is
      per-block. The last line of a broken `<p>` keeps `.paragraph`; a
      following heading still wins via lookahead; scene-break promotion via
      `max` is unchanged.

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

- [x] **Check for stacked pauses — checked 2026-08-25, they do not stack.**
      `[measured]` The worry was that `…` yields 0.5–1 s from the model and
      `KokoroPauseAssembler` then appends a structural pause on top, so an
      ellipsis at a paragraph end would run ~1.3 s. It does not, because
      `trimEdgeSilence` runs **first** and cuts the model's trailing silence
      back to `keepEdgeSeconds` (20 ms). Measured on a synthetic clip with
      0.10 s of tone and 0.80 s of trailing silence: assembling with
      `.paragraph` gives **0.44 s**, not the 1.22 s the stack would produce.
      The ordering is the entire reason, so it is pinned by
      `testAModelPauseIsNotStackedOnTopOfTheStructuralOne` — swapping those
      two steps would reintroduce the stack without failing anything else.
- [ ] **Default speed 0.9, not 1.0.** `[prior-art]` Audiobook narration is
      widely recommended at 0.9 (1.05 for ads). One line in
      `ReaderSpeechPreferences.defaultRate`, but it changes everyone's
      experience — A/B first.
- [ ] **Normalization escape hatch — not the one-line toggle this was
      written as.** `[code]` Kokoro-FastAPI exposes `normalization_options:
      {normalize: false}` because normalization "can incorrectly remove or
      change some phrases". We stack two normalizers with no way to inspect or
      disable either. Checked 2026-08-25, and **neither stage takes a toggle
      cheaply**:

      1. `KokoroSpeechNormalizer` is ours but **load-bearing for structure**,
         not just pronunciation. It is what converts straight quotes *to*
         curly, and `classify` detects dialogue by testing the normalised
         first character against `openQuote`; `KokoroBoilerplateFilter` and
         `KokoroPhonemeBudget` normalise before matching too. Disabling it
         globally would silently reclassify every dialogue block, so an
         honest toggle has to be scoped to the phonemiser input alone.
      2. NeMo's `EnglishTextNormalizer` is `internal` to FluidAudio
         (`TTS/Shared/EnglishTextNormalizer.swift`, called from
         `KokoroAneManager.swift:223`). It is not reachable from our module at
         all — no toggle, and not even a *preview* — without adding a `public`
         to `Scripts/fluidaudio-kudos.patch`, which is more upstream-bump
         maintenance for a debug affordance.

      So the realistic shape is a **read-only preview** of stage 1 in
      Developer Settings, and stage 2 stays opaque unless the patch grows. Not
      started: worth doing when a real mispronunciation needs tracing, rather
      than speculatively.

---

## 8. Housekeeping and known defects

- [x] **Speed changes need a restart — fixed 2026-08-25.** `[code]`
      `CoreMLKokoroTTSService.speak` captured `currentSpeed` into a local at
      start, so the slider did nothing until the next utterance batch — and
      since a batch is a whole chapter, effectively never. Each clip now reads
      the live value, so a change lands one clip later (the next is already
      prefetched at the old rate). Voice stays captured deliberately:
      switching narrator mid-chapter should finish in the voice it started
      in.
- [ ] **Republish the pack with 28 voices.**
      `Scripts/pack-kokoro-ane-github-release.sh` → `gh release create` → bump
      `tag` and `expectedSHA256` in `KokoroGitHubPack`. The published release is
      still the 1-voice build.
- [ ] **Device-test both engines.** Core ML needs an iOS 27 device; Sherpa needs
      iOS 26. **Nothing on this branch has produced audible audio.**
- [x] **Pre-existing suite failures — fixed 2026-08-25.** 9 tests failed
      identically on commit `2a61aaf4`, before any TTS work and with the
      original MiniZip: `FolderSyncTests` + `KudosBackupFontRestoreTests`
      case-folding, and `WorkStatLabelTests/categoryColorMatchesAO3sOwnCoding`.
      All three now pass; the full suite is **1,485 tests / 0 failures** in
      ~22s. That last number is the point: these failures were making
      `xcodebuild` run `simctl diagnose --timeout=600` on every run, which is
      why the suite used to take over an hour.
- [ ] **Heading detection depends on the CSS selector.** `[measured]` The
      text-only regex matches 74/104 headings; "Preface" and a work's title
      match nothing. Fine while Readium supplies `cssSelector`, silent
      degradation if it ever does not.
- [ ] **Two speech files exceed their SwiftLint length warnings.**
      `ReaderSpeechController` is at 780 lines against a 700 limit (it was
      already over at 760; the pronunciation pre-flight added the rest).
      `ReaderSpeechSettingsSection` exceeds type-body-length (556 lines as of
      2026-08-25, up from 532) after gaining the
      Core ML section and the Developer Settings link. Non-blocking, but it
      only grows: the natural split is to lift each engine's block into its
      own view, the way `ReaderSpeechDeveloperSettingsView` already is.
- [ ] **x86_64 simulators no longer link** — FluidAudio ships an arm64-only
      `libtext_processing_rs.a`.
