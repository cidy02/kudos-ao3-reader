# 3fa result

Implemented on `android/agent-codex-3fa` at `f7ea565e`; left uncommitted for Claude.
No Room schema, archive layout, manifest, or version changes.
Revised in place for **3fa-2**: atomic move-aside undo, crash-leftover recovery,
and natural singular/plural export wording replace the original hard-link design.

## Changes by file

- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupRepository.kt`:
  Replace holds one Room transaction through row refresh, guarded asset installs,
  and final flags. Any failure rolls back rows and undoes installed files; the
  per-file `removedMeanwhile`, `deletedMeanwhile`, `mayRestoreEpub`, pending-file,
  original/record, and font collision checks remain. Replace skips the preliminary
  tombstone re-sign migration (not needed for Replace's suppression policy), so
  even unmigrated tombstones stay unchanged on failure; launch and non-Replace
  imports still migrate. Added `exportV2Zip()` returning bytes plus missing/empty
  book/font names. `exportV2ZipBytes()` delegates and remains compatible for the
  safety copy and every existing byte-only caller, including sync-related tests.
  Production folder sync's separate asset/export path is unchanged.
  Before either public Replace import captures file state, it now repairs old
  asides under the persistence gate; the internal planned-apply entry repairs
  them too. `recoverInterruptedReplace` exposes the same gated repair to launch.
- `.../backup/BackupFileUndo.kt`: Replace-only file undo journal. `beforeWrite`
  atomically moves an existing file to `<filename>.kudos-replace-undo`; no hard
  links or full-file copies. Destination checks still precede the move.
  Rollback deletes the destination and atomically moves the aside back, or removes
  a newly created file. Originals, conversion-record deletion/writes, and fonts
  participate. Rollback runs before releasing Room on install errors and also
  covers transaction-commit errors. Successful commit deletes asides. Recovery
  scans works/fonts/originals: restore an aside if the destination is missing,
  otherwise delete the aside. A leftover aside cannot be silently overwritten.
- `.../backup/BackupExportResult.kt`: local receipt and export message: omitted
  book/font counts, three names per category, then `and N more`. Now uses
  `1 book was left out because its file is missing: A.` and
  `3 books were left out because their files are missing: A, B and C.`;
  fonts use the same singular/plural grammar. No transport keys.
- `.../backup/BackupScreen.kt`: manual export displays that receipt. Failed Replace
  says the library was not replaced and names the saved safety copy.
- `.../files/WorkFileStore.kt`: EPUB writer can be overridden by the failure fake;
  original/record paths are module-internal so undo covers their exact destinations.
  Works/originals directories are module-internal for recovery. `findOriginal`
  excludes undo asides so `writeOriginal` cannot mistake an aside (including an
  orphan conversion record's aside) for an original and delete it.
- `.../files/FontFileStore.kt`: fonts directory is module-internal for recovery.
- `.../KudosApplication.kt`: runs the gated repair at the start of the existing
  launch-repair coroutine, before `TombstoneLocalMigration` and deletion sweeps.
- `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupRepositorySafetyTest.kt`:
  Robolectric/Room tests below; uses the existing store on temporary directories,
  with a subclass that fails precisely the second EPUB write. Font apply tests
  intentionally use the internal already-planned apply entry, as existing backup
  tests do, to isolate installation from font decoding.

## Tests added (not executed here)

| Test | What its assertions prove |
|---|---|
| `secondEpubFailureRestoresOverwrittenBytesAndEveryRow` | ZIP Replace fails exactly at write two; full library snapshot, raw work rows, tags, omitted work, local link/tombstones, and all asset bytes/names return to their prior state, including old flags and removal of undo asides. |
| `secondEpubFailureRemovesNewlyInstalledBytesAndEveryRow` | Same failure with a new first book; its newly installed file and row disappear. |
| `lateFontFailureAlsoUndoesEarlierEpubAndRows` | A late font destination conflict restores an earlier EPUB and rows and preserves the blocking directory. |
| `replaceNeverOverwritesADifferentFontInstalledAfterCapture` | A different font arriving after planning is kept and reported deferred. |
| `successfulReplaceKeepsNewFilesAndDiscardsUndoAsides` | Successful Replace keeps archive bytes, soft-deletes omitted work, and leaves no undo/temp files. |
| `interruptedReplaceRestoresAsidesWithoutDestinations` | The launch repair restores deterministic asides without an in-memory journal, for EPUB, font, original and conversion record; a second sweep is harmless. |
| `interruptedReplaceDiscardsAsidesBesideDestinations` | The launch repair keeps installed bytes and deletes old asides for all four asset types; a second sweep is harmless. |
| `everyReplaceEntryRecoversInterruptedFilesBeforeWriting` | Package, ZIP and internal planned Replace repair a prior interrupted EPUB move; a new injected write failure then restores the old rows and bytes with no leftovers. |
| `mergeAndReconcileRetainTheirPartialApplyAndPendingFileFlags` | Both other modes still commit rows/earlier files on write two's failure, with the unwritten book marked `hasEpub=false`, `remoteEpubPending=true`. |
| `lateOriginalFailureUndoesEpubFontOriginalAndConversionRecordDeletion` | A second original's failure removes earlier new font/original files, restores EPUBs/rows, and restores an orphan conversion record deleted by the first original write. |
| `exportReportsTheBookWhosePromisedFileIsMissing` | A missing promised EPUB names its book; its metadata/promise remain in the readable archive. |
| `exportReportsEmptyEpubAndMissingAndEmptyFonts` | Empty EPUBs and missing/empty font files are reported by name and omitted from the archive's asset entries. |
| `completeExportReportsNoOmissionsAndIgnoresMetadataOnlyWorks` | An available EPUB is exported, metadata-only books cause no warning, and a complete receipt reports none. |
| `omissionMessageNamesThreeTitlesThenTheRemainingCount` | Five omissions show three titles and `and 2 more`. |
| `omissionMessageUsesSingularPluralAndNaturalListsForBooksAndFonts` | Exact message grammar for one through five books/fonts, including `A and B`, `A, B and C`, and truncated lists. |

Existing `BackupTrustPhase2Test` covers Replace's preserved-work, removed-download,
hard-deleted-work and untouched-asset checks. Those tests also need rerunning.

Merge/Reconcile intentionally retain partial apply: they do not replace the whole
library, and reconciliation persists pending-file flags for sync retry. Changing
their transaction scope would affect sync batching and concurrency; this brief
does not require that behavior change. They could gain atomic imports separately
with a deliberate sync policy and corresponding tests.

## Verification boundary

Read the surrounding Kotlin (including launch and file lookup paths); `git diff --check`
and whitespace checks of new files passed. No Gradle/build/tests, emulator/UI,
real disk-full, or Android filesystem verification was possible here. Claude must
build and run the new suite plus existing backup/sync suites and inspect the UI.
Device verification should exercise atomic moves and force-stop/relaunch recovery.
Reported failures roll back rows and files; after process death, recovery follows
destination existence, keeping installed bytes rather than rolling back the whole
library. The existing ungated file-writer race is unchanged. An exceptional failure
of undo retains its aside and is attached as a suppressed error; post-commit aside
cleanup is best-effort and retried by recovery. Sync may remain
paused after a failed Replace, as before. No sign-in, AO3 contact, helper scripts,
stub files, `.orig` files, `TASKS.md` edits, commits, pushes, or branch switches.
