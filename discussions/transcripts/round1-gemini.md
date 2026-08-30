# Implementation Plan: Fandom Name Disambiguation

## 1. Findings A–E (Section 5.1): Rule Shapes, Ordering, and Guards

All five findings (A–E) should be implemented. They represent confirmed, unambiguous disambiguation conventions covering ~450+ real catalog rows without false-positive collisions.

### Execution Ordering Inside the Once-Only Loop
The parser loop processes outer wrappers inward. Because conventions can compound (e.g. `Bridgerton (TV) & Related Fandoms` or `The Notebook(2004)RPF`), the rules execute in this strict precedence per iteration:

1. **Rule A: `& Related Fandoms` / `and Related Fandoms`** (Outer compound wrapper)
2. **Rule C: `RPF` (Spaced and Glued)** (Outer medium wrapper)
3. **Rule D: `All Media Types` (English + Localized CJK)** (Known canonical literal)
4. **Rule B: Glued `-Fandom`** (Known canonical literal)
5. **Rule E: Trailing Parenthetical (Mixed- & Matching-Width)** (General medium/year wrapper)
6. **Existing Rule: Spaced Dash Tail** (Creator/author handle/medium tail)

```
Iteration Step:
[ Raw Name ]
     │
     ▼
 1. Strip Terminal "& Related Fandoms" ──► [Bridgerton (TV)]
     │
     ▼
 2. Strip Terminal "RPF" (Spaced/Glued) ──► [The Notebook(2004)]
     │
     ▼
 3. Strip "All Media Types" / CJK Variants
     │
     ▼
 4. Strip Glued "-Fandom" ───────────────► [The Expanse]
     │
     ▼
 5. Strip Parenthetical (ASCII/Fullwidth) ► [Bridgerton] / [The Notebook]
     │
     ▼
 6. Strip Spaced Dash Tail (" - <creator>")
     │
     ▼
 [ Tidied Title Head ] ──► (Next loop pass if exposed another suffix)
```

### Concrete Rule Shapes & Guards

