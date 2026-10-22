# A73: adversarial review of everything landed on 2026-10-21

Read-only review of Android commits `701595c9`, `4a63e64b`, `3c4a6d0c`, `be73a737` (this worktree, branch `android/agent-grok-a73`) and iOS commits `84d4dca4`, `54d2455b`, `a162b6e0` (`/Users/cidy02/kudos-ios-polish`). Checked against `docs/DATA_AND_PERSISTENCE_INVARIANTS.md` and `docs/AO3_NETWORKING_POLICY.md`. No Gradle, no xcodebuild, no sign-in, no contact with archiveofourown.org.

Severity: **P1** data loss, crash, privacy leak, or a write sent twice or wrongly. **P2** a wrong result a reader would notice. **P3** the rest. A suspicion without a failing case is under Unconfirmed. A commit that was read and cleared says "no fault found".

## Findings

### 1. P1 — A real soft-deleted collection still never arrives on a paired device

`BackupMergeService.mergeCollections` (`android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt:1348-1354`), together with `softDeleteCollection` (`WorkRepository.kt:1077-1088`) and `SyncMerge.tombstoneResolution` (`BackupMergeService.kt:2530-2540`). Folder sync calls `merge` in `RECONCILE` (`BackupRepository.kt:107-114`).

`4a63e64b` only deletes `if (archived.isDeleted == true) return@forEach`. The tombstone check in front of the insert is unchanged, and a tie goes to the tombstone (`incomingModifiedAt.isAfter(tombstone)` is required to revive; equal suppresses).

Failing case:
- On device A, `softDeleteCollection` sets the collection's `lastModifiedAt`, `deletedAt`, and the `workCollection` tombstone's `lastModifiedAt` to the same `now`.
- The backup/sync manifest carries both the `isDeleted: true` collection and that signed tombstone. Device B already trusts A's key (paired folder sync, or a file restore onto a device that has the trust store). B has no row for that id.
- Mode `RECONCILE` or `MERGE`. `collectionResolution` returns `SUPPRESS_STALE`. The function returns before `toWorkCollection`. B's Recently Deleted stays empty, and the tombstone is still adopted (`merge` lines 84-137), so a later reconcile of the same snapshot suppresses it again.
- Replace is the exception: it builds the tombstone index from an empty list (`BackupMergeService.kt:130-135`) and uses `replaceCollections`, which this commit does not change.

The new test `absentSoftDeletedRecordsRestoreInEveryModeWithALocalRecoveryWindow` feeds a snapshot with no collection tombstone. `absentSoftDeletedCollectionStillRespectsTombstonesExceptInReplace` uses `lastModifiedAt` of 100/200/300 against a tombstone at 200, not the equal clocks `softDeleteCollection` writes. A golden fixture collection (`expected-values.json` id `E0000000-0000-4000-8000-000000000001`, `lastModifiedAt` == `deletedAt` == `2023-11-14T22:31:20Z`) is also shipped with no `workCollection` tombstone.

If A is gone and B's only copy is that paired sync folder, the shelf (name, order, membership) is dropped. The works remain; the collection does not, and the 90-day window never starts on B.

### 2. P1 — A second File Merge resurrects the deleted collection the first import just parked

`BackupMergeService.mergeCollections` (`BackupMergeService.kt:1363-1383`). Reachable only because finding 1's early return is gone: the first import can now create the row.

Failing case:
- Empty library, no trusted `workCollection` tombstone (file import before the signer is trusted, or a snapshot shaped like the new golden fixture).
- Archive collection `{id: C, name: "Winter", isDeleted: true, deletedAt: T, lastModifiedAt: T}`.
- First `MERGE`: `existing == null`, `toWorkCollection` (`BackupMappers.kt:391-417`) stores C as deleted with `permanentDeletionScheduledAt = now + 90 days`. It shows in Recently Deleted.
- Second `MERGE` of the same archive: `existing.isDeleted` is true, so the branch copies the row with `isDeleted = false`, `deletedAt = null`, `permanentDeletionScheduledAt = null` and never reads `archived.isDeleted`. C is back on the active shelf.
- Same outcome if the first import was `RECONCILE` (folder sync of an untrusted or tombstone-free snapshot) and the second is File Merge.

