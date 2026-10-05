| Control (comparison before this change) | Android panel / field / matching | iOS panel / field / matching | Other side has it? |
|---|---|---|---|
| Sheet title | `Filter and Sort`; no predicate | `Filters`; no predicate | Yes, different label |
| Reset | Conditional `Clear`; resets filter state, not the separate sort/search | Reset icon, accessibility `Reset filters`; replaces `LibraryFilters` including sort | Yes; Android now resets filters, sort and its panel search |
| Finish / dismiss | `Close` and `Apply`; both dismiss, selections already apply live | Checkmark, accessibility `Done`; dismisses live filters | Yes; Android now uses Done and sheet dismissal |
| Search library | Optional outlined field; separate `searchQuery`; normalized AND terms over `WorkSearchIndex` plus collection names; obscured works do not match a nonblank query | No library-query field in this panel | Android only here; retained |
| Sort by | Chips; separate `LibrarySort`; Default, Date Added, Date Downloaded, Last Read, Title, Author, Word Count, Kudos | Picker; `filters.sort`; same eight titles; Default preserves each section's own order | Both |
| Rating | No panel control; hidden `ratings: Set<String>` requires all trimmed, case-insensitive exact texts | Picker; `rating` enum; case-insensitive substring `general`, `teen`, `mature`, `explicit`, `not rated`; Any bypasses | Android state had a different predicate; iOS enum control added without removing legacy field |
| Warnings | No panel control; hidden `warnings`; all normalized exact categorized texts, flat-tag fallback | Inline checkmark rows; enum set; ALL exact lowercased names; Underage accepts `Underage Sex` or `Underage`; flat fallback | Android predicate existed; control and spelling parity added |
| Categories | No panel control; hidden `categories`; all normalized exact categorized texts, flat fallback | Inline checkmark rows; enum set; ALL exact lowercased titles; flat fallback | Android predicate existed; control exposed, matching aligned |
| Completion | Chips `Complete` / `InProgress`; `completion`; tests `SavedWork.isComplete` | Picker `All` / `Complete` / `In Progress`; `completion`; tests `isComplete` | Both; labels aligned |
| Language | Absent | Picker, only when local nonempty languages exist; empty means any; display-name equality ignoring case | Added to Android |
| Word count | Absent | `From` / `To` text fields; `wordsFrom`, `wordsTo`; inclusive numeric bounds; all digits retained; only count > 0 is constrained | Added to Android |
| Tags (group) | No AO3-tag group in panel | Group containing the six fields below | Added to Android |
| My Tags / Your Tags | `My Tags` chips; `userTagIds`; ALL selected IDs must be work-tag relationships | `Your Tags` option picker; `userTags`; ALL selected names must be work-tag relationships | Both; Android ID-based behavior retained under iOS label |
| Fandoms | No panel picker; hidden `fandoms` and dashboard quick filters; all normalized exact strings with flat fallback | Option picker; ALL exact `FandomDisplayName.bareTitle` families with flat fallback | Android model/quick filter existed; picker added and family rule aligned |
| Characters | No panel picker; hidden `characters`; all normalized exact strings with flat fallback | Option picker; ALL exact case-sensitive tag members, categorized list or flat fallback | Android model existed; picker added, iOS rule wins |
| Relationships | No panel picker; hidden `relationships`; same old normalized rule | Option picker; ALL exact case-sensitive members, categorized list or flat fallback | Android model existed; picker added, iOS rule wins |
| Additional Tags | No panel picker; hidden `freeforms`; same old normalized rule | Option picker; `additionalTags`; ALL exact case-sensitive members, categorized list or flat fallback | Android model existed; picker added using `freeforms`, iOS rule wins |
| Exclude Tags | Absent | Option picker; `excludeTags`; reject ANY exact case-sensitive member of the flat `workTags` list | Added to Android |
| Status: Favorites | Chip; `favoriteOnly`; require `isFavorite` | Absent from panel | Android only here; retained as SubjectToggle |
| Status: Finished / Unfinished | Chips; `finished`; require `isFinished` or its complement | Absent from panel; completion means AO3 completion, not reading status | Android only here; retained with an Any option |
| Download | Chips `Downloaded` / `Not Downloaded`; `download`; require `isDownloaded` or its complement | Absent from panel | Android only here; retained with an Any option |
| Collections | Named chips, if collections exist; `collectionIds`; ALL selected membership IDs required | Absent from panel | Android only here; retained as an option picker |
| Option-picker search | No option picker | `Filter <title>`; trimmed, case- and diacritic-folded substring of option text | Added to Android multi-select pickers; local data only |
| Option-picker selections / Done | No option picker | Whole-row toggle, trailing checkmark, multiple choices, Done dismisses picker | Added to Android; single-choice fields use whole-row menus |