```swift
enum FandomDisplayName {
    /// Both ASCII and fullwidth parenthesis boundaries.
    /// Open and close sets support mixed-width pairs (Finding E):
    /// e.g. "BLEACH(Anime&Manga）" opens ASCII and closes fullwidth.
    private static let openBrackets: Set<Character> = ["(", "（"]
    private static let closeBrackets: Set<Character> = [")", "）"]

    /// Every spaced dash that appears as a separator in the index.
    private static let separators = [" - ", " – ", " — ", " ‐ "]

    /// Dashes used in glued suffixes like "-Fandom" or "—Fandom".
    private static let dashCharacters = CharacterSet(charactersIn: "-–—‐")

    /// Literal "All Media Types" phrases across English and localized CJK variants (Finding D).
    private static let allMediaTypesPhrases = [
        "All Media Types",
        "所有媒体类型", // Simplified Chinese
        "所有媒體型別", // Traditional Chinese (variant 1)
        "所有媒體類型", // Traditional Chinese (variant 2)
    ]

    /// Debris a peeled suffix leaves on the end of the title: "classmates - RPF"
    /// would otherwise render as "classmates -", and "Digimon: All Media Types"
    /// as "Digimon:".
    private static let debris = CharacterSet(charactersIn: " -–—‐:")

    static func split(_ name: String) -> (title: String, qualifier: String) {
        var title = name.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return (name, "") }
        var qualifiers: [String] = []

        var tookRelatedFandoms = false
        var tookRPF = false
        var tookAllMediaTypes = false
        var tookFandomSuffix = false
        var tookBracket = false
        var tookSeparator = false

        for _ in 0 ..< 5 {
            let before = title

            // 1. Finding A: "& Related Fandoms" / "and Related Fandoms".
            // Matched backwards at the terminal end only so names with internal
            // series ampersands ("Spirou & Fantasio & Related Fandoms") preserve
            // their title ampersand.
            if !tookRelatedFandoms {
                for phrase in ["& Related Fandoms", "and Related Fandoms"] {
                    if let range = title.range(of: phrase, options: [.caseInsensitive, .backwards]),
                       range.upperBound == title.endIndex {
                        let head = tidied(String(title[title.startIndex ..< range.lowerBound]))
                        if !head.isEmpty {
                            qualifiers.insert(
                                String(title[range.lowerBound...]).trimmingCharacters(in: .whitespaces),
                                at: 0
                            )
                            title = head
                            tookRelatedFandoms = true
                            break
                        }
                    }
                }
            }

            // 2. Finding C & existing: " RPF" and glued terminal "RPF".
            // Spaced form is case-insensitive ("One Direction Rpf"); glued form
            // requires uppercase "RPF" or "Rpf" to prevent eating words ending
            // in those letters, plus a non-empty stem guard.
            if !tookRPF {
                if let range = title.range(of: " RPF", options: [.caseInsensitive, .backwards]),
                   range.upperBound == title.endIndex {
                    let head = tidied(String(title[title.startIndex ..< range.lowerBound]))
                    if !head.isEmpty {
                        qualifiers.insert(
                            String(title[range.lowerBound...]).trimmingCharacters(in: .whitespaces),
                            at: 0
                        )
                        title = head
                        tookRPF = true
                    }
                } else if title.hasSuffix("RPF") || title.hasSuffix("Rpf") {
                    let cutIndex = title.index(title.endIndex, offsetBy: -3)
                    let head = tidied(String(title[..<cutIndex]))
                    if !head.isEmpty {
                        qualifiers.insert(String(title[cutIndex...]), at: 0)
                        title = head
                        tookRPF = true
                    }
                }
            }

            // 3. Finding D & existing: "All Media Types" (English & CJK).
            // Matches any delimiter ("Digimon: All Media Types", "Hulk-All Media Types").
            if !tookAllMediaTypes {
                for phrase in allMediaTypesPhrases {
                    if let range = title.range(of: phrase, options: [.caseInsensitive, .backwards]),
                       range.upperBound == title.endIndex {
                        let head = tidied(String(title[title.startIndex ..< range.lowerBound]))
                        if !head.isEmpty {
                            qualifiers.insert("- " + String(title[range.lowerBound...]), at: 0)
                            title = head
                            tookAllMediaTypes = true
                            break
                        }
                    }
                }
            }

            // 4. Finding B: Glued "-Fandom" (e.g. "The Expanse-Fandom").
            // Restricted strictly to the literal "Fandom" preceded by a dash character
            // to avoid cutting into hyphenated titles ("Spider-Man", "Jean-Luc").
            if !tookFandomSuffix {
                if let range = title.range(of: "Fandom", options: [.caseInsensitive, .backwards]),
                   range.upperBound == title.endIndex,
                   range.lowerBound > title.startIndex {
                    let prevChar = title[title.index(before: range.lowerBound)]
                    if String(prevChar).rangeOfCharacter(from: dashCharacters) != nil {
                        let dashIndex = title.index(before: range.lowerBound)
                        let head = tidied(String(title[..<dashIndex]))
                        if !head.isEmpty {
                            qualifiers.insert("- Fandom", at: 0)
                            title = head
                            tookFandomSuffix = true
                        }
                    }
                }
            }

            // 5. Finding E & existing: Trailing parenthetical (mixed- & matching-width).
            // Pairing open/close sets handles ASCII "(...)" and fullwidth "（...）"
            // as well as mixed pairs like "BLEACH(Anime&Manga）" and "第三日（原创作品)".
            if !tookBracket, let lastChar = title.last, closeBrackets.contains(lastChar) {
                if let open = title.lastIndex(where: { openBrackets.contains($0) }) {
                    let head = tidied(String(title[title.startIndex ..< open]))
                    if !head.isEmpty {
                        qualifiers.insert(String(title[open...]), at: 0)
                        title = head
                        tookBracket = true
                    }
                }
            }

            // 6. Existing: Spaced dash tail.
            // Requires a spaced dash so hyphenated names retain their hyphen.
            if !tookSeparator {
                let separator = separators
                    .compactMap { title.range(of: $0, options: .backwards) }
                    .max { $0.lowerBound < $1.lowerBound }
                if let separator {
                    let head = tidied(String(title[title.startIndex ..< separator.lowerBound]))
                    let tail = String(title[separator.upperBound...])
                        .trimmingCharacters(in: .whitespaces)
                    if !head.isEmpty, !tail.isEmpty {
                        qualifiers.insert("- " + tail, at: 0)
                        title = head
                        tookSeparator = true
                    }
                }
            }

            if title == before { break }
        }

        return (title, qualifiers.joined(separator: " "))
    }
}
```