`RECONCILE` repeated against an already-deleted local row does keep the deletion and the local deadline (`keptDeletionSchedule`, `BackupMappers.kt:115-116`). The new test `reconcilingAnImportedDeletedCollectionKeepsItsRecoveryDeadline` covers only that default mode, and only a second pass whose `lastModifiedAt` moved forward.

### 3. P2 — The new absent-collection path keeps the archive's work ids

`BackupMergeService.mergeCollections` (`BackupMergeService.kt:1355-1360`) calls `BackupCollection.toWorkCollection` (`BackupMappers.kt:405`), which assigns `workIDs` with `canonicalUuid` only. `remapWorkId` is applied on the Merge update path (`1367`), the Reconcile update path (`1408`), and `replaceCollections` (`1302`). It is not applied on the path this commit newly uses for a soft-deleted collection that is absent locally. The membership sweep (`1462-1476`) only removes ids; it does not rewrite them. `BackupRepository` then inserts those ids (`BackupRepository.kt:639-643`).

Failing case:
- Device B already has the work as id `LOCAL` (AO3 id 820001).
- Device A's archive has the same work as id `ARCHIVE` (the cross-device remap `merge` builds at `BackupMergeService.kt:151-166`) and a soft-deleted collection whose `workIDs` is `[ARCHIVE]`. No suppressing collection tombstone, mode `MERGE` or `RECONCILE`.
- The restored Recently Deleted row's `workIds` stay `[ARCHIVE]`. Restoring the shelf on B shows an empty collection. The works are on B under `LOCAL`.
- `REPLACE_LIBRARY` does not hit this: `replaceCollections` remaps.

`softDeleteCollection` does not clear members (`WorkRepository.kt:1072-1076`). The golden deleted collection has an empty `workIDs` list, so the new test does not catch this.

### 4. P2 — A deleted collection now consumes its name, and can rename the live one

`BackupMergeService.mergeCollections` (`BackupMergeService.kt:1324` and `1356-1361`) and `String.uniqueName` (`2313-2320`).

`names` starts as the active local names. The removed `return` used to skip a deleted archive row before `uniqueName`. The new path always does `names += restoredName`, including when the row is deleted. Export order is by id (`BackupMappers.kt:56-58`), not by name.

Failing case:
- Empty library, no suppressing tombstone, mode `MERGE` or `RECONCILE`.
- Archive order (sorted by id): `{id: 00000000-…, name: "Favorites", isDeleted: true}` then `{id: 10000000-…, name: "Favorites", isDeleted: false}`.
- The deleted row takes `"Favorites"`. The live row is stored as `"Favorites (Restored)"`. The reader’s active collection is renamed. Reversing the ids keeps the live name and renames only the Recently Deleted row.

### 5. P2 — History and Favorites selection chrome is inside the blur

`WorkLedgerRow` (`android/app/src/main/java/io/github/cidy02/kudos/ui/subject/WorkLibraryComponents.kt:163-214` and `202-251`). History and Favorites compose it (`LibraryScreen.kt:1027-1054`, `LibrarySectionKind.defaultsToLedgerRows`).

`Modifier.blur(10.dp)` is the first modifier on the row, so it blurs the accent border drawn later on that chain and the `Checkbox` drawn as a child. `SensitiveWorkRow` keeps the selected fill and the checkbox outside its blur (`SensitiveWorkRow.kt:202-243`). The reveal capsule is a sibling and is removed while selecting (`WorkLibraryComponents.kt:253`, `LibraryScreen.kt:1078`).

Failing case:
- Hide Mature is on, mode Blur. An unrevealed Explicit work is in History (or Favorites). The reader enters selection and taps that row.
- `onClick` still calls `actions.onSelect` (`LibraryScreen.kt:1044-1046`). `selected` becomes true.
- The 2.dp accent border and the checkbox are under the 10.dp blur, so the row does not show that it is selected. The same tap on a saved card (`SensitiveWorkRow`) shows a checkbox and a selected fill outside the blur.

Hide mode never composes the row (`LibraryQuery.kt:53`). Swipe is not attached while `selecting || obscured` (`LibraryScreen.kt:1078-1085`). Long-press does not open the menu while obscured or selecting (`LibraryScreen.kt:1052`).

### 6. P2 — A bare deleted comment is shown as a Guest comment

`AO3CommentParser.parseOneComment` (`AO3CommentParser.kt:176-214`), drawn by `CommentThreadComponents.kt:615-622`.

