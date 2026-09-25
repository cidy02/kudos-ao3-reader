# Brief — search-filters (wave 3, cloud)

Source: `search-filters.json` with `critic-wave3.json`'s corrections already
applied. 1au.2 was rewritten there, because its first form contradicted a
pinned test. Facts: `otwarchive-facts-wave3.json` Q11 and Q22. Base `c4ce1e2`.
Paths are under `kudos-ao3-reader/` unless they start with `KudosTests/` or
`docs/`.

Seven items: three bugs, then four small gaps.

**Keep out of:** `Services/AO3Client.swift` (the query builder lives there;
nothing here needs it), `AO3RequestCoordinator.swift`, `RequestCoalescer`, and
`project.pbxproj`. **Do not change `AO3SummaryFilter.ratingMatches`**: its
Rating-Any rule is pinned by
`KudosTests/AO3SummaryFilterRatingTests.swift:69-76`.

---

## Bugs

### S1 — Refine shows an inert "Include Not Rated" when Rating is Any (1au.2)

- **Files:** `Features/Search/AO3FilterPanel.swift:190`.
- **Wrong today:** in `.refine` with Rating on Any, the toggle looks live, but
  flipping it changes nothing. The "N of M on this page match" line does not
  move, because Refine ignores the toggle until a rating is chosen (a pinned
  decision).
- **Change:** `static func showsIncludeNotRated(mode: Mode, rating:
  AO3SearchFilters.Rating) -> Bool` returns `mode == .search || rating != .any`,
  and wraps the `Toggle`. Search keeps the toggle, because there it does filter
  (`-rating_ids:9`).
- **Test:** `(.refine, .any) == false`; `(.refine, .teen) == true`;
  `(.search, .any) == true`.

### S2 — The Completion footer states a false reason (1aq.4)

- **Files:** `Features/Search/AO3FilterPanel.swift:230-237`.
- **Wrong today:** "Crossover status and completion are not carried on a search
  result". Completion is on every blurb, and Refine narrows by it
  (`Features/Search/AO3SummaryFilter.swift:101-107`).
- **Change:** "Crossover status is not carried on a search result, so it needs
  AO3 to answer the query."
- **Test:** none needed (copy). Grep that no string says completion is missing
  from a result.

### S3 — Try Again after a failed page jumps to page 1 (1k.7)

- **Files:** `Features/Search/SearchView.swift:588-602` (overlay),
  `:678-690` (`runSearch`), `:801-846` (`load(page:)`).
- **Wrong today:** on page 4, tapping page 5 fails. The overlay's Try Again
  calls `runSearch()`, which resets to page 1.
- **Change:** `@State private var requestedPage: Int?`. Set it in `load(page:)`
  and clear it on success. Try Again calls a pure
  `SearchRetry.page(requested: requestedPage, current: currentPage, hasResults:
  !results.isEmpty) -> Int?`. When that returns a page, call `load(page:)`;
  when it returns nil, call `runSearch()` (a first-load failure).
- **Test:** `page(requested: 5, current: 4, hasResults: true) == 5`;
  `page(requested: nil, current: 4, hasResults: true) == 4`;
  `page(requested: 5, current: 1, hasResults: false) == nil`.

## Small gaps (no owner decision)

### S4 — The Filter button carries no count (1k.4)

- **Files:** `Features/Search/SearchView.swift:172-174`.
- **Spec:** 1k: "an accent filter button with its count".
- **Change:** pass `badgeCount: filters.summaryLabels(excluding:
  filters.searchSubject.text, includesSort: false).count`. That is the same
  number as the hero's "Filters" cell, which excludes the subject and the sort
  (`Features/Search/SearchResultsHero.swift:115-117`, `:163-170`).
- **Test:** a pure helper that both call sites use, so the badge and the cell
  cannot disagree: `SearchFilterBadge.count(for: filters)` equals
  `nonSortFilterLabels.count` for a subject-plus-two-facets fixture.

### S5 — The filter panel opens full height on iPhone (1ao.1)

- **Files:** `UIComponents/FilterPanelPresentation.swift:29-57`, and the call
  sites in `Features/Search/SearchView.swift:193` and
  `Features/Browse/NativeBrowseView.swift:202`, `:497`.
- **Spec:** 1ao: "Medium detent. The panel opens over the results at half
  height".
- **Change:** add a `detents: Set<PresentationDetent>? = nil` parameter to
  `filterPanelPresentation`. The phone sheet applies `.presentationDetents(...)`
  only when it is non-nil. Pass `[.medium, .large]` from the three AO3
  filter-panel call sites above. The fandom-list filter sheet (1an) keeps
  today's full height.
- **Test:** none (presentation). Needs a screenshot at the Mac.

### S6 — No footer explains that the date filters combine (1aq.3)

- **Files:** `Features/Search/AO3FilterPanel.swift:240-258`.
- **Spec:** 1aq: "the footer says so instead of leaving a reader to wonder why
  a valid-looking pair returns nothing". The code comment at :246-249 claims
  a footer that does not exist.
- **Fact:** Q11. Both are `revised_at` ranges, ANDed (`work_query.rb:107-116`,
  `:220-230`).
- **Change:** in search mode, give that section a footer: "Updated and the
  After / Before dates all apply to the same date, and a work has to pass every
  one."
- **Test:** none (copy).

### S7 — Save Search seeds its name from the query, not the subject (1ax.2)

- **Files:** `Features/Search/SearchView.swift:751-763`.
- **Spec:** 1ax: "The name is seeded from the search subject, which is the
  fandom when exactly one tag field holds exactly one name." The sheet's own
  caption promises "Named from what the search is of".
- **Change:** `defaultSavedSearchName` returns `filters.searchSubject.text`,
  mapping `AO3SearchFilters.searchResultsFallback` to "Saved Search". Move it to
  a static `func defaultSavedSearchName(for: AO3SearchFilters) -> String` so it
  can be tested.
- **Test:** fandom "A, B" plus characters "C" gives the query (or "Saved
  Search"), not "A". Characters "C" alone gives "C".

---

## Needs the owner

- **1au.4 — Search and Refine disagree on Include Not Rated under Rating Any.**
  Search excludes Not Rated works (`Models/AO3Models.swift:634-637`); Refine
  keeps them (pinned test). The Rating picker also switches the toggle off when
  leaving Any and never back on (`AO3FilterPanel.swift:170-178`), so a reader who
  tried Teen and returned to Any keeps excluding Not Rated in Search. Pick one
  rule.

## Later

- Nothing else from this area.
