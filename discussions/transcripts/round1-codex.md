I would ship all A–E, add a stable sibling-collision treatment, and keep F–I out of this cosmetic change. The raw `AO3Fandom.name` remains the only identity and query value.

## Parser rules

Keep the bounded, once-only loop in [`FandomListView.swift`](/Users/cidy02/kudos-tts-kokoro/kudos-ao3-reader/Features/Search/FandomListView.swift:158), but expand it from four to six distinct rule families. Each flag is set only after a non-empty head was successfully peeled; rules remain separate `if`s so newly exposed suffixes can be handled in the same pass.

```swift
for _ in 0 ..< 6 {
    let before = title

    takeRPF()                 // existing + glued fallback
    takeAllMediaTypes()       // English + two observed Chinese forms
    takeRelatedFandoms()      // new
    takeTrailingBracket()     // existing + mixed-width pairs
    takeSpacedDashTail()      // existing
    takeGluedFandom()         // new, deliberately after spaced dash

    if title == before { break }
}
```

1. C — RPF first. Retain the current terminal `" RPF"` match, then fall back to terminal `"RPF"` case-insensitively. In both cases, require `tidied(head)` to be non-empty; `"RPF"` alone stays whole. Use the existing `tookRPF` flag and render the qualifier as `RPF`.

2. D — All Media Types next. Expand the current literal list to exactly:

   ```swift
   ["All Media Types", "所有媒体类型", "所有媒體型別"]
   ```

   Match only a terminal occurrence, retain `tookAllMediaTypes`, require a non-empty tidied head, and display `"- " + observedSuffix`. Do not add speculative translations.

3. A — Related Fandoms next. Match only terminal, case-insensitive forms with their leading separator:

   ```swift
   [" & Related Fandoms", " and Related Fandoms"]
   ```

   Use a backwards terminal range so `Spirou & Fantasio & Related Fandoms` keeps `Spirou & Fantasio`. The leading space excludes `Chinese Related Fandoms` and `Eason-Related Fandoms`. Add `tookRelatedFandoms`; retain the observed qualifier (`& Related Fandoms` or `and Related Fandoms`).

4. E — Brackets next. Extend the existing pairs to:

   ```swift
   [("(", ")"), ("（", "）"), ("(", "）"), ("（", ")")]
   ```

   Keep the existing “last matching opener, non-empty head, once only” behavior. This handles `BLEACH(Anime&Manga）` without broadening into square/CJK book brackets.

5. Existing spaced dashes unchanged.

6. B — Glued `-Fandom` last. Match only a terminal, case-insensitive `Fandom` immediately preceded by the two observed glued separators: `-` or `—`. Require a non-empty tidied head and use a new `tookGluedFandom` flag. Display it as `- Fandom` while preserving the source’s `Fandom` casing if desired.

Putting B after the generic spaced-dash rule intentionally preserves existing behavior for something like `Title - Creator-Fandom`; the new rule fixes only otherwise-missed glued suffixes.

All peeled qualifiers continue to insert at index zero, preserving their source order when suffixes stack.

## J — sibling collisions

I would detect ambiguity once per loaded category and render a qualifier at full body/primary strength when it is needed to distinguish siblings.

Create a small internal, `Sendable` presentation value—say `FandomListEntry`—that holds:

```swift
let fandom: AO3Fandom          // canonical raw name remains here
let normalizedName: String     // from full raw fandom.name
let title: String
let qualifier: String
let aliasText: String?
let qualifierIsRequired: Bool
var id: String { fandom.name } // never title
```

After parsing every entry in the category, count exact parsed titles in that category. Set `qualifierIsRequired` only when `qualifier` is non-empty and that title occurs more than once. Do this before filtering, so styles do not flicker while typing, and do not scan the global catalog.

For ordinary rows, retain `.footnote` + `.secondary`. For an ambiguous stem, use `.body` + `.primary` for the qualifier too. That makes `Doctor Who (1963)` / `(2005)` and the many `Les Misérables` rows scan as distinct full names, while unique rows keep the intended hierarchy.

The parsed title is only a temporary grouping key for styling. It is never used as `List` identity, a dictionary identity beyond that local count, or a search/query value.

## Placement and performance

Move invocation of the parser out of `FandomListRow.body`. The row should receive `FandomListEntry` and contain no computed splitting, alias extraction, or joining.

Build entries once after the raw list is fetched and sorted, off the main actor using the project’s existing detached-computation pattern. Make this pure builder and `FandomDisplayName.split` nonisolated as needed. `AO3Fandom` is already `Sendable`.

Filtering remains a scan over precomputed `normalizedName`, preserving the current full-raw-name search behavior. Buttons and zoom keys continue to use `entry.fandom.name`.

Do not put display fields on `AO3Fandom`, persist them in `FandomCatalogCache`, add a view model, or change the cache schema. They are screen-local presentation data.

## F–I: separate ingestion work

Do not fix F–I here and do not hide/repair them in `FandomDisplayName`.

They belong in `AO3Client.parseFandomIndex(_:)` in [`AO3Client.swift`](/Users/cidy02/kudos-tts-kokoro/kudos-ao3-reader/Services/AO3Client.swift:1428), with fixtures in [`AO3ClientTests.swift`](/Users/cidy02/kudos-tts-kokoro/KudosTests/AO3ClientTests.swift:427).

That separate task should:

- constrain the linear scanner to real fandom-link/list-item structure for F/G;
- verify the browser-rendered entity result for H rather than blindly repeatedly decoding;
- handle I conservatively—especially not globally deleting ZWNJ, which can be meaningful text;
- invalidate/version the cached fandom catalog so old malformed names do not linger.

No extra AO3 requests are needed for this display feature.

## Tests and definition of done

Extend [`FandomDisplayNameTests.swift`](/Users/cidy02/kudos-tts-kokoro/KudosTests/FandomDisplayNameTests.swift:1) with real examples for all five findings:

- A: positive, lowercase, last-occurrence, and `Chinese/Eason Related Fandoms` negatives.
- B: ASCII and em-dash glued forms.
- C: glued RPF, compound `(2004)RPF`, and bare `RPF`.
- D: Simplified and Traditional Chinese forms.
- E: both mixed-width bracket directions.
- Stacking regressions: `Bridgerton (TV) & Related Fandoms` and existing compound suffix cases.

Add pure entry-builder tests proving that:

- `Doctor Who`, `Doctor Who (1963)`, and `Doctor Who (2005)` promote only the qualified siblings;
- a unique qualified fandom remains secondary;
- entry IDs and tap/query payloads remain the full raw names;
- filtering still normalizes the full raw name.

Before committing, run the proposed parser over the supplied catalog: zero empty titles, inspect every newly matched pattern, and record affected-row counts. Benchmark preparation and scroll behavior against the 68,271-row Uncategorized category; no per-row parsing should remain. Then complete `Scripts/verify.sh` and the required iOS/macOS visual screenshot gate, including a filtered collision group and a normal unique row.

## Explicit non-goals

- No general dash heuristic, proactive exception list, or title-correction registry.
- No `RPS`, bare-year, square-bracket, tilde, `《》`, or fullwidth-pipe parsing.
- No global collision map or post-filter collision recalculation.
- No scraper cleanup, cache migration, model change, or query behavior change in this feature.

Confidence: high for A/C/D/E and the precomputed local collision rule; medium-high for B only because it is intentionally limited to observed separators. The only measurements I would require before landing are the proposed-parser corpus audit, largest-category preparation/scroll cost, and visual density screenshots.
