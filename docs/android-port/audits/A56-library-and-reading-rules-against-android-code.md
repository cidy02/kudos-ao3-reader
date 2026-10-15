# A56: iOS's Library, queue and reading-record rules: does Android's code keep them?

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/A56-result.md`. **Leave no other file behind.** Do not edit `TASKS.md`.

The method of your A52, A54 and A55, for what a reader keeps locally. Android:
`~/kudos-android-lane` at `0498ef2a` (read-only). iOS: `/Users/cidy02/kudos-ios-polish/`
(read-only; `kudos-ao3-reader/`, `KudosTests/`). Binding: `docs/DATA_AND_PERSISTENCE_INVARIANTS.md`.

Read every `@Test` in these iOS files: `LibraryFiltersTests`, `LibrarySortTests`,
`LibrarySectionKindTests`, `LibraryHistoryGroupingTests`, `FavoriteQuickFilterTests`,
`HistoryHideAndQueueNotesTests`, `KeepOfflineAndHomeShelvesTests`, `HomeSubscriptionsTests`,
`HomeUpdatePillTests`, `PreservedWorkTests`, `CollectionMembershipDeletionTests`,
`CollectionWorkPickerTests`, `QueueOrganizerSelectionTests`, `ReadingQueueTests`,
`ReadingQueueFactsTests`, `ReadingLogTests`, `ReadingStatisticsTests`, `ReadingInsightsTests`,
`ReadingAffinitiesTests`, `WorkReadingPositionTests`, `ReadiumLocatorPreservationTests`,
`ReadingAnnotationMatchingTests`, `AnnotationNotePreservationTests`, `WorkTagsTests`.

For each test: quote its assertion (`file:line`), say in one line what it guarantees a reader,
then **kept** (quote the Kotlin, `path:line`; name Android's own test of it if there is one),
**missing** (quote the code that breaks it; say what a reader loses or sees wrongly), **not
applicable** (say which feature Android lacks), or **unsure**. Without quotes on both sides it
is **unsure**.

Weigh most: anything a reader loses (a note, a highlight, a reading place, a queue's order or
membership, a work kept offline, a recently deleted item purged early), counts and statistics
that are wrong, and Hide mode showing what it should hide.

## Report

A table per test file, then **the missing ones worth fixing first**, one line each, the most
harmful first. Stop where you run out of time and say where. Say plainly where Android is right.