iOS treats a comment `li` with no `h4.heading.byline` as deleted and keeps `li.text()` (`AO3Client+Comments.swift:273-299` in `/Users/cidy02/kudos-ios-polish`). The live shape, covered by `KudosTests/AO3CommentsParseTests.swift` `deletedCommentParsesAsTombstoneAndKeepsItsReplies`, is:

```html
<li class="comment group even" id="comment_2">
  <p>(Previous comment deleted.)</p>
</li>
```

No `blockquote.userstuff`, no `.comment-text`, no class `deleted`. Android's body lookup misses the `<p>`, so `body` stays `""`. The `contains("Previous comment deleted")` checks run on that empty string, and `isDeletedOrHidden` stays false. The id starts with `comment_`, so the node is kept. The blank body is then replaced with `"Deleted or hidden comment."` and `parseCommentAuthor` (`AO3CommentParser.kt:375-410`) names it `"Guest"`.

Failing case: that `li`, with its reply in the following sibling `<li><ol class="thread">`. The reply still attaches (`parseThread`, `AO3CommentParser.kt:160-169`). The row is not the italic deleted tombstone. It is a Guest comment whose body is "Deleted or hidden comment." The words AO3 wrote are dropped. The paragraph join added in `be73a737` does not run, because `bodyElement` is null.

### 7. P3 — An existing Saved for Later queue takes an older archive membership clock

`KudosBackup.swift` restore (`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Services/KudosBackup.swift:2773-2779`, `2848-2851`, `2928-2941`), commit `84d4dca4`.

Saved for Later is matched by kind, not id. `hadExistingQueue` is `queuesByID[archived.id] != nil`, computed from the archive UUID. `hadSavedForLaterQueue` is captured before `ensureSavedForLaterQueue`. When this library already has the system queue, the dedicated branch is skipped. The archive's UUID is not the local one, so `hadExistingQueue` is false, and `lastMembershipChangedAt` is replaced with `archivedChangedAt`. That assignment is not gated on `incomingWins` (computed at `2838-2847` from the pre-overwrite clock). `dateUpdated` still uses `max`.

Failing case:
- This phone's Saved for Later has `lastMembershipChangedAt` of 2026-10-21 because the reader queued a work today (`ReadingQueue.markMembershipChanged`, `Models.swift:978-980`, sets both clocks). Its id is this phone's UUID.
- A backup from the other phone has Saved for Later under a different UUID with `lastMembershipChangedAt` of 2023-11-14.
- Reconcile or File Merge on this phone. `hadSavedForLaterQueue` is true, `hadExistingQueue` is false. File Merge has `incomingWins == false` and still writes the clock. `dateUpdated` stays 2026-10-21. `lastMembershipChangedAt` becomes 2023-11-14.
- The membership loop raises the queue clock only when an incoming membership wins or is newly inserted (`3021-3042`). The local membership that does not win does not put 2026-10-21 back.

A custom queue that already has the same id still takes `max`. A queue this restore inserts (including one revived past a tombstone, where the row was absent) correctly keeps the archive clock. There is no name mapping. A library that did not yet have Saved for Later uses the first branch (`2928-2930`) and keeps the archive clock, which is what that branch is for.

The stored clock is what changes. A later sync deleting those memberships is not shown; see Unconfirmed.

### 8. P3 — At accessibility sizes the last figure in an odd strip stretches across the card

`SubjectStatStrip` (`android/app/src/main/java/io/github/cidy02/kudos/ui/subject/SubjectComponents.kt:615-625`), added in `701595c9`.

When the font scale is above 1.3 and the strip has more than two cells, the cells are `chunked(2)`. Each chunk is a `Row` whose cells use `Modifier.weight(1f)`. A chunk of one cell is the only child, so that weight takes the whole row.

Failing case:
- The reader is at an accessibility text size. They open My copy on a saved work.
- The strip is Progress, On device, Preserved (`WorkDetailMyCopySheet.kt:308-319`).
- Progress and On device share the first row, half the width each. Preserved is alone on the second row and draws across the full width of the strip.
- The same stretch happens on Comments whenever that strip has three cells. It has three when one of the work's comment total, the signed-in Yours count, or Latest is absent (`CommentsScreen.kt:429-460`). A four-cell strip (work identity, search results) stays two and two.

## Commit `3c4a6d0c` — no fault found