# Brief 3af result

Implemented in this worktree on `android/agent-codex-3af`, without committing, pushing, switching branches or editing `TASKS.md`. No sign-in, AO3 contact, Gradle invocation, helper script, stub or `.orig` file. Room schemas and backup code/formats are unchanged. Build, unit-test execution and emulator review are for Claude; this report does not claim they passed.

The comparison uses the files actually read from `/Users/cidy02/kudos-ios-polish`: `Features/Library/LibraryFilterPanel.swift`, `LibraryFilters.swift`, `LibraryFilterEmptyState.swift`, `KudosTests/LibraryFiltersTests.swift`, and the shared enums/helpers in `Models/AO3Models.swift`. Android's opening panel and model were `library/LibraryFilterPanel.kt`, `LibraryFilter.kt`, and `LibraryQuery.matchesFilters`.

## Where iOS's code wins over the brief

- The header uses Reset and Done **icons**, with accessibility strings `Reset filters` and `Done` (`LibraryFilterPanel.swift:28–45`). Android now uses those same strings with plain icon buttons, without filled buttons.
- Warnings and Categories are **inline whole-row checkmarks**, not option-picker fields (`LibraryFilterPanel.swift:66–84`). Android follows that structure and offers only include/clear, without Search's exclude cycle.
- Word count has editable `From` and `To` fields, not a choices picker (`LibraryFilterPanel.swift:98–112`). Android keeps editable number-keyboard fields in a subject panel.
- There is one `Tags` section, containing `Your Tags`, `Fandoms`, `Characters`, `Relationships`, `Additional Tags`, and `Exclude Tags` (`LibraryFilterPanel.swift:114–135`). There are no sections literally called “Tags to include” or “Tags to exclude.” Android uses iOS's actual labels and order.

## Panel and callers

`LibraryFilterPanel.kt` uses `LocalKudosTokens` for the sheet ground, title, values and accent; `SubjectMetrics.headerGutter`; `subjectPanel`, `SubjectFormRow`, `SubjectRowSeparator` and `SubjectFieldLabel`. `SubjectToggle` retains Favorites. No segmented control is needed: the iOS reference uses pickers/checkmarks here. Notes are 12sp with 17sp line height, following `AO3CollectionsFilterPanel.kt`. No Material chips, outlined fields, outlined buttons or filled buttons remain in this panel. The remaining dropdown menus are the single-choice option pickers.

The first group is Sort by / Rating, followed by Warnings, Categories, Completion / Language, Word count, then Tags. Retained Android controls follow: Status, Download, Collections, and optional Search library. Whole choice rows open their menus or searchable multi-select sheets. Selection applies live; Done dismisses. Reset clears the entire filter state, returns sort to Default, and clears the optional Library query.

`LibraryScreen.kt` passes `state.collectionMembers.map { it.item.work }`, a source that is not narrowed by these filters. `HomeSectionListScreen.kt` passes its unfiltered `sectionItems`, matching iOS `HomeSectionListView.swift:220`'s section-scoped options. Both sources respect the existing surface privacy selection; they do not add fetching. Language values and each AO3 tag field are exact distinct, sorted local values (`LibraryFilterPanel.swift:142–161`); include choices use categorized lists, while Exclude Tags uses the flat list. Matching falls back to flat tags even though the include picker's choices come from categorized lists, as iOS does. Empty categories still open their honest empty picker. Your Tags and Collections remain conditional on having available local records. New filter fields also appear on Home's existing summary rail; their active count reaches existing badges and clear actions.

`LibraryFilterEmptyState.swift` was read to understand the live-filter and clear behavior. Its collision-card UI (drop-one counts, Edit and Clear all filters) is outside this panel port; Android's existing empty states remain in place.

## Every user-visible string before → after

The “before” column is Android at the start of this brief. This includes accessibility names and child pickers; dynamic strings are listed as templates. Group labels are rendered uppercase by `SubjectFieldLabel`, retaining the source labels below.

