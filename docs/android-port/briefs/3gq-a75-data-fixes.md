# Brief 3gq: the data and reader findings from A75

**Write code in this worktree only; do not commit, push, switch branches, sign in, run Gradle or
contact archiveofourown.org.** Claude builds, tests and lands it. Do not edit `TASKS.md`. Create
`docs/android-port/briefs/3gq-result.md` FIRST and write each item into it as you finish it:
**fixed / not changed (why)**, Android `path:line`, the iOS `path:line` you followed, the test, and
**what you would expect the test to do if the fix were reverted** (it must fail).

Your own audit A75 (`/Users/cidy02/kudos-android-lane/docs/android-port/audits/A75-result.md`,
"Differs and absent, ranked", with Claude's triage at the foot) has the evidence. Re-read the code
before changing it. iOS: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` and its tests in
`/Users/cidy02/kudos-ios-polish/KudosTests/`. Rules that hold everywhere here:
`docs/DATA_AND_PERSISTENCE_INVARIANTS.md` (read it first); Room migrations additive only, never
edit a released one; the backup manifest stays v8 with additive keys; nothing may lose a reader's
data on any path, including a failure halfway through.

1. **#2, the first place after opening a book.** `reader/ReaderProgressGate.kt` treats the first
   locator after the seed as the landing and drops it; iOS writes it (immediately or about two
   seconds later) and ignores an empty locator (`ReadiumProgressPersistence.swift`, tests
   `progressionPastThresholdIsWrittenAfterInterval`, `emptyLocatorIsIgnored`,
   `firstDifferentLocatorAfterSeedCanWrite`, `meaningfulChangeInsideWindowArmsTrailingWrite`).
   Follow iOS's rules exactly, including the empty-locator-with-spine case.
2. **#5 and #6, fonts restored beside a case-variant file.** Follow iOS's `-restored-N` naming
   and keep the reader's selected font on the original name (`KudosBackup.swift:3296`, `:3458`;
   `KudosBackupFontRestoreTests`, `FolderSyncTests.syncDownTreatsTwoLocalFiles…`). Never leave an
   orphan file without a row, never point the selection at a file the reader did not pick.
3. **#7, export of a book over 128 MB.** iOS allows 1 GB per entry (`MiniZip.swift:101`). Raise
   Android's per-entry limit to iOS's only if export streams each entry (no whole-entry byte array
   in memory); if it does not, say so and change nothing.
4. **#10, content hashes.** Fill `epubDigest` for an existing book at launch in small paced
   batches as iOS does (`PersistenceSync.swift:174`, `digestBackfillPerPass`), re-checked after
   the hash so an import finishing meanwhile wins, and write it into a backup's work entry as iOS
   does (`KudosBackup.swift:1027`) as an additive key that older readers ignore.
5. **#12 and #14, what a restore and a sync say.** The restore summary's sentence for a work whose
   promised EPUB never arrived (`IncompleteBackupReportingTests`), and the sync result's absorbed
   counts (restored works, suppressed and revived queues, ambiguous queue conflicts) as iOS's
   `FolderSyncResult.absorb` (`FolderSyncService.swift:47`), in the footnote where iOS shows them.

Tests: port iOS's named tests for each item as JVM/Robolectric tests (no `captureToImage`), with
the same cases. Existing tests that pin the old behaviour change with the fix; say which and why.
