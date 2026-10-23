# Brief 3fx — A65's Small Rows (Android)

Implemented in `/Users/cidy02/kudos-agent-flash` on branch `android/agent-flash-3fx`.
Changes are uncommitted for Claude to build, test, and land.
No commits, pushes, branch switches, sign-ins, Gradle invocations, AO3 contacts,
Room schema changes, backup format changes, or `TASKS.md` edits were made.
The iOS repository at `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` was read-only source of truth.

---

## Row-by-Row Audit & Changes

### 1. Row #99 — Search filter badge counts subject fandom and sort direction
- **Status:** Confirmed
- **Path:line:** `android/app/src/main/java/io/github/cidy02/kudos/search/SearchFilterHelpers.kt:131`
- **What changed:**
  - `activeFilterCount(filters)` previously called `summaryLabels(filters).size` without excluding the search subject or sort direction, causing the search filter badge to overcount and disagree with the hero's Filters count cell.
  - In `SearchFilterHelpers.kt`, added `includesSort: Boolean = true` parameter to `summaryLabels(...)` and excluded `filters.sort` when `includesSort == false`.
  - Updated `activeFilterCount(filters)` to `summaryLabels(filters, excluding = filters.searchSubject().text, includesSort = false).size`.
- **iOS code followed:**
  - `Features/Search/SearchResultsHero.swift:320` (`filters.activeFilterCount(excluding: filters.searchSubject.text, includesSort: false)`)
  - `Features/Search/SearchFilters.swift:150–180`
- **Tests added / updated:**
  - `android/app/src/test/java/io/github/cidy02/kudos/search/SearchFilterHelpersTest.kt`: Ported `filterBadgeMatchesTheHeroFiltersCell` from iOS `KudosTests/SearchPanelRulesTests.swift:38` asserting that `activeFilterCount(filters)` matches the hero's count exactly.
  - `android/app/src/test/java/io/github/cidy02/kudos/search/SearchFiltersTests.kt`: Updated assertions in `activeFilterCountReportsWhatTheUserChanged` verifying that changes to `sort` and `sortDirection` do not increment the active filter count.

---

### 2. Row #100 — Pager ‹ / › lack long press to first / last page
- **Status:** Confirmed
- **Path:line:** `android/app/src/main/java/io/github/cidy02/kudos/ui/components/KudosPaginationBar.kt:82`
- **What changed:**
  - On iOS (`SearchPaginationBar.swift:29`, `245–257`), tapping ‹ / › navigates to adjacent pages, while long-pressing ‹ jumps to page 1 and long-pressing › jumps to `totalPages`. The inline bar on iOS does not have separate First/Last buttons (those exist only in the pagination sheet).
  - Following iOS, removed the redundant separate First/Last `IconButton`s from the inline bar.
  - Added `PaginationDirection` enum (`Previous`, `Next`) and `navigationPage(direction, isLongPress, currentPage, totalPages)` helper matching iOS `SearchPaginationBar.swift:245–257`.
  - Wired `combinedClickable(onClick = { ... }, onLongClick = { ... })` with haptic feedback to the previous and next arrow buttons, jumping to page 1 on long-press of ‹ and `totalPages` on long-press of ›.
- **iOS code followed:**
  - `Features/Search/SearchPaginationBar.swift:29`
  - `Features/Search/SearchPaginationBar.swift:245–257`
- **Tests added / updated:**
  - `android/app/src/test/java/io/github/cidy02/kudos/ui/components/PaginationHintTest.kt`: Ported `arrowsUseTapForAdjacentAndLongPressForEnds()` testing `navigationPage` across all directions and press types. Added Compose UI test `paginationBarArrowsSupportTapAndLongPress()` verifying long-pressing ‹ navigates to page 1 and long-pressing › navigates to `totalPages`.

---

### 3. Row #101 — Tapped tag works address omits `view_adult=true` and `utf8`/`commit`
- **Status:** Confirmed
- **Path:line:** `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/search/AO3SearchUrlBuilder.kt:32`
- **What changed:**
  - Rebuilding a tapped tag's works URL dropped arbitrary query items (`utf8=✓`, `commit=Sort and Filter`) and omitted `view_adult=true`.
  - In `AO3SearchUrlBuilder.kt`, added `buildFilteredWorksUrl(baseUrl: String, filters: AO3SearchFilters, page: Int = 1)` and `filteredWorksUrl(baseUrl: HttpUrl, filters: AO3SearchFilters, page: Int = 1)`. Matches iOS `AO3Client.filteredWorksURL` parameter-for-parameter: parses existing query parameters, drops any existing `work_search[...]`, `page`, and `view_adult` items while retaining other items (`utf8`, `commit`), appends `view_adult=true`, appends serialized `work_search[...]` filter parameters, and appends `page` when `> 1`.
  - In `AO3SearchRepository.kt:45`, routed full URLs (`http://`/`https://`) through `buildFilteredWorksUrl`.
