# Brief 5f: Replace Library's sweep, and fields Android does not know

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind. **Don't change the backup format** (manifest version, key names, file and folder names)
**or a Room schema.** Your sandbox can't run Gradle or Xcode. Claude builds, tests and commits
afterwards, so make what you write compile by reading the real symbols you use, and say which
claims need a test run.

**Android only.** iOS is the reference: read it at `/Users/cidy02/kudos-ios-polish/`, change
nothing there. If iOS looks wrong, say so at the top of the result and leave it.

Write `docs/android-port/briefs/5f-result.md` as you go. Do the parts in order; a finished part is
worth more than two half-done ones.

## Read first

- `docs/android-port/briefs/5c-landing.md`, all of it: what the sync and backup code does now,
  what was corrected in your earlier patches and why, and what is still open. Two rules from it:
  - **A sync always writes its manifest and deletes nothing without a full view of the folder.**
    It never stops because a file is missing.
  - **When a brief and iOS's code disagree, iOS's code wins.** Say so in the result; don't
    follow the brief.
- `docs/android-port/DECISIONS.md`, the entries dated 2026-10-04.

## Part 1: Replace Library's own sweep (the rest of 5c finding F7)

`BackupRepository.applyMergeResult` calls `removeRecordsAbsentFromReplaceSnapshot(snapshot)` for
a Replace Library import. That function reads the rows the database holds **now** and removes
every one the merged snapshot does not list. A row the reader made while the import ran is not
in the merged snapshot, so it goes:

- a saved link (bookmark) and a saved search are **deleted outright** (`deleteById`);
- a work, a collection and a custom queue go to Recently Deleted;
- a highlight or note is marked for deletion.

In 5c and 5e you fixed the same fault in `applyMergeResult` for saved searches, reading sessions,
favorites and watermarks: the merge names the rows it removed from the snapshot it was given
(`BackupMergeResult.removedSavedSearches` and its siblings, filled in `BackupMergeService`), and
the apply removes only those, and only if the row is unchanged since capture. Give Replace's
sweep the same rule for all six kinds it sweeps: it may touch only a row that was in the
captured snapshot and is absent from the result, and for the two outright deletions only if the
row is unchanged. Reuse the existing lists where they already cover a kind; don't sweep one kind
twice. Read how iOS's Replace branch decides (`KudosBackup.swift`, about lines 2700 to 2760 and
3387 to 3419) and say whether iOS can have this fault at all (its restore may not interleave
with the reader's edits).

Tests, in the style of `aSearchCreatedAfterSnapshotCaptureSurvivesTheApply`
(`BackupTrustPhase2Test`): for each of the six kinds, a row created after capture survives a
Replace; an unchanged captured row the archive omits is still removed (or sent to Recently
Deleted) exactly as today; a captured saved link or saved search the reader changed after
capture is kept.

## Part 2: a field Android does not know survives an Android sync (5c finding F16, the rest)

Today, when Android writes the folder's manifest, a **top-level** key it does not know is
carried over from the manifest it replaces (`SyncRepository`, the block that builds
`manifestJson + unknown`, and `knownManifestKeys`). A key it does not know **inside a record**
is dropped: the record is decoded into `BackupWork`, `BackupCollection` and the rest, and
written back from those.

Why it matters: iOS adds a field to a record in a later version. An older Android build on the
same folder rewrites the manifest without it. If Android's copy of that record is the newer one
(reading progress alone makes that common), iOS takes Android's record and the field falls back
to its default. Nothing warns anyone.

Carry them the same way the top-level keys are carried: for every record Android writes, find
the record with the same identity in the manifest this run replaces (`manifestBytesAtRead`,
only when `decodedLive != null`) and add the keys of that record that this build's type does not
have. The known keys of a type are its serializer's element names
(`BackupWork.serializer().descriptor`), so no list is kept by hand. Do it for every record list
in `KudosBackupManifest` (works, bookmarks, fonts, collections, savedSearches, readingQueues,
readingQueueMemberships, annotations, readingSessions, readingFavorites, fandomReadWatermarks,
tombstones). Identity is whatever the merge already uses for that kind (ids compared through
`BackupPaths.normalizeIdForComparison`; read how bookmarks, fonts and watermarks are matched and
use the same). Rules:

- A record Android does not write (deleted, tombstoned, pruned) takes its unknown keys with it.
- A known key is never overwritten by this step, whatever the old manifest says.
- A record that is not a JSON object, or a list that is not a JSON array, in the old manifest:
  carry nothing for it, and never fail the sync over it.
- A tombstone is signed. Check what the signature covers before adding a key to one; if adding
  an unknown key could break a signature check on either app, leave tombstones out and say so.
- Only the first level of a record. A nested object with an unknown key inside it is out of
  scope: say so in the result.

State plainly in the result what this does **not** cover: a `.kudosbackup` made on Android
(there is no old manifest to carry from), and fields Android wrote that iOS does not know (read
iOS's manifest types and list any such field you find; change nothing).

Tests (`SyncRepositoryTest`, with the existing `FakeTempDocumentsProvider` harness): a folder
whose manifest gives a work, a collection and a saved link each an extra key; after an Android
sync that also changes that work locally, the written manifest still has the three extra keys
with their exact JSON values, and the known fields carry Android's values; a record Android
deletes does not come back because of this step; a malformed record in the old manifest does not
stop the sync; a second sync is idempotent (bytes equal when nothing changed, so the
own-manifest digest skip still works).

## Part 3 (only if parts 1 and 2 are finished): the same font copied again on every restore

5c finding F8, what is left: restoring the same backup twice adds a second copy of a custom font
under a suffixed name, on both apps. On Android, when an incoming font's bytes are identical
(size, then SHA-256, `BackupPaths.sha256`) to a font this device already holds under the same
base name, don't write a second copy. Read how the font-colliding path names the copy first, and
keep every reference to the font pointing at a file that exists. One test: the same archive
restored twice leaves one font file. Say what iOS does and leave it.

## Not in this brief

Anything on iOS; findings F19, F25, F26 and F27 and the queued flag (they wait for the owner);
any screen. If you see a data-loss bug on the way, write it at the top of the result and go on.
