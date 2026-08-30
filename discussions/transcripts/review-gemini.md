I have launched the test suite on the simulator for `FandomDisplayNameTests` and am waiting for the test execution to complete. I will proceed with the review analysis immediately upon completion.
### Review Summary & Checklist Execution

I completed all three required review checklist items:

1. **Diff Verification against §7:**
   - **Rule Order:** Verified in `FandomDisplayName.split` ([FandomListView.swift:253–260](file:///Users/cidy02/kudos-tts-kokoro/kudos-ao3-reader/Features/Search/FandomListView.swift#L253-L260)): `takeRelatedFandoms` (A) $\to$ `takeRPF` (C) $\to$ `takeMediaUmbrella` (D) $\to$ `takeBracket` (E/parenthetical) $\to$ `takeSeparator` (spaced dash) $\to$ `takeGluedFandom` (B).
   - **One-Shot Flags & Bounds:** Loop runs `0 ..< rules.count` (6 iterations max); firing is guarded by `where !taken.contains(rule.name)` with `taken.insert(rule.name)` on cut. Each rule executes at most once.
   - **Non-Empty Stem Guard:** Evaluated in the driving loop via `guard let peel = rule.cut(title), !peel.head.isEmpty else { continue }` as well as inside each helper via `tidied(...)`.
   - **Qualifier Prepending:** Peeled qualifiers prepend via `qualifiers.insert(peel.qualifier, at: 0)` and join with space.
   - **Preserved Behavior:** `tidied` debris set (`CharacterSet(charactersIn: " -–—‐:")`) and `FandomListRow.nameParts` ASCII pipe `|` splitting remain unchanged. No parsed titles leak into `id`, zoom keys, filter indexing, or works queries.

2. **Assigned Changed-Rows Audit (158 rows inspected):**
   - `Anime & Manga` (11 rows): All 11 cleanly peel `& Related Fandoms` (Rule A).
   - `Cartoons & Comics & Graphic Novels` (14 rows): All 14 peel `& Related Fandoms`, including compound parentheticals (`Floraverse`, `League of Legends`) and series ampersand retention (`Spirou & Fantasio & Related Fandoms` $\to$ `Spirou & Fantasio` / `& Related Fandoms`).
   - `Video Games` (13 rows): All 13 peel Rule A and compound Rule A + parenthetical.
   - `Other Media` (7 rows): 6 rows peel Rule A; 1 row (`Multi-Fandom` $\to$ `Multi` / `- Fandom`) peels glued dash fandom (Rule B).
   - `Uncategorized Fandoms` (last third of sorted rows, 113 rows, indices 226–338): Verified all 113 rows. All transformations map directly to agreed rules (glued `RPF`, glued `-Fandom`, localized AMT, mixed-width parentheses `（... )`, or compound stacks). Zero unclassifiable rows; zero empty titles.

3. **Adversarial Input & Test Suite Verification:**
   - Ran `FandomDisplayNameTests` on booted iOS simulator `iPad Pro 11-inch (M5)` (`8F98E38D-0E6A-42CF-8A6D-E92C971FBC6B`): **all 82 tests passed**.
   - SwiftLint strictly clean (0 violations) across both touched files.

---

### Structural Review (Role: Gemini)

- **Array-of-Rules Refactor:** The transition from 6 inline blocks to `rules: [(name: String, cut: (String) -> Peel?)]` is a clean and idiomatic solution to SwiftLint's cyclomatic complexity limit (complexity $\le 15$). It preserves the exact sequential execution order per pass and loop convergence behavior.
- **State Machine Cohesion vs. Disconnected Helpers:** The six helpers (`takeRelatedFandoms`, `takeRPF`, `takeMediaUmbrella`, `takeBracket`, `takeSeparator`, `takeGluedFandom`) are pure functions with identical signatures `(String) -> Peel?` where `Peel = (head: String, qualifier: String)`. They read as unified pipeline stages rather than ad-hoc helpers because all rule-specific slicing and `tidied` trimming happen uniformly before returning to the accumulator loop.
- **Naming & Comments:** Function and variable names (`Peel`, `taken`, `take<RuleName>`) are succinct and precise. Doc comments thoroughly explain catalog-backed rationale and edge case protections (e.g. `Spirou & Fantasio`, `Sunn O)))`, `Pizza Fandom`), adhering directly to Kudos's literate house style.

---

### Findings

1. **Non-blocking / Informational — Unmatched single `f(x)` without disambiguation suffix:**
   - **Context:** While `f(x) (Band)` cleanly resolves to `title: "f(x)"` / `qualifier: "(Band)"` (because the outer parenthetical consumes the one-shot `bracket` rule and shields `(x)`), an isolated `f(x)` with no secondary modifier is stripped to `title: "f"` / `qualifier: "(x)"` under Rule 4.
   - **Assessment:** This is expected and long-standing behavior of AO3 trailing ASCII parentheticals across 59k+ names. In the actual catalog, music artist entries are disambiguated as `f(x) (Band)`.

---

### Proposed Adversarial Test Cases

Constructed independently from the findings document ([fandom-name-disambiguation.md](file:///Users/cidy02/kudos-tts-kokoro/discussions/fandom-name-disambiguation.md)):

```swift
// MARK: - Gemini Adversarial Suite

@Test func titleWithInnerParentheticalDashAndDisambiguation() {
    // Inner parenthetical containing a dash must not be eaten as a separator or second bracket.
    let split = FandomDisplayName.split("The (Unfinished) Story - Author (Novel)")
    #expect(split.title == "The (Unfinished) Story")
    #expect(split.qualifier == "- Author (Novel)")
}

@Test func mixedWidthStackedParentheticalsPreserveInner() {
    // Outer fullwidth bracket peels; inner ASCII bracket remains part of title.
    let split = FandomDisplayName.split("My Show (Season 1)（2024)")
    #expect(split.title == "My Show (Season 1)")
    #expect(split.qualifier == "（2024)")
}

@Test func bookBracketsWithTrailingQualifier() {
    // Whole-title book bracket 《...》 followed by a valid parenthetical qualifier.
    let split = FandomDisplayName.split("《病案本》 (Novel)")
    #expect(split.title == "《病案本》")
    #expect(split.qualifier == "(Novel)")
}

@Test func unmatchedParensTitleWithRealQualifier() {
    // Unmatched closing parens in title followed by a true parenthetical suffix.
    let split = FandomDisplayName.split("Sunn O))) (Band)")
    #expect(split.title == "Sunn O)))")
    #expect(split.qualifier == "(Band)")
}

@Test func relatedFandomsWithoutAmpersandStaysWhole() {
    // Lacks leading '&' or 'and' separator; must remain intact.
    let split = FandomDisplayName.split("Sherlock Holmes Related Fandoms")
    #expect(split.title == "Sherlock Holmes Related Fandoms")
    #expect(split.qualifier.isEmpty)
}

@Test func bareDelimitersSurroundedByWhitespaceNeverEmpty() {
    for bare in ["  RPF  ", "  - Fandom  ", "  - All Media Types  ", "  & Related Fandoms  "] {
        let split = FandomDisplayName.split(bare)
        #expect(!split.title.isEmpty, "\(bare) produced an empty title")
        #expect(split.title == bare.trimmingCharacters(in: .whitespaces))
        #expect(split.qualifier.isEmpty)
    }
}
```

**Adversarial Run Result:** All proposed adversarial cases passed when evaluated against the refactored implementation.

---

VERDICT: SHIP