| Before | After | Where / reason |
|---|---|---|
| `Filter and Sort` | `Filters` | Header, iOS verbatim |
| `Clear` | `Reset filters` (accessibility, icon) | Header action; always present, disabled at defaults |
| `Close` | `Done` (accessibility, icon); sheet drag/back dismissal | Removed redundant footer; live state retained on dismissal |
| `Apply` | `Done` (accessibility, icon) | Header dismisses; no Apply footer |
| `Sort by` | `Sort by` | Whole-row picker |
| `Default`, `Date Added`, `Date Downloaded`, `Last Read`, `Title`, `Author`, `Word Count`, `Kudos` | Same eight strings | Existing sort options preserved |
| — | `Rating` | New enum picker |
| — | `Any rating`, `General Audiences`, `Teen And Up`, `Mature`, `Explicit`, `Not Rated` | iOS shared rating titles, verbatim |
| — | `Warnings` | Inline multi-select group |
| — | `No Archive Warnings Apply`, `Creator Chose Not To Use Archive Warnings`, `Graphic Depictions Of Violence`, `Major Character Death`, `Rape/Non-Con`, `Underage Sex` | Six iOS warning titles, verbatim |
| — | `Categories` | Inline multi-select group |
| — | `F/F`, `F/M`, `Gen`, `M/M`, `Multi`, `Other` | Six iOS category titles, verbatim |
| `Completion` | `Completion` | Whole-row picker |
| No unconstrained chip | `All` | iOS completion default |
| `Complete` | `Complete` | Completion option |
| `InProgress` | `In Progress` | iOS spelling |
| — | `Language`, `Any language`, `<local language display name>` | iOS labels; Language omitted when no local language exists |
| — | `Word count`, `From`, `To` | iOS section and input labels |
| — | `A work's word count appears after you open it, using the number from AO3.` | iOS word-count footnote, verbatim |
| — | `Tags` | iOS group label |
| `My Tags` | `Your Tags` | Same Android tag-ID filter, iOS title |
| `<tag.normalizedName>` | `<tag.normalizedName>` | Local tag option labels preserved |
| — | `Fandoms`, `Characters`, `Relationships`, `Additional Tags`, `Exclude Tags` | iOS field and picker titles |
| — | `<exact local AO3 tag>` | Option labels; no network suggestions |
| — | `Any`, `<N> selected` | iOS multi-select row values |
| — | `Choose AO3 tags to show matching works. Exclude Tags hides works with those tags.` | iOS Tags footnote, verbatim |
| — | `Filter <title>` | iOS multi-select search prompt, verbatim template |
| — | `Your Library has no <lowercased title> yet.` | iOS empty-options text, verbatim template |
| — | `None of your options match “<query>”.` | iOS no-search-matches text, including curly quotes |
| — | `Done` (accessibility, icon) | Child option-picker completion |
| `Status`, `Favorites`, `Finished`, `Unfinished` | Same strings | Kept Android controls; Favorites also labels its switch |
| No unconstrained status chip | `Any` | Status menu's neutral choice |
| `Download`, `Downloaded`, `Not Downloaded` | Same strings | Kept Android controls |
| No unconstrained download chip | `Any` | Download menu's neutral choice |
| `Collections`, `<collection.name>` | Same strings | Kept Android collection-ID picker |
| `Search library` | `Search library` | Kept optional query, now GlassFieldBar |
| No summary for new fields | `<rating title>`, `<language>`, `−<tag>`, `Words <from>–<to>`, `<compact count>+ words`, `Words ≥ <from>`, `Words ≤ <to>` | Home summary rail, following `LibraryFilters.swift:107–131,416–422`; typed non-integer lower bounds use the ≥ form |

## Retained Android-only controls and iOS equivalents elsewhere

| Kept capability | Why retained / where iOS offers it |
|---|---|
| Status: Favorites | Keeps `favoriteOnly` behavior. iOS has Library's Favorites shelf (`LibrarySectionKind.swift:162–165`), rather than this panel switch. |
| Status: Finished / Unfinished | Keeps the reader's `isFinished` axis distinct from AO3 completion. iOS has Finished and Reading Now sections (`LibrarySectionKind.swift:116–129`); Reading Now is narrower than “not finished,” so it is not an exact replacement for Android's Unfinished. |
| Downloaded / Not Downloaded | Keeps existing `isDownloaded` semantics, including kept reading copies. iOS has the Downloaded section (`LibrarySectionKind.swift:132–136`) and Favorites' Offline quick filter (`FavoriteQuickFilter.swift:72–73`). No complementary Not Downloaded option was found in the reference panel. |
| My Tags | Kept under `Your Tags`: iOS does have the same organizational-tag facet in this panel (`LibraryFilterPanel.swift:115–118`). Android continues matching stable IDs; the rename does not change membership semantics. |
| Collections | Keeps ALL selected collection-ID memberships. iOS offers collection navigation and collection-specific works pages (`Collections.swift:101`, with a filter panel at line 373), not a multi-collection intersection picker in this panel. |
| Search library | Keeps the existing normalized AND-term predicate and query callback. iOS offers global Search with live Library work/tag/fandom/collection matches (`SearchView.swift:475–513`, prompt at line 572). This does not duplicate the optional Android panel query's location. Home still has no panel query, exactly as before. |

