# A58: iOS's reader, Browse and work-detail rules: does Android's code keep them?

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/A58-result.md`. **Leave no other file behind.** Do not edit `TASKS.md`.

The method of your A52 to A57. Android: `~/kudos-android-lane` at the dispatch commit
(read-only). iOS: `/Users/cidy02/kudos-ios-polish/` (read-only; `kudos-ao3-reader/`,
`KudosTests/`). **Write the priority list early and keep it current as you go**, so a usage
limit cannot leave it empty (A57 stopped before its list).

Read every `@Test` in these iOS files: `ReaderChapterScrubTests`, `ReaderControllerM8Tests`,
`ReaderPageMetricsTests`, `ReaderPageSampleTests`, `ReaderPageSkeletonTests`,
`ReaderProgressBridgeTests`, `ReaderSearchGroupingTests`, `ReaderSectionTests`,
`ReaderThemeTests`, `ReaderTimeEstimateTests`, `ReadiumProgressParityTests`,
`ReadiumReaderTests`, `SavedWorkProgressTests`, `AuthorNoteDetectorTests`, `HTMLTextTests`,
`TextChunkerTests`, `AO3WordCounterTests`, `WorkDetailPresentationTests`, `WorkOriginTests`,
`WorkStatLabelTests`, `WorkSearchIndexTests`, `WorkSelectionTitleTests`, `SeriesCreatorTests`,
`BrowseAndWorkDetailRulesTests`, `BlurbRequiredTagsTests`, `AO3FandomUnionTests`,
`AO3SummaryFilterRatingTests`, `AO3WorksSortTests`, `WorksSortFilterSheetTests`,
`FandomCatalogCacheTests`, `FandomCatalogSearchTests`, `FandomDisplayNameTests`,
`FandomFamilyTests`, `FilterSummaryLabelTests`, `CategoryChipTests`, `ResultSummaryTests`,
`AuthorNewestWorkStoreTests`. Skip the speech-engine files (Kokoro, TTS tuning).

For each test: quote its assertion (`file:line`), say in one line what it guarantees a reader,
then **kept** (quote the Kotlin, `path:line`; Android's own test if any), **missing** (quote the
code that breaks it; say what a reader sees wrongly or loses), **not applicable**, or
**unsure**. Without quotes on both sides it is **unsure**.

Weigh most: a reading place lost or wrong, progress or time-left figures that mislead, search
in a book that misses or misplaces results, a work's facts shown wrongly, a filter or sort that
returns other works than it says.

## Report

The priority list first (**the missing ones worth fixing first**, one line each, most harmful
first), then a table per test file. Say plainly where Android is right.