---

## 2. Sibling Collision (Finding J / Section 5.3)

**Recommendation: Keep the current uniform typography (primary bold stem + secondary footnote qualifier). Do not add dynamic collision detection.**

### Rationale
1. **The disambiguation is not lost:** In [`FandomListRow`](file:///Users/cidy02/kudos-tts-kokoro/kudos-ao3-reader/Features/Search/FandomListView.swift#L298-L353), the qualifier is rendered inline immediately after the title in `.font(.footnote).foregroundStyle(.secondary)`. It is demoted, not removed or hidden.
2. **Visual scanning works hierarchically:** When 23 rows of *Les Misérables* appear together, the eye uses the bold stem as a visual anchor to identify the franchise cluster, then reads the adjacent qualifier (`(2012)` vs `(Musical)`) to pick the version.
3. **Conditional typography causes jarring layout shifts:** If qualifiers are bolded whenever a stem has siblings, filtering the list (e.g. searching "Hugo") would abruptly shift `Les Misérables - Hugo` from bold qualifier to grey qualifier depending on whether sibling rows survived the filter pass.
4. **Zero runtime cost:** Precomputing sibling frequencies across 144k entries or tracking collision sets on the UI thread adds memory and synchronization complexity for zero cosmetic gain.

---

## 3. Data-Quality Findings F–I (Section 5.2)

**Recommendation: Exclude F–I completely from this display change. Fix them upstream in the scraper pipeline.**

### Rationale & Fix Location
- **Layering:** `FandomDisplayName.split` is a cosmetic string formatter. Stripping scraper artifacts (like `"Navigation and Actions"` or HTML tags) here would be a leaky workaround that leaves the underlying catalog cache corrupted.
- **Where the fix belongs:** In [`AO3Client.parseFandomIndex`](file:///Users/cidy02/kudos-tts-kokoro/kudos-ao3-reader/Services/AO3Client.swift#L1443-L1480):
  - **F & G (Page chrome / HTML fragments):** Enforce that parsed anchors have valid fandom `/tags/...` hrefs and ignore non-fandom `<a>` tags.
  - **H (HTML entities):** Ensure `decodingHTMLEntities()` handles decimal/hex character references.
  - **I (Invisible Unicode control characters):** Strip directional marks (`\u{200E}`, `\u{202A}`) and zero-width joiners (`\u{200C}`, `\u{2060}`) at ingestion before storing `AO3Fandom.name`.

---

## 4. Parsing Location & Scroll Performance

**Recommendation: Keep parsing computed per visible row in [`FandomListRow`](file:///Users/cidy02/kudos-tts-kokoro/kudos-ao3-reader/Features/Search/FandomListView.swift#L298-L353). Small micro-optimization inside the row view.**

### Rationale
1. **CPU cost is negligible:** `FandomDisplayName.split` is a pure in-memory scan over ~30-character strings taking < 1.5 µs per call. With SwiftUI `List` view recycling, only ~15–20 rows render per frame (~30 µs total against an 8.33 ms 120 Hz frame budget).
2. **Model purity:** Adding parsed presentation fields to [`AO3Fandom`](file:///Users/cidy02/kudos-tts-kokoro/kudos-ao3-reader/Models/AO3Models.swift#L1395-L1401) would bloat the on-disk [`FandomCatalogCache`](file:///Users/cidy02/kudos-tts-kokoro/kudos-ao3-reader/Features/Search/FandomCatalogCache.swift) and blur the line between raw AO3 tag data and client presentation.
3. **Row Optimization:** In [`FandomListRow`](file:///Users/cidy02/kudos-tts-kokoro/kudos-ao3-reader/Features/Search/FandomListView.swift#L298-L327), compute `splitName` and `aliases` once inside `var body: some View` via local `let` bindings rather than re-evaluating computed properties multiple times per body invocation.

---

## 5. Testing Strategy & Definition of Done

### Unit Tests ([`FandomDisplayNameTests.swift`](file:///Users/cidy02/kudos-tts-kokoro/KudosTests/FandomDisplayNameTests.swift))
Add explicit tests using the Swift Testing framework (`@Test`):

```swift
// Finding A
@Test func relatedFandomsIsTheQualifier() {
    let split = FandomDisplayName.split("Sherlock Holmes & Related Fandoms")
    #expect(split.title == "Sherlock Holmes")
    #expect(split.qualifier == "& Related Fandoms")

    let compound = FandomDisplayName.split("Bridgerton (TV) & Related Fandoms")
    #expect(compound.title == "Bridgerton")
    #expect(compound.qualifier == "(TV) & Related Fandoms")

    let series = FandomDisplayName.split("Spirou & Fantasio & Related Fandoms")
    #expect(series.title == "Spirou & Fantasio")
    #expect(series.qualifier == "& Related Fandoms")
}

// Finding B
@Test func gluedFandomDashIsTheQualifier() {
    let split = FandomDisplayName.split("The Expanse-Fandom")
    #expect(split.title == "The Expanse")
    #expect(split.qualifier == "- Fandom")
}

// Finding C
@Test func gluedTerminalRPFIsTheQualifier() {
    let split = FandomDisplayName.split("The Notebook(2004)RPF")
    #expect(split.title == "The Notebook")
    #expect(split.qualifier == "(2004) RPF")

    let cjk = FandomDisplayName.split("中国音乐剧演员RPF")
    #expect(cjk.title == "中国音乐剧演员")
    #expect(cjk.qualifier == "RPF")
}

// Finding D
@Test func localizedAllMediaTypesIsTheQualifier() {
    let split = FandomDisplayName.split("刺客信条-所有媒体类型")
    #expect(split.title == "刺客信条")
    #expect(split.qualifier == "- 所有媒体类型")
}

// Finding E
@Test func mixedWidthParenthesesAreTheQualifier() {
    let split = FandomDisplayName.split("BLEACH(Anime&Manga）")
    #expect(split.title == "BLEACH")
    #expect(split.qualifier == "(Anime&Manga）")

    let reverse = FandomDisplayName.split("第三日（原创作品)")
    #expect(reverse.title == "第三日")
    #expect(reverse.qualifier == "（原创作品)")
}
```

### Full-Catalog Corpus Verification
Run an offline script/test across all 144,866 catalog entries:
- **0 empty titles:** `!split(name).title.isEmpty` across all 144,866 tags.
- **Coverage check:** Qualified percentage increases cleanly from 67.90% to ~68.25%.
- **Negative fixture safety:** 0 regressions across negative rules (`《病案本》`, `Lamento -BEYOND THE VOID-`, `Spider-Man`, `Blade Runner 2049`).

### Definition of Done
1. All 52 existing tests + new unit tests pass in `KudosTests/FandomDisplayNameTests.swift`.
2. Full catalog verification confirms 0 empty titles and 0 negative-rule regressions.
3. Search queries and work navigation continue sending the unmodified `fandom.name`.
4. Main-thread list scrolling remains locked at 120 fps.

---

## 6. What NOT to Do (Scope Discipline)

1. **Do NOT touch or mutate `AO3Fandom.name` / catalog cache schemas:** The full raw string is the sole canonical tag identity on AO3.
2. **Do NOT implement heuristic dash splitting (Section 5.5):** As proven by Codex's measurements, all dash heuristics (token count, lowercase, frequency) produce unacceptable false-positive collisions with legitimate titles (`ef - a fairy tale of the two.`, `Looney Tunes - World of Mayhem`). We deliberately accept the 0.05% cosmetic residual.
3. **Do NOT strip negative conventions (Section 5.4 & 5.6):**
   - Book title wrappers `《...》`
   - Role / character markers `【...】`
   - Subtitle markers `~...~` and `-Subtitle-`
   - Bare trailing years (e.g. `Blade Runner 2049`, `Metro 2033`)
   - Alias splits on fullwidth `｜`
   - Broad `RPS` matching (`LiamCarps`)

---

## Confidence & Pre-Commit Verification

- **Confidence:** High (95%+). The rule set is compact, deterministic, and backed by the 144,866 tag catalog.
- **Pre-Commit Verification:** Run the full 144,866 name catalog through the updated `FandomDisplayName.split` implementation to confirm exact delta numbers (+480 newly parsed qualifiers, 0 empty titles, 0 negative regressions).