- **iOS code followed:**
  - `Services/AO3Client.swift:1189–1220` (`filteredWorksURL(for:filters:page:)`)
- **Tests added:**
  - `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/search/FilteredWorksUrlTest.kt`: Ported all 7 test cases from iOS `KudosTests/FilteredWorksURLTests.swift`:
    - `filteredWorksURLRetainsBaseQueryItemsAndAppendsViewAdultAndFilters`
    - `filteredWorksURLPreservesExistingNonFilterQueryItems`
    - `filteredWorksURLDropsExistingWorkSearchParametersBeforeReapplying`
    - `filteredWorksURLHandlesPercentEncodedTagPaths`
    - `filteredWorksURLOmitsPageWhenFirstPage`
    - `filteredWorksURLAppendsPageWhenBeyondFirstPage`
    - `filteredWorksURLDropsExistingPageBeforeReapplying`

---

### 4. Row #102 — Ticked challenge-settings checkbox sends both hidden `0` and checked `1`
- **Status:** Confirmed
- **Path:line:** `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/account/AO3ChallengeSettingsForm.kt:122` (and line 60 in `parameters()`)
- **What changed:**
  - When Rails serves a checkbox with a companion hidden input of value `"0"`, ticking the checkbox previously emitted both the hidden `"0"` and checked `"1"` in `AO3ChallengeSettingsForm.parameters()`.
  - In `AO3ChallengeSettingsForm.kt:64–69`, when processing a hidden control with a companion checkbox of the same name: if the companion checkbox is disabled or ticked (`this[name] == "1"`), the hidden `"0"` is omitted from the submission, matching iOS `submittedHiddenFields`.
  - Updated `AO3ChallengeSettingsEditTest.kt` test helper `browserSubmission` to match browser/iOS behavior.
- **iOS code followed:**
  - `Services/AO3Client+Challenges.swift:237–257` (`submittedHiddenFields`)
  - `Services/AO3ChallengeModels.swift:410`
- **Tests added:**
  - `android/app/src/test/java/io/github/cidy02/kudos/account/AO3ChallengeSettingsEditTest.kt`: Ported `undrawnRestrictionBoxesKeepTheirTickOnSave` and `disabledAndAbsentRestrictionFieldsAreNotPosted` from iOS `KudosTests/AO3ChallengeFormTests.swift:169–220`.

---

