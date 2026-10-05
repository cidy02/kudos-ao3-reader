# Brief 3ai result: the reader's Find in Work

**Landing note (Claude, 2026-10-05).** Landed as written, with two changes: a test line that did
not compile (a locator string that can be null), and the swipe actions widened from 72 to 84dp
so "Bookmark" stays on one line. Gate green (1,396 tests, 17 new). Seen on the emulator with the
demo's one-chapter work: the menu's Find in Work, the empty state, results under "This Chapter
(Ch. 1)" with the match in bold, the no-results text, a tap that jumps and closes, the three
swipe actions, and Bookmark storing one bookmark without moving the reader. Not seen: a work
with several chapters (the demo has none with matches in more than one), more than 200 hits,
and the sheet in the reader's Sepia and Dark themes. The three gaps listed under "Remaining
engine/reader work" stand; the one a reader can meet is that tapping Bookmark twice on the same
result stores two bookmarks, where iOS returns the first.

| iOS behavior (code inspected first) | Android capability before this change | Implemented / missing |
|---|---|---|
| Searchable-publication gate | `ReaderSearch.isAvailable` already wraps Readium's `isSearchable`; fan pill ignored it | Find pill now uses the gate |
| Reader-themed sheet, title, focused search field, Clear, Done | Display sheet already supplies reader `KudosTokens`; old Find used app Material colors | Separate `ReaderSearchSheet.kt`; reader palette for container, field, text, separators, indicators, and actions; shared `ToolbarCircleButton` |
| Scope selector | **Not present in the supplied iOS source** | None added; iOS code wins over the brief |
| “This Chapter” | Android has normalized `ReaderSection`s and live locator href | Current href matched against the same section keys as results; current group pinned first, with the iOS suffix |
| Chapter-grouped results, other chapters ascending; unknown hits retained | Existing section builder and locator href provide everything needed | Plain Kotlin `ReaderSearchGrouping`, including unknown bucket `-1` / “This Work” |
| Type-to-search after 350 ms; keyboard Search; empty queries excluded | Existing Readium search service; old sheet required its button | Debounce, keyboard submit, Clear; trim query and skip whitespace/empty; **one-character queries allowed, as in iOS** |
| One iterator call at a time; first page eager, further pages on scroll | Android `SearchIterator.next()` / `close()` already available; old wrapper accumulated 200 hits | One coroutine owns each iterator, appends stable integer IDs, loads near the last five appended hits; removed the 200-hit truncation |
| Auto-page toward current chapter, bounded at 40 extra pages, pending group/spinner | Same per-resource iterator and section keys | Ported; after the bound, further pages require visible near-end rows, as in iOS |
| Initial progress, idle instruction, no-results view, search failure; retain hits after paging failure | Old sheet had loading text and “No matches.”; discarded engine failures | All states implemented; iOS literal strings and the iOS 26.5 system English no-results copy |
| Optional section title, emphasized match with surrounding sentence/context; five-line row; leading context clipped to 70 characters | Locator already holds `title`, `text.before`, `highlight`, `after` | Displays available context, bold match, five lines, clipped leading context only. **Android's StringSearchService returns bounded word context, not a guaranteed whole sentence; full-sentence recovery requires engine/extractor work** |
| Tap / trailing Go / full-swipe Go jumps to passage, closes sheet | `ReadiumNavigatorController.go(Locator)` already supports passage anchors | Reuses it; trailing swipe reveals Go / Bookmark / Copy; accessibility custom actions provide all three without a gesture |
| Bookmark result without moving reader | `ReaderViewModel.addBookmarkAtProgress` → `AnnotationRepository.addBookmark` already exists | Built using that exact record path: `kindRaw = "bookmark"`, result locator in Android's compatible envelope, result progression and normalized spine index, section title |
| iOS bookmark helper fills missing `locations.position` and returns an existing bookmark at that position | Android's existing bookmark add path does not resolve positions or deduplicate; toggle uses progression proximity; fan state checks chapter membership | **Not synthesized.** Result bookmarking preserves Android's current bookmark semantics. Position-based matching/backfill and duplicate prevention need a reader/annotation matching change |
| Copy full returned passage, with no display-only ellipsis | Locator supplies original before/match/after; Compose clipboard exists | Built; copies unmodified engine-provided context |
| Reset/cancel when sheet closes; query changes replace scan | Old ViewModel jobs were not retained or canceled | Sheet owns the session; edits cancel before debounce, dismissal/Go/Done/disposal cancel; canceled late results cannot publish; iterator closes in its owner's `finally` |

