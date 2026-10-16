# Brief 3fl result

Implemented all 13 requested findings, in the brief's order. **Not built or run under Gradle**: Claude owns compilation, JVM/Compose tests and commits. No visual correctness claim.

## Lane and constraints

- Worktree: `/Users/cidy02/kudos-agent-codex`; branch: `android/agent-codex-3fl`.
- HEAD remains `ced5d49d1d5eda03f1334f45dd1a2cdfcdc8d0c4`; clean at start; changes intentionally uncommitted.
- No commits, pushes, branch switches, sign-in, AO3 requests, Gradle invocation, helper scripts, `.orig` files or stubs.
- `TASKS.md`, Room entities/schema and backup format are untouched. Added SavedWork properties are computed only.
- Compared against the read-only iOS worktree `/Users/cidy02/kudos-ios-polish` and read `docs/AO3_NETWORKING_POLICY.md` before editing.

## Confirmations and fixes

Each finding was confirmed in Android code before its fix; none of the requested findings was dismissed as unreal.

| Brief order / A58 | Confirmed Android fault and resulting behavior | Ported assertion / coverage |
|---|---|---|
| 1 / #1 | `FandomListChrome.FamilyBlock` sent `first.fandom`. The family callback and `Routes.browseWorks` now carry every raw sibling into `FandomWorksScreen` and `AO3BrowseRepository.worksForFandoms`. Numeric IDs resolve sequentially through the existing paced client, then **one** search uses `filter_ids:(A OR B)`, clears the intersecting fandom field and retains the reader's filters. Single-tag destinations keep their existing listing endpoint. IDs are reused in a bounded 128-entry cache. | `AO3FandomUnionTest` ports the iOS grouped/single/empty/deduplicated clauses, authoritative feed controls, exact sidebar fallback, invalid IDs/tag types/hosts, and URL assertions. `AO3BrowseRepositoryTest` checks ID reads → one search, filter retention, pagination/cache reuse, and unresolved siblings. `RoutesNavigationTest` covers all sibling names and special-character round trips. |
| 2 / #2 | `WorkDetailScreen` always said Last Copy for unavailable works. Derived `SavedWork.preservationBadge` now says Last Copy only with `hasEpub`; otherwise Unavailable. | `WorkDetailFiguresTest.lastCopyRequiresAnEpub` ports `WorkOriginTests` last-copy/unavailable/ordinary states. |
| 3 / #3 | `WorkDetailUiState` preferred local words/kudos/comments/hits. `WorkDetailFigures.preferred` now prefers remote figures, including a printed zero; absent remote figures fall back to positive local ones. Bookmarks use the same rule. | `WorkDetailFiguresTest.fresherRemoteFiguresWinIncludingPrintedZero` ports `BrowseAndWorkDetailRulesTests.workDetailPrefersTheFresherRemoteFigure`. |
| 4 / #4 | `ReadiumTocAdapter.sections` flattened children into the shared builder's last-write-wins map. Adapter-level deduplication now preserves the outermost title/classification for a shared spine item. The shared builder's existing semantics remain intact. | `ReadiumTocAdapterTest` ports outer-title/numbering, Afterword-excluded totals and distinct deeply nested children from `ReadiumReaderTests`. |
| 5 / #5 | `SCROLL_EXTENT_SCRIPT` admitted complete blank documents and tiny windows; `ReaderViewport.scrolled` admitted tiny positive extents. Sampling now requires a body child, window width/height ≥32, and extent ≥32. | `ReaderPageSampleTest` ports the iOS body/window guard assertion and checks tiny/nonfinite metrics. Local Node execution of the actual script checked absent/empty bodies, narrow/short windows, and a valid sample. Real WebView execution remains pending. |
| 6 / #6 | Saved-work UI passed its default `false` directly. Computed `SavedWork.knownCompletion` uses the existing AO3 identity index; undeclared non-AO3 status is null/Unknown, while AO3 false and declared true remain known. Wired through saved rows/cards, Home, Library, queues, collections and detail. | `WorkCompletionImportTest` ports `WorkStatLabelTests` AO3/import status assertions; `WorkStatsTest` expects Unknown for unknown completion text. No stored completion field changed. |
| 7 / #8 | Empty reader sections returned null; chapter lookup required an exact position. Empty/out-of-range sections now target chapter 1, explicit null still means no chapter request, and chapter-index positions clamp first/last (empty/unavailable index remains null). | `ReaderSectionBuilderTest.commentsFallbacksKeepAChapterWhenSectionsAreMissing` and `AO3ChapterIndexRepositoryTest.chapterPositionsClampToTheFirstOrLastChapter` port `ReaderSectionTests`. |
| 8 / #9 | Both Later-removal paths and Remove from Library cleared local state without dismissal. Shared `applyRemoval` now keeps surviving local records, shows an existing/reconstructed AO3 summary for deleted AO3 records, or invokes the navigation dismissal callback for deleted source-less records. | `WorkDetailPresentationTest` ports the iOS removal matrix and summary identity assertions. `WorkDetailSaveForLaterTest` adds Compose checks for source-less Library removal, source-less Later removal, and AO3 Later removal preserving a remote summary. New/modified test works use a fixed millisecond dateAdded. |
| 9 / #10 | `CommentComposerSheet` subtracted UTF-16 length. `remainingCommentCharacters` now counts Unicode code points; cursor offsets remain UTF-16 as required by Compose. | `CommentBudgetTest` ports the iOS joined-emoji, empty and exact-limit assertions, plus supplementary-plane and over-budget boundaries. |
| 10 / #15 | More actions always said Add to Queue/Collection. `WorkDetailPresentation.queueLabel` and `collectionLabel` name active membership counts, including Saved for Later in queues. | `WorkDetailPresentationTest.queueAndCollectionLabelsPluralize` ports zero/singular/plural assertions, including In 2 Queues. |
| 11 / #17 | `ReaderProgressDisplay` dropped malformed chapter labels when `storyChapterIndex` was absent. It now uses chapter 1 and retains the total-floor behavior. | `ReaderProgressDisplayTest.malformedChapterSectionFallsBackToChapterOne` ports `ReaderTimeEstimateTests.chapterSectionMissingItsIndexFallsBackToOne`. |
| 12 / #18 | Both series edit gates compared accounts directly without trimming or orphan exclusion. Shared `isSeriesCreator` trims and compares account identities case-insensitively, excludes orphan_account, and is used on the series screen and author-profile series rows. `ao3CreatorUsernames` excludes orphan identities at parsing too. | `SeriesCreatorTest` ports pseud/account distinction, whitespace/case, orphan, empty/signed-out and co-creator assertions from `SeriesCreatorTests`, plus offsite-link rejection. |
| 13 / #14 | `WorkDetailFactsCard` displayed raw dates. Both Published and Updated now use `WorkDetailDates.displayDate`: strict ISO/search-blurb parsing to MM/dd/yyyy, unrecognized text preserved. | `WorkDetailDatesTest` ports the three iOS display-date assertions and adds invalid-date/empty cases. |

