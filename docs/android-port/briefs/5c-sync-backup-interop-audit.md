# Brief 5c: sync and backup, iOS and Android: full parity, and one folder for both

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind. **Don't change the backup format** (manifest version, key names, file and folder names)
or a Room schema: if a fix seems to need one, stop and describe it in the result instead. Your
sandbox can't run Gradle or Xcode. Claude builds, tests and commits afterwards, so make what you
write compile by reading the real symbols you use, and say which claims need a test run.

**Report first, fix second.** You may be cut off. Write `docs/android-port/briefs/5c-result.md`
as you go, the most severe finding first, and save it after each finding. A complete list of
findings is worth more than patches.

## The owner's goal, in their words

"Make sure Android and iOS sync/backup systems have full parity and are completely
interoperable. Looking for any bugs, especially data loss related ones. But also you should be
able to place a sync folder in cloud storage (say, Google Drive) and use iOS and Android devices
both syncing to the same storage without issue."

## Where things are

- Android: `android/app/src/main/java/io/github/cidy02/kudos/backup/` (`SyncRepository.kt`,
  `BackupMergeService.kt`, `BackupRepository.kt`, `BackupImporter.kt`, `BackupExporter.kt`,
  `BackupPaths.kt`, `TombstoneSigning.kt`, `TombstoneTrustStore.kt`, `PairingKeyCodec.kt`),
  `files/WorkFileStore.kt`, `files/FontFileStore.kt`, and where the folder is chosen:
  `settings/SettingsPages2.kt` (`SettingsFolderSyncPage`),
  `onboarding/SyncFolderOnboardingScreen.kt`. Tests: `android/app/src/test/.../backup/`.
- iOS, the reference, **read it at `/Users/cidy02/kudos-ios-polish/`** (the copy in this
  worktree is a little older): `kudos-ao3-reader/Services/FolderSyncService.swift`,
  `FolderSyncBackgroundTask.swift`, `KudosBackup.swift`, `KudosBackupExport.swift`,
  `PersistenceSync.swift`, `TombstoneSigning.swift`, `Storage.swift`,
  `WorkConversionRecord.swift`; where the folder is chosen (search for `fileImporter` and
  `FolderSyncService.connect`); tests in `KudosTests/` (`FolderSyncTests`,
  `CrossPlatformFolderSyncTests`, `CrossPlatformBackupTests`, `KudosBackupTests`,
  `PersistenceSyncTests`).
