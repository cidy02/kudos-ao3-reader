# Brief 5e: sync and backup, the leftovers that need no owner decision

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind. **Don't change the backup format** (manifest version, key names, file and folder names)
**or a Room schema.** Your sandbox can't run Gradle or Xcode. Claude builds, tests and commits
afterwards, so make what you write compile by reading the real symbols you use, and say which
claims need a test run.

**Android only.** iOS is the reference: read it at `/Users/cidy02/kudos-ios-polish/`, change
nothing there. If iOS looks wrong, say so at the top of the result and leave it.

Write `docs/android-port/briefs/5e-result.md` as you go. Do the parts in order; a finished part is
worth more than three half-done ones.

## Read first

- `docs/android-port/briefs/5c-landing.md`, all of it. It says what the code does now, what was
  corrected in your 5c and 5d patches and why, and what is still open. Two rules from it that
  your patches broke before:
  - **A sync always writes its manifest and deletes nothing without a full view of the folder.**
    It never stops because a file is missing.
  - **When a brief and iOS's code disagree, iOS's code wins.** Say so in the result; don't
    follow the brief. (Brief 5d said iOS takes the newer snapshot's queued flag. It does not.)
- `docs/android-port/DECISIONS.md`, the entries dated 2026-10-04.

## Part 1: the queued flag follows queue membership (the rest of 5c finding F21)

iOS: the merge ORs `isQueuedForLater` (`KudosBackupService.apply`, `KudosBackup.swift` about
line 4508), and then `ReadingQueueService.normalizeAllQueuedWorks` (called at the end of every
restore, `KudosBackup.swift` about 3042) sets it from membership for every work that is in a
queue or still claims the flag: `work.isQueuedForLater = hasMembership`, and for a flagged work
with no membership the preservation status goes back to not preserved
(`ReadingQueueService.normalize`, about lines 318 to 349). A queue in Recently Deleted still
counts as a membership (`$0.queue != nil`).

Android ports only the first half (`normalizeQueuedWorks` in `backup/BackupMergeService.kt`: a
membership sets the flag). So a work taken out of its last queue on another device stays queued
on Android for good. Claude tried the second half and took it out again: older Android data
holds queued works that carry the flag and **no membership at all**
(`BackupCompatibilityTest.restoreKeepsAQueueOnlyWorkOutOfTheLibrary` is such an archive), and
cleared, those end up in neither the library nor a queue.

Do both, in this order:

1. **Give flag-only queued works a real membership.** A work that carries the flag and is in no
   queue, in the library on this device or in an incoming archive, gets a membership in the
   Saved for Later queue, the way `ReadingQueueRepository` adds one today (read how it creates
   and pins that queue; reuse it, don't write a second one). Decide where this runs so that it
   has happened before any merge clears a flag: say where, and why there. It must run once per
   work, not create a second membership on a later run, and not bring back a work the reader
   took out of a queue on purpose (that work's flag is cleared by `ReadingQueueRepository`
   already; check, and say what you found).
2. **Then port iOS's second half** into `normalizeQueuedWorks`, exactly as iOS does it,
   including the preservation reset for a flagged work with no membership, and leaving works
   that never claimed the flag alone (`BackupEpubPreservationPassThroughTest`).
   Replace Library needs care: a queue the archive omits now goes to Recently Deleted with its
   memberships (brief 5d part 3), and the merge's own snapshot no longer lists those
   memberships. Its works must stay queued while the queue can be restored, as on iOS.

Tests: a flag-only queued work in the local library gets one Saved for Later membership and
stays queue-only through two restores; the same for one that arrives in an archive; a work whose
last membership a paired device removed (a membership tombstone) loses the flag and its
preservation here; a work in a queue that Replace sent to Recently Deleted keeps the flag; a
work that never had the flag keeps a `preserved` status untouched; no EPUB is deleted by any of
it.

## Part 2: rows made while an import runs (5c finding F7, the rest)

In 5c you fixed saved searches: `BackupRepository.applyMergeResult` deleted every saved search
absent from the merged set, which included one the reader created while the import ran. It now
deletes only the rows the merge removed from the snapshot it was given, and only if they are
unchanged (`removedSavedSearches`). Reading sessions, reading favorites and fandom visit
watermarks are swept the same old way in the same function. Give them the same fix, with one
test each in the style of `aSearchCreatedAfterSnapshotCaptureSurvivesTheApply`
(`BackupTrustPhase2Test`). Replace Library's own omission sweep is a different thing: say in the
result whether it has the same fault, and leave it.

## Part 3: a conversion record that arrives without its original (5c finding F12)

`SyncRepository.importOriginals` takes an original and its record together, and only for a work
that holds no original. If the record arrives in a later sync than the original (the folder is a
cloud folder; files land in any order), or the original was over the limit, the record is never
taken: the work has an original by then, so its group is skipped. iOS fetches an absent record on
its own (`FolderSyncService.swift`, `readChangedRemoteAssets`, the originals loop, about lines
839 to 842), which can attach another device's record to a different local original.

Port the safe version: when this device holds an original and no record, and the folder holds
both for that work, take the folder's record only if the folder's original is the same file as
the local one (same size, then same SHA-256; `BackupPaths.sha256`). Read the folder's original
with the byte limit already used there. Tests: a record that arrives one sync after its original
is taken; a record beside a different original is not; an original this device imported itself
is never replaced.

## Part 4: two tests the audit said were missing

- **Fonts at the real limit.** `aFontLibraryLargerThanOnePassArrivesOverSeveralSyncs` uses an
  injected allowance of one font. Add a test at the real `BackupLimits.MAX_TOTAL_FONT_BYTES` if
  it can be done with valid font bytes and without a test that takes minutes; if it cannot, say
  exactly what stops it.
- **A work that becomes preserved between batches** (5c finding F5, what was left): an earlier
  batch's merge marks a work preserved, and a later batch carries its EPUB. Write the test first
  and say what it shows; fix it only if the fix is small and clearly iOS's behaviour.

## Not in this brief

Anything on iOS; findings F19, F25, F26 and F27 (they wait for the owner); the Backup screen
(brief 6b, another agent). If you see a data-loss bug on the way, write it at the top of the
result and go on.