- `SyncRepository.kt:442-444` runs inside `runSyncLocked`, which `runSync` calls on `Dispatchers.IO` (`SyncRepository.kt:148-158`). `edit(commit = true)` is `editor.commit()` on that IO thread, same as the `.commit()` it replaced. It is not the main thread. The return value was already ignored.
- `KokoroTTSController.kt:50-52` logs a fixed sentence. The catch comment and the string do not include the correction words.
- `MainActivity.kt:49-67`: `kudosTheme` is read and `updateAppTheme` is called only inside `if (BuildConfig.DEBUG)`. `onNewIntent` (`114-128`) recreates for that extra only inside the same check. `sessionTheme` stays null otherwise. `android/app/build.gradle.kts` `release` does not set `debuggable` or `BuildConfig.DEBUG`. Nothing from this extra runs in a release build.
- `CustomizeThemeSheet.kt:125-130` sizes the preview from `LocalWindowInfo.containerSize` in dp. A zero first frame would collapse the preview until the next composition; that is not a crash, and the threshold matches the old `screenHeightDp < 600` check.

## Commit `701595c9` — besides finding 8

Read the screen diffs and the new `A70ScreenFixesTest`. No other fault found.

- Jump Back In scrolls to item 0 when the first pick's fandom name changes (`BrowseCategoryPanels.kt:69-73`). Picks are one per fandom (`JumpBackIn.kt:64-70`), so a fandom that arrives in front changes that key. The Robolectric test does not reproduce the cut-off; this pass did not run the emulator.
- The account session line uses `AO3SessionHealth.Healthy(System.currentTimeMillis())` (`AO3AuthRepository.kt:373`) and `relativeSyncPhrase` (`AccountWorksListScreen.kt:1806-1814`). A future stamp clamps to "just now".
- Fandom chips take their hue from the first Continue Reading work (`LibraryScreen.kt:760-764`). Hide mode has already dropped a hidden work before that list is built. A blurred hero can color the chips. The chips do not print that work's title. The same wash is what iOS uses.
- Bookmark badges, saved-search `cardRow`, Settings `formGround`, Listening's accent values, the disabled stepper, and own-Works chips are presentation. `cardRow` puts the click after the background on the saved-search row (`SearchScreen.kt:858-862`).

## Commit `be73a737` — besides findings 5 and 6

Privacy, with Hide Mature on:

- Hide mode removes the work before a row is composed (`LibraryQuery.kt:53`). No compact row, saved card, ring, or count is built.
- Blur mode sets `obscured`. On a compact row the title, the fandom kicker, the metadata line (author, words, chapters: `HomeFacts.localWorkMetadata`, `HomeFacts.kt:168-171`, passed at `LibraryScreen.kt:1032`), and the progress ring's "$percent%" / "Reading" / "Finished" (`SubjectComponents.kt:800-818`) are children of `Modifier.blur(10.dp)`. `hiddenMatureWorkSemantics` is last on that chain and replaces the label with "Hidden mature work" (`SensitiveWorkRow.kt:78-81`). The reveal capsule is a sibling and does not name the work.
- On a saved card the "by" line (`WorkDetailIdentity.kt:201` and `218`, `includesBy = savedCard` at `SensitiveWorkRow.kt:291`) and the figure row, including a demo zero (`DemoLibrary.kt` `withDemoCounts`), sit in the inner column under `blur(16.dp)` (`SensitiveWorkRow.kt:239-243`). The checkbox and the selected fill stay outside that blur.
- Swipe is not attached while the row is obscured or selecting (`LibraryScreen.kt:1078-1085`). Long-press does not open the menu in those states (`LibraryScreen.kt:1052`).

`Modifier.blur` is a no-op below API 31. History and Favorites used `SensitiveWorkRow`, which already blurred the same way, so the compact row does not newly reveal a work on those APIs.

Other comment shapes, after the paragraph join:

- No `<p>` inside the blockquote falls through to `normalizedText()` of that element (`AO3CommentParser.kt:181-183`).
- Class `deleted` or `hidden` still sets `isDeletedOrHidden` before the body text is consulted (`184-185`).
- Guest bylines still resolve from the byline spans (`375-410`). The commit did not change that branch.
- A reply's chapter badge is hidden because `parentAuthor` is set (`CommentThreadGeometry.kt:76` and `229`). A root keeps `parentAuthor = null` (`206`, `223`), so its chapter badge stays. iOS uses the same `parentAuthor == nil` gate (`CommentThreadRow.swift:827`).
- Thread Reply passes `plainAccent = palette.accent` (`CommentThreadComponents.kt:780-784`) and draws accent text. Inbox Reply does not pass it (`AccountInboxPane.kt:811-815`), so it keeps the capsule (`CommentThreadComponents.kt:1048`).

