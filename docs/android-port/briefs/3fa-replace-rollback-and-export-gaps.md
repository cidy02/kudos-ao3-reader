# Brief 3fa: a failed Replace leaves the library as it was; an export names what it left out (A52 #1, #8)

Rules (binding): work only in this worktree (`~/kudos-agent-codex`, branch
`android/agent-codex-3fa`, at the lane's HEAD named in the dispatch); don't commit, push, or
switch branches; never sign in and never contact archiveofourown.org; no stub files; no helper
scripts or `.orig` files left behind; **don't edit `TASKS.md`**. **No Room schema change and no
backup-format change** (the archive layout and manifest stay exactly as they are; both apps
read each other's). Your sandbox can't run Gradle: Claude builds, tests and commits afterwards,
so make what you write compile by reading the code around it. End with a short note,
`docs/android-port/briefs/3fa-result.md`: what you changed, file by file, what each test proves,
and what you could not check. Binding: `docs/DATA_AND_PERSISTENCE_INVARIANTS.md`.

Your A52 (`docs/android-port/audits/A52-result.md`) found both; Claude checked them in the code.

## 1. A failed Replace is all or nothing (A52 #1)

`backup/BackupRepository.kt` `applyMergeResultLocked` commits every row (Replace removes what
the archive lacks) in one transaction, then installs EPUBs and fonts one transaction each; a
late `orThrow()` (disk full, an unwritable file) ends the import with an error after the rows
are in. iOS (`KudosTests/KudosBackupTests.swift`
`failedRestoreLeavesNoSwiftDataMutationsVisibleAfterCallerAutosave`, in
`/Users/cidy02/kudos-ios-polish/`, read-only) leaves the library untouched when a restore
fails. Make Android's **Replace** do the same: when any file it must install cannot be
written, no row changes and no installed file remain. Choose the smallest sound design
(for example: write every file to a staging place before the row transaction and move them in
after it commits; or undo on failure). Keep what the current code protects: the per-file
checks against a row changed or deleted while the import ran (`removedMeanwhile`,
`deletedMeanwhile`, `mayRestoreEpub`), the `remoteEpubPending` flags, and fonts never
overwriting a different local file. Say what Merge and Reconcile do on the same failure and
whether that should change too (do not change them without saying why).

The screen already says, on failure, that the library may be partly replaced and names the
safety copy (`BackupScreen.kt`, landed in 3ez); once Replace is all or nothing, make that
sentence say only what is then true.

Tests: a Replace whose second EPUB write fails leaves every row and file as before (a fake
`workFileStore` that fails on demand; see how existing backup tests build one).

## 2. An export names the books it could not include (A52 #8)

`BackupRepository.exportV2ZipBytes` skips a work marked `hasEpub` whose file is missing or
empty, silently, so the reader believes the backup holds every book. iOS names them
(`IncompleteBackupReportingTests.theStreamingExporterNamesWhatItCouldNotInclude`). Return
what was left out alongside the bytes (keep `exportV2ZipBytes()` for the safety copy and for
sync, or change its callers; say which), and have the Backup screen's export message say how
many books were left out and name them (at most a few titles, then "and N more"). Fonts the
same, if a font row's file is missing.

Tests: an export with one book's file missing reports that book; one with none reports none.