- What was done on 2026-10-04, by Claude, unreviewed: `docs/android-port/briefs/5a-result.md`
  and `5b-result.md` (what was fixed, what was left, a table of iOS's 65 sync tests against
  Android's), `docs/android-port/DECISIONS.md` (the entries dated 2026-10-04), and
  `docs/DATA_AND_PERSISTENCE_INVARIANTS.md`.

## Part A: review Claude's eleven commits

`docs/android-port/briefs/5-review-sync-backup.md` is that brief: its diff command, its table of
commits, and its six things to look for. Do it as written, except that the findings go into
`5c-result.md`.

## Part B: the two apps on one folder

Take one folder that an iPhone and an Android phone both sync to, and walk it through, in both
apps' code: first sync from each side; an edit on each side; the same work deleted on one and
edited on the other; both syncing at once; one device offline for a month; an app updated on one
device only; a restore from a backup on one of them. For each, what does each app write, read
and delete, and can the other misread it or delete what it should not?

Then the same folder **on a cloud provider instead of iCloud Drive or local storage**. Neither
app's code was written with that in mind. Check what each assumes about the storage it is given:

- **Can the folder be chosen at all?** Android asks for a folder with `ACTION_OPEN_DOCUMENT_TREE`;
  iOS asks its document picker for a folder. Claude's search found that Google Drive's Android
  provider does not offer folders to that picker, and that on iOS third-party providers
  (Drive, Dropbox, Box) are greyed out when an app asks for a folder: only the built-in
  locations work (On My iPhone, iCloud Drive, network shares, USB). Claude could not check this
  on a device. Say what the code needs for a provider to work on each side, which kinds of
  location can work on **both**, and what it would take to make Drive itself work.
- **Writes that are not atomic and arrive out of order.** Android replaces the manifest by
  writing a temporary file, renaming the live one to `manifest.json.bak`, then renaming the
  temporary one into place (`writeManifestAtomically`). Through a provider that uploads each
  step separately, another device can see a folder with **no** `manifest.json`. iOS treats a
  missing manifest as a first write (`performSyncUp`: `viewIsCurrent` is true when there is no
  manifest), writes its own, and prunes by it. iOS does not know `.bak`. Is that a way to lose
  the folder's EPUBs? What is the smallest change, on which side?
- **Conflict copies.** Android folds any `manifest*.json` beside the manifest and deletes it.
  iOS folds only `NSFileVersion` conflict versions, which only iCloud makes. What happens on
  each side to "manifest (1).json", to a provider's "conflicted copy" name, and to two files
  with the **same** name in one folder (Drive allows it)? And to a duplicated EPUB or font?
- **Dates and sizes.** iOS decides whether its view of the folder is current, and whether to
  read the manifest at all, from the manifest's modification date. Android compares the date
  before and after its own run, and an EPUB's size and digest. What if the provider reports no
  date, a date that changes on download, or no size?
- **Names.** EPUB names were the first bug found (letter case). Look for the next: Unicode
  normalisation of a font's file name between the two platforms, names that differ only in
  case on a provider that folds case, characters one side sanitises and the other does not.
- **A file that is still uploading**, or a placeholder for one not downloaded. iOS has code for
  iCloud's placeholders; what does each side do elsewhere?

## Part C: parity that is still open, as far as Claude knows

Confirm or refute each, and add what is missing from the list:

1. iOS looks an EPUB up, and prunes, by one exact name (UUID in capitals). Android 0.2.1 and
   0.2.2 wrote lowercase. Run against iOS's own code, such a folder reaches iOS **without its
   EPUBs** (`5a-result.md`). The owner wants full interoperability: iOS should find either case
   and never prune a listed work's EPUB under another case. (iOS already does this when
   restoring an archive: search `uuidString.lowercased()` in `KudosBackup.swift`.)
2. **Deletions across the two platforms.** A deletion travels as a signed tombstone and is
   adopted only from a device this one has paired with. Can an iPhone and an Android phone pair
   with each other (`PairingKeyCodec`, the QR and code formats, iOS's
   `TombstoneTrustStore`)? Do the two sign and verify the same bytes? If they cannot trust each
   other, a work deleted on one comes back from the other for ever.
3. Each app folds an older sync file of its own that the other ignores
   (iOS `KudosLibrary.kudosbackup`, Android `Kudos.kudosbackup`).
4. Limits differ: Android reads a whole archive into memory and caps an entry at 128 MB; iOS
   streams and allows 1 GB. An EPUB read from the sync folder has no cap on either side.
5. Android holds a record's clock to the date of the snapshot that carries it; iOS does so for
   tombstones only.
6. Android keeps the local EPUB when the clocks are equal; iOS takes the incoming one.
7. Android carries iOS's conversion record through and writes none of its own.
8. Anything iOS's manifest carries that Android drops, or the reverse. The golden archives
   (`CrossPlatformRestoreTest`, `CrossPlatformBackupTests`) compare a canonical form: check what
   that form leaves out (`canonical(...)` on each side), because a field left out of the
   comparison is a field nobody is watching.

## Fixing

For a bug you are sure of, write the smallest fix and a test for it, in this worktree:

- Android: under `backup/` (and `files/` where it must be), with a JVM test beside the existing
  ones. Cite the iOS file and function in a comment on each fix.
- iOS: edit this worktree's copy under `kudos-ao3-reader/` and `KudosTests/`. Claude ports it
  to the iOS lane and runs the suite there. Keep an iOS change small and say why iOS, the
  reference, is the side to change.

Leave alone anything that needs the owner to choose (a new storage provider, a format change,
dropping support for a released build): describe it.

## Result

`docs/android-port/briefs/5c-result.md`:

1. **Findings**, most severe first. For each: which app, the file and line, what is wrong, the
   concrete sequence (state, then input, then the wrong outcome), whether you are sure or it
   needs a test, and the fix (made, or proposed).
2. **Can one cloud folder serve both apps today?** A plain answer, then what stands in the way,
   in order.
3. **What you changed**, Android and iOS apart, with every file.
4. **For the owner to decide.**
5. **What you checked and found sound**, so it is clear what was covered.
