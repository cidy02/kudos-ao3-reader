# Brief 3x result: AO3 Collections sort and filter

Implemented in this worktree on `android/agent-codex-3x`. Changes are uncommitted. No branch switch, push, sign-in, AO3 contact, Gradle run, Room schema change, backup change, or `TASKS.md` edit was performed.

## Added

- `account/AO3CollectionsFilter.kt`: plain Kotlin port of the filter, draft editor and whole-index rules. AO3 ordering is the default; all four switches intersect. Title uses a case-insensitive locale-aware collator. Numeric/date sorting is stable, with unknown values after ranked rows in either direction. Dates recognise the four iOS formats using fixed English parsing; `LocalDate` avoids device time-zone reinterpretation.
- `account/AO3CollectionsFilterPanel.kt`: the Library panel's fully expanded Material bottom sheet, with subject field labels, panel rows, row separators, segmented direction control, toggles and theme tokens. Cancel/swipe dismissal discard the draft; Apply commits it; Reset affects the draft only. Apply and Reset follow iOS's disabled conditions.
- `AO3CollectionsScreen.kt`: conditional Filter button and active tint, existing long-press Clear All Filters menu, summary rail below the unchanged scope chips, filtered rows, filtered tally, no-match card and Clear Filters. Ordinary mode has pagination above and below the rows. Whole-index mode hides paging and exposes the cap note. A single scrolling list keeps the footer reachable. Page-change failures retain the previous rows and show the iOS alert. The tally waits for the whole-index result rather than showing a misleading zero while it loads.
- `AO3CollectionsViewModel` and `AO3CollectionsUiState`: screen-owned cancellation, session/load fences, cached whole index for the current session, independent whole-index loading/failure state and explicit retry. The crawl reuses a loaded page one, otherwise starts at page one; reads strictly sequentially; stops on an empty fetched page; and caps at 25 pages. A new rule reuses a completed index. Cancel and changes between already-active rules do not implicitly retry a failed crawl. Filtered refresh invalidates the index, fetches fresh page one, then reuses it for the bounded crawl. Ordinary refresh reloads the current page.
- Supporting account-index changes: the repository retains pagination from the same GET; remote collection counts preserve unknown/null versus zero; auth exposes its existing session generation and optionally fences expiry. No new endpoint, role lookup, background crawler, or demo route was added.

## User-visible strings

New feature copy is verbatim iOS copy (including en dashes in direction labels):

- Sheet/header/actions: `Sort and filter`, `Cancel` (close accessibility label), `Apply` (check accessibility label), `Reset`, `Sort by`, `Order by`, `Direction`, `Show only`.
- Sort choices: `AO3 order`, `Title`, `Works`, `Bookmarks`, `Recently updated`.
- Direction labels: `A–Z`, `Z–A`, `Fewest`, `Most`, `Oldest`, `Newest`. The plain Kotlin enum also exposes iOS's `Ascending` and `Descending`; the panel hides Direction for AO3 order.
- Switches and rail labels: `Open to new works`, `Has works`, `Moderated`, `Unrevealed`. Sort chips use `<sort title> · <direction title>`. Chip order is sort, Open to new works, Moderated, Unrevealed, Has works.
- Notes:
  - `Recently updated uses the date shown on each AO3 collection. If a date can't be read, that collection stays in AO3's order.`
  - `You can turn on more than one of these. Each choice narrows the results further.`
  - `AO3 doesn't show your role in its collections list, so you can't filter by Maintainer, Member or Invited here.`
- List states/actions: `No collections match`, `Clear Filters`, `Couldn't load all collections`, `Couldn't load that page`, `OK`.
- Hidden-count line: `<count> collection[s] are hidden by the current filters.` This retains iOS's wording even for singular counts.
- Tally: existing `<shown> collection[s]` gains ` · <total> in all`, ` · page <current> of <total>`, and ` · first 25 of <reported> pages` as applicable.
- Collection status: `Revealed` is now included for revealed rows, mirroring the final test in the specified iOS suite; `Unrevealed` and `Anonymous` already existed.

Existing shared controls now reachable on this screen add their existing strings: `Filter` (accessibility), `Clear All Filters` (long-press menu), `First Page`, `Previous Page`, `Next Page`, `Last Page` (accessibility), `Page <current> of <total>`, `<draft page>`, `of <total>`, `First`, `Last`, `Cancel`, `Go` (pagination/scrubber). Those shared components are unmodified.

All pre-existing list strings and callbacks remain, including `Loading collections`, the auth/error/empty-state copy, `Try Again`, the footer `These are your AO3 collections...`, `New Collection`, `Collections`, and `Your items`.

## Signatures

Existing changed signatures:

- `AO3Collection.worksCount` and `.bookmarksCount`: `Int = 0` → `Int? = null`, including the corresponding constructor/copy parameters and getters. This is a remote value type, not a Room entity or backup type. Collection-detail parsing still supplies its existing numeric fallback, and every consumer was read for compatibility; no other screen was edited. The existing collection-parser test's positive-count assertion now unwraps the nullable value.
- `AO3CollectionsUiState.Loaded(collections)` adds defaulted fields: `currentPage: Int = 1`, `totalPages: Int = 1`, `wholeIndex: List<AO3Collection>? = null`, `wholeIndexLoading: Boolean = false`, `wholeIndexError: String? = null`, `wholeIndexPartialNote: String? = null`, `pageError: String? = null`. Existing single-argument construction remains valid.
- `AO3AuthRepository.sessionDidExpire()` → `suspend fun sessionDidExpire(expectedGeneration: Int? = null)`. Existing calls retain their behavior; the collections path supplies the captured generation.
- Private `AccountListRepository.parseCollectionsPage(html, finalUrl, statusCode)` gains `page: Int` and `generation: Int`; its result changes from `AO3Result<List<AO3Collection>>` to `AO3Result<AO3CollectionsIndexPage>`.
- Private `CollectionsListContent` was replaced by the screen's single lazy-list body; no external caller used it.

New APIs:

- `AO3CollectionsFilter(sort: Sort = AsReturned, order: Order = Descending, showsOpenOnly: Boolean = false, showsUnrevealedOnly: Boolean = false, showsModeratedOnly: Boolean = false, showsWithWorksOnly: Boolean = false)`. Read-only `hasActiveFilters`, `needsWholeIndex`, `summaryLabels`; `apply(List<AO3Collection>): List<AO3Collection>`; companion `updatedDate(String): LocalDate?`; `Sort.title: String`; `Order.title(Sort): String`.
- `AO3CollectionsFilterDraft(initial: AO3CollectionsFilter, draft: AO3CollectionsFilter = initial)` with mutable `draft`, `reset(): Unit`, `resolved(Resolution): AO3CollectionsFilter`, and `Resolution.Cancel/Apply`.
- `AO3CollectionsWholeIndex.maximumPages = 25`; `refreshPage(Int, Boolean): Int`; `canReusePageOne(Int, Boolean, Boolean): Boolean`; `nextPage(after: Int, reportedTotalPages: Int, pageWasEmpty: Boolean): Int?`; `partialNote(Int, Boolean): String?`; `append(page: AO3CollectionsIndexPage, collections: MutableList<AO3Collection>, capturedLoadGeneration: Int, loadGeneration: Int, capturedSessionGeneration: Int, sessionGeneration: Int): Boolean`.
- `AO3CollectionCardCopy.statusLabels(isUnrevealed: Boolean, isAnonymous: Boolean): List<String>` is shared by the card and parity test.
- Composable `AO3CollectionsFilterPanel(initial: AO3CollectionsFilter, onFinish: (AO3CollectionsFilter) -> Unit)`. Private composables `FilterToggleRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit)` and `FilterNote(text: String)`.
- `AO3CollectionsIndexPage(collections: List<AO3Collection>, currentPage: Int = 1, totalPages: Int = 1)`.
- `AO3AccountParser.parseCollectionsIndex(html: String, page: Int = 1, finalUrl: String? = null): AO3CollectionsIndexPage`. Existing `parseCollections` still returns the rows.
- `AccountListRepository.loadCollectionsIndex(page: Int = 1): AO3Result<AO3CollectionsIndexPage>` (suspend). Existing `loadCollections(page: Int = 1): AO3Result<List<AO3Collection>>` is unchanged and delegates to it, issuing only one GET.
- `AO3AuthRepository.generation: StateFlow<Int>` publishes the existing identity-generation counter.
- `AO3CollectionsViewModel.filters: StateFlow<AO3CollectionsFilter>`; `onAppear()`, `onDisappear()`, `setFilters(AO3CollectionsFilter)`, `clearFilters()`, `loadPage(Int)`, `dismissPageError()`, suspend `refresh()`. Existing `load()`, constructor, factory, screen and card signatures remain unchanged. Private helpers: `cancelLoad(): Unit`, `startLoad(wholeOnly: Boolean = false): Job`, suspend `loadWholeIndex(generation: Int, session: Int): Unit`.

## iOS test mapping

Each row maps to the identically named Kotlin method in `account/AO3CollectionsFilterTest.kt`, with the same input cases and expected values.