No existing visible Android facet was removed. The legacy hidden `ratings` set remains and keeps its original normalized exact-text matcher; the iOS rating picker uses the new `rating` enum. Existing warning/category/tag-set fields remain source-compatible. The owner's approval would be needed to remove the Android extras.

## Matching rules and exact iOS source lines

All line references below are in the iOS lane read for this task, not in Android's Swift snapshot. All active facets combine with AND. The reused shared rules are extracted into `search/AO3SummaryFilter.kt`; its existing `matchesSummary` calls the same helpers as `LibraryQuery.matchesFilters`.

| New or corrected Android rule | iOS source followed | Implementation / reuse |
|---|---|---|
| Rating enum defaults to Any; stored text contains the enum's keyword ignoring case, including Not Rated; no severity-range or include-unrated control in Library | `LibraryFilters.swift:297`, `383–395` | Shared `AO3Rating.matchesRatingText`; Search's existing ladder now classifies via that same helper |
| Require every warning, exact case-insensitive name; Underage accepts both AO3 spellings; categorized list wins unless empty | `LibraryFilters.swift:299–305`, `399–407` | Shared `AO3Warning.matchesWarningText` and `matchesFacetText`; Library supplies flat fallback |
| Require every category's exact case-insensitive title, with categorized/flat fallback | `LibraryFilters.swift:307–312` | Shared `matchesFacetText`; no substring matching or trimming |
| Fandoms require every exact bare family; fallback only if categorized field is empty | `LibraryFilters.swift:279–285`, `353–355` | Existing Android `FandomDisplayName.bareTitle`, rather than another family parser |
| Characters, relationships, additional tags require ALL exact case-sensitive members, with independent flat fallback | `LibraryFilters.swift:287–292`, `353–355` | `containsAll` over existing model lists. Old Android's trimmed/lowercased matching is superseded by iOS here |
| Exclude Tags rejects ANY exact case-sensitive flat-tag match, across the entire flat list | `LibraryFilters.swift:293` | `excludeTags.any { it in work.workTags }`. Search's exclusion matcher is substring-based over categorized lists, so it is intentionally not reused for this different rule |
| Completion remains a direct test of `isComplete` / its complement, not reading completion | `LibraryFilters.swift:314–318` | Existing `LibraryCompletionFilter` matcher retained; menu uses iOS shared completion titles |
| Empty language means any; otherwise exact display-name equality ignoring case | `LibraryFilters.swift:320–321` | Shared `matchesFacetText` |
| Bounds apply only to known counts > 0; inclusive edges; all nondigits ignored; absent/non-numeric/overflowing bound ignored; reversed bounds are not silently swapped | `LibraryFilters.swift:323–328`; `Models/AO3Models.swift:199–208` | Shared `filterWordBound` returns Long to match Swift's 64-bit Int. Library supplies the > 0 guard; Search retains its nullable-count guard |
| Default fields and active detection, including both bounds as one word-count facet | `LibraryFilters.swift:8–39` | Appended fields with defaults in `LibraryFilter.kt`; new facets included in `activeCount` and data-class equality |

The shared bound parser now also accepts valid 64-bit bounds on Search's loaded-page refine path, where Android previously ignored values above Int.MAX_VALUE. This follows iOS's shared `FilterTextMatching.bound`; tests cover the change. Completion derivation for nullable remote metadata remains Search-specific. No AO3 request or query-URL construction changed.

## Stored-form compatibility checked

- Searched every Android `LibraryFilterState` reference. It is a plain, non-serializable data class, held in `LibraryViewModel.kt:38`'s `MutableStateFlow` and `HomeSectionListScreen.kt:142`'s `remember(kind)` state. It is also carried in the in-memory `LibraryUiState`.
- No `LibraryFilterState` reference exists in `data/` or `backup/`; there is no persisted Library filter form to migrate or reload. Existing saved searches are a different type: `SearchFiltersCodec.kt` encodes/decodes `AO3SearchFilters`, and `SavedSearchRepository`/backup mappers carry that existing form. Those files were not edited.
- Appended `rating = AO3Rating.ANY`, `language = ""`, `wordsFrom = ""`, `wordsTo = ""`, `excludeTags = emptySet()` after all existing constructor fields. Existing names, types, enum tokens, defaults and copy paths remain intact. No Room entity, schema/version or backup DTO/format changed.
- Reset clears new and old fields together. Home recomputes through `remember(sectionItems, filters, sort)`; Library recomputes through the existing combined StateFlows. Kotlin data-class equality includes new values, so a same-count facet change still updates results. Filters remain session-only across process restart, as before.

