### Positions on Live Disagreements

#### (1) Finding J: Sibling Collisions
**Position: DO NOT IMPLEMENT NOW (Concur with Claude, Gemini, Grok; Codex should concede)**
* **Typography & Hierarchy:** The qualifier is not hidden—it is rendered inline in `.font(.footnote).foregroundStyle(.secondary)` immediately after the bold title. In clusters like *Les Misérables* (23 rows) or *Doctor Who* (4 rows), the bold title acts as a franchise visual anchor while the adjacent secondary qualifier (`(1963)` vs `(2005)`) differentiates the row.
* **Visual Inconsistency:** Even with Codex’s pre-filter category count avoiding typing flicker, promoting ~10% of rows to `.body .primary` introduces a mixed two-tier visual language across long lists.
* **Recommendation:** Keep uniform typography. If design review finds grey qualifiers insufficient, adjust global qualifier contrast or line styling holistically rather than creating dynamic ambiguity flags.

#### (2) Where the Parsing Lives
**Position: KEEP COMPUTED PER VISIBLE ROW (Concur with Claude, Gemini, Grok; Codex should concede)**
* SwiftUI `List` is lazy and view-recycled; only ~15–20 rows are rendered at a time.
* `FandomDisplayName.split` executes in < 1.5 µs per call (< 30 µs per frame vs. the 8.33 ms 120 Hz budget).
* Without Finding J, the sole motivation for `FandomListEntry` disappears. Precomputing 14,000–68,000 wrapper models during category load introduces unnecessary allocations and background-thread coordination for zero perceptible frame-rate benefit.

#### (3) Finding D: Localized "All Media Types"
**Position: INCLUDE (Claude should concede to Gemini, Grok, Codex)**
* Grok verified 20 unique catalog entries across CJK (`所有媒体类型`, `所有媒體類型`, `所有媒體型別`), Portuguese (`Todos os Tipos de Mídia`), and Spanish (`Todos los tipos de medios`).
* It has 0 false positives, fits into the existing literal array, and avoids leaving non-English tags with dangling trailing delimiters (e.g. `刺客信条-所有媒体类型`).

---

### Changes of Mind Since Round 1
* **Glued RPF Case-Sensitivity (Gemini R1 concession):** In Round 1, Gemini guarded glued RPF with uppercase-only matching. Grok's full catalog audit proved that case-insensitive terminal `RPF` has **0 false positives** in 144,866 rows while correctly handling lowercase tags like `真人rpf`. We adopt full case-insensitivity for glued RPF.
* **Expanded Localized AMT (Gemini/Codex R1 update):** Adopting Grok's measured inclusion of Portuguese and Spanish strings alongside CJK in the literal array for Finding D.

---

### Fact Checks & Technical Observations
1. **Claude (Finding D):** Claude’s assumption that Finding D is "~15 rows of rotting CJK phrase maps" missed that Portuguese and Spanish use the identical canonical phrase structure, accounting for 20 unique tags with zero false positives.
2. **Codex (Finding J):** Codex’s assertion that disambiguation is "lost" conflates demoted typography with missing data. The qualifier is visible on the same line and wraps cleanly.
3. **Gemini R1 (Finding C):** Restricting glued RPF to uppercase was unnecessary; case-insensitive backwards matching is 100% safe across the catalog.

---

### Single Combined Implementation Plan

#### 1. Scope & Invariants
* **In-Scope:** Findings A, B, C, D, E in `FandomDisplayName.split` in [`FandomListView.swift`](file:///Users/cidy02/kudos-tts-kokoro/kudos-ao3-reader/Features/Search/FandomListView.swift#L178-L296) + unit tests in [`FandomDisplayNameTests.swift`](file:///Users/cidy02/kudos-tts-kokoro/KudosTests/FandomDisplayNameTests.swift).
* **Out-of-Scope:** Findings F–I (upstream scraper fixes in `AO3Client.parseFandomIndex`), Finding J (sibling collision styling), dash-residual exception lists, and non-parenthesis bracket rules (`《》`, `【】`, `[]`).
* **Canonical Identity:** `AO3Fandom.name` remains untouched as the single source of truth for identity, filter matching, and work search queries.

#### 2. Parser Execution Loop Order
Run up to 5 iterations (breaking when `title == before`), with 6 once-only rule families:

```swift
for _ in 0 ..< 5 {
    let before = title

    // 1. Finding C: Terminal RPF (Spaced & Glued, case-insensitive, non-empty stem)
    // 2. Finding A: Terminal "& Related Fandoms" / "and Related Fandoms" (Backwards last-occurrence)
    // 3. Finding D: Terminal "All Media Types" (English, CJK, PT, ES literals)
    // 4. Finding E: Trailing Parentheses (Mixed- & matching-width: ")" or "）" paired with nearest "(" or "（")
    // 5. Existing: Trailing Spaced Dash (" - ", " – ", " — ", " ‐ ")
    // 6. Finding B: Trailing Glued "-Fandom" (Terminal "Fandom" preceded by "-–—‐", normalized to "- Fandom")

    if title == before { break }
}
```

#### 3. Verification & Definition of Done
1. All existing + new unit tests pass in `KudosTests/FandomDisplayNameTests.swift`.
2. Full catalog run (144,866 entries) confirms 0 empty titles and expected +480 qualifier deltas.
3. `Scripts/verify.sh` passes cleanly (tests, linter, formatting).
4. Manual simulator check in Browse → Movies/TV confirms proper rendering and query routing.

---

CONSENSUS: yes
