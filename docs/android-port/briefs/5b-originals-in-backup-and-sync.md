# Brief 5b: a converted import's original travels with the backup and the sync folder

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; don't change Room schemas or migrations. Don't edit `TASKS.md`. Your sandbox can't run
Gradle; Claude builds and tests afterwards, so make it compile by reading the real symbols you use.

The owner's rule: a backup must round-trip with nothing lost. Today the original file of a
converted import (a PDF, HTML, text or ZIP the reader imported, kept so the work can be rebuilt by
a newer converter, and often the last copy of the work there is) does not survive Android:

- iOS writes `Originals/<UUID>.<ext>` and `Originals/<UUID>.conversion.json` into a `.kudosbackup`
  archive (`kudos-ao3-reader/Services/KudosBackupExport.swift`, about lines 150–165) and into the
  sync folder (`Services/FolderSyncService.swift`: `originalsSubdirectoryName`, the last loop of
  `readChangedRemoteAssets`, `removeOrphanedOriginals`).
- Android's importer drops every archive entry that is not the manifest, `Works/` or `Fonts/`
  (`backup/BackupImporter.kt`, the `else -> Unit`). `KudosBackupPackage` has nowhere to carry them,
  the exporter writes none, and folder sync never looks at `Originals/`.
- Android's own originals (`files/WorkFileStore.kt`: `writeOriginal`, `readOriginal`, stored as
  `originals/<uuid>.<ext>`) are not in its backups either. Android to Android loses them too.

This is not a format change: it is iOS's existing layout, which Android does not yet read.

The iOS lane is `/Users/cidy02/kudos-ios-polish`. Read first:

- iOS: `Services/KudosBackup.swift` (`originalFiles`, `originalFileNames`, `originalData(named:)`,
  and the restore loop that ends in `restoredOriginals += 1`, about lines 3320–3365);
  `Services/Storage.swift` (`originalDocumentURL`, `existingOriginalDocumentURL`);
  `Services/WorkConversionRecord.swift`.
- Android: `backup/BackupImporter.kt`, `BackupExporter.kt`, `KudosBackup.kt`
  (`KudosBackupPackage`), `BackupRepository.kt` (`applyMergeResult`, the export path),
  `BackupMergeService.kt` (`workIdRemap`), `SyncRepository.kt`, `files/WorkFileStore.kt`.
- `docs/android-port/briefs/5a-result.md`, for how the sync folder's EPUBs were brought to iOS's
  names and rules. Originals need the same care.

## Do this

1. **Carry them.** `KudosBackupPackage` gains the original files by name (default empty). The ZIP
   importer and the directory importer collect entries under `Originals/`, with the name checked
   the way iOS's `isSafeFileName` checks it and the same per-entry size limit other entries have.
2. **Restore them, by iOS's rule.** A name is `<workID>.<ext>` or `<workID>.conversion.json`. The
   work must be one this restore brought in or matched (use the merge's id remap: the file is
   written under the local work's id). Never over an original already here, and never beside one:
   a work has one original, whatever its extension. A conversion record is written only if there
   is none.
3. **Export them.** Every work in the snapshot that has an original: `Originals/<UUID>.<ext>`.
   Android keeps no conversion record of its own. Store the one that arrives byte for byte and
   write it back out; don't invent one, unless you port `WorkConversionRecord` (say which).
4. **The sync folder.** Sync-up writes them. Sync-down reads one only when this device holds no
   original for that work. Prune as iOS's `removeOrphanedOriginals` does: by work id, without
   regard to letter case, and only when the prune of EPUBs is allowed.
5. **Letter case.** iOS names with capitals (`uuidString`); Android stores lowercase. Compare
   without regard to case, and write iOS's.

## Tests

- Android to Android: a backup of a work with an original, restored into an empty library, has
  the original.
- The golden archives: seed one work with an original and its conversion record in iOS's
  `CrossPlatformBackupTests`, regenerate (`TEST_RUNNER_KUDOS_WRITE_GOLDEN=1`), and make Android's
  `CrossPlatformRestoreTest` assert it arrives and is written back out
  (`-Dkudos.writeGolden=true`). Then the sync folder's goldens the same way
  (`CrossPlatformFolderSyncTests`, `SyncRepositoryTest`).
- A work that already has an original keeps it, and gains no second one, when the archive carries
  a different one.

## Result

Write `docs/android-port/briefs/5b-result.md`: what changed; each iOS rule and the Android test
for it; whether the conversion record is passed through or ported; anything you could not
determine from the code.