Sources: supplied iOS lane, HEAD `d0b85f4f`, files `Features/ReaderReadium/ReaderSearchView.swift`, `ReaderSearchGrouping.swift`, `ReadiumReaderView.swift`, `ReadiumBook.swift`, and `KudosTests/ReaderSearchGroupingTests.swift`. Line references below are to those inspected iOS files. Only this Android worktree was edited; no Gradle, sign-in, AO3 contact, commits, pushes, branch changes, TASKS edits, Room schema changes, or backup-format changes.

The brief and source disagree: iOS has **no scopes** and accepts **one-character queries** (`ReaderSearchView.swift:125–126,247–258`). “This Chapter” is a result group, not a search restriction. Two iOS comments still say descending/most recent first; the grouping implementation and actual test assertions say **ascending**, which this port follows.

Both readers run Readium full-text search over the opened publication. iOS uses `publication.search(query:)` and its `SearchIterator`, storing each returned `Locator` plus append index (`ReaderSearchView.swift:35–64,116–139,190–223`). Android uses Readium Kotlin 3.3.0's `publication.search(query)` and `SearchIterator.next()`, returning `Try<LocatorCollection?, SearchError>`; results now retain each actual `Locator` plus append index. The cached toolkit's `SearchIterator`, `SearchServiceKt`, `SearchError`, `Try`, and locator symbols were inspected directly. No second text index or AO3 request was introduced.

Jump path: iOS sheet calls `book.go(to: locator)` and closes its panel (`ReadiumReaderView.swift:1624–1628`); `ReadiumBook.go(to:)` delegates to the navigator (`ReadiumBook.swift:609`). Android's sheet passes the same returned locator to `ReadiumNavigatorController.go(locator, animated = true)`, then cancels the session and hides the sheet.

Bookmark path: the existing reader toggle calls `addBookmarkAtProgress` when adding, which calls `AnnotationRepository.addBookmark`. Search calls that same add method, without using or moving the live reader position. `ReadiumProgressAdapter.toReaderProgress` supplies the locator envelope and progression; the result's href is normalized to the section's spine index. The record's selected-text snapshot remains empty, matching the existing reader add action and iOS's bookmark constructor. The locator itself retains the match/context for a passage jump. iOS's extra position resolution/deduplication is in `ReadiumReaderView.swift:767–824`; it is not part of Android's existing add call and is listed as a gap above.

Every user-visible string before → after (including accessibility-only labels):

