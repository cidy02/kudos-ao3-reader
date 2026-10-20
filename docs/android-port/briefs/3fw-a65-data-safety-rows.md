# Brief 3fw: A65's data-safety rows (Android)

**Write code; do not commit, push, switch branches, sign in, run Gradle or contact
archiveofourown.org.** Claude builds, tests and lands it. Do not edit `TASKS.md`. Leave a result
file `docs/android-port/briefs/3fw-result.md`, written as you go: per row, **confirmed / already
fixed / not real** at this HEAD with `path:line`, what changed, the iOS rule followed
(`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`, read-only), the test added.

Hard rules: read `docs/DATA_AND_PERSISTENCE_INVARIANTS.md` first. Room migrations additive only
(none expected). Backup manifest v8, additive keys only. iOS is the source of truth. A fix may
never make a restore, Replace or sync lose a record or file iOS would keep. Android's ICU regex
rejects some JVM-accepted flags (`RegexPortabilityTest`).

Rows from `docs/android-port/audits/A65-result.md` §1 (an index that has been wrong before:
**confirm each first**, including against commit `2f00aa6a`, which changed Replace's pause):

1. **#96** Local file writes (EPUB, cover, original) are not held off while a backup Replace or a
   folder sync swaps files (`works/WorkFileStore.kt:42`; iOS
   `Services/PersistenceOperationGate.swift:18`). Route them through Android's persistence gate
   the way iOS's writers wait on `PersistenceOperationGate`, without a deadlock when a Replace
   itself writes files.
2. **#97** Sync may stay paused after a Replace that failed after pausing it
   (`backup/BackupRepository.kt:129`; iOS `Services/KudosBackupService.swift:612`). Follow iOS:
   what iOS does with the pause on failure, Android does. A pause the reader chose stays.
3. **#117** Backup import streams entries with `ZipInputStream` and never reads the central
   directory, so an archive iOS's MiniZip refuses (a broken central directory, a truncated
   ZIP64 extra) is admitted (`backup/BackupImporter.kt:34`; iOS `Reading/MiniZip.swift:10`).
   Validate the central directory / ZIP64 chain before anything is applied, refusing what iOS
   refuses, with iOS's message. Keep streaming (no size ceiling: T-139/T-140).
4. **#112** Temp files for EPUB metadata and backup staging use `java.io.tmpdir`
   (`works/EpubImportMetadata.kt:208`, `BackupImporter`). Put them in `context.cacheDir` and
   delete them on every path, failures included.

Tests for each confirmed row; for #117, a malformed-archive fixture refused before any write.
