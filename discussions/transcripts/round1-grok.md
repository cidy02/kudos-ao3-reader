=== grok delegate result ===
mode:    write-capable
stop:    end_turn
session: 01a0515d-2141-74d1-a260-32f89278432f

I'll start by reading the findings document, the existing fandom-name display code, and the tests so the plan is grounded in what's already there.I have the parser and tests. Next I’ll locate the scraper, catalog types, and any other call sites so the plan can say exactly where each change belongs.I’ll re-measure A–E and the glued-RPF false-positive risk against the catalog so the rule shapes aren’t just guesses.Checked the catalog (144,866 rows) against A–E, glued-RPF false positives, and per-category sibling collisions. Plan below is the one I would implement.

---

# Fandom display-name plan (Grok)

**Confidence:** ~85% on A–E rule shapes (re-measured against the catalog). ~90% on leaving J and F–I out of this change. I would re-run the three “before commit” checks in §7, then ship.

This is a **cosmetic parser extension** in `FandomDisplayName.split`, plus tests. One commit. The full raw `fandom.name` remains identity, filter text, and the works-query payload.

---

## 0. What already works — do not reopen

Keep the once-only loop, the four existing flags, `tidied`, both parenthesis widths, the four spaced dashes (including U+2010), and “a second bracket or dash belongs to the title.”

Keep `|` handling in `FandomListRow`: last segment is primary, earlier segments are aliases. Do not switch to “least-CJK segment.”

Keep `onSelect(fandom.name)`, `AO3Fandom.id == name`, `.workCardZoomSource(..., fandom.name)`, and catalog search on the raw name.

---

## 1. Findings A–E — implement all of them, in one change

Counts below are **unique primary names** (last `|` segment) from this catalog, unless noted.

| # | Unique | Why it is worth a rule |
|---|---:|---|
| **C** | 47 | One-character change to an existing rule; **0 false positives** in 144k |
| **E** | 16–21 | Same: fix the matcher that already exists |
| **D** | 20 | Same named-phrase family as English “All Media Types” |
| **B** | 193 glued + 46 messy spacing | Same job as 17k spaced `- Fandom`, currently missed |
| **A** | 80 | Same job as “All Media Types”; existing test treated it as a plain title by accident |

Ship order is the loop order below, not “smallest diff first.” All five go in together; they stack.

### Loop shape

Bump `0 ..< 4` → `0 ..< 6`. Add two flags: `tookRelatedFandoms`, `tookFandomTail`. Do **not** reuse `tookSeparator` for B — a spaced dash and a glued `-Fandom` can both be real (0 such names in the catalog, but the flag split is the existing design).

**Order inside each iteration** (each block still once-only):

1. **RPF** (C: drop the required leading space)
2. **`& Related Fandoms` / `and Related Fandoms`** (A) — must run while the string still *ends* with that phrase, or `Bridgerton (TV) & Related Fandoms` never exposes `(TV)`
3. **All Media Types + localized phrases** (D)
4. **Trailing parenthetical, mixed-width** (E)
5. **Spaced dash** (existing)
6. **Dash + `Fandom` with flexible spacing** (B) — after the spaced dash so `" - "` still wins when both could apply

Stop when `title == before`, same as now.

### C — glued `RPF` (extend the existing rule)

**Catalog:** 47 unique glued hits (`RPF` ×46, `rpf` ×1). The only Latin-letter-preceded one is `hetamyuRPF`, which *is* RPF. The feared “names that merely end in those letters” set is **empty**.

Change the needle `" RPF"` → `"RPF"`. Keep case-insensitive, backwards, `upperBound == endIndex`, nonempty tidied stem.

```swift
if !tookRPF,
   let range = title.range(of: "RPF", options: [.caseInsensitive, .backwards]),
   range.upperBound == title.endIndex {
    let head = tidied(String(title[..<range.lowerBound]))
    if !head.isEmpty {
        qualifiers.insert(String(title[range]), at: 0)
        title = head
        tookRPF = true
    }
}
```

`classmates - RPF` still works: peel `RPF`, `tidied` eats the leftover dash. `The Notebook(2004)RPF` becomes title `The Notebook`, qualifier `(2004) RPF` on the next turn. Update the comment that currently forbids the unspaced form — that comment is now false.

### A — Related Fandoms (new named suffix)

**Catalog:** 80 unique. Suffixes: `& Related Fandoms` ×76, `and Related Fandoms` ×3, `& related fandoms` ×1. Fullwidth `＆`: 0. Glued `&related`: 0.

**Must not match:** `Eason-Related Fandoms`, `Chinese Related Fandoms` (no `&` / `and` connector).

**Must keep the series ampersand:** `Spirou & Fantasio & Related Fandoms` → title `Spirou & Fantasio`. End-anchored match does this; do not `replace` globally.

