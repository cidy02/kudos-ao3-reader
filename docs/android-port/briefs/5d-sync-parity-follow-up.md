# Brief 5d: sync and backup parity, what 5c left open

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind. **Don't change the backup format** (manifest version, key names, file and folder names).
One Room change is allowed, in part 1, with its migration and migration test; no other. Your
sandbox can't run Gradle or Xcode. Claude builds, tests and commits afterwards, so make what you
write compile by reading the real symbols you use, and say which claims need a test run.

**Android only.** iOS is the reference: read it at `/Users/cidy02/kudos-ios-polish/`, change
nothing there. If iOS looks wrong, say so in the result and leave it.

Write `docs/android-port/briefs/5d-result.md` as you go: for each part, what you changed, the
tests you wrote, and what you could not settle. You may be cut off; a finished part is worth more
than four half-done ones. Do the parts in order.

## Read first

- `docs/android-port/briefs/5c-landing.md`: what the code does now. It differs from your 5c
  patches in one rule, on both apps: **a sync always writes its manifest, and deletes nothing
  without a full view of the folder.** It never stops because a file is missing. Don't bring the
  "refuse to publish" guards back.
- `docs/android-port/DECISIONS.md`, the entries dated 2026-10-04.
- `android/app/src/main/java/io/github/cidy02/kudos/backup/SyncRepository.kt` as it is now.

## Part 1: `remoteEPUBPending`

iOS remembers that a work was promised an EPUB it has not received (`SavedWork.remoteEPUBPending`,
`Models/Models.swift`), and keeps saying `hasEPUB` in the manifests it writes
(`KudosBackup.swift`, search `remoteEPUBPending`: the export at about line 980, the restore at
about 2530; cleared in `WorkLifecycle.swift`, `WorkImporter.swift`, `ReadingQueueService.swift`).
Its sync-down fetches an EPUB only for a work whose manifest entry says `hasEPUB`
(`readChangedRemoteAssets`).

Android has neither. It exports `hasEPUB = hasEpub`, so a work whose EPUB it could not take is
published as having none, and an iPhone that reads that stops looking for the file. And it
fetches every listed work's EPUB that is in the folder whatever the flag says, so a download
removed on Android comes back at the next sync, which iOS does not do.

Port both, exactly as iOS does them:

- A Room column on the work (`remoteEpubPending`, default false), database version 13 to 14,
  the migration in `data/local/KudosDatabaseMigrations.kt`, and its test in
  `KudosDatabaseMigrationTest.kt`, in the style of the migrations already there. It is local
  state: it is not a manifest key.
- Set where iOS sets it (a restore that was promised an EPUB and received no usable bytes, and
  holds no file), cleared where iOS clears it (an EPUB is written; the download is removed; the
  work is deleted). Find every Android writer of `hasEpub` and every caller of
  `WorkFileStore.writeWorkEpub` / `deleteWorkEpub`, and say in the result which you changed.
- Export `hasEPUB = hasEpub || remoteEpubPending`, in the backup and the sync folder alike.
- The sync-down reads an EPUB from the folder only for a work whose entry says `hasEPUB`, as
  iOS's loop does. Keep everything else in `importManifest` as it is.
- Tests, named for what they prove: a work promised an EPUB that did not arrive is still
  published with `hasEPUB`; when the file arrives it is taken and the flag clears; a download
  removed here stays removed when no manifest says the work has one, and comes back when another
  device's manifest says it does (that is iOS's behaviour; confirm it in iOS's code and say
  where).

## Part 2: "kept" and "queued" follow the newer snapshot (5c finding F21)

`BackupMergeService.mergeWork` ORs `isSaved` and `isQueuedForLater` with the local flags even
when the incoming record wins, so a flag turned off on one device can never turn off on Android.
iOS takes the winning snapshot's flags (`KudosBackupService.apply` in `KudosBackup.swift`). Port
iOS's rule. The comment in `mergeWork` about not promoting a queue-only work to a library work
names a real bug: keep that protection, and read `docs/DATA_AND_PERSISTENCE_INVARIANTS.md` on
kept copies and reading copies before touching it. An EPUB on disk is never deleted by this
merge. Tests for: a flag cleared on the newer side clears here; a flag cleared on the older side
does not; a queue-only work stays queue-only; the EPUB stays on disk in every case.

## Part 3: Replace Library keeps collections and queues for 90 days (5c finding F29)

`BackupRepository.removeRecordsAbsentFromReplaceSnapshot` deletes collections and queues the
archive does not list. iOS soft-deletes them, recoverable for 90 days (`KudosBackup.swift`, the
Replace branch at about 3387 to 3412), and never touches the system queue. Port that with the
soft-deletion fields Android already has; no Room change. iOS also marks omitted annotations as
pending deletion: check whether Android's annotation rows can express that without a schema
change, and if they cannot, leave annotations as they are and say so. Tests: after a Replace,
an omitted collection and an omitted queue are in Recently Deleted with a date 90 days out, and
their memberships are still there to restore; the system queue is untouched.

## Part 4: a sync that fails in the background leaves a message

iOS stores its last sync error and clears it on success (`FolderSyncService`, `lastErrorKey`,
`recordError`, `recordSuccess`), and shows it on the Sync Folder page and as "Error" on the
Settings row (`Settings/SettingsRoute.swift`, about line 130). Android shows an error only after
a tap on Sync Now, from page state (`SettingsFolderSyncPage` in `settings/SettingsPages2.kt`,
`lastSyncError`). Store it in `SettingsRepository` beside `syncLastSyncAt` (a DataStore key, not
Room, and not part of the backup's settings payload), set and clear it in
`SyncRepository.runSync` for every caller, and show it where iOS does. Replace the page state
with it. A test that a failed run stores the message and the next successful run clears it.

## Part 5: one folder, written by both apps in turn

The golden folders prove one direction at a time: iOS reads a folder Android wrote
(`KudosTests/CrossPlatformFolderSyncTests.swift`), Android reads a folder iOS wrote (the golden
tests in `SyncRepositoryTest`, search `ios-sync-folder`). Nothing tests a folder both have
written to.

Add, on Android, a test that takes iOS's golden folder, syncs it from a device that has one work
of its own with an EPUB and an original, and checks the folder afterwards: iOS's two EPUBs and
its original are still there under the same names, Android's are added under iOS's naming, the
manifest lists all three works with `hasEPUB`, and nothing was pruned. With
`-Dkudos.writeGolden=true` (see how the existing golden test writes its fixture) it saves that
folder as a third fixture, `KudosTests/Fixtures/cross-platform/android-after-ios-sync-folder/`,
for an iOS test Claude will write. Describe in the result exactly what that folder holds.

## Not in this brief

The remaining 5c findings (F12, F19, F25, F26, F27, the F7 analogues), and anything on iOS. If
you see a data-loss bug on the way, write it at the top of the result and go on.