### Deliberate union failure behavior

Unlike iOS's older intersection fallback, an unresolved sibling ID returns a parse error with Try again instead of presenting an incomplete/intersected answer as the family. No partial union/search is sent. A transport refusal also stops resolution immediately. No new request fan-out, retry loop, UA, pacing rule or authenticated scraping path was added.

## Verification actually performed

- `android/Scripts/check-invariants.sh`: **PASS** (UA identity/version, credentials separation, backup version and 600ms pace checks).
- `git diff --check`: **PASS**.
- Executed the actual sampling JavaScript in local Node VM with five mocked cases: **PASS** (absent body, empty body, width 31, height 31 all null; valid dimensions retain extents). This is not an Android WebView test.
- Static caller review covered family routing, both series edit gates, saved-work completion presentation and all three detail-removal entry points.
- Branch/HEAD rechecked; TASKS.md and persistence/backup files have no diff.

## Claude handoff

Run the Android debug build and unit suite, including new/extended tests above. Prioritize `RoutesNavigationTest`, `AO3BrowseRepositoryTest`, `ReadiumTocAdapterTest`, and `WorkDetailSaveForLaterTest` for integration/Compose compilation and behavior, then the full suite. Verify family pagination/filter reset, unknown import status, Last Copy/Unavailable badges, formatted dates, membership labels, removal navigation, and blank/resize page sampling visually on Android. Keep AO3 traffic/sign-in prohibited for this brief; fixtures/fakes suffice for automation.

## Deferred as requested

A58 #7, #11, #12, #13, #16, #19 and #20 remain unchanged: system media time estimates, semantic note markup, sentence chunking, status colours, Dark background tokens, skeleton sizing and alias italics. No additional deferred fix was assessed as safe enough to include. There is no unfinished requested item; build/test/device validation remains Claude's responsibility.