```swift
if !tookRelatedFandoms {
    for needle in [" & Related Fandoms", " and Related Fandoms"] {
        guard let range = title.range(
            of: needle, options: [.caseInsensitive, .backwards]
        ), range.upperBound == title.endIndex else { continue }
        let head = tidied(String(title[..<range.lowerBound]))
        if !head.isEmpty {
            qualifiers.insert(
                String(title[range]).trimmingCharacters(in: .whitespaces), at: 0
            )
            title = head
            tookRelatedFandoms = true
            break
        }
    }
}
```

**Contract change:** `aPlainNameHasNoQualifier` currently lists `Sherlock Holmes & Related Fandoms` as a name that stays whole. That was “no dash / no paren,” not a product decision that the phrase is title. Drop it from that test; add the cases below. Leave `Marvel Cinematic Universe` and `Haikyuu!!`.

### D — localized All Media Types (extend the existing rule)

Replace the single English literal with a small phrase list. Case-insensitive, trailing, nonempty stem, same `"- " + matched` qualifier the English path already synthesizes for `Digimon: All Media Types`.

Measured phrases that actually occur (and nothing else I could find: no JP/KR/FR/DE “all media” hits):

```swift
private static let allMediaTypesPhrases = [
    "All Media Types",
    "所有媒体类型",       // simplified
    "所有媒體類型",       // traditional
    "所有媒體型別",       // traditional, Taiwan wording
    "Todos os Tipos de Mídia",
    "Todos los tipos de medios",
]
```

Do **not** match `多媒体艺术` or `虛擬流媒體` — they are title, not the phrase.

Finding D’s examples were CJK-only; PT/ES are the same finding (5+5 unique names) and belong on this list.

### E — mixed-width brackets (extend the existing rule)

**Catalog:** 16 simple mixed pairs (`(…）` or `（…)`), 21 if both widths appear anywhere.

Today each close only accepts its own open, so `BLEACH(Anime&Manga）` never fires.

Treat `(` / `（` as equivalent opens and `)` / `）` as equivalent closes. Take the **last** open of either width. Keep the empty-head guard: `(movie）` stays whole. `Sunn O)))` still has no open. `Ellie and Abbie (and Ellie's Dead Aunt) (2020)` still peels only `(2020)`.

```swift
if !tookBracket, title.hasSuffix(")") || title.hasSuffix("）") {
    let asciiOpen = title.lastIndex(of: "(")
    let fullOpen = title.lastIndex(of: "（")
    if let open = [asciiOpen, fullOpen].compactMap({ $0 }).max() {
        let head = tidied(String(title[..<open]))
        if !head.isEmpty {
            qualifiers.insert(String(title[open...]), at: 0)
            title = head
            tookBracket = true
        }
    }
}
```

No regex. Do not add `《》`, `【】`, `[]`.

### B — dash-attached `Fandom` the spaced rule misses (new)

**Catalog:** 193 unique with dash immediately before `Fandom` (191 hyphen-minus, 2 em dash), of which 13 are ` -Fandom` (space before dash, none after). Plus 46 `x- Fandom` (dash then space, missing the left space) that finding B did not name but that are the same convention.

Do **not** peel a trailing `Fandom` with no dash (`Pizza Fandom`, `James Marriott fandom`).

No regex; same `range(of:)` style as RPF:

```swift
if !tookFandomTail,
   let range = title.range(of: "Fandom", options: [.caseInsensitive, .backwards]),
   range.upperBound == title.endIndex {
    let before = title[..<range.lowerBound]
        .trimmingCharacters(in: .whitespaces)
    if let last = before.last, "-–—‐".contains(last) {
        let head = tidied(String(before.dropLast()))
        if !head.isEmpty {
            qualifiers.insert("- Fandom", at: 0) // normalize glue, like AMT
            title = head
            tookFandomTail = true
        }
    }
}
```

`Mafia -- Fandom`: `dropLast` + `tidied` → `Mafia`. `The Expanse-Fandom` / `Creepypasta-fandom` / `杀死你的旅程—Fandom` / `Fanfic -Fandom` / `Jinkx Monsoon- Fandom` all peel. `Taylor Swift - Fandom` still goes through the spaced-dash rule first; same visible result.

`Religion & Lore - Ambiguous Fandom` does **not** match (word between dash and `Fandom`); the spaced-dash rule keeps peeling `Ambiguous Fandom` as a creator-style tail, which is the existing dash-residual behavior. Leave it.

---

## 2. Finding J — sibling collisions: do not restyle

**What I would actually do: nothing in this change.** Qualifier stays `.font(.footnote).foregroundStyle(.secondary)` on every row.

This is the one finding that looks like a product bug if you stare at `Les Misérables` ×24. It is also the one that is **not a parse miss**. The qualifier is on the same line and still readable; it is demoted, not removed. Work-count sort already puts the canonical row first.