| Surface | Before | After / iOS source |
|---|---|---|
| Fan pill | `Find in Work` | `Find in Work` (unchanged) |
| Sheet heading | `Find in work` | `Find in Work`; iOS sheet title / field |
| Field label/placeholder | `Search` | `Find in Work` (`ReaderSearchView.swift:287`) |
| Separate submit button | `Search` / `…` while loading | Removed; keyboard Search submits, matching `.submitLabel(.search)` (`:289`) |
| Initial loading | `Searching…` | Spinner; no authored text (`:325–326`) |
| Pending current-chapter group | Absent | `This Chapter`, `Searching…` (`:362–365`) |
| Idle title/instruction | Absent | `Find in Work`; `Search the text of this work. Tap a result to jump to that passage.` (`:321–324`) |
| No results | `No matches.` | `No Results for “<query>”`; `Check the spelling or try a new search.` (`:334` calls the system search empty state) |
| Search failure | Absent | `Couldn't Search` + actual engine/error message (`:328–330`) |
| Clear control | Absent | `Clear search` (accessibility, `:307`) |
| Done control | Absent | `Done` (accessibility, `ReadiumReaderView.swift:1641`) |
| Current story chapter | Absent | `This Chapter (Ch. <storyChapterIndex>)` (`ReaderSearchGrouping.swift:55–57,70–72`) |
| Current front/back matter | Absent | `This Chapter (Preface)`, `This Chapter (Summary)`, `This Chapter (Afterword)` (`:73–75`) |
| Other current section / chapter with no number | Absent | `This Chapter` (`:71,76`) |
| Other groups | Absent | Actual section title, or `This Work` for an unmatched resource (`:59`) |
| Row title | Actual locator title | Actual locator title (unchanged; `ReaderSearchView.swift:397–401`) |
| Row passage | 40-character tail/head, synthetic leading/trailing `…`, collapsed whitespace | Actual before/match/after; only a long leading context gets `…` + last 70 characters; bold match (`:42–50,405–412`) |
| Row actions | Absent | `Go`, `Bookmark`, `Copy` (`:425,432,439`), also accessibility actions |
| Clipboard content | Absent | Actual unmodified before + match + after (`:61–63`) |

The no-results strings are system-generated in iOS, not literals in its sheet source. Their exact English spelling and curly quotes were read from the installed **iOS 26.5** `SwiftUI.framework/en.lproj/Localizable.strings`: `ContentUnavailableView_Search_Text %@` and `ContentUnavailableView_Search_Secondary_Text`. Android keyboard/system accessibility announcements remain platform-provided.

Grouping rules and their iOS authority:

| Rule | iOS `ReaderSearchGrouping.swift` | Kotlin |
|---|---|---|
| Empty input → no groups | 27 | Early return |
| Normalize section href keys with the existing section builder; last duplicate key wins | 29–32 | `associateBy` using `ReaderSectionBuilder.hrefKey` |
| Extract already-normalized result key; bucket by matched spine index | 36–43 | `groupBy`; caller uses the same href normalizer |
| Preserve hit order within a bucket | 43 | Kotlin `groupBy` preserves input order |
| Unknown resource → bucket `-1`, never dropped | 37–38,59 | Same bucket and `This Work` title; sorts before known chapters unless the current chapter is pinned |
| Current spine index first, all others ascending | 46–51 | Comparator with current-first priority, then integer index |
| Current title → `This Chapter` + honest suffix | 55–57,68–76 | Story chapter number, named Preface/Summary/Afterword; no invented chapter number for OTHER or a null story index |
| Other title → section title or `This Work` | 58–61 | Same fallback |

The live current chapter is href-matched, following `ReadiumReaderView.swift:755–757,1615–1623`, rather than assuming a positions-array chapter index equals the section index. Existing Android `ReaderSectionBuilder.hrefKey` strips path prefixes/fragments and folds case; no second normalizer was added.

Tests and verification:

- `ReaderSearchGroupingTests.kt`: the six iOS names are retained: `currentChapterIsPinnedFirstRegardlessOfIndex`, `currentChapterSuffixNamesAO3FrontAndBackMatterHonestly`, `remainingChaptersAreAscendingWhenNoCurrentChapterMatches`, `multipleHitsInOneChapterStayInOneGroup`, `unmatchedHrefStillSurfacesRatherThanBeingDropped`, `emptyResultsProduceNoGroups`. Two extra tests check normalized path/case/fragments, hit order, duplicate keys, and a chapter with no story number. The ascending test also uses shuffled hits and an unmatched current index.
- `ReaderSearchModelTests.kt`: eight tests exercise empty/one-character queries and debounce replacement; cancellation with a deliberately late old page; dismissal during debounce/in-flight scan; serialized near-end requests; automatic current-chapter coverage past 200 hits; the first-page + 40-extra-page bound and on-demand continuation; initial versus paging failure; and grapheme-safe context display (including joined emoji) versus unmodified Copy. They drive the production model through Readium's real iterator interface.
- `AnnotationTombstoneTest.searchResultBookmarkUsesReaderBookmarkRecordAndCompatiblePassageLocator`: added real Room/repository coverage for bookmark kind/work/target progression/spine/title and compatible locator round-trip with match/context. **Not run here; Claude must run it with the app suite.** It covers the persistence boundary, not a UI tap.
- Direct Kotlin 2.3.21 compiler with the real Compose compiler plugin, cached Android/Compose/Readium libraries: the extracted sheet, search model, grouping, existing section/palette support, and both new test suites compile. This is a focused compiler check, **not a full app build**; `ReaderScreen`, `ReaderViewModel`, and the Room suite still require Claude's normal build/test gate.
- Offline JUnit/Robolectric execution: **16 tests passed** (8 grouping + 8 search model). No Gradle or network resolver was used. Temporary compiler outputs were removed.
- `git diff --check` passes. UI has not been seen on an emulator, so visual correctness is not claimed.

Remaining engine/reader work, without substitutes:

1. Whole-sentence boundaries beyond the context returned by Android's `StringSearchService` require extraction/search-service work. Rows and Copy use only the real locator context available now.
2. iOS's exact position-based bookmark matching/backfill/idempotence requires an Android reader/annotation matching adaptation. Repeated Bookmark taps currently follow the existing add path and can create multiple records; the fan's bookmark indicator remains its existing chapter-based check. No positions are invented.
3. A chapter-only search restriction/scope would require an engine filtering/search design; neither supplied iOS UI nor its search options implements it. This port does not introduce a selector with false semantics.

Emulator checklist for Claude / human (offline local EPUB only):

- [ ] Use an EPUB with matches in several chapters. Open from the fan's `Find in Work` pill; keyboard focuses the field. Type and pause; see grouped matches, optional titles, bold match, readable context, and no duplicate row keys even when nearby hits have identical text.
- [ ] Repeat in the reader's **Light, Sepia, and Dark** themes while the app uses a different theme. Check sheet background, heading/Done, field/clear/cursor, group bands, passages, separators, spinners and swipe actions. Sepia controls should use the reader's warm tint. OLED is an additional useful check.
- [ ] Start in a later story chapter; verify `This Chapter (Ch. N)` comes first and remaining chapters ascend. Test Preface, Summary and Afterword to confirm their honest suffixes. A current chapter with no matches must not become a fake result group; while paging toward it, it may show the iOS pending placeholder.
- [ ] Use a common one-letter query and an EPUB with over 200 early hits. Confirm current-chapter auto-paging stays bounded and scrolling brings more hits; typing, page turns and closing remain responsive.
- [ ] Change queries quickly, Clear during a scan, close by Done/back/drag, and reopen. Confirm old hits/spinners do not return and the new sheet starts clean. Submit via the keyboard too. Whitespace/empty must never scan; a one-character query must scan.
- [ ] Tap a result from another chapter; confirm it lands at the actual matched passage and closes the sheet. Repeat with trailing Go and full-swipe Go. Check horizontal actions against vertical list scrolling, large text, and TalkBack custom actions.
- [ ] Swipe a result, tap Bookmark **without jumping first**, then open Bookmarks & Highlights. Confirm the bookmark is in the result's chapter, with its title and target progression. Reopen the work, select that bookmark and confirm the passage anchor still navigates. A bookmark must not appear at the previously live reader position. Duplicate prevention is the documented gap above.
- [ ] Copy a long-context result and inspect pasted text: it must contain the real engine passage, without the UI's added leading ellipsis. Paste it into Find and check behavior with the existing engine.
- [ ] Use a query with no matches; check `No Results for “<query>”` and the spelling/new-search instruction. Check empty/idle presentation separately and inspect a local unreadable-resource failure if a fixture permits it.