### 5. Row #124 — Add Chapter custom-date switch has no spoken name
- **Status:** Confirmed
- **Path:line:** `android/app/src/main/java/io/github/cidy02/kudos/writing/WritingChapterFormScreen.kt:138`
- **What changed:**
  - In `WritingChapterFormScreen.kt:138`, the switch for setting a different publication date had no distinct spoken accessibility label (it defaulted to the row's visible label "Set a different publication date"), whereas iOS uses `Toggle("Custom publication date", ...)`.
  - In `WritingWorkFormScreen.kt:462`, added `spokenLabel: String = label` to `WorkFormToggle` and passed `contentDescription = spokenLabel` to `SubjectToggle`.
  - In `WritingChapterFormScreen.kt:138`, passed `spokenLabel = "Custom publication date"` to `WorkFormToggle`.
- **iOS code followed:**
  - `Features/Writing/AddChapterView.swift:265` (`Toggle("Custom publication date", isOn: Binding(...))`)
- **Tests added:**
  - `android/app/src/test/java/io/github/cidy02/kudos/writing/WritingChapterFormScreenTest.kt`: Added `customPublicationDateSwitchHasSpokenName()` asserting that a node with contentDescription `"Custom publication date"` exists, clicking it sets `publishedYear`, and reveals the publication date picker row.

---

### 6. Row #113 — `RegexPortabilityTest` scans only `network/ao3`
- **Status:** Already fixed (widened to `src/main/java` in `5a74078c16dd`; portability tokens extended in this brief)
- **Path:line:** `android/app/src/test/java/io/github/cidy02/kudos/RegexPortabilityTest.kt:13`
- **What changed:**
  - Commit `5a74078c16dd` previously widened `RegexPortabilityTest.kt` to scan the whole tree via `listOf("src/main/java", "app/src/main/java", "android/app/src/main/java")`.
  - In this brief, `RegexPortabilityTest.kt` was hardened to scan for all JVM flags unsupported by Android ICU: `(?U)` / `UNICODE_CHARACTER_CLASS`, `(?d)` / `UNIX_LINES`, and `CANON_EQ`.
  - Static ICU audit across all 512 Kotlin files (127 regex occurrences) confirmed zero violations across the entire Android source tree.
- **iOS code followed:**
  - N/A (Android ICU regex engine portability guard).
- **Tests updated:**
  - `android/app/src/test/java/io/github/cidy02/kudos/RegexPortabilityTest.kt`: Updated `noPatternUsesAFlagAndroidRejects()` scanning for `(?U)`, `UNICODE_CHARACTER_CLASS`, `(?d)`, `UNIX_LINES`, and `CANON_EQ` across all Kotlin files in `src/main/java`.

---

### 7. Row #108 — Missing unit tests for Clear History session change during GET and 307/308 write redirect refusal
- **Status:** Confirmed (production fix in `42155cc1`; unit test coverage added)
- **Path:line:** `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/writes/AO3WriteRepository.kt:1265`
- **What changed:**
  - In `AO3WriteRepository.kt:1265`, added guard `response.value.statusCode !in setOf(307, 308)` so 307/308 redirect responses are never treated as confirmation even if `redirectConfirms` is true.
  - In `AO3WriteRepositoryTest.kt`, updated `FakeAuthenticatedClient` to support `currentGeneration`, `afterGet` hook, and override `sessionGeneration(): Int`.
- **iOS code followed:**
  - `KudosTests/AO3WriteDispatchFenceTests.swift:276–296` (`aSessionChangeDuringTheUnmarkCSRFFetchPostsNothing`)
  - `KudosTests/AO3RedirectCookieRelayTests.swift:11–19` (refusing 307/308 write redirect)
- **Tests added:**
  - `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/writes/AO3HistoryDeleteTest.kt`:
    - `clearHistoryStopsAndSendsNothingIfSessionChangesDuringGet()`: Verifies that when session changes during the GET of `/confirm_clear`, the write cancels with `CancellationException` and `posts` is empty.
    - `deleteReadingStopsAndSendsNothingIfSessionChangesDuringGet()`: Verifies that when session changes during the readings GET, `deleteReading` cancels and posts nothing.
    - `a307Or308AnswerToAWriteIsNotReSentAndFails()`: Verifies that 307 and 308 answers (both direct HTTP status and transport refusal) fail without being re-sent (single POST).

---

## File Summary

- **Production code modified:**
  - `android/app/src/main/java/io/github/cidy02/kudos/search/SearchFilterHelpers.kt` (#99)
  - `android/app/src/main/java/io/github/cidy02/kudos/ui/components/KudosPaginationBar.kt` (#100)
  - `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/search/AO3SearchUrlBuilder.kt` (#101)
  - `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/search/AO3SearchRepository.kt` (#101)
  - `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/account/AO3ChallengeSettingsForm.kt` (#102)
  - `android/app/src/main/java/io/github/cidy02/kudos/writing/WritingWorkFormScreen.kt` (#124)
  - `android/app/src/main/java/io/github/cidy02/kudos/writing/WritingChapterFormScreen.kt` (#124)
  - `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/writes/AO3WriteRepository.kt` (#108)

- **Test code modified / created:**
  - `android/app/src/test/java/io/github/cidy02/kudos/search/SearchFilterHelpersTest.kt` (#99)
  - `android/app/src/test/java/io/github/cidy02/kudos/search/SearchFiltersTests.kt` (#99)
  - `android/app/src/test/java/io/github/cidy02/kudos/ui/components/PaginationHintTest.kt` (#100)
  - `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/search/FilteredWorksUrlTest.kt` (new file) (#101)
  - `android/app/src/test/java/io/github/cidy02/kudos/account/AO3ChallengeSettingsEditTest.kt` (#102)
  - `android/app/src/test/java/io/github/cidy02/kudos/writing/WritingChapterFormScreenTest.kt` (#124)
  - `android/app/src/test/java/io/github/cidy02/kudos/RegexPortabilityTest.kt` (#113)
  - `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/writes/AO3WriteRepositoryTest.kt` (#108)
  - `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/writes/AO3HistoryDeleteTest.kt` (#108)

---

## Review fixes

Audit findings from `/Users/cidy02/kudos-android-lane/docs/android-port/audits/review-3fz-3ft-3fx-3ga.json` on patch `3fx` addressed:

### 1. Row #101 — Tapped tag address built on real tap path with `view_adult=true`
- **What changed:**
  - `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/browse/AO3BrowseRepository.kt:160–169`:
    In `worksForTag(tagName, page, filters)`: Bare tag names (e.g. from `ReaderLinkHandler` / `Routes.tagWorks` / `FandomWorksScreen`) are resolved into canonical tag works addresses `"${AO3Constants.BASE_URL}/tags/$segment/works"` using `AO3SearchUrlBuilder().tagPathSegment(trimmed)` before delegating to `searchRepository.searchTagWorks`.
  - `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/search/AO3SearchRepository.kt:46`:
    Routes HTTP(S) tag URLs directly to `urlBuilder.filteredWorksUrl(tag, filters, page)`.
  - `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/search/AO3SearchUrlBuilder.kt:54–77`:
    Made `filteredWorksUrl` the primary builder matching iOS `AO3Client.filteredWorksURL`, with `buildFilteredWorksUrl` delegating to it.
- **Test that fails without the fix:**
  - `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/browse/AO3BrowseRepositoryTest.kt:133` (`worksForTagSendsViewAdultTrue`):
    Calling `repository.worksForTag("Fluff")` previously passed the bare string `"Fluff"` into `buildFandomWorksUrl`, sending no `view_adult=true` parameter. With the fix, the tag's address is built and `view_adult=true` is sent on the wire, while `worksForFandom("Naruto")` still sends no `view_adult` (retaining browse endpoint contract).

### 2. Row #99 — Browse filter badge agrees with Browse hero Filters cell
- **What changed:**
  - `android/app/src/main/java/io/github/cidy02/kudos/search/SearchFilterHelpers.kt:130–133`:
    Added `excluding: String? = filters.searchSubject().text` parameter to `activeFilterCount(filters, excluding)` so callers can specify the subject excluded from summary count.
  - `android/app/src/main/java/io/github/cidy02/kudos/browse/FandomWorksScreen.kt:114`:
    Updated `activeFilterCount` to pass `excluding = fandomName`, matching the hero at `FandomWorksScreen.kt:271` (`summaryLabels(filters, excluding = fandomName)`).
- **Test that fails without the fix:**
  - `android/app/src/test/java/io/github/cidy02/kudos/search/SearchFilterHelpersTest.kt:133` (`browseFilterBadgeMatchesBrowseHeroFiltersCell`):
    On Browse for "Naruto", adding a single character filter ("Sasuke") gives a hero cell count of 1. Previously, `activeFilterCount(filters)` dropped "Sasuke" as the lone subject and returned 0, creating a badge/hero mismatch. With the fix, `activeFilterCount(filters, excluding = "Naruto")` returns 1, matching the hero cell.

### 3. Row #102 — Restored test oracle `browserSubmission` and fixed app companion box behavior
- **What changed:**
  - `android/app/src/test/java/io/github/cidy02/kudos/account/AO3ChallengeSettingsEditTest.kt:365–370`:
    Removed the modified hidden checkbox branch from `browserSubmission`, restoring it as an independent fixture browser oracle.
  - `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/account/AO3ChallengeSettingsForm.kt:68`:
    Changed condition from `if (companionBox.disabled || this@AO3ChallengeSettingsForm[served.name] == "1")` to `if (!companionBox.disabled && this@AO3ChallengeSettingsForm[served.name] == "1")`. When only the checkbox is disabled, its enabled companion hidden input is preserved and posts `"0"`, matching both iOS `submittedHiddenFields` and a real browser.
- **Test that fails without the fix:**
  - `android/app/src/test/java/io/github/cidy02/kudos/account/AO3ChallengeSettingsEditTest.kt:335` (`enabledHiddenInputWithDisabledCheckboxPostsZero`):
    With an enabled hidden input of value "0" and a disabled checkbox of the same name, the app previously dropped the hidden input and posted nothing. With the fix, `form.parameters()` posts `listOf("0")`.
