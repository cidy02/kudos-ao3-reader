# Fandom name disambiguation — findings and implementation plan

**Date:** 2026-08-30
**Branch:** `grok/kokoro-coreml-ane`
**Code under discussion:** `FandomDisplayName.split` and `FandomListRow` in
`kudos-ao3-reader/Features/Search/FandomListView.swift`; tests in
`KudosTests/FandomDisplayNameTests.swift`.

---

## 1. What this is about

AO3 appends disambiguation to fandom tags so they stay unique:
`Naruto (Anime & Manga)`, `One Piece - All Media Types`, `Hamilton - Miranda`,
`One Direction RPF`, `博士斯通（漫画）`.

The Browse → category → fandom list renders the **title** in primary text and the
**disambiguation** smaller and grey on the same line. `FandomDisplayName.split`
decides where the title ends and the suffix begins.

**Getting it wrong is cosmetic.** The full name is still displayed, still
searched, and is still what the works query receives.

## 2. Evidence base

The app's own catalog cache: **144,866 fandom tags (142,933 unique)** across all
11 AO3 media categories, pulled from the simulator's
`Library/Caches/Metadata/fandom-catalog.json`. No AO3 requests were made for this
analysis.

Measured distribution over the *primary* name (last `|` segment):

| Convention | Share |
|---|---|
| trailing ASCII parenthetical | 59,158 (40.8%) |
| contains a spaced dash | 41,886 (28.9%) |
| ` RPF` suffix | 2,394 |
| fullwidth `（...）` | 699 |
| `《...》` (whole-title wrapper, must NOT strip) | 161 |
| en/em dash variants | ~130 |

Most common dash tails: `Fandom` 17,424 · `All Media Types` 652 · then ~15,432
distinct tails, **12,601 occurring exactly once** and overwhelmingly creators and
author handles.

## 3. Current implementation

Three forms, each firing **at most once**, in a loop so they can stack in any
order:

1. `" RPF"` (case-insensitive, spaced only)
2. trailing parenthetical, ASCII or fullwidth, via `lastIndex(of:)`
3. trailing spaced dash tail — `" - "`, `" – "`, `" — "`, `" ‐ "` (U+2010)

Plus the literal `All Media Types` attached by any delimiter, and a debris trim
that removes a separator left dangling on the end of a peeled title.

Current result: **67.90% of names get a qualifier, 0 empty titles**, 52 tests.

### Why the loop needs the once-only flags

A single pass was not a fixed point — stripping a dash tail exposes an RPF that
was never revisited (62 titles still ended in "RPF"). But an *unguarded* loop
over-strips: it ate a title's own parenthetical and turned
`Ellie and Abbie (and Ellie's Dead Aunt) (2020)` into `Ellie and Abbie`. A second
bracket or dash belongs to the title.

---

## 4. The four independent passes

Four agents analysed the same 144,866 names independently, without seeing each
other's work or the parser.

| Pass | Outcome |
|---|---|
| Claude | 7 patterns |
| Gemini | 15 patterns |
| Grok | 12+ patterns, richest single catalogue |
| Codex | 15 patterns (first attempt died on a usage limit; re-run succeeded) |

Counts differ between agents mainly because some counted **unique names** and
others **raw catalog rows** (a tag can appear under several categories).

---

## 5. Consolidated findings

### 5.1 Confirmed, actionable, uncontested

| # | Pattern | Count | Found by |
|---|---|---|---|
| A | **`& Related Fandoms`** | 80 unique / 143–148 rows | Gemini, Grok, Codex |
| B | **`-Fandom` glued, no space** | 178–193 | Grok, Codex |
| C | **Glued terminal `RPF`** | 49 | Codex |
| D | **Localized "All Media Types"** | 8–21 | Grok, Codex |
| E | **Mixed-width bracket pairs** | 16–23 | Claude, Grok, Codex |

**A** — `Sherlock Holmes & Related Fandoms`, `Swan Lake & Related Fandoms`,
`Bridgerton (TV) & Related Fandoms`, `Arsène Lupin & related fandoms`.
Forms: `& Related Fandoms` ×76, `and Related Fandoms` ×3, lowercase ×1.
Grok's caveat: match the **last** occurrence only, or
`Spirou & Fantasio & Related Fandoms` loses its series ampersand. And
`Eason-Related Fandoms` / `Chinese Related Fandoms` are titles, not suffixes.