## Tests and verification

Added `android/app/src/test/java/io/github/cidy02/kudos/library/LibraryFiltersTest.kt`: 14 tests. The eight matching names below are taken directly from iOS `KudosTests/LibraryFiltersTests.swift`; no Room or network fixtures are needed:

- `fandomFacetUsesCategorizedTagsAndFallsBackToFlatTags`
- `excludeTagsRejectAnyFlatTagMatch`
- `userTagFacetMatchesTheTagRelationship`
- `ratingMatchesLenientText`
- `underageWarningMatchesBothAO3Spellings`
- `completionFacetSplitsCompleteAndWIP`
- `languageMatchesCaseInsensitively`
- `wordBoundsSkipWorksWithUnknownCounts`

Additional tests: `fandomFacetMatchesTheSameFamily`, `warningAndCategorySelectionsRequireEveryChoice`, `categorizedIncludesRequireExactTagsAndFallBackOnlyWhenEmpty`, `wordBoundsIgnoreNonDigitsAndUnparseableBounds`, `newFieldsCombineWithExistingFiltersAndBothQueryPaths`, `defaultsAndActiveCountCoverAllNewFields`. Together these cover AND semantics, category fallback precedence, case/substring distinctions, 0/negative unknown counts, inclusive/reversed/malformed/64-bit bounds, default-state behavior and active counts. Existing `LibraryQueryTest.kt` still covers retained status, download, tag-ID, collection-ID, sort and combined-filter behavior.

Added `sharedLibraryMatchersPreserveExactFacetsAndBothUnderageSpellings` to `AO3SummaryFilterTest.kt`: exact warning/category matching, the alias, malformed/overflowing bounds and a valid large lower bound. Existing Search tests still cover rating ranges, unrated inclusion, remote chapter metadata and nullable word counts.

Static verification: `git diff --check` passed; inspected all changed callers and the actual SavedWork/Tag/WorkCollection properties, AO3 enums, subject component signatures, GlassFieldBar, search normalization and filter-state storage paths. No compilation or unit tests were run, and no emulator UI was viewed. Claude should build and run the Android unit suite, including the new `LibraryFiltersTest`, existing `LibraryQueryTest.kt` suites and `AO3SummaryFilterTest`.

## What Claude / the owner must see on the emulator

1. Open Filters from Library and from a Home section, signed out and offline or with AO3 traffic blocked. Verify the plain sheet ground, reset/title/done header, section order, panels/separators and absence of chips, outlined fields and filled buttons. Review Light, Dark, Sepia and OLED, phone and wide-screen layouts, and large font scale.
2. Tap the label side and blank space of Sort by, Rating, Completion, Language, every tag field, Status, Download and Collections. Each full row must open choices. Warning/category rows must toggle checkmarks across the row and announce selected state in TalkBack; Favorites must work from both its row and switch.
3. Check every rating including Not Rated, both Underage spellings, multi-warning/category AND behavior, and categorized versus flat-only metadata. Choose Doctor Who against a stored Doctor Who (2005) work. Exact character/relationship/additional-tag matching must not become substring matching.
4. Enter `1,000` to `10,000`: keep counts on the edges and unknown 0 counts; reject known counts outside. Check a reversed range, pasted nondigits and a lower bound of `2147483648`. Clear fields without losing other facets. Number keyboard and reset/done remain usable with the IME open.
5. Open tag pickers, search case/diacritic variants, toggle several options and deselect them. Done and drag/back must return to the parent sheet without dismissing it or losing live choices. Confirm the empty-options and no-query-match texts, long labels, long lists and picker scrolling. Language/tag options must remain available after filters hide all works.
6. Verify Your Tags still filters stable tag IDs, Collections still intersects every chosen membership, Favorites/Finished/Unfinished and Downloaded/Not Downloaded keep their meanings, and Library search still works. Home still shows no optional Library search field. Inspect the new Home summary labels after dismissing.
7. With only sort changed, Reset must be enabled and restore Default. With only Library search changed, it must clear the query. With any new facet changed, badges/reset must activate; Reset must clear all facets and selections. Done and sheet dismissal retain live filters. Confirm a no-match state can be cleared from the existing surface controls.
8. Confirm session filters reset after process restart as before, with library works, saved searches, Room data and backup import/export unchanged. This is a visual/behavioral handoff checklist, not evidence that those checks have been performed.
