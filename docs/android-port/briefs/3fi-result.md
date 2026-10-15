# Brief 3fi result

Dispatch: `4ebf4e4d92cf9602d8d52795982bb57ed26c43aa`, branch `android/agent-codex-3fi`.
Changes are **uncommitted and untested** for Claude to build, test, review and commit.
Revised in place for **3fi-2** after Claude's reported gate of 2,768 tests with ten
failures. That gate predates this revision; no passing rerun is claimed here.

**No Room schema, migration, stored-field, backup-key or backup-format change.**
`TASKS.md` is unchanged. No branch switch, commit, push, sign-in, AO3 request,
Gradle invocation, helper script or `.orig` file. The iOS worktree was read-only.

## 3fi-2: causes and corrections for all ten failures

Eight failures share one cause in `ReadingQueueRepository.normalizeWork`: the
optional file callback used to default to `{ false }` for download scheduling.
3fi reused that default as authoritative disk evidence and wrote
`hasEpub = work.hasEpub && hasFile`. The demo and lifecycle/footprint tests construct
the repository without a callback, so normalization falsely cleared the flag even
when the actual EPUB existed. **The demo seeder calls neither the identity matcher
nor acquisition/import. No demo rows were matched together, and normalization did
not delete the files.**

`epubOnDisk` is now an optional callback whose absence means unknown. Normalization
retains the stored flag when no probe was supplied; an injected real file probe can
still invalidate a genuinely missing file. The production container still injects
`WorkFileStore.workEpubExists`. Queue download scheduling and restricted-series
checks keep their prior conservative behavior when no probe exists. No demo,
identity, importer, scanner, or history-query production change was needed.

| # | Failing test | Cause and change |
| --- | --- | --- |
| 1 | `DemoLibraryTest.seedPopulatesExpectedWorksQueuesCollectionsAndIsIdempotent` | Adding Sodium Lights to Neon reread ran normalization with the absent probe represented as false, clearing `hasEpub`. The unknown-probe fallback now preserves its true flag and existing EPUB. Assertion unchanged. |
| 2 | `DemoLibraryTest.searchFixtureHasSeparateChaptersAndOriginalSearchTermsEvenOnAnExistingDemo` | The first seed wrote the correct nine-spine EPUB, then queue add falsely cleared its flag. The test subsequently installs the old one-spine EPUB; the installed-demo upgrade's `title == "The Long Way Down" && hasEpub` guard then skipped it. Preserving the flag lets that existing upgrade replace the old fixture with nine entries again. Neither the fixture writer nor its assertion changed. |
| 3 | `DemoLibraryTest.demoBookmarkPairsWithTheMatureLibraryWorkAndBlursUntilRevealed` | Ashfall's add to Slow burns falsely cleared `hasEpub`. Its saved flag, AO3 identity, bookmark pairing and physical file were intact. The probe fix retains its downloaded state. Assertion unchanged. |
| 4 | `DemoLibraryTest.installedDemoHistoryDatesUpgradeOnlyUntouchedFixturesAndRespectUndo` | Winter Garden's queue add falsely cleared `hasEpub`; `ReadingAbandonment.isAbandoned` requires `isInProgress`, which requires a local EPUB. The date upgrade itself was correct. The probe fix restores eligibility without changing progress/dates/undo. Assertion unchanged. |
| 5 | `DemoLibraryTest.demoLibraryShelfCountsMatchIos` | Sodium Lights, Ashfall and Winter Garden all lost their EPUB flags on queue add, so Reading Now became empty. The probe fix retains those three entries. Shelf/query rules and assertion unchanged. |
| 6 | `DemoLibraryTest.demoHistoryHasThreeTimeBucketsAbandonedAndReadNotFinishedWithoutAddingRows` | Winter Garden ceased to qualify as in progress after its flag was cleared, eliminating the demo's Abandoned bucket. The probe fix retains the intended state. Grouping and assertion unchanged. |
| 7 | `WorkLifecycleRepositoryTest.keepOfflineQueueDrivesDownloadedQueryAndClearsHold` | Queue add correctly cleared the hold and established Keep offline, but normalization then cleared `hasEpub` through the absent probe, making `isDownloaded` false. The probe fix preserves the flag. Hold release is now shared by normalization, including repeat adds and launch reconciliation, using the existing `WorkDao.isKeptOffline` policy. Assertion unchanged. |
| 8 | `WorkLifecycleRepositoryTest.collectionNilDoesNotKeepButOnDoesAndClearsHold` | 3fi's new existing-membership return in `addWorkToCollection` ran before `releaseHeldCopy`; after enabling the collection's Keep offline, repeat add left `freedAt` behind. Hold release now runs before that return. Repeat add still leaves the membership clock untouched. Assertion unchanged. |
| 9 | `LibraryHistoryScreenTest.tallyFollowsEveryGroupingAndZerosDisappear` | 3fi correctly enabled the History ledger default, which adds a normalized uppercase fandom kicker to each of the two Doctor Who rows. The text-only selector now sees the heading plus two kickers. The test now scrolls to and asserts the unique **non-clickable** Doctor Who heading; both row kickers are clickable fandom searches. This is the only existing test assertion changed in 3fi-2; iOS evidence is quoted below. |
| 10 | `LocalDataFootprintTest.demoSelectionReallyGivesEveryMeasuredCategoryANonzeroValueAndReseedingPreservesIt` | The repository passed to `DemoLibrary.seed` has no file probe. Its Ashfall row therefore lost `hasEpub` on queue add and cannot satisfy the test's `title == "Ashfall" && isDownloaded` assertion (line 179). The scanner also relies on the flags to classify reading copies. The probe fix preserves them; the scanner and test are unchanged. The supplied failure report did not identify a line, so line 179 is the code-traced failing assertion, not a newly observed stack trace. |