**B** — `The Expanse-Fandom`, `Creepypasta-fandom`, `Bleach TYBW-Fandom`,
`杀死你的旅程—Fandom`. Rule 2 requires a *spaced* dash, so these are missed.

**C** — `hetamyuRPF`, `The Notebook(2004)RPF`, `中国音乐剧演员RPF`,
`逆爱｜Revenged Love（TV）RPF`. We match only the spaced form. Needs a
nonempty-stem guard.

**D** — `刺客信条-所有媒体类型`, `死侍-所有媒体类型`, `蝙蝠俠-所有媒體型別`
(traditional variant). A small translated-phrase map.

**E** — `BLEACH(Anime&Manga）` opens ASCII and closes fullwidth;
`南风知我意(TV）`, `第三日（原创作品)`. Neither bracket rule fires.

### 5.2 Data quality — upstream, not display

| # | Pattern | Count | Notes |
|---|---|---|---|
| F | **`Navigation and Actions` glued onto tags** | 21 | Codex. `Digimon - All Media TypesNavigation and Actions` — the fandom-index scrape is capturing page chrome. |
| G | **Raw HTML fragments as tag names** | 2 | `</li>\n </ul>...`, `<span class="__cf_email__"...` |
| H | **HTML entities left encoded** | 9 | Codex. `&lt; - Fandom`, `Alice in the wonderland inspired &lt;3` |
| I | **Invisible Unicode controls** | 14 | Codex. U+200E, U+200C, U+2060, U+202A. One row is *visually blank* before ` - Fandom`. |

**These are parser/ingestion bugs in the AO3 fandom-index scrape, not display
bugs.** F and G in particular mean the scraper is picking up navigation markup.

### 5.3 Design issue, not parsing

| # | Pattern | Count |
|---|---|---|
| J | **Sibling collision** | 1,110 names (Claude) / 6,223 stems, 14,232 names (Grok) / 534 bare-name collisions (Codex) |

`Political RPF` ×39, `Les Misérables` ×23, `Spider-Man` ×21, `Frankenstein` ×17,
`Doctor Who` + `(1963)` + `(2005)` + `(Big Finish Audio)`.

Where a stem has many variants, **the qualifier is the only thing telling the
rows apart**. Uniformly greying it makes 23 Les Misérables rows look identical
while scanning — the opposite of the feature's goal.

Codex's related safety note: **never use the parsed title as a unique key.**
534 stems exist both bare and parenthesized.

### 5.4 Negative rules — confirmed safe, do NOT strip

| Pattern | Count | Why |
|---|---|---|
| `《...》` | 161 | Wraps the whole title (`《病案本》`) |
| `【...】` | 367 (352 leading) | Inner text is the identity — ship name, chapter, or part of the Japanese title |
| Tilde wraps `~…~` `～…～` `〜…〜` | 214 | `D.C. 〜ダ・カーポ〜` |
| `-Subtitle-` wraps, incl. U+FF0D / U+2015 | 82 | `Lamento -BEYOND THE VOID-` |
| `[furigana]` | — | `炎の蜃気楼[ミラージュ]`, `Tell Me A Lie [私にウソをついて]` |
| `:)` `:(` and `Sunn O)))` | 14 + 1 | A smiley is not a parenthetical |

### 5.5 Inherently ambiguous — no general rule exists

**The dash residual.** A title that legitimately contains a spaced dash gets its
tail wrongly greyed:

- `ef - a fairy tale of the two.`
- `Looney Tunes - World of Mayhem`
- `Vampire: The Masquerade – Bloodlines`
- `Space Pirate Captain Harlock: Outside Legend - The Endless Odyssey (Anime)`
- `Neverwinter Nights 2 - Baldur's Gate: The Sword Coast Chronicles`

Codex tested every candidate signal against the full index and **all of them
collide**:

| Signal | Result |
|---|---|
| Tail recurs across ≥2 distinct titles | demotes only 69.6%, leaves 12,738 bold; and `The Sith Lords` recurs but is title in both |
| Lowercase initial | 550 tails, nearly all author handles (`priest`, `refrainbow`) that SHOULD be demoted |
| Token count | 1: 20,655 · 2: 12,049 · 3: 6,168 · 4+: 3,014 — no threshold |
| Tail length | median 10, P99 35, max 130 — a real 130-char qualifier exists |
| Article/preposition/verb in tail | collides with `Cuttlefish that Loves Diving` |
| Any punctuation | 21.6% — `J. R. R. Tolkien`, `clipping.` |
| Tail is a standalone fandom | 43.8%, but 18,076 of those are just `Fandom`/`All Media Types` |