| iOS `AO3CollectionsFilterTests.swift` | Kotlin `AO3CollectionsFilterTest` |
|---|---|
| `theDefaultLeavesAO3sOwnOrderAlone` | `theDefaultLeavesAO3sOwnOrderAlone` |
| `titleSortsAsAStringRatherThanSilentlyDoingNothing` | `titleSortsAsAStringRatherThanSilentlyDoingNothing` |
| `rowsWithNoCountKeepAO3sPositionInsteadOfCountingAsZero` | `rowsWithNoCountKeepAO3sPositionInsteadOfCountingAsZero` |
| `anUnparseableDateDoesNotGetSortedSomewhereWrong` | `anUnparseableDateDoesNotGetSortedSomewhereWrong` |
| `theDateParserAcceptsAO3sShapesAndRejectsOthers` | `theDateParserAcceptsAO3sShapesAndRejectsOthers` |
| `showOnlyFiltersNarrowTogetherRatherThanReplacingEachOther` | `showOnlyFiltersNarrowTogetherRatherThanReplacingEachOther` |
| `hasWorksExcludesBothZeroAndUnknown` | `hasWorksExcludesBothZeroAndUnknown` |
| `everyClientSideSortAndFilterNeedsTheWholeIndex` | `everyClientSideSortAndFilterNeedsTheWholeIndex` |
| `onlyNonDefaultSettingsProduceAChip` | `onlyNonDefaultSettingsProduceAChip` |
| `filterDraftCancelApplyAndResetResolveIndependently` | `filterDraftCancelApplyAndResetResolveIndependently` |
| `collectionStatusLabelsAlwaysNameVisibilityAndOptionallyAnonymity` | `collectionStatusLabelsAlwaysNameVisibilityAndOptionallyAnonymity` |

Whole-index cases from iOS `AO3CollectionSessionReloadTests.swift` also map to identically named methods in the same Kotlin file:

| iOS | Kotlin |
|---|---|
| `theWholeIndexPreservesServerOrderAndRejectsStalePages` | `theWholeIndexPreservesServerOrderAndRejectsStalePages` |
| `theWholeIndexStopsAtItsCapAndOnAnEmptyPage` | `theWholeIndexStopsAtItsCapAndOnAnEmptyPage` |
| `aCappedCrawlSaysItIsPartial` | `aCappedCrawlSaysItIsPartial` |
| `filteredRefreshRestartsAtPageOneAndTheCrawlReusesIt` | `filteredRefreshRestartsAtPageOneAndTheCrawlReusesIt` |

Additional filter tests cover unknown bookmark counts, stable ties in both directions, chip order and sort-specific direction labels. `AO3CollectionsViewModelTest.kt` uses an in-memory AO3Client to cover page-one reuse, later-page entry, sequential requests, cached-index reuse, refresh, cap/partial note, empty-page stop, clear/navigation/session cancellation, retired-request serialization, explicit failure retry, and real-parser pagination/null counts. The tests do not use the live client.

## Deliberate platform differences and scope exclusions

- No requested filter or panel control was omitted. “My role” is unavailable in iOS too; the same explanatory note is shown without participants requests.
- Sheet presentation follows Android's `LibraryFilterPanel` (`ModalBottomSheet`), rather than an Apple inspector/navigation stack. Subject form controls supply the contents.
- iOS cancels its URLSession task; Android's existing GET coalescer owns the underlying request in a separate scope. This port lets the one already-started request finish under the existing client timeout/retry policy, discards its result on cancellation, and joins its waiter before a replacement crawl can start. It stops all later pages and never changes shared networking policy or the coalescer. A cancelled pull-refresh may therefore wait for that existing request to finish before another load proceeds.
- The Android screen retains its existing header and scope chips while a whole-index load is pending, with a loading card and no tally; iOS replaces that body with a progress view. This preserves Android screen chrome while hiding incomplete rows.
- Kept today's Android footer verbatim as explicitly requested, although the iOS footer has a longer sentence. Kept today's auth prompt and loading-card strings for the same reason.
- New Collection and Your items retain their existing behavior. Collection editing, management, deletion notifications and other screens are outside this brief and were not ported.

## Verification and next step

Read the four specified iOS sources, the Android repository/model/parser/auth symbols, shared sheet/subject/refresh/pagination implementations, networking policy, and relevant operational docs. Audited all collection-count consumers after making counts nullable. `git diff --check` passes; a static test-name comparison confirms all 11 specified filter tests and all four whole-index helper tests are present. No helper scripts, stubs, `.orig` files, or build output were added.

Gradle, unit-test execution and device/UI verification were not run, per the brief. Claude should compile Android, run the new filter/ViewModel tests plus existing account/parser/auth regression suites, then inspect the demo sheet, active rail, no-match state, page-three entry, filtered refresh and long-press clear in the app. No visual correctness claim is made here.