### iOS justification for the sole existing assertion change

Read-only reference: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`.
`Features/Library/LibrarySectionKind.swift:104`, `defaultDisplayMode`, says:

```swift
case .history, .favorites: .ledger
default: .detailed
```

`Features/Library/WorkRow.swift:135`, `ledgerRow`, constructs each row with:

```swift
WorkLedgerRow(
    palette: subjectPalette,
    kicker: nonemptyFandomNames.first.map(FandomDisplayName.bareTitle),
```

`Features/Library/LibrarySectionListView.swift:740` separately draws
`SectionRuleHeader(title: group.title, count: group.workIDs.count)`.
Thus iOS retains the group heading **and** each ledger row's fandom label. A unique
occurrence of the fandom text across the entire screen was not an iOS contract.
The revised matcher still requires exactly one heading; it does not accept an
arbitrary first match or remove work metadata.

### Additional regression coverage and file changes in 3fi-2

- `library/ReadingQueueRepository.kt`: distinguish unknown file evidence from a
  negative probe. Normalize the queue flag, preservation state and hold release
  together; remove the now-redundant first-add-only flag/hold writer. A kept copy
  cannot retain a stale hold through a repeat add. No file deletion path added.
- `works/WorkRepository.kt`: release a kept collection copy before the repeat-add
  return, retaining idempotent membership clocks and the existing transaction.
- `library/LibraryHistoryScreenTest.kt`: target the group heading as explained above.
- `works/WorkLifecycleTest.kt`: add
  `queueReconciliationKeepsRealCopiesWithAndWithoutAFileProbe`. With the real iOS
  EPUB, exercise default and real-probe repositories, new/repeat add, launch
  normalization, the held-copy sweep, queue hard-delete and last-membership
  removal; assert download flags, hold release, UUID/place and byte-identical
  retained files. Add
  `readdingACollectionKeeperPreservesItsRealCopyAndMembershipClock`: turn on Keep
  after membership exists, repeat add, retain the original membership clock, clear
  the hold and survive the sweep with the downloaded flag and EPUB bytes intact.
  iOS's `Services/WorkLifecycle.swift:54–59`, `sweepHeldCopies`, expressly keeps a
  protected copy and releases its hold:

  ```swift
  guard work.isFinished, !work.isProtected, !work.isPendingDeletion, work.hasEPUB else {
      work.freedAt = nil
      continue
  }
  ```

  `ReadingQueueService.normalize` only clears `hasEPUB` inside `if !hasFile` after
  an actual `FileManager.default.fileExists` call. These added tests enforce those
  same file/keep rules; no pre-existing lifecycle assertions were changed.
- `docs/android-port/briefs/3fi-result.md`: this failure-by-failure revision record.

Claude's `author` compile fix in `WorkIdentityIndexTest.kt` is retained. No test was
deleted, ignored, disabled or given a weaker download/file/hold expectation.
Static verification: `git diff --check` passes; every optional disk-probe reference
and the queue/collection writers and callers were inspected. **No Gradle or
Kotlin compilation, unit tests or UI run was performed**, per the inherited brief.
Claude must rerun the ten named tests, the new regression tests, then the full gate.

## Findings and changes, in brief order

| Brief / A56 | Dispatch-code finding and resulting behavior |
| --- | --- |
| 1 / #3 | Confirmed. `WorkDetailScreen.ensureLocalThen` handed actions its cached local record; `ReadingQueueRepository.addWork` returned existing memberships before restoration. Details now re-reads and restores through `WorkRepository.resolveLocalWork`; queue add restores even on repeat add and retracts the work tombstone. `downloadExisting` also resolves before attempting the download, so an offline failure cannot leave the reacquired work deleted. Revival does not assert that a missing EPUB exists. |
| 2 / #4 | Confirmed. Source identity alone could not recognize the source-less iOS fixture. `WorkIdentityIndex.findImportedEpub` now uses iOS's normalized title + author + on-disk file-size fallback after source lookup. The importer keeps the UUID, place, flags and original download date, restores deletion state, and fills metadata. A source match whose file is missing now installs the supplied EPUB even if its old `hasEpub` flag was true. |
| 3 / #5 | Confirmed. Acquisition probed a few exact strings rather than canonicalizing stored rows. All acquisition callers now load the inclusive local snapshot into the existing identity index: stored AO3 ID, canonical URL, exact non-AO3 source, then UUID fallback. Stored `/downloads/id` and incoming `/works/id` match in both directions. Direct download of the matched download-URL record also extracts the correct ID. |
| 4 / #6 | Confirmed. Queue hard-delete relied on cascade and left work flags and membership tombstones behind. It now tombstones and removes memberships, tombstones/deletes the queue, and normalizes affected works in one transaction. Add, repeat add and remove reconcile preserved/queued/missing-file/not-preserved state. Launch normalizes queued members and orphaned flags under the existing persistence gate, after the unchanged sweep calls. Recently Deleted queues still own memberships until hard-delete. |
| 5 / #7 | Confirmed. `removeWork` always used destructive queue-only semantics. Its default now removes only membership, preserving the live work, EPUB and place. Explicit `removeWorkAndDeleteIfQueueOnly` retains the old destructive intent for Remove from Later and Remove All Queues, with a saved-work tombstone and 90-day schedule. Caller decisions are below. |
| 6 / #8 | Confirmed live stamping fault; **no schema/format change needed**. `CollectionEntity`, its migration and domain mappers already store `lastMembershipChangedAt`. Add/remove now stamp that field; rename and other cosmetic edits leave it alone. The existing merge sweep already prefers it over `lastModifiedAt`. My interim claim that transport needed a new key was incorrect: iOS `KudosBackupCollection` omits this clock too; it represents this device's last membership choice. The fix and test use that existing local contract. |
| 7 / #13 | Confirmed. Adding collection membership left the work edit clock stale. New membership now stamps the work and collection together in a transaction. Repeat add stays idempotent and does not pretend the reader chose membership again. |
| 8 / #9 | Confirmed. A shared work-delete message now warns that an AO3-unavailable copy cannot be downloaded again after permanent removal. Wired into Work Details, Library single/bulk delete, Home single/bulk delete, shared bulk actions and Settings' queue-only deletion confirmation. Ordinary deletion still explains Recently Deleted and the 90-day recovery window. |
| 9 / #10 | Confirmed. The collection picker subscribed to `observeSavedWorks`, discarding unkept reading/history records upstream. It now observes all active works and applies iOS eligibility: exclude existing members, deleted works and queue-only records. Existing nameability/privacy filtering in `AddLibraryWorksSheet` remains in place. |
| 10 / #11 | Confirmed. Exact-name tag collisions returned without doing anything; non-colliding `INSERT OR REPLACE` could also cascade away tag links. Rename now consolidates an exact collision across **all** work and queue links in one transaction, deduplicates overlapping links, deletes only the losing tag, and updates work search indexes/edit clocks and queue clocks. Non-colliding rename uses SQL UPDATE. The edit sheet explains global consolidation and permits exact collisions. Case-only conflicts remain reported by the existing case-insensitive UI guard; direct API renames retain iOS's case-sensitive uniqueness behavior. The separately named queue-scoped merge keeps its scope. |
| 11 / #12 | The helper's missing newest-work support is real; A56's live-entry characterization needs qualification. `FandomVisits` now accepts an optional newest work, persists its stored AO3 ID/title, updates one watermark, and retains prior seen data when no snapshot is supplied. **Both** Android's Browse entry writer and iOS `NativeBrowseView` call without a newest snapshot. Those live entry calls remain unchanged; no newest work is guessed or fetched. The ported assertion supplies a snapshot, as the iOS test does. |
| 12 / #14 | A56's explanation was wrong: despite its name, `LibrarySubjectLedgerRow` used `SensitiveWorkRow` with `ledger = false`, so the other sections were already detailed. It also meant History/Favorites were detailed. `LibrarySectionKind.defaultsToLedgerRows` now drives the actual renderer flag: only History/Favorites default to ledger; other sections keep detailed cards. |

The 3fh stale-deletion protections remain: all sweep/Recently Deleted callers still
pass `onlyIfStillDeleted = true`, the queue guard now runs inside its transaction,
and launch sweeps still run under the persistence gate. No time cutoff or deferred
schema request remains.

## Every dispatch caller of queue `removeWork`

| Caller | Chosen behavior |
| --- | --- |
| `ReadingQueueRepository.moveWorks` | Non-destructive. Add the destination first, then detach the source. |
| `ReadingQueueRepository.removeFromAllQueuesAndDeleteIfQueueOnly` | Explicit destructive variant. Only an unsaved/unfavorited queue-only work losing its final membership goes to Recently Deleted. |
| `ReadingQueueRepository.removeFromSavedForLater` | Explicit destructive variant, matching iOS `removeFromSavedForLater` / Work Details' Remove from Later. |
| `QueuePageScreen` selection-bar `onRemove` | Non-destructive Remove from Queue. |
| `QueuePageScreen` confirmed multi-remove | Non-destructive Remove from Queue. |
| `ReadingQueueRepositoryTest` direct calls | Ordinary removal assertions use the default. Existing intentional queue-only deletion assertions now call the named destructive variant. Favorite/saved protection is tested through that variant. |
| `DeletionTransactionTest` direct calls | Non-destructive membership deletion; rollback and tombstone-first assertions still apply. |

The two destructive wrappers keep their existing indirect callers: Library actions,
Home menus/bulk actions, Work Details, shared bulk actions and Queue Storage. Calls
named `CollectionDao.removeWork` and Collection Details' local `removeWork` operate
on collections and are not this queue API.

## Files changed

Production paths below are under `android/app/src/main/java/io/github/cidy02/kudos/`.

| File | Change |
| --- | --- |
| `KudosApplication.kt` | Run queued-work normalization inside the existing launch persistence gate. |
| `browse/FandomVisits.kt` | Optional newest-work watermark fields; null preserves the existing seen snapshot. |
| `core/model/SavedWork.kt` | Correct the preservation-field comment to describe queue normalization. No stored property change. |
| `data/local/dao/TagDao.kt` | Read all work/queue links for a tag, update its name without replacement, and delete a consolidated loser. DAO SQL only. |
| `files/WorkFileStore.kt` | Read the EPUB's actual size on the IO dispatcher for the import fallback. |
| `home/HomeSectionListScreen.kt` | Use the shared unavailable-copy deletion warning. |
| `home/HomeWorkMenu.kt` | Use that warning for Home single/bulk targets. |
| `library/CollectionDetailScreen.kt` | Feed all active works through the collection eligibility rule. |
| `library/LibraryScreen.kt` | Warn for unavailable single/bulk deletion targets; use the section's actual ledger default. |
| `library/LibrarySectionKind.kt` | History/Favorites-only ledger default. |
| `library/QueueTags.kt` | Explain and permit exact-name global consolidation; preserve the case-insensitive conflict guard for case-only collisions. |
| `library/ReadingQueueRepository.kt` | Queue revival, normalization, atomic hard-delete bookkeeping, distinct removal intents, global tag rename consolidation. Reuse its existing revival logic for series acquisition. |
| `settings/QueueStorageScreen.kt` | Show the shared deletion warning when Remove Queues will delete a queue-only work. |
| `ui/components/DeleteConfirmation.kt` | Shared available/unavailable-copy message for single and batch deletion. |
| `ui/components/WorkBulkActionBar.kt` | Pass selected works to that message. |
| `works/DownloadQueue.kt` | Use the shared snapshot acquisition matcher. |
| `works/WorkDetailScreen.kt` | Use that matcher; restore/re-read existing local works before actions; shared deletion warning. |
| `works/WorkIdentityIndex.kt` | Reuse the canonical snapshot for both acquisition sides; centralize iOS's user-EPUB fallback; resolve stored/download-URL IDs. |
| `works/WorkImporter.kt` | Use the import fallback; repair a missing file on source match; use snapshot acquisition; revive before direct redownload. |
| `works/WorkRepository.kt` | Inclusive identity snapshot, local resolution, collection eligibility, transactional membership add, independent membership clock and work edit stamping. |

Test paths below are under `android/app/src/test/java/io/github/cidy02/kudos/`.

| File | Tests / adjustments |
| --- | --- |
| `backup/DeletionTransactionTest.kt` | Queue hard-delete rollback and tombstone ordering. |
| `library/LibrarySectionKindTest.kt` | All section display defaults. |
| `library/ReadingQueueRepositoryTest.kt` | Queue lifecycle, normalization, preserved-state and tag-consolidation assertions listed below. Existing deletion tests now explicitly request deletion. The render-filter fixture deletes **after** add, since add now revives. Keep-offline expectations include reacquisition of a deleted work and correction of an absent-file flag. Non-colliding rename also asserts retained work/queue links. |
| `reader/ReadingLogServiceTest.kt` | Newest-work watermark update and null-snapshot preservation. |
| `works/DownloadQueueTest.kt` | A queued download without a summary matches a stored download URL and retains its record. |
| `works/WorkDetailSaveForLaterTest.kt` | Compose regression for a stale existing-local Details snapshot deleted after the page opened. |
| `works/WorkIdentityIndexTest.kt` | Canonical acquisition in both directions and identity-tier priority. Existing callback-based tests now supply real snapshot rows. |
| `works/WorkLifecycleTest.kt` | Repository/importer, collection and confirmation-message assertions listed below. |

Other files:

- `android/app/src/test/resources/epub/sample-source-less.epub`: the **actual iOS**
  `KudosTests/Fixtures/sample.epub`, copied byte for byte (1,786 bytes). Its OPF has
  neither a source nor an identifier. SHA-256:
  `2be63c7aa2950b6b7bbda7be0eff723a9a2410fc71dac2bf5a9b9ab07061d644`.
- `docs/DATA_AND_PERSISTENCE_INVARIANTS.md`: clarify membership-only removal versus
  explicit remove-and-delete-if-queue-only actions; no data/format rule weakened.
- `docs/android-port/briefs/3fi-result.md`: this handoff.

## What each added test asserts (not executed here)

| Test | Guarantee |
| --- | --- |
| `resolveLocalWorkRevivesASoftDeletedWorkWithoutMaskingAMissingEPUB` | Same UUID, cleared deletion dates/tombstone, retained locator, and no invented file or EPUB flag. |
| `addToSavedForLaterRevivesRecentlyDeletedWork` | Both first queue add and the existing-membership fast path revive, clear tombstones and avoid a duplicate work/membership. |
| `requeuedWorkStaysRevivedWhenPreservationFailsOffline` | An explicitly failed fake download leaves a live, queued metadata record, with failed preservation status and no deletion schedule. |
| `directRedownloadRevivesBeforeAnOfflineFailure` | Direct existing-work redownload restores before the fake offline response, without claiming a missing EPUB. |
| `existingLocalDetailRevivesBeforeSavingForLater` | The actual Details action re-reads a stale local snapshot, revives the work, joins Later and makes no AO3 read for the held copy. |
| `userEPUBImportRevivesRecentlyDeletedDuplicate` | Re-importing the source-less iOS fixture under another filename restores the same row and retains place, favorite and download date. |
| `sourceLessImportDoesNotCollapseDifferentTitlesOrFileSizes` | Different title or byte size does not satisfy the EPUB fallback. |
| `existingWorkMatchesCanonicalAO3URLVariants` | Stored downloads URL versus incoming works URL matches; reverse direction matches too. |
| `acquisitionUsesStoredAO3IdBeforeCanonicalUrlAndRecordUuid` | The stored-ID tier wins over URL/UUID matches; blank source is not an arbitrary match. |
| `importEPUBMergesAcrossAO3URLVariants` | Real importer download writes to the existing download-URL record and retains its locator instead of inserting a second row. |
| `queuedDownloadFindsAStoredDownloadUrlAndKeepsItsLocalIdentity` | The serial queue's no-summary branch resolves and downloads the stored download-URL record, revives it and retracts its tombstone. |
| `sweepExpiredHardDeletingAQueueTombstonesMembershipsAndUpdatesWork` | A recoverable queue still owns its work; after expiry its membership and queue are tombstoned, the work flag/status clears, and the work stays live. |
| `queueHardDeleteRollsBackMembershipTombstonesAndFlagsWhenQueueDeleteFails` | A real SQLite trigger aborts queue deletion; all earlier membership/tombstone edits roll back. The successful path requires tombstones before both deletes. |
| `normalizeClearsStaleQueueFlagWithoutMembership` | An orphaned queued flag and preservation date/status clear without deletion or a new user-edit clock. |
| `addingAndRemovingMembershipReconcilesPreservationStatus` | Local file becomes preserved on add, absent copy queues, repeat add notices a lost file, and final removal resets preservation state. |
| `hardDeletingOneQueueKeepsOtherMembershipAndStaleConfirmationKeepsRestoredQueue` | A stale Delete Forever is harmless after restore; deleting one of two queues retains the other membership and queued flag. |
| `removeLastQueueMembershipDoesNotDeleteWorkByDefault` | Ordinary removal retains a live work/EPUB flag/locator, tombstones only membership, and clears preservation state. |
| `removingLastQueueMembershipKeepsTheActualEpubAndPlace` | The real on-disk iOS EPUB remains byte-identical after last-queue removal, with the same live work/place. |
| `renamingACollectionDoesNotOverrideARemovalElsewhere` | The real add writer stamps the local membership clock; a later real rename leaves it unchanged; existing backup merge then honors a newer peer removal. |
| `addStampsBothSidesModified` | Real collection add stamps work and collection together; repeat add keeps the membership clock; remove advances it. |
| `collectionCandidatesIncludeUnkeptHistoryButExcludeMembersQueueOnlyAndDeleted` | The active-works feed actually supplies unkept history to the picker rule, while existing members, queue-only and deleted works stay out. |
| `deleteConfirmationMessageEscalatesWhenAO3Unavailable` | Normal text names Recently Deleted; unavailable single/batch text warns that re-download is impossible. |
| `collidingTagRenameCollapsesTheTwoTags` | Two tags collapse globally across separate works and queues, overlapping links deduplicate, search/edit clocks update, and case-distinct names can still coexist at the API level. |
| `markVisitedUpdatesExistingWatermark` | Repeat visit updates one watermark's newest ID/title and visit time; a subsequent visit without a snapshot preserves the prior seen-work fields. |
| `historyAndFavoritesDefaultToLedgerRows` | Only History/Favorites return the ledger default across every section kind. |

## Verification and remaining limits

Passed static checks: `git diff --check`; all acquisition call sites updated to
the snapshot signature; all dispatch queue-removal callers inspected; dispatch
HEAD and branch unchanged; `TASKS.md`, Room entities/schemas/migrations and backup
production files unchanged; copied fixture hash/content match verified. No stub
or helper artifact was introduced.

**Not checked:** Kotlin/Room/Compose compilation, Gradle lint or unit tests,
Robolectric timing, device behavior, screenshots, accessibility/font-size layout,
or runtime performance. Claude must run the added tests and the wider Android
suite, particularly queue/series, deletion transactions, backup merge and privacy
tests. No UI visual approval is claimed.

The EPUB fallback deliberately matches iOS's title/author/size heuristic; it is
not a content hash and can equate distinct equal-sized files with identical
metadata. Source-less files whose original local copy is gone cannot use its size
as evidence. Acquisition now indexes an inclusive library snapshot, so very large
libraries merit profiling. A live Browse entry still has no newest-work snapshot,
as on iOS; this brief adds no speculative lookup or network request to produce one.