Feature-vector collision proving it: `Saint Seiya: Episode G - Assassin` and
`Doujin Work - Hiroyuki (Manga)` have identical tail signatures — 8 chars, one
token, uppercase, no punctuation, singleton, same category. One is a title
continuation, one is a creator.

**Verdict: no general rule.** A manual exception list is the only precise option,
and at roughly one name per 2,000, Codex advises adding entries only when a real
one is reported rather than maintaining a list proactively.

### 5.6 Measured and rejected

- **Least-CJK `|` segment as primary** instead of the last: right 14,512 vs wrong
  100 (0.07%). Not worth a Unicode scan per row.
- **Dropping en/em dash separators** (Grok raised the risk): measured ~10–20
  wrong against ~90–100 right across 114 names. **Keep them.**
- **Trailing bare year** (136, `Avatar 2026`): would break `Blade Runner 2049`,
  `Cyberpunk 2077`, `Metro 2033`.
- **Fullwidth `｜` alias split** (330): some titles wrap in it — `[雨成｜R]易感`.
- **Square brackets as suffix** (45–60): `Captain America: Civil War [2016]`
  argues for, `[ミラージュ]` furigana argues against.
- **`RPS`** (64): unrestricted matching catches `LiamCarps`, `zgyyjrps`.

---

## 6. Implementation discussion

Four agents were given the same question — *given these findings and the existing
code, how should this be implemented?* — first independently, then in shared
rounds where each read the others' plans.

Two rounds were needed. Round 1 was independent; Round 2 was a shared room where
each read the others' plans. **All four ended at CONSENSUS: yes on the same plan.**

### Round 1 — where they split

| Question | Claude | Gemini | Grok | Codex |
|---|---|---|---|---|
| Rules A, B, C, E | ship | ship | ship | ship |
| Rule D (localized AMT) | **skip** | ship | ship | ship |
| J — sibling collision | defer | defer | defer | **fix now** |
| Parsing location | keep in row | keep in row | keep in row | **move out** |
| F–I | separate task | separate task | separate task | separate task |

### Round 2 — the concessions

**Codex conceded both of its positions.** On J: full-category counting does remove
the filter flicker, but not "the unvalidated conditional typography or load-time
projection cost". On placement: "without J, precomputed `FandomListEntry`s have no
independent case."

**Claude conceded D.** The "it will rot" objection applies equally to the English
literal already shipped; refusing the translated form while keeping the English one
is not scope discipline.

**Claude withdrew its performance argument** for keeping parsing in the row — 14k
splits is ~20ms once per category open, off the main actor, which is not a real
cost. The reason to keep it in the row is that a new type and builder is
maintenance cost that only pays for itself if J is taken too.

**Gemini conceded** its uppercase-only glued-RPF guard after Grok measured that
case-insensitive terminal `RPF` has zero false positives.

### Corrections surfaced by the cross-read

- **Codex:** the largest category is **Uncategorized Fandoms at 68,271 rows**, not
  14k. 144,866 is the all-category total. *(Verified.)*
- **Codex:** finding D is not CJK-only — there are Portuguese and Spanish forms.
  *(Verified: `Todos os Tipos de Mídia` ×5, `Todos los tipos de medios` ×5.)*
- **Grok:** Codex's D list dropped 11 of the 20 localized names; its B rule was too
  tight (misses 13 `x -Fandom` and 46 `x- Fandom`); its E pair-list can bind the
  wrong opener on a mixed-width name.
- **Grok:** Gemini's proposed ZWNJ stripping at ingest would corrupt real Persian
  and Telugu names (`تی‌ام`, `شب‌های`). This must not be carried into the F–I task.
- **Grok:** Gemini's loop bound `0..<5` with six rules is an off-by-one.
- **Claude:** the existing test `aPlainNameHasNoQualifier` uses
  `Sherlock Holmes & Related Fandoms` as a "plain name" fixture. It is not one —
  that fixture has to be rewritten.

---

## 7. THE VERDICT — agreed plan

**One commit. Parser rules and tests only.** Raw `fandom.name` remains identity,
filter text, zoom key, and works-query payload; the parsed title is never a key.

### Loop order

Keep the once-only flags; bump the bound to `0 ..< 6`. Order inside each iteration,
outer named suffixes first:

| # | Rule | Shape |
|---|---|---|
| 1 | **A** `& Related Fandoms` | New flag. Needles `" & Related Fandoms"` / `" and Related Fandoms"`, case-insensitive, terminal, **last** match. The leading space keeps `Eason-Related Fandoms` and `Chinese Related Fandoms` whole; last-match keeps `Spirou & Fantasio`. |
| 2 | **C** `RPF` | Existing flag. Needle `" RPF"` → `"RPF"`, case-insensitive, terminal, nonempty tidied stem. `hetamyuRPF` and `真人rpf` peel; bare `RPF` stays whole. |
| 3 | **D** All Media Types | Existing flag, extended literal list: `All Media Types` · `所有媒体类型` · `所有媒體類型` · `所有媒體型別` · `Todos os Tipos de Mídia` · `Todos los tipos de medios`. No speculative translations. |
| 4 | **E** trailing parenthetical | **Must stay before the spaced dash**, or `À Tout le Monde (Set Me Free) - Megadeth (Music Video)` loses its title parenthetical on the next turn. Accept any terminal `)` or `）`, then take the **later** of `lastIndex("(")` and `lastIndex("（")` — not a pair list, which can bind an earlier opener of the wrong width. |
| 5 | — spaced dash | Unchanged, including U+2010. |
| 6 | **B** glued `Fandom` | New flag, **after** the spaced dash so `" - "` still wins. Terminal `Fandom` case-insensitive; trim left whitespace; last char in `-–—‐`; nonempty tidied stem. Catches `The Expanse-Fandom`, `杀死你的旅程—Fandom`, `Fanfic -Fandom`, `Jinkx Monsoon- Fandom`. Does not peel `Pizza Fandom`. |

Peeled pieces still insert at index 0. `tidied` unchanged. `|` handling unchanged.

### Deferred, with the reason

- **J (sibling collision)** — deferred, not rejected. If it proves annoying on
  device, the agreed next step is *not* collision detection: it is a
  screenshot-gated uniform contrast tweak on the qualifier for every row. Only if
  that fails should a full-category collision `Set` be considered — and a `Set`,
  not an entry model.
- **F–I** — a separate task against `AO3Client.parseFandomIndex`, with fixtures in
  `AO3ClientTests`. Must invalidate the cached catalog so malformed names do not
  linger. **Must not blanket-strip Unicode format characters.**
- **Parsing location** — stays computed per visible row, with local `let` bindings
  in `body` so it runs once per body evaluation. No `init` cache (SwiftUI recreates
  the struct), no model fields, no cache-schema change.

### Not in this change

J · F–I · any dash-residual exception list · RPS · bare trailing years · `[]` /
`《》` / `【】` / tilde wraps · fullwidth `｜` alias split · least-CJK `|` selection ·
`SearchView` · new files · regex · `project.pbxproj`.

### Definition of done

- Real index strings as test fixtures for A–E, plus the negative guards:
  `Spirou & Fantasio & Related Fandoms`, `Eason-Related Fandoms`, `Sunn O)))`,
  `MYSTERIOUS MURDER DIY :)`, `f(x) (Band)`,
  `Ellie and Abbie (and Ellie's Dead Aunt) (2020)`, `Pizza Fandom`.
- Rewrite `aPlainNameHasNoQualifier` — `Sherlock Holmes & Related Fandoms` is no
  longer a valid "plain name" fixture.
- Pin that `Doctor Who (1963)` and `(2005)` share a display title while their ids
  remain the raw names.
- Full-catalog diff of old vs new output before commit — every name whose split
  changes, not just counts. Record coverage, empty titles (must stay 0), and
  titles still ending in a separator in the commit body. No 144k sweep in CI.
- `Scripts/verify.sh` green; manual Browse pass on Movies/TV confirming a
  Related-Fandoms row, a glued `-Fandom` row, a CJK or PT All-Media-Types row, and
  that tapping still searches the **full** tag.
- `TASKS.md` records F–I as a `parseFandomIndex` follow-up and J as deferred.

---

## 8. Division of labour

Rounds 3 and 4. The owner's constraint: **all code written by an agent must be
reviewed by the others.**

### Unanimous in Round 3

**Do not divide the implementation.** All four agents independently reached the
same conclusion: this is one ordered state machine — six rules sharing flags, a
loop bound, peel order, cleanup and qualifier assembly — not six independent
rules. Splitting it per-rule means four agents editing one function, and the
merge would be hand-reconciled, which is exactly where the load-bearing ordering
constraint (E before the spaced dash) gets lost. Tests stay with the
implementation for the same reason.