The scope menu compares `route.id` (`AO3AuthorModels.kt:13-15`), which lowercases the username and the pseud. Works / In collections / Gifts are composed only when `ownAccount` (`AuthorProfileScreen.kt:864`). What's New, My copy's spacing, and the collection form's wash are presentation. The tagline sets `fillsRemainingWidth` (`AO3CollectionFormScreen.kt:121`); at the default text size the field is the remaining width and a long value scrolls inside it.

## Commits `54d2455b` and `a162b6e0` — no fault found

- The collection card's eyebrow and chips use the existing `FlowLayout` (`AO3CollectionsList.swift:740-758` in `/Users/cidy02/kudos-ios-polish`). It wraps when the next subview does not fit (`FlowLayout.swift:81-96`). The `Spacer` that had forced one row is gone.
- Listening's Sample Text and its speed pills stack only when `dynamicTypeSize.isAccessibilitySize` (`ReaderSpeechAuditionHarness.swift:45-48` and `77-80`).
- `comments:` and `author:` live in `DemoLibrary.swift`, which is `#if DEBUG` from line 1 through `#endif` at line 560. The only call site is inside `#if DEBUG` in `HomeView.swift:214-229`. `a162b6e0` falls back to work id `999_000_005` when the matched work has no AO3 id (`DemoLibrary.swift` `commentsRoute`). That fallback is inside the same DEBUG file.

## Unconfirmed

- A later sync removes Saved for Later memberships because finding 7 lowered `lastMembershipChangedAt`. Not shown. Both apps' membership tombstone passes judge the membership's own `lastModifiedAt` (iOS `KudosBackup.swift:3054-3056`; Android `BackupMergeService.kt:1851-1855`). `effectiveQueueModifiedAt` still includes `dateUpdated` and every membership timestamp (iOS `PersistenceSync.swift:600-606`), and finding 7 leaves `dateUpdated` at the newer value. Launch backfill (`PersistenceSync.swift:276-285`) raises the clock to the newest membership on a later launch. No queue sweep uses the queue clock the way collections use `collection.lastMembershipChangedAt` (`KudosBackup.swift:2707-2713`).

## Commits read

| SHA | Subject | Verdict |
|---|---|---|
| `701595c9` | A70/A70b screen fixes | finding 8 |
| `4a63e64b` | 3ge mergeCollections restore | findings 1–4 |
| `3c4a6d0c` | lint + debug theme extra | no fault found |
| `be73a737` | A71 screen differences | findings 5 and 6 |
| `84d4dca4` | iOS T-423 queue membership clock | finding 7 |
| `54d2455b` | iOS T-422 FlowLayout / Listening | no fault found |
| `a162b6e0` | iOS T-422 follow-up | no fault found |

## Triage (Claude, 2026-10-21 23:30)

Each finding checked in both apps' code before acting.

1. **Not a fault.** iOS suppresses the same absent snapshot (`collectionResolution` →
   `.suppressStaleData` → `continue`), and a tie goes to the tombstone on both apps: the deletion
   record wins over a copy it already describes. Recorded in DECISIONS.
2. **Real, both apps, wider than reported:** File Merge un-parks a work, collection or queue the
   archive itself has deleted (and retracts a work's tombstone). Brief 3gj (Android, and an iOS
   patch).
3. **Real, Android only** (iOS maps archived work ids through `restoredWorksByArchivedID`): brief 3gj.
4. **Real, Android only** (`uniqueName` is Android's): brief 3gj.
5. **Real** (Codex's compact row, `be73a737`): brief 3gj.
6. **Real, older than this commit** (the body lookup missed the bare `<p>` before `be73a737` too):
   brief 3gj.
7. **Real, Claude's own (T-423):** Saved for Later is matched by kind, so `hadExistingQueue` is
   false for this library's own system queue and the new exact assignment lowered its clock. Fixed
   by Claude after 3gj's iOS patch (same file).
8. **Not a fault:** iOS's figure cell has `.frame(maxWidth: .infinity)`, so a lone last cell spans
   its row on both apps.