Measured on this catalog, under the current splitter: Movies has 14,004 rows, **645 colliding stems / 1,446 names** (~10%). TV 372 stems / 826 names. So J is common, not a curiosity. I still would not special-case it here.

Why not collision-detect at render:

- It forces a split of **every** row in the category (up to ~14k), not the ~20 visible ones. That is exactly the work the list was restructured to avoid.
- Row appearance then depends on siblings. Filter to a unique leftover and the qualifier suddenly greys; that looks like a bug.
- “Collision” is undefined until you pick case-folding, `|` aliases, and full-list vs filtered-list. The four agents already disagreed (1,110 / 6,223 / 534).
- Mixed emphasis (some suffixes grey, some primary) is a second visual language on a 14k list. That needs the screenshot gate on purpose, not as a drive-by.

**Identity (the part of J that *is* a bug if we get it wrong):** 534 stems exist both bare and parenthesized. Parsed title is never a key. That is already true in code (`onSelect(fandom.name)`, `id: name`). Pin it with a test that two `Doctor Who (1963)` / `(2005)` splits share a title and with a one-line comment on the row, not a model change.

**If the human tries Les Misérables and hates it**, the next increment is: one O(n) pass in `refresh()` over the category list, a `Set` of colliding display-titles, `qualifierEmphasized: Bool` on the row, and when true skip `.secondary` but **keep footnote**. Compute the set on the **full** category, not the filter. Do not build that now.

---

## 3. Findings F–I — not this change

These are ingest bugs in `AO3Client.parseFandomIndex`, not display. Do not strip them in `split`. A display hack like “cut `Navigation and Actions` off the title” hides a scrape wound in the wrong layer and can theoretically match a real tag.

| # | What the catalog actually contains | Where a fix belongs |
|---|---|---|
| **F** | 21 names with `Navigation and Actions` glued *inside* the `<a class="tag">` text (`…TypesNavigation and Actions`, one `…ActionsWorks`) | `parseFandomIndex` + `AO3ClientTests` fixture. Cut or reject that chrome at ingest. |
| **G** | 2 raw HTML blobs (`</li>…`, Cloudflare `<span class="__cf_email__">`) | Same function: reject names containing `<` or newlines. The linear `</a>` scan overran a broken/unclosed tag. |
| **H** | 9 strings still showing `&lt;` / `&gt;` | Parser already calls `decodingHTMLEntities()` once. Remaining `&lt;3` is likely double-encoding or a literal user tag. Investigate with a live HTML fixture; do not recurse-decode in `split`. |
| **I** | 15 with format chars | **Do not strip `CharacterSet` Cf.** This catalog uses U+200C ZWNJ in Persian/Telugu (`تی‌ام`, `شب‌های`) and U+200D in emoji. Blind strip would corrupt real names. The LRM-only visually blank ` - Fandom` row is a one-off; leave it until ingest sanitizes *leading/trailing bidi isolates only*. |

Follow-up task, different owner, different tests. Mention it in the `TASKS.md` row as out of scope, do not start it.

---

## 4. Where the parsing lives — stay computed per visible row

The 14k-row concern in this file is **filter + List identity diff**, already fixed (pre-normalized `searchEntries`, 120 ms debounce, `filtered` stored in `@State`). `List` is lazy. `split` runs on ~20 on-screen names of ~80 characters, a handful of `range(of:)` calls, two iterations typical.

A–E add a few more end-anchored scans. Same complexity class.

**Do not:**

- Precompute 14k splits into `FandomCatalog.SearchEntry` (~extra strings × 14k, zip hazard with `filtered`)
- Cache on `AO3Fandom` (pollutes the model with display; `name` is identity)
- Collision maps at load
- `AttributedString` cache
- Move the call into `refresh()` “for performance”

`let splitName` in the row’s `init` vs a computed property is a wash: SwiftUI recreates the struct. Leave the computed properties.

**Keep `FandomDisplayName` in `FandomListView.swift`.** It has one consumer. Extracting a file is churn.

**Do not** restyle Global Search (`SearchView` shows `Label(fandom.name)` on ≤12 suggestions). The user is matching against the full tag there. Out of scope.

---

## 5. Tests and definition of done

All new strings are real tags from this index, same style as `FandomDisplayNameTests`.

**C**

- `hetamyuRPF` → `hetamyu` / `RPF`
- `The Notebook(2004)RPF` → `The Notebook` / `(2004) RPF`
- `中国音乐剧演员RPF` → stem / `RPF`
- `真人rpf` → stem / `rpf`
- existing spaced / `(Musician) RPF` / `Political RPF - US 21st c.` still pass

**A** (and rewrite `aPlainNameHasNoQualifier`)