Codex put it best: *"Per-rule branches would create semantic merge conflicts."*

### Round 4 — the one deadlock

Round 3 split 2–2 on **who authors**: Grok and Claude said Claude; Gemini and
Codex said Gemini. The argument for Gemini was process, not capability — if
Claude both writes the source and runs the gate, the fixes made chasing compile
errors are unreviewed source edits.

**Gemini changed its position in Round 4, making it 3–1 for Claude.** Its stated
reason: authoring should default to whichever candidate has direct execution and
gate tooling for the target environment. Grok agreed and added that a patch
authored elsewhere still routes through Claude to compile, so every compile error
becomes a round trip.

**Codex did not concede** and remains on record for Gemini authoring, on the
grounds that the non-gatekeeper should author whenever an eligible one exists.
Recorded rather than smoothed over.

### The agreed division

| Who | Role |
|---|---|
| **Claude** | Authors the parser + tests as one patch. Runs `Scripts/verify.sh`, the simulator Browse check, and makes the single commit. |
| **Grok** | Reviews rule semantics against the corpus — the localized AMT literal set, creator/RPF tails, long-tail results. |
| **Codex** | Reviews control flow — §7 ordering, once-only flags, mixed-width brackets, cleanup, scope creep. Smallest brief of the three; it hit a usage limit today and is not reliable for long unattended work. |
| **Gemini** | Reviews structure, and writes adversarial test cases independently of the author's. |

### The gate-fix rule

All three round-4 answers converged on the same principle, worded differently.
Adopted:

> Claude iterates to a **green gate before review opens**. Once review has
> started, only two kinds of edit are allowed: reviewer-requested changes, and
> mechanical fixes determined by a compiler, SwiftLint or harness diagnostic that
> preserve behaviour. Mechanical fixes must be disclosed to all three reviewers
> before commit. Any change to parse logic, control flow or a test assertion is a
> new patch and needs three reviews.

### Future deadlocks — no fourth round next time

> If the shape is agreed and the disagreement is only staffing, do not vote
> again: the agent that can run the verification loop authors. Escalate to the
> human owner only for product, scope, or outward-facing conflicts.

### Review checklist for this change

A reviewer must do all three and say which they did:

1. **Read the diff** against §7's rule table. Verify the order
   `A → C → D → parenthetical → spaced dash → B`, six one-shot flags, `0..<6`,
   a nonempty tidied stem on every rule, qualifiers still prepending, and
   `tidied` / `|` behaviour unchanged.
2. **Run the corpus diff** — old vs new over all 144,866 names — and inspect the
   names whose output *changed*, not the counts. Counts have agreed while the
   behaviour was wrong twice already in this work.
3. **Write one adversarial input** they expect to break it, and report the result
   either way. A review producing no new test case has not been done.

Required in any sign-off: empty titles still 0; no title ends in a separator or
`:`; the negative guards hold (`Sunn O)))`, `Eason-Related Fandoms`,
`Pizza Fandom`, `f(x) (Band)`, `Ellie and Abbie (and Ellie's Dead Aunt) (2020)`,
`MYSTERIOUS MURDER DIY :)`); and `id` / filter / zoom key / works query all still
use the raw name.

**Blocking rules.** A reviewer may block on evidence — a name whose output
changes wrongly — but not on taste. Any unclassifiable changed row blocks the
ship. Anything where the parsed title could leak into identity, search or the
works query escalates to the owner immediately, not after a second round.

Two review rounds maximum. Ties break toward the smaller change.

### Sharded catalog audit — the genuinely parallel piece

144,866 names is too many to eyeball; the *changed* set will not be. Each row is
emitted with category, raw name, trimmed primary segment, old split, new split,
and a rule label. Every changed row gets one accountable reviewer, labelled
expected / unexpected / needs-owner-decision.

| Reviewer | Slice |
|---|---|
| Grok | `Celebrities & Real People`, `Music & Bands`; leads count reconciliation |
| Codex | `Movies`, `TV Shows`, `Books & Literature`, `Theater` |
| Claude | `Anime & Manga`, `Cartoons & Comics & Graphic Novels`, `Video Games`, `Other Media` |
| split three ways | `Uncategorized Fandoms` (68,271) — allocated by sorted changed-row ranges to equalise load, each range recorded |

Claude re-runs the whole corpus before committing so nothing falls between
slices.