- `Sherlock Holmes & Related Fandoms` → `Sherlock Holmes`
- `Bridgerton (TV) & Related Fandoms` → `Bridgerton` / `(TV) & Related Fandoms`
- `Spirou & Fantasio & Related Fandoms` → `Spirou & Fantasio`
- `The Nutcracker and the Four Realms and Related Fandoms` → `The Nutcracker and the Four Realms`
- `Arsène Lupin & related fandoms` (case)
- negatives: `Eason-Related Fandoms`, `Chinese Related Fandoms` stay whole

**D**

- `刺客信条-所有媒体类型` → `刺客信条`
- `蝙蝠俠-所有媒體型別` and `蝙蝠俠 - 所有媒體類型`
- `X-Men - Todos os Tipos de Mídia`
- `Spider-Man - Todos los tipos de medios`
- negative: `红白站多媒体艺术` stays whole

**E**

- `BLEACH(Anime&Manga）` → `BLEACH` / `(Anime&Manga）`
- `南风知我意(TV）`
- `第三日（原创作品)` (fullwidth open, ASCII close)
- `(movie）` stays whole
- `Sunn O)))` stays whole if we mention it; otherwise the empty-open path is enough
- existing double-paren title test still peels only the last

**B**

- `The Expanse-Fandom`, `Creepypasta-fandom`, `杀死你的旅程—Fandom`
- `Fanfic -Fandom`, `Jinkx Monsoon- Fandom`, `Mafia -- Fandom`
- `Taylor Swift - Fandom` unchanged
- negative: `Pizza Fandom` / `James Marriott fandom` stay whole

**Invariants (already there, keep green)**

- title never emptied
- `《病案本》` / `-BEYOND THE VOID-` / `[]` furigana left alone
- `Doctor Who (1963)` and `Doctor Who (2005)` share a display title — comment that list identity is still the raw name

No catalog.json in the test bundle. No 144k sweep in CI.

### Done means

1. Those tests + the existing suite green.
2. `Scripts/verify.sh` green (invariants, lint, iOS tests, macOS build, whitespace).
3. **Manual, required:** Browse → a large category (Movies or TV). Confirm a Related Fandoms row, a glued `-Fandom`, a CJK/PT AMT row if present in cache, and that tapping still searches the **full** tag (e.g. works query is `Sherlock Holmes & Related Fandoms`, not `Sherlock Holmes`). Glance at `Les Misérables` / `Spider-Man` and accept grey qualifiers (J unchanged).
4. `TASKS.md` row: what was verified, F–I called out as a separate `parseFandomIndex` follow-up, J explicitly deferred.
5. Human screenshot gate before `main`. Do not claim visual correctness from unit tests.

Errors here are cosmetic. If a new rule has any doubt against the catalog, drop that rule rather than add a heuristic.

---

## 6. What I would not do

- **J restyling, second line, or “bold qualifier when ambiguous.”** See §2.
- **F–I in `split`.** Wrong layer; ZWNJ must not be stripped.
- **Dash-residual exception list** (`ef - a fairy tale of the two.`, `Vampire: The Masquerade – Bloodlines`). No general rule exists; do not add a dictionary “just in case.” Add a name if a human reports it.
- **RPS, trailing bare years, `[]` suffixes, `《》` / `【】` / tildes, fullwidth `｜` as alias split, least-CJK `|` segment.** Measured and rejected in the findings. Stay rejected.
- **Loosening the general spaced-dash rule** (optional spaces, unspaced dash before arbitrary tails). That *is* the residual problem. B is allow-listed to the word `Fandom` only.
- **Precomputing splits, moving parse into the catalog, or changing `AO3Fandom`.**
- **SearchView, tag chips, work detail, Android.** One surface: `FandomListRow`.
- **Using parsed title as `id`, zoom key, or search token.**
- **Regex.** The file is `range(of:)` + `hasSuffix` + `lastIndex`. Match that.
- **Bulk reformat, pbxproj edits, new files.** `FandomDisplayName` stays where it is; tests stay in `FandomDisplayNameTests.swift`.

---

## 7. Measure before committing (15-minute catalog pass)

I already ran these; re-run on the then-current cache so comments stay honest:

1. Glued `RPF` case-insensitive unique set — confirm still ~47 and still no Latin false positive besides `hetamyuRPF`.
2. All-media phrase list — confirm no fourth CJK wording and no new PT/ES spelling.
3. `Related Fandoms` without `&`/`and` — still only `Eason-Related Fandoms` and `Chinese Related Fandoms`.

If (1) grows a real false positive, keep C **uppercase-only** for the glued path and leave spaced case-insensitive. I do not expect that.

---

**Bottom line:** extend the existing once-only loop with five high-confidence, catalog-backed peels; leave collision styling and scraper wounds alone; leave the parse on the visible row. Smallest change that actually works.

Continue this thread: grok -c   (in the same directory)
