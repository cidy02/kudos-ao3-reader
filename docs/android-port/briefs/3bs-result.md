# Brief 3bs result

Android only; iOS reference read-only at `/Users/cidy02/kudos-ios-polish/`.
Branch: `android/agent-codex-3bs`. Existing brief edit and untracked A12 audit retained.
No TASKS edit, branch switch, commit, push, login, AO3 traffic, Gradle or Xcode run.
Tests are written before production edits. Red/green execution must be done by Claude;
pre-change failure descriptions below are code-path predictions, not executed results.

## Evidence before changes

### 1 · A3-3

`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Services/KudosBackup.swift` · pre-edit lines 4401–4416:

```swift
4401:         let incomingWins = isNewRecord || SyncMerge.shouldApplyIncoming(
4402:             localModifiedAt: work.lastModifiedAt,
4403:             incomingModifiedAt: incomingModifiedAt
4404:         )
4405:
4406:         work.createdAt = min(work.createdAt, archived.createdAt ?? archived.dateAdded)
4407:         work.dateAdded = min(work.dateAdded, archived.dateAdded)
4408:         // Missing means an older client had no opinion; it must never erase a
4409:         // date already captured or edited on this device.
4410:         if let downloadedAt = archived.downloadedAt,
4411:            incomingWins || work.downloadedAt == nil {
4412:             work.downloadedAt = downloadedAt
4413:         }
4414:         if let assetIdentifier = archived.assetIdentifier, !assetIdentifier.isEmpty {
4415:             work.assetIdentifier = work.assetIdentifier.isEmpty ? assetIdentifier : work.assetIdentifier
4416:         }
```

`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Services/KudosBackup.swift` · pre-edit lines 2631–2635:

```swift
2631:                incomingWins || collection.workOrderRaw.isEmpty {
2632:                 collection.workOrderRaw = archivedOrder
2633:             }
2634:             collection.dateAdded = min(collection.dateAdded, archived.dateAdded)
2635:             if let archivedCreatedAt = archived.createdAt {
```

`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Services/KudosBackup.swift` · pre-edit lines 2918–2921:

```swift
2918:                 queue.tags.removeAll { !snapshot.contains($0.name) }
2919:             }
2920:             queue.dateCreated = min(queue.dateCreated, archived.dateCreated)
2921:             // `ensureSavedForLaterQueue` inserts the system queue at "now" when
```

`android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt` · pre-edit lines 781–798:

```kotlin
781:                 dateAdded = minInstant(existing.dateAdded, restored.dateAdded),
782:                 createdAt = minNullableInstant(existing.createdAt, restored.createdAt),
783:                 lastModifiedAt = maxInstant(existing.lastModifiedAt, incomingModifiedAt)
784:                     ?: incomingModifiedAt,
785:                 comments = archived.comments ?: existing.comments,
786:                 hits = archived.hits ?: existing.hits,
787:                 knownChapterCount = archived.knownChapterCount ?: existing.knownChapterCount,
788:                 lastUpdateCheck = restored.lastUpdateCheck ?: existing.lastUpdateCheck,
789:                 hasGivenKudos = existing.hasGivenKudos || restored.hasGivenKudos,
790:                 freedAt = existing.freedAt,
791:                 authorIdentitiesJSON = existing.authorIdentitiesJSON,
792:                 keepInProgressOverride = archived.keepInProgressOverride ?: existing.keepInProgressOverride,
793:                 hiddenFromHistoryAt = if (archived.hiddenFromHistoryAt != null) restored.hiddenFromHistoryAt else existing.hiddenFromHistoryAt,
794:                 datePublished = restored.datePublished.ifBlank { existing.datePublished },
795:                 dateUpdated = restored.dateUpdated.ifBlank { existing.dateUpdated },
796:                 epubDigest = restored.epubDigest.ifBlank { existing.epubDigest },
797:                 assetIdentifier = restored.assetIdentifier.ifBlank { existing.assetIdentifier },
798:                 bookmarks = archived.bookmarks ?: existing.bookmarks,
```

`android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt` · pre-edit lines 802–814:

```kotlin
802:         } else {
803:             // Keep local flags/metadata; still absorb non-destructive fills.
804:             existing.copy(
805:                 hasEpub = existing.hasEpub || restored.hasEpub,
806:                 isQueuedForLater = existing.isQueuedForLater || restored.isQueuedForLater,
807:                 title = existing.title.ifBlank { restored.title },
808:                 author = existing.author.ifBlank { restored.author },
809:                 summary = existing.summary.ifBlank { restored.summary },
810:                 sourceUrl = existing.sourceUrl.ifBlank { restored.sourceUrl },
811:                 createdAt = minNullableInstant(existing.createdAt, restored.createdAt),
812:                 comments = existing.comments ?: archived.comments,
813:                 hits = existing.hits ?: archived.hits,
814:                 knownChapterCount = existing.knownChapterCount ?: archived.knownChapterCount,
```

`android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt` · pre-edit lines 1212–1221:

```kotlin
1212:         var created = 0
1213:         var updated = 0
1214:         val incomingIds = mutableSetOf<String>()
1215:         incoming.forEach { archived ->
1216:             val id = BackupPaths.canonicalUuid(archived.id, "collection.id")
1217:             incomingIds += id
1218:             val existing = collectionsById[id]
1219:             val restored = archived.toWorkCollection(exportedAt = exportedAt)
1220:             collectionsById[id] = restored.copy(
1221:                 workIds = restored.workIds.map { remapWorkId(it, workIdRemap) }.distinct()
```

`android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt` · pre-edit lines 1320–1330:

```kotlin
1320:                         tombstoneIndex.collectionMembershipResolution(
1321:                             collectionMembershipRecordId(id, workId),
1322:                             incomingModified
1323:                         ) == TombstoneResolution.SUPPRESS_STALE
1324:                     }
1325:                 val deletionState = restoredDeletionState(archived.isDeleted)
1326:                 val base = existing.copy(
1327:                     name = if (archivedIsDeleted) existing.name else archived.name,
1328:                     dateAdded = BackupValidator.parseInstant(
1329:                         archived.dateAdded,
1330:                         "collection.dateAdded",
```

`android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt` · pre-edit lines 1382–1403:

```kotlin
1382:             archived.showsOnHome
1383:         } else {
1384:             existing.showsOnHome
1385:         }
1386:         val orderRaw = if (!archived.workOrderRaw.isNullOrEmpty() && (incomingWins || existing.workOrderRaw.isEmpty())) {
1387:             archived.workOrderRaw
1388:         } else {
1389:             existing.workOrderRaw
1390:         }
1391:         return existing.copy(
1392:             createdAt = minNullableInstant(
1393:                 existing.createdAt,
1394:                 parseOptionalInstant(archived.createdAt, exportedAt)
1395:             ),
1396:             syncStatusRaw = if (incomingWins) {
1397:                 archived.syncStatusRaw ?: existing.syncStatusRaw
1398:             } else {
1399:                 existing.syncStatusRaw ?: archived.syncStatusRaw
1400:             },
1401:             hue = chosenHue,
1402:             colorHex = chosenHex,
1403:             keepsWorksOffline = keepsOffline,
```

`android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt` · pre-edit lines 1599–1605:

```kotlin
1599:                 } else {
1600:                     created
1601:                 }
1602:                 queuesCreated += 1
1603:             } else if (mode == BackupImportMode.MERGE) {
1604:                 // Keep local queue name / fields. New memberships still insert below.
1605:                 val filled = fillQueueFields(existing, archived, incomingWins = false)
```

`android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt` · pre-edit lines 1651–1659:

```kotlin
1651:                         keepsWorksOffline = filled.keepsWorksOffline,
1652:                         notes = filled.notes
1653:                     )
1654:                     queuesUpdated += 1
1655:                 } else {
1656:                     val filled = fillQueueFields(existing, archived, incomingWins = false)
1657:                     if (filled != existing) {
1658:                         queuesById[id] = filled
1659:                         queuesUpdated += 1
```

### 2 · A3-4

`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Services/KudosBackup.swift` · pre-edit lines 2838–2855:

```swift
2838:             let localModifiedAt = SyncMerge.effectiveQueueModifiedAt(queue)
2839:             let incomingWins = switch mode {
2840:             case .merge: false
2841:             case .replaceLibrary: true
2842:             case .reconcile:
2843:                 SyncMerge.shouldApplyIncoming(
2844:                     localModifiedAt: localModifiedAt,
2845:                     incomingModifiedAt: incomingModifiedAt
2846:                 )
2847:             }
2848:             if kind == .savedForLater {
2849:                 queue.name = ReadingQueueService.savedForLaterName
2850:                 queue.kind = .savedForLater
2851:             } else if incomingWins || queue.name.isEmpty {
2852:                 queue.name = archived.name
2853:                 queue.kind = kind
2854:                 queue.sortOrder = archived.sortOrder
2855:             }
```

`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Services/KudosBackup.swift` · pre-edit lines 2999–3022:

```swift
2999:                 // Replace takes the archive's order and note outright. Leaving
3000:                 // this gated on recency meant a membership the reader had moved
3001:                 // or annotated SINCE the backup kept its local position — which
3002:                 // is precisely the edit a Replace is asking to undo, so Replace
3003:                 // silently did not restore the queue's order. Merge still never
3004:                 // touches an existing membership; reconcile still settles on
3005:                 // recency.
3006:                 let membershipWins = switch mode {
3007:                 case .merge: false
3008:                 case .replaceLibrary: true
3009:                 case .reconcile:
3010:                     SyncMerge.shouldApplyIncoming(
3011:                         localModifiedAt: existing.lastModifiedAt,
3012:                         incomingModifiedAt: incomingModifiedAt
3013:                     )
3014:                 }
3015:                 if membershipWins {
3016:                     existing.sortOrderInQueue = archived.sortOrderInQueue
3017:                     existing.note = archived.note
3018:                     existing.lastModifiedAt = incomingModifiedAt
3019:                     queue.lastMembershipChangedAt = max(queue.lastMembershipChangedAt, incomingModifiedAt)
3020:                 }
3021:                 work.isQueuedForLater = true
3022:                 continue
```

`android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt` · pre-edit lines 1610–1641:

```kotlin
1610:             } else {
1611:                 val localModified = SyncMerge.effectiveQueueModifiedAt(
1612:                     queueUpdatedAt = existing.dateUpdated,
1613:                     lastMembershipChangedAt = existing.lastMembershipChangedAt,
1614:                     membershipModifiedAts = localMembershipTimes[id].orEmpty()
1615:                 )
1616:                 if (SyncMerge.shouldApplyIncoming(localModified, incomingModified)) {
1617:                     val restored = archived.toReadingQueue(exportedAt)
1618:                     val finalIsDeleted = !isSystemQueue && restored.isDeleted
1619:                     val deletionState = restoredDeletionState(finalIsDeleted)
1620:                     val base = restored.copy(
1621:                         // Keep the local identity: local memberships already point
1622:                         // at it, and for the system queue the incoming id is a
1623:                         // different platform's UUID entirely.
1624:                         id = existing.id,
1625:                         // iOS pins the system queue's name and kind rather than let
1626:                         // a restore rename it, and nothing may soft-delete it —
1627:                         // there is no UI that could ever bring it back.
1628:                         name = if (isSystemQueue) ReadingQueueKind.SAVED_FOR_LATER_NAME else restored.name,
1629:                         kindRaw = if (isSystemQueue) ReadingQueueKind.SAVED_FOR_LATER else restored.kindRaw,
1630:                         // Archived sort is not applied to Saved for Later. iOS
1631:                         // keeps `min(local, -1000)` from ensure.
1632:                         sortOrder = if (isSystemQueue) {
1633:                             minOf(existing.sortOrder, ReadingQueueKind.SAVED_FOR_LATER_SORT_ORDER)
1634:                         } else {
1635:                             restored.sortOrder
1636:                         },
1637:                         isDeleted = deletionState.isDeleted,
1638:                         deletedAt = if (deletionState.isDeleted) restored.deletedAt else null,
1639:                         permanentDeletionScheduledAt = keptDeletionSchedule(
1640:                             deletionState.permanentDeletionScheduledAt,
1641:                             existing.isDeleted,
```

`android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt` · pre-edit lines 1710–1720:

```kotlin
1710:             if (existing == null) {
1711:                 membershipsById[id] = restored
1712:                 membershipsCreated += 1
1713:             } else if (mode != BackupImportMode.MERGE &&
1714:                 SyncMerge.shouldApplyIncoming(existing.lastModifiedAt ?: existing.queuedAt, incomingModified)
1715:             ) {
1716:                 membershipsById[id] = restored
1717:                 membershipsUpdated += 1
1718:             }
1719:         }
1720:
```

### 3 · A3-5

`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Services/KudosBackup.swift` · pre-edit lines 2358–2374:

```swift
2358:                 if mode == .merge {
2359:                     if existing.isPendingDeletion {
2360:                         // Not in the active library (Recently Deleted). Merge
2361:                         // adds it back without planting a tombstone.
2362:                         existing.isPendingDeletion = false
2363:                         existing.deletedAt = nil
2364:                         existing.permanentDeletionScheduledAt = nil
2365:                         PreservedWorkService.retractTombstone(
2366:                             recordID: existing.id,
2367:                             type: .savedWork,
2368:                             ao3WorkID: existing.ao3WorkID
2369:                                 ?? archived.ao3WorkID
2370:                                 ?? WorkTags.ao3WorkID(from: existing.sourceURL),
2371:                             sourceURL: existing.sourceURL.isEmpty ? archived.sourceURL : existing.sourceURL,
2372:                             in: context
2373:                         )
2374:                         work = existing
```

`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Services/KudosBackup.swift` · pre-edit lines 2554–2563:

```swift
2554:             let isNewCollection: Bool
2555:             if let existing = collectionsByID[archived.id] {
2556:                 // Mirror the work path: Merge must be able to undo a prior
2557:                 // Replace that parked this collection in Recently Deleted.
2558:                 if mode == .merge, existing.isPendingDeletion {
2559:                     existing.isPendingDeletion = false
2560:                     existing.deletedAt = nil
2561:                     existing.permanentDeletionScheduledAt = nil
2562:                 }
2563:                 collection = existing
```

`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Services/KudosBackup.swift` · pre-edit lines 2785–2795:

```swift
2785:                 queue = savedForLaterQueue
2786:             } else if let existing = queuesByID[archived.id] {
2787:                 // Mirror the work path: Merge must be able to undo a prior
2788:                 // Replace that parked this queue in Recently Deleted.
2789:                 if mode == .merge, existing.isPendingDeletion {
2790:                     existing.isPendingDeletion = false
2791:                     existing.deletedAt = nil
2792:                     existing.permanentDeletionScheduledAt = nil
2793:                 }
2794:                 queue = existing
2795:             } else {
```

`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Services/PreservedWorkService.swift` · pre-edit lines 119–141:

```swift
119:     static func retractTombstone(
120:         recordID: UUID,
121:         type: SyncTombstoneRecordType,
122:         ao3WorkID: Int? = nil,
123:         sourceURL: String = "",
124:         in context: ModelContext
125:     ) {
126:         guard let tombstones = try? context.fetch(FetchDescriptor<SyncTombstone>()) else { return }
127:         let canonical = WorkTags.canonicalAO3WorkURL(from: sourceURL)
128:         for tombstone in tombstones where tombstone.recordType == type {
129:             let idMatch = tombstone.recordID == recordID
130:             let ao3Match = type == .savedWork
131:                 && ao3WorkID != nil
132:                 && tombstone.ao3WorkID == ao3WorkID
133:             let urlMatch = type == .savedWork
134:                 && canonical != nil
135:                 && WorkTags.canonicalAO3WorkURL(from: tombstone.sourceURL) == canonical
136:             if idMatch || ao3Match || urlMatch {
137:                 context.delete(tombstone)
138:             }
139:         }
140:     }
141:
```

`android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt` · pre-edit lines 198–214:

```kotlin
198:             } else if (mode == BackupImportMode.MERGE && existing.isDeleted) {
199:                 // Recently Deleted is not in the active library. File Merge
200:                 // adds it back without planting a tombstone, matching iOS. The clocks then
201:                 // decide the fields, as iOS's `apply` does: copying the archive row put last
202:                 // month's reading position over today's (audit A3-2).
203:                 summary = summary.copy(worksUpdated = summary.worksUpdated + 1)
204:                 mergeWork(
205:                     existing.copy(isDeleted = false, deletedAt = null, permanentDeletionScheduledAt = null),
206:                     restored, archived, incomingModifiedAt, exportedAt
207:                 ).copy(isDeleted = false, deletedAt = null, permanentDeletionScheduledAt = null)
208:             } else if (mode == BackupImportMode.MERGE) {
209:                 existing.copy(downloadedAt = existing.downloadedAt ?: restored.downloadedAt)
210:             } else if (mode == BackupImportMode.REPLACE_LIBRARY) {
211:                 summary = summary.copy(worksUpdated = summary.worksUpdated + 1)
212:                 applyReplaceWork(existing, restored)
213:             } else {
214:                 summary = summary.copy(worksUpdated = summary.worksUpdated + 1)
```

`android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt` · pre-edit lines 1281–1297:

```kotlin
1281:                             incomingModified
1282:                         ) == TombstoneResolution.SUPPRESS_STALE
1283:                     }
1284:                 val existingIds = existing.workIds
1285:                     .map { BackupPaths.normalizeIdForComparison(it) }
1286:                     .toSet()
1287:                 val added = incomingWorkIds.filter { it !in existingIds }
1288:                 val filled = fillCollectionFields(
1289:                     existing, archived, incomingWins = false, exportedAt = exportedAt
1290:                 )
1291:                 val target = if (added.isNotEmpty()) {
1292:                     filled.copy(workIds = filled.workIds + added)
1293:                 } else {
1294:                     filled
1295:                 }
1296:                 if (target != existing) {
1297:                     collectionsById[id] = target
```

`android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt` · pre-edit lines 1599–1605:

```kotlin
1599:                 } else {
1600:                     created
1601:                 }
1602:                 queuesCreated += 1
1603:             } else if (mode == BackupImportMode.MERGE) {
1604:                 // Keep local queue name / fields. New memberships still insert below.
1605:                 val filled = fillQueueFields(existing, archived, incomingWins = false)
```

`android/app/src/main/java/io/github/cidy02/kudos/works/WorkRepository.kt` · pre-edit lines 362–373:

```kotlin
362:     suspend fun restoreFromRecentlyDeleted(workId: String): SavedWork? {
363:         val work = getWork(workId) ?: return null
364:         val now = clock()
365:         val restored = work.copy(
366:             isDeleted = false,
367:             deletedAt = null,
368:             permanentDeletionScheduledAt = null,
369:             lastModifiedAt = now
370:         )
371:         upsert(restored)
372:         retractWorkTombstone(work)
373:         return restored
```

`android/app/src/main/java/io/github/cidy02/kudos/works/WorkRepository.kt` · pre-edit lines 509–533:

```kotlin
509:     suspend fun retractWorkTombstone(
510:         recordId: String,
511:         ao3WorkId: Int? = null,
512:         sourceUrl: String = ""
513:     ) {
514:         val canonical = WorkTags.canonicalAO3WorkURL(sourceUrl).orEmpty()
515:         tombstoneDao.deleteSavedWorkByIdentity(
516:             recordId = recordId,
517:             ao3WorkId = ao3WorkId,
518:             canonicalSourceUrl = canonical,
519:             sourceUrl = sourceUrl,
520:             recordType = SyncTombstoneRecordType.SAVED_WORK
521:         )
522:     }
523:
524:     private suspend fun retractWorkTombstone(work: SavedWork) {
525:         val ao3Id = WorkTags.ao3WorkIdFromUrl(work.sourceUrl)
526:             ?.takeIf { it in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong() }
527:             ?.toInt()
528:         retractWorkTombstone(
529:             recordId = work.id,
530:             ao3WorkId = ao3Id,
531:             sourceUrl = work.sourceUrl
532:         )
533:     }
```

### 4 · A3-7

`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Services/KudosBackup.swift` · pre-edit lines 3830–3845:

```swift
3830:                 if preexistingIDs.contains(local.id), !local.note.isEmpty, archived.note != local.note {
3831:                     parkDisplacedNote(local.note, from: local, work: work, in: context)
3832:                 }
3833:                 local.kindRaw = archived.kindRaw
3834:                 local.colorRaw = archived.colorRaw
3835:                 local.locatorString = archived.locatorString
3836:                 local.selectedText = archived.selectedText
3837:                 local.note = archived.note
3838:                 local.progression = archived.progression
3839:                 local.spineIndex = archived.spineIndex
3840:                 local.chapterTitle = archived.chapterTitle
3841:                 local.createdAt = min(local.createdAt, archived.createdAt)
3842:                 local.lastModifiedAt = incomingModifiedAt
3843:                 local.deletedAt = archived.deletedAt
3844:                 local.isPendingDeletion = archived.isPendingDeletion
3845:                 // Re-home onto the work this restore just resolved — usually a
```

`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Services/KudosBackup.swift` · pre-edit lines 3905–3931:

```swift
3905:     private static func parkDisplacedNote(
3906:         _ note: String,
3907:         from original: ReadingAnnotation,
3908:         work: SavedWork,
3909:         in context: ModelContext,
3910:         now: Date = Date()
3911:     ) -> ReadingAnnotation? {
3912:         guard !note.isEmpty else { return nil }
3913:         let parked = ReadingAnnotation(
3914:             work: work,
3915:             kind: original.kind,
3916:             locatorString: original.locatorString,
3917:             selectedText: original.selectedText,
3918:             note: note,
3919:             color: original.color,
3920:             progression: original.progression,
3921:             spineIndex: original.spineIndex,
3922:             chapterTitle: original.chapterTitle,
3923:             createdAt: original.createdAt
3924:         )
3925:         // Born hidden: it is a salvage record, not a second live highlight. Dedup skips
3926:         // pending-deletion rows, so it never competes with the live one it was split from.
3927:         parked.isPendingDeletion = true
3928:         parked.deletedAt = now
3929:         parked.lastModifiedAt = now
3930:         context.insert(parked)
3931:         return parked
```

`android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt` · pre-edit lines 2050–2064:

```kotlin
2050:             if (existing == null) {
2051:                 byId[id] = restored
2052:                 created += 1
2053:             } else if (mode == BackupImportMode.MERGE) {
2054:                 // Keep local note / locator / color. New ids still insert above.
2055:             } else if (mode == BackupImportMode.REPLACE_LIBRARY ||
2056:                 SyncMerge.shouldApplyIncoming(existing.effectiveLastModifiedAt, incomingModified)
2057:             ) {
2058:                 byId[id] = restored.copy(
2059:                     createdAt = minInstant(existing.createdAt, restored.createdAt)
2060:                 )
2061:                 updated += 1
2062:             }
2063:         }
2064:
```

### 5 · A3-8

`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Features/ReaderReadium/ReadiumReaderView.swift` · pre-edit lines 858–862:

```swift
858:         // Signed: see `toggleBookmarkAtCurrentPosition` (audit A12-2).
859:         SyncTombstones.recordDeletion(of: annotation, in: modelContext, reason: "annotationDeleted")
860:         modelContext.delete(annotation)
861:         try? modelContext.save()
862:         FolderSyncService.markDirty()
```

`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Services/ReadingQueueService.swift` · pre-edit lines 726–740:

```swift
726:
727:     static func removeFromQueue(_ work: SavedWork, from queue: ReadingQueue, in context: ModelContext) {
728:         let matches = work.queueMemberships.filter { $0.queue?.id == queue.id }
729:         for membership in matches {
730:             SyncTombstones.recordDeletion(of: membership, in: context)
731:             work.queueMemberships.removeAll { $0.id == membership.id }
732:             queue.memberships.removeAll { $0.id == membership.id }
733:             context.delete(membership)
734:         }
735:         let now = Date()
736:         queue.markMembershipChanged(now)
737:         work.markModified(now)
738:         work.isQueuedForLater = !work.queueMemberships.isEmpty
739:         normalize(work)
740:         context.saveBestEffort(reason: "Saving queue removal failed")
```

`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Services/WorkLifecycle.swift` · pre-edit lines 171–194:

```swift
171:     static func hardDelete(_ work: SavedWork, in context: ModelContext) {
172:         SyncTombstones.recordDeletion(of: work, in: context)
173:         // The cascade delete rule on SavedWork.queueMemberships removes these rows as a
174:         // side effect of context.delete(work) below — tombstone them explicitly first so
175:         // a future cloud merge doesn't resurrect a queue membership for a deleted work.
176:         for membership in work.queueMemberships {
177:             SyncTombstones.recordDeletion(of: membership, in: context)
178:         }
179:         // ReadingAnnotation.work has no @Relationship cascade rule (it's a plain
180:         // optional, unlike queueMemberships above), so SwiftData's default
181:         // .nullify would otherwise leave these rows behind forever — orphaned,
182:         // untombstoned, and invisible to every list (they all filter by
183:         // work?.id). Fetch and delete them explicitly, tombstoning each first so
184:         // a future restore from an older archive can't resurrect a mark whose
185:         // book no longer exists.
186:         let workID = work.id
187:         let orphanedAnnotations = (try? context.fetch(FetchDescriptor<ReadingAnnotation>()))?
188:             .filter { $0.work?.id == workID } ?? []
189:         for annotation in orphanedAnnotations {
190:             SyncTombstones.recordDeletion(of: annotation, in: context)
191:             context.delete(annotation)
192:         }
193:         try? FileManager.default.removeItem(at: work.fileURL)
194:         try? FileManager.default.removeItem(at: Storage.readerDirectory(for: work.id))
```

`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Features/Library/Collections.swift` · pre-edit lines 524–529:

```swift
524:     private func remove(_ work: SavedWork) {
525:         SyncTombstones.recordCollectionMembershipRemoval(work: work, collection: collection, in: context)
526:         work.collections.removeAll { $0.id == collection.id }
527:         work.markModified()
528:         collection.markMembershipChanged()
529:         try? context.save()
```

`android/app/src/main/java/io/github/cidy02/kudos/reader/AnnotationRepository.kt` · pre-edit lines 43–61:

```kotlin
43:     suspend fun deleteAnnotation(id: String) {
44:         val existing = dao.getById(id)
45:         dao.deleteById(id)
46:         if (existing == null) return
47:         val now = clock()
48:         tombstoneDao.upsert(
49:             TombstoneSigning.sign(
50:                 SyncTombstone(
51:                     id = uuidFactory(),
52:                     recordID = id.lowercase(),
53:                     recordTypeRaw = SyncTombstoneRecordType.READING_ANNOTATION,
54:                     createdAt = now,
55:                     lastModifiedAt = now,
56:                     deletionReason = "annotationDeleted"
57:                 )
58:             ).toEntity()
59:         )
60:     }
61:
```

`android/app/src/main/java/io/github/cidy02/kudos/library/ReadingQueueRepository.kt` · pre-edit lines 140–158:

```kotlin
140:         val existing = queueDao.getMembershipForWork(queueId, workId) ?: return
141:         val now = clock()
142:
143:         queueDao.deleteMembershipById(existing.id)
144:         // Without a tombstone, restoring a backup that still lists this membership
145:         // silently resurrects it (mergeQueues/TombstoneIndex.membershipResolution
146:         // expect one to exist for every removed membership).
147:         upsertSignedTombstone(
148:             SyncTombstone(
149:                 id = uuidFactory(),
150:                 recordID = existing.id,
151:                 recordTypeRaw = SyncTombstoneRecordType.READING_QUEUE_MEMBERSHIP,
152:                 createdAt = now,
153:                 lastModifiedAt = now,
154:                 deletedOnDeviceID = "",
155:                 deletionReason = "queueMembershipRemoved"
156:             )
157:         )
158:         touchQueueMembershipChanged(queueId, now)
```

`android/app/src/main/java/io/github/cidy02/kudos/works/WorkRepository.kt` · pre-edit lines 381–427:

```kotlin
381:     suspend fun hardDelete(workId: String) {
382:         val work = getWork(workId)
383:         deleteDependents(workId)
384:         fileStore.deleteWorkEpub(workId)
385:         workDao.deleteById(workId)
386:         if (work != null) {
387:             recordWorkTombstone(work, clock(), deletionReason = "workDeleted")
388:         }
389:     }
390:
391:     /**
392:      * Queue memberships and annotations have no foreign key to `works`, so they
393:      * would outlive the work: orphaned, and resurrectable by an older backup.
394:      * Tombstone each and delete it, as iOS `WorkLifecycle.hardDelete` does, in
395:      * the same shapes `ReadingQueueRepository.removeWork` and
396:      * `AnnotationRepository.deleteAnnotation` write.
397:      */
398:     private suspend fun deleteDependents(workId: String) {
399:         val now = clock()
400:         for (membership in queueDao.getMembershipsForWork(workId)) {
401:             queueDao.deleteMembershipById(membership.id)
402:             upsertSignedTombstone(
403:                 SyncTombstone(
404:                     id = uuidFactory(),
405:                     recordID = membership.id,
406:                     recordTypeRaw = SyncTombstoneRecordType.READING_QUEUE_MEMBERSHIP,
407:                     createdAt = now,
408:                     lastModifiedAt = now,
409:                     deletedOnDeviceID = "",
410:                     deletionReason = "queueMembershipRemoved"
411:                 )
412:             )
413:         }
414:         for (annotation in annotationDao.getAllForWork(workId)) {
415:             annotationDao.deleteById(annotation.id)
416:             upsertSignedTombstone(
417:                 SyncTombstone(
418:                     id = uuidFactory(),
419:                     recordID = annotation.id.lowercase(),
420:                     recordTypeRaw = SyncTombstoneRecordType.READING_ANNOTATION,
421:                     createdAt = now,
422:                     lastModifiedAt = now,
423:                     deletionReason = "annotationDeleted"
424:                 )
425:             )
426:         }
427:     }
```

`android/app/src/main/java/io/github/cidy02/kudos/works/WorkRepository.kt` · pre-edit lines 795–813:

```kotlin
795:     suspend fun removeFromCollection(workId: String, collectionId: String): List<WorkCollection> {
796:         collectionDao.removeWork(collectionId, workId)
797:         touchCollection(collectionId)
798:         val now = clock()
799:         // Without a tombstone, restoring a backup that still lists this membership
800:         // silently resurrects it — same reasoning as reading-queue removeWork.
801:         upsertSignedTombstone(
802:             SyncTombstone(
803:                 id = uuidFactory(),
804:                 recordID = membershipRecordId(collectionId, workId),
805:                 recordTypeRaw = SyncTombstoneRecordType.WORK_COLLECTION_MEMBERSHIP,
806:                 createdAt = now,
807:                 lastModifiedAt = now,
808:                 deletedOnDeviceID = "",
809:                 deletionReason = "collectionMembershipRemoved"
810:             )
811:         )
812:         return collectionsForWork(workId)
813:     }
```

`android/app/src/main/java/io/github/cidy02/kudos/search/SavedSearchRepository.kt` · pre-edit lines 48–68:

```kotlin
48:     suspend fun delete(id: String) {
49:         val existing = dao.getById(id)
50:         if (existing != null && tombstoneDao != null) {
51:             val now = clock()
52:             tombstoneDao.upsert(
53:                 TombstoneSigning.sign(
54:                     SyncTombstone(
55:                         id = uuidFactory(),
56:                         recordID = id.lowercase(),
57:                         recordTypeRaw = SyncTombstoneRecordType.SAVED_SEARCH,
58:                         createdAt = now,
59:                         lastModifiedAt = now,
60:                         deletionReason = "savedSearchDeleted"
61:                     )
62:                 ).toEntity()
63:             )
64:         }
65:         dao.deleteById(id)
66:     }
67:
68:     fun filtersOf(saved: SavedSearch): AO3SearchFilters {
```

### 6 · merge suspicions

`android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMappers.kt` · unchanged incoming DTO mapping (used by the winning `restored.copy`):

```kotlin
287:         ao3Unavailable = ao3Unavailable ?: false,
288:         lastAvailabilityCheck = BackupValidator.parseNullableInstant(
289:             lastAvailabilityCheck?.takeIf { it.isNotBlank() },
290:             "work.lastAvailabilityCheck",
```

`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Services/KudosBackup.swift` · pre-edit lines 4414–4416:

```swift
4414:         if let assetIdentifier = archived.assetIdentifier, !assetIdentifier.isEmpty {
4415:             work.assetIdentifier = work.assetIdentifier.isEmpty ? assetIdentifier : work.assetIdentifier
4416:         }
```

`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Services/KudosBackup.swift` · pre-edit lines 4507–4508:

```swift
4507:         work.ao3Unavailable = work.ao3Unavailable || archived.ao3Unavailable
4508:         work.isQueuedForLater = work.isQueuedForLater || archived.isQueuedForLater
```

`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Services/KudosBackup.swift` · pre-edit lines 3950–4002:

```swift
3950:     private static func dedupeSamePassageAnnotations(
3951:         context: ModelContext,
3952:         preexistingIDs: Set<UUID>
3953:     ) {
3954:         let live = ((try? context.fetch(FetchDescriptor<ReadingAnnotation>())) ?? [])
3955:             .filter { !$0.isPendingDeletion && $0.deletedAt == nil }
3956:
3957:         var groups: [String: [ReadingAnnotation]] = [:]
3958:         for annotation in live {
3959:             guard let workID = annotation.work?.id else { continue }
3960:             let key = "\(workID.uuidString)|\(annotation.kindRaw)|\(annotation.locatorString)"
3961:             groups[key, default: []].append(annotation)
3962:         }
3963:
3964:         for group in groups.values where group.count > 1 {
3965:             let ranked = group.sorted {
3966:                 if $0.lastModifiedAt != $1.lastModifiedAt { return $0.lastModifiedAt > $1.lastModifiedAt }
3967:                 return $0.id.uuidString < $1.id.uuidString
3968:             }
3969:             guard let winner = ranked.first else { continue }
3970:             for loser in ranked.dropFirst() {
3971:                 if !loser.note.isEmpty, winner.note != loser.note {
3972:                     if winner.note.isEmpty {
3973:                         // Empty-winner fill, as before the audit: no text is in contention,
3974:                         // so the rescued note simply becomes the winner's.
3975:                         winner.note = loser.note
3976:                         // Salvaging is a real content edit: without stamping it, the winner
3977:                         // keeps its old `lastModifiedAt`, and the very next merge would see a
3978:                         // "newer" remote copy of the winner (which still has an empty note)
3979:                         // and overwrite the rescued note — silently undoing this salvage.
3980:                         winner.markModified()
3981:                     } else if let work = loser.work {
3982:                         // Both notes are non-empty and different. Concatenating them onto the
3983:                         // winner was the first fix and it ping-pongs without bound between two
3984:                         // honest devices (see `parkDisplacedNote`). Park instead: the winner
3985:                         // stays a clean LWW result and the loser's text is still not lost.
3986:                         parkDisplacedNote(loser.note, from: loser, work: work, in: context)
3987:                     }
3988:                 }
3989:                 SyncTombstones.recordDeletion(of: loser, in: context, reason: "samePassageDeduped")
3990:                 if preexistingIDs.contains(loser.id) {
3991:                     // Soft-delete: the row and its text survive and can be recovered.
3992:                     loser.isPendingDeletion = true
3993:                     loser.deletedAt = Date()
3994:                     loser.markModified()
3995:                 } else {
3996:                     context.delete(loser)
3997:                 }
3998:             }
3999:         }
4000:     }
4001:
4002:     private struct TombstoneIndex {
```

`android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt` · pre-edit lines 793–807:

```kotlin
793:                 hiddenFromHistoryAt = if (archived.hiddenFromHistoryAt != null) restored.hiddenFromHistoryAt else existing.hiddenFromHistoryAt,
794:                 datePublished = restored.datePublished.ifBlank { existing.datePublished },
795:                 dateUpdated = restored.dateUpdated.ifBlank { existing.dateUpdated },
796:                 epubDigest = restored.epubDigest.ifBlank { existing.epubDigest },
797:                 assetIdentifier = restored.assetIdentifier.ifBlank { existing.assetIdentifier },
798:                 bookmarks = archived.bookmarks ?: existing.bookmarks,
799:                 ao3SeriesID = archived.ao3SeriesID ?: existing.ao3SeriesID,
800:                 ao3WorkID = archived.ao3WorkID ?: existing.ao3WorkID
801:             )
802:         } else {
803:             // Keep local flags/metadata; still absorb non-destructive fills.
804:             existing.copy(
805:                 hasEpub = existing.hasEpub || restored.hasEpub,
806:                 isQueuedForLater = existing.isQueuedForLater || restored.isQueuedForLater,
807:                 title = existing.title.ifBlank { restored.title },
```

`android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt` · pre-edit lines 2078–2090:

```kotlin
2078:             suppressed = suppressed
2079:         )
2080:     }
2081:
2082:     private fun Map<String, ByteArray>.normalizedWorkFileMap(): Map<String, ByteArray> {
2083:         return mapKeys { BackupPaths.normalizeIdForComparison(it.key) }
2084:     }
2085:
2086:     private fun BackupSettingsPayload.retargetRenamedFont(
2087:         renamedFonts: Map<String, String>
2088:     ): BackupSettingsPayload {
2089:         if (!readerFontID.startsWith("custom:")) return this
2090:         val fileName = readerFontID.removePrefix("custom:")
```

### 7 · A12-2/A12-3

`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Services/KudosBackup.swift` · pre-edit lines 3544–3570:

```swift
3544:     /// Deletes local records an accepted, newer tombstone covers.
3545:     ///
3546:     /// `resolution` is the same check the incoming loop runs, asked the other way
3547:     /// round: not "should this arriving record be suppressed" but "has this record
3548:     /// already here been deleted elsewhere".
3549:     ///
3550:     /// **Never in `replaceLibrary`.** That mode deliberately bypasses tombstones —
3551:     /// it is "make this device look like the archive", and the archive wins even
3552:     /// over a local delete. Running this pass there made a repeated identical
3553:     /// replacement destructive: the first replace restores a record the archive
3554:     /// contains, the tombstone from the earlier local delete is still on file, and
3555:     /// the second replace deletes what it had just restored. [1,1,1] became
3556:     /// [0,0,0] on the second run. The same `mode` guard the incoming loop already
3557:     /// has belongs here.
3558:     private static func applyTombstonesToExisting<Record: PersistentModel>(
3559:         _ records: [Record],
3560:         in context: ModelContext,
3561:         mode: BackupImportMode,
3562:         resolution: (Record) -> SyncMerge.TombstoneResolution
3563:     ) {
3564:         guard mode != .replaceLibrary else { return }
3565:         for record in records {
3566:             if case .suppressStaleData = resolution(record) {
3567:                 context.delete(record)
3568:             }
3569:         }
3570:     }
```

`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Services/KudosBackup.swift` · pre-edit lines 3115–3150:

```swift
3115:         )
3116:
3117:         let existingBookmarks = try context.fetch(FetchDescriptor<Bookmark>())
3118:         var bookmarksByURL = Dictionary(
3119:             existingBookmarks.map { ($0.urlString, $0) },
3120:             uniquingKeysWith: { first, _ in first }
3121:         )
3122:         for archived in contents.manifest.bookmarks {
3123:             if mode != .replaceLibrary {
3124:                 switch tombstones.bookmarkResolution(
3125:                     id: archived.id,
3126:                     incomingModifiedAt: archived.dateAdded
3127:                 ) {
3128:                 case .suppressStaleData:
3129:                     continue
3130:                 case .reviveNewerData, .preserveAmbiguous, .noTombstone:
3131:                     break
3132:                 }
3133:             }
3134:             let bookmark: Bookmark
3135:             if let existing = bookmarksByURL[archived.urlString] {
3136:                 bookmark = existing
3137:             } else {
3138:                 bookmark = Bookmark(title: archived.title, urlString: archived.urlString)
3139:                 bookmark.id = archived.id
3140:                 context.insert(bookmark)
3141:                 bookmarksByURL[archived.urlString] = bookmark
3142:             }
3143:             bookmark.title = archived.title
3144:             bookmark.dateAdded = archived.dateAdded
3145:         }
3146:         if mode == .replaceLibrary {
3147:             // Immediate-delete class, same as ReadingAnnotation: mint a
3148:             // signed tombstone then hard-delete. No Recently Deleted UI.
3149:             let snapshotURLs = Set(contents.manifest.bookmarks.map(\.urlString))
3150:             for bookmark in existingBookmarks where !snapshotURLs.contains(bookmark.urlString) {
```

`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Services/KudosBackup.swift` · pre-edit lines 3785–3807:

```swift
3785:         guard !contents.manifest.annotations.isEmpty else { return }
3786:         let existing = (try? context.fetch(FetchDescriptor<ReadingAnnotation>())) ?? []
3787:         var byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
3788:         // Everything that already belonged to this device before the archive was
3789:         // applied. `dedupeSamePassageAnnotations` must never hard-delete one of these
3790:         // (see its doc comment); it needs the set to tell them from records this
3791:         // restore has just inserted.
3792:         let preexistingIDs = Set(existing.map(\.id))
3793:
3794:         for archived in contents.manifest.annotations {
3795:             guard let work = restoredWorksByArchivedID[archived.workID] else { continue }
3796:             let incomingModifiedAt = archived.lastModifiedAt ?? archived.createdAt
3797:
3798:             switch tombstones.annotationResolution(id: archived.id, incomingModifiedAt: incomingModifiedAt) {
3799:             case .suppressStaleData:
3800:                 // Deleted here on purpose — an older archive must not revive it.
3801:                 suppressed += 1
3802:                 continue
3803:             case .reviveNewerData, .preserveAmbiguous, .noTombstone:
3804:                 break
3805:             }
3806:
3807:             if let local = byID[archived.id] {
```

`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Services/KudosBackup.swift` · pre-edit lines 2955–2975:

```swift
2955:             switch tombstones.membershipResolution(
2956:                 id: archived.id,
2957:                 incomingModifiedAt: archived.lastModifiedAt ?? archived.queuedAt
2958:             ) {
2959:             case .suppressStaleData:
2960:                 // The user explicitly removed this queue membership on this device —
2961:                 // don't resurrect it from an older backup.
2962:                 suppressedQueueMemberships += 1
2963:                 continue
2964:             case .preserveAmbiguous:
2965:                 ambiguousQueueConflicts += 1
2966:             case .reviveNewerData, .noTombstone:
2967:                 break
2968:             }
2969:             if suppressedQueueIDs.contains(archived.queueID) {
2970:                 // Its whole queue was deleted here; dropping the membership with it is
2971:                 // the user's intent — never re-home it into Saved for Later.
2972:                 continue
2973:             }
2974:             let queue: ReadingQueue
2975:             if let mapped = queueIDMap[archived.queueID] {
```

`android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt` · pre-edit lines 974–1001:

```kotlin
974:                 val incomingModified = BackupValidator.parseInstant(
975:                     archived.dateAdded,
976:                     "bookmark.dateAdded",
977:                     exportedAt
978:                 )
979:                 if (tombstoneIndex.bookmarkResolution(archivedId, incomingModified) ==
980:                     TombstoneResolution.SUPPRESS_STALE
981:                 ) {
982:                     return@forEach
983:                 }
984:             }
985:             val existing = byUrl[archived.urlString]
986:             byUrl[archived.urlString] = if (existing == null) {
987:                 created += 1
988:                 archived.toBookmark(exportedAt)
989:             } else {
990:                 updated += 1
991:                 existing.copy(
992:                     title = archived.title,
993:                     dateAdded = BackupValidator.parseInstant(
994:                         archived.dateAdded,
995:                         "bookmark.dateAdded",
996:                         exportedAt
997:                     )
998:                 )
999:             }
1000:         }
1001:         if (mode == BackupImportMode.REPLACE_LIBRARY) {
```

`android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt` · pre-edit lines 1463–1478:

```kotlin
1463:         // A search this device still has that a trusted tombstone says was deleted
1464:         // elsewhere (iOS `applyTombstonesToExisting`). The loop above only declines
1465:         // to add one back: the copy already here stayed visible, and was published
1466:         // again on the next export, so the deletion could never settle between two
1467:         // devices. The reading-log merges below already make this pass. Never in
1468:         // Replace, which is "make this device look like the archive".
1469:         if (mode != BackupImportMode.REPLACE_LIBRARY) {
1470:             searchesById.entries.removeAll { (id, search) ->
1471:                 tombstoneIndex.savedSearchResolution(id, search.dateAdded) ==
1472:                     TombstoneResolution.SUPPRESS_STALE
1473:             }
1474:         }
1475:
1476:         if (mode == BackupImportMode.REPLACE_LIBRARY) {
1477:             val incomingIds = incoming.mapTo(mutableSetOf()) {
1478:                 BackupPaths.canonicalUuid(it.id, "savedSearch.id")
```

`android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt` · pre-edit lines 1680–1725:

```kotlin
1680:         incomingMemberships.forEach { archived ->
1681:             val id = BackupPaths.canonicalUuid(archived.id, "membership.id")
1682:             val incomingQueueId = BackupPaths.canonicalUuid(archived.queueID, "membership.queueID")
1683:             // Follow the system-queue remap above, or these memberships would point
1684:             // at the *other* platform's queue UUID and be dropped on the next line.
1685:             val queueId = queueIdRemap[incomingQueueId] ?: incomingQueueId
1686:             val workId = remapWorkId(
1687:                 BackupPaths.canonicalUuid(archived.workID, "membership.workID"),
1688:                 workIdRemap
1689:             )
1690:             if (queueId !in queuesById) return@forEach
1691:             if (workId !in worksById) return@forEach
1692:
1693:             val incomingModified = sanitizeArchivedLastModifiedAt(
1694:                 archived.lastModifiedAt,
1695:                 exportedAt,
1696:                 now
1697:             ) ?: parseOptionalInstant(archived.queuedAt.takeIf { it.isNotBlank() }, exportedAt)
1698:
1699:             when (tombstoneIndex.membershipResolution(id, incomingModified)) {
1700:                 TombstoneResolution.SUPPRESS_STALE -> {
1701:                     membershipsSuppressed += 1
1702:                     return@forEach
1703:                 }
1704:                 else -> Unit
1705:             }
1706:
1707:             val existing = membershipsById[id]
1708:             val restored = archived.toReadingQueueMembership(exportedAt)
1709:                 .copy(queueID = queueId, workID = workId)
1710:             if (existing == null) {
1711:                 membershipsById[id] = restored
1712:                 membershipsCreated += 1
1713:             } else if (mode != BackupImportMode.MERGE &&
1714:                 SyncMerge.shouldApplyIncoming(existing.lastModifiedAt ?: existing.queuedAt, incomingModified)
1715:             ) {
1716:                 membershipsById[id] = restored
1717:                 membershipsUpdated += 1
1718:             }
1719:         }
1720:
1721:         if (mode == BackupImportMode.REPLACE_LIBRARY) {
1722:             val incomingQueueIds = incomingQueues.mapTo(mutableSetOf()) { archived ->
1723:                 val incomingId = BackupPaths.canonicalUuid(archived.id, "queue.id")
1724:                 queueIdRemap[incomingId] ?: incomingId
1725:             }
```

`android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt` · pre-edit lines 2029–2087:

```kotlin
2029:             // here (as this used to) means a highlight deleted on iOS silently comes
2030:             // back on Android. iOS assigns `isPendingDeletion` through instead, and
2031:             // the LWW check below decides whether the deletion actually wins.
2032:
2033:             val incomingModified = sanitizeArchivedLastModifiedAt(
2034:                 archived.lastModifiedAt,
2035:                 exportedAt,
2036:                 now
2037:             ) ?: parseOptionalInstant(archived.createdAt.takeIf { it.isNotBlank() }, exportedAt)
2038:                 ?: Instant.EPOCH
2039:
2040:             when (tombstoneIndex.annotationResolution(id, incomingModified)) {
2041:                 TombstoneResolution.SUPPRESS_STALE -> {
2042:                     suppressed += 1
2043:                     return@forEach
2044:                 }
2045:                 else -> Unit
2046:             }
2047:
2048:             val existing = byId[id]
2049:             val restored = archived.toReadingAnnotation(exportedAt).copy(workID = workId)
2050:             if (existing == null) {
2051:                 byId[id] = restored
2052:                 created += 1
2053:             } else if (mode == BackupImportMode.MERGE) {
2054:                 // Keep local note / locator / color. New ids still insert above.
2055:             } else if (mode == BackupImportMode.REPLACE_LIBRARY ||
2056:                 SyncMerge.shouldApplyIncoming(existing.effectiveLastModifiedAt, incomingModified)
2057:             ) {
2058:                 byId[id] = restored.copy(
2059:                     createdAt = minInstant(existing.createdAt, restored.createdAt)
2060:                 )
2061:                 updated += 1
2062:             }
2063:         }
2064:
2065:         if (mode == BackupImportMode.REPLACE_LIBRARY) {
2066:             val incomingIds = incoming.mapTo(mutableSetOf()) {
2067:                 BackupPaths.canonicalUuid(it.id, "annotation.id")
2068:             }
2069:             byId.keys.toList().forEach { id ->
2070:                 if (id !in incomingIds) byId.remove(id)
2071:             }
2072:         }
2073:
2074:         return AnnotationMerge(
2075:             items = byId.values.sortedBy { it.createdAt },
2076:             created = created,
2077:             updated = updated,
2078:             suppressed = suppressed
2079:         )
2080:     }
2081:
2082:     private fun Map<String, ByteArray>.normalizedWorkFileMap(): Map<String, ByteArray> {
2083:         return mapKeys { BackupPaths.normalizeIdForComparison(it.key) }
2084:     }
2085:
2086:     private fun BackupSettingsPayload.retargetRenamedFont(
2087:         renamedFonts: Map<String, String>
```

## Verified findings and implementation

1. **A3-3 true.** `mergeWork` now takes `min(dateAdded)` after either clock branch;
   Replace already did and keeps it. Collections take the minimum in Replace,
   winning reconcile and the shared fill path; queues do in the shared fill path.
   T-353 is actually in `docs/android-port/DECISIONS.md:14–18`, not a root `DECISIONS.md`.
   **iOS wins over the broad wording:** an active work in File Merge is skipped at
   Swift line 2409; its Date Added stays local. A returned, formerly deleted work does run
   `apply` and takes the minimum. Tests cover both date orders and both clock winners in
   all three modes, plus returned works separately.

2. **A3-4 true.** Replace forces the incoming queue and membership; reconcile stays LWW,
   File Merge stays add-only. System queue matching by kind, local UUID, pinned name/kind
   and sort remain. Reading-session and favorite merge functions were read and left LWW.
   Queue creation date remains the earlier copy. **iOS wins over “takes the archive”
   literally for edit clocks:** contents take the snapshot, but `dateUpdated` and
   `lastMembershipChangedAt` keep the newer existing clock (Swift lines 2932–2935).

3. **A3-5 true.** File Merge clears deletion state on a returned collection/queue,
   only when the existing row was deleted, as Swift's `existing.isPendingDeletion` guard says.
   A returned work retracts saved-work markers by UUID, AO3 ID and canonical address.
   `WorkRepository.retractWorkTombstone` now has a pure overload used by BOTH snapshot
   merge and the existing live Recently Deleted restore. It canonicalizes both addresses,
   as Swift does, so a tombstone with a chapter/query variant is retracted too; other kinds
   and other works stay. Live restore reads the tombstone table once to reuse that rule,
   then deletes matching IDs. Merge uses the already-captured list, with no extra DB read.
   The apply path persists only captured, unchanged saved-work tombstones absent from the
   merged set; it never deletes a new/changed tombstone just because it was not captured.
   Removing from the snapshot alone was insufficient: `applyStoredMerge` used to only upsert
   tombstones, so Room would have exported the old marker again.

4. **A3-7 true.** A winning same-id update first parks a non-empty, different local note.
   The new sibling gets a fresh UUID (Swift's omitted `id` argument defaults to `UUID()`,
   `Models/Models.swift:1095`), the resolved work, original enum kind, locator, selection, note,
   enum colour, progression, spine, chapter and `createdAt`. It gets `isPendingDeletion = true`,
   `deletedAt = now`, `lastModifiedAt = now`. Unknown stored kind/colour use Swift's enum getters' defaults (bookmark/yellow),
   only on the parked copy; raw kinds/colours on the live row are not rewritten.
   Nothing is concatenated onto the live note. A newer archive that still wins against
   a note typed between capture and apply parks that intervening text too, through the
   same helper; the capture-time sibling alone would not have saved it.
   Replace's cleanup preserves salvage siblings born during that import.
   Identical/empty notes and a losing archive make no sibling; File Merge does not overwrite.

   **Visibility/retention checked in code, not on screen:**
   `AnnotationDao.observeForWork` filters `isPendingDeletion = 0`; `ReaderViewModel` builds
   its bookmark/highlight lists from that flow. `RecentlyDeletedViewModel` in
   `library/RecentlyDeletedScreen.kt` builds work, held-copy, collection and queue rows only
   (lines 144–195 before changes), no annotations. No annotation-specific expiry/sweep was
   found; annotations have no permanent-deletion schedule. A parked row therefore remains
   hidden and exportable beyond 90 days, while its work exists. Permanently deleting the
   work deletes ALL its annotations, including parked ones, and tombstones them. There is
   no tap-to-recover UI; this matches Swift's explicit limitation in the `parkDisplacedNote` doc comment.
   `captureStoredRows` reads `annotationDao.getAll()`, so hidden rows travel in backup.
   A Room test exercises hiding, capture/export input and the work sweep after 91 days.

5. **A3-8 true at all four sites.** Annotation deletion uses a concrete Room `@Transaction`
   DAO method across the annotation/tombstone DAOs. Queue removal and collection removal
   use `database.withTransaction` around marker-first delete plus their clock updates.
   Work hard deletion records the work marker, tombstones/deletes each dependent, and
   deletes the work in one Room transaction. The EPUB is removed after successful commit:
   a DAO failure leaves its bytes. Function signatures and constructors stay unchanged.

   **Correction to the premise:** `SavedSearchRepository.delete` is marker-first but
   NOT transactional; there is no `withTransaction` or `@Transaction` around its two DAO
   calls. It was left alone (not one of the four named sites).

   Atomicity tests use a real in-memory Room database with temporary SQLite triggers.
   The real DAO delete statement first checks its marker exists, then throws `secondStatement`.
   Every rollback assertion requires the original row AND no marker, plus unchanged owner
   clocks. Old code instead throws `tombstoneMissing`, which fails the test. Work tests also
   fail the second write (dependent tombstone insertion), and fail the final work delete
   AFTER dependent deletes; both must retain all rows, collection cross-ref and (for the
   final-delete test) the EPUB. Success paths enforce marker-first and assert row-gone +
   marker-present. These tests are written, not run here; Room-generated transaction
   behavior and KSP compilation specifically need Claude's run.

6. **All three merge suspicions true; iOS's rules are unambiguous.**
   - `ao3Unavailable` now ORs across work reconciliation/returned-work merge and Replace,
     matching `apply`. Losing an unavailability fact can cause another device to treat an
     unavailable AO3 work as available and attempt metadata/download work. No path proving
     EPUB deletion from this boolean was found; do not claim it deleted a library file.
   - `assetIdentifier` fills only an EMPTY local value, including Replace. An archive could
     otherwise rewrite the exported identifier of an existing preserved/custom iOS file;
     Android reads its EPUB by work UUID (`WorkFileStore.workEpubPath`), so direct Android
     byte loss was not established. Empty-library insertion still uses `<UUID>.epub`, as
     iOS's constructor + fill-only `apply` already did. Active File Merge keeps local state.
   - Same work + raw kind + EXACT locator deduplicates live rows after annotation restore.
     Newest modification wins; equal dates use UUID order. Only live rows with a resolved
     work compete. Non-empty loser notes fill an empty winner AND stamp its edit, or park
     on a hidden sibling when both differ. Every loser gets a signed `samePassageDeduped`
     tombstone; pre-existing losers stay as hidden rows, newly inserted losers are removed.
     Before: duplicate marks, not demonstrated note loss (both rows remained). The port
     protects text while collapsing; it never uses fuzzy text or nearby progression.

7. **A12-2/A12-3 hole true on Android AND in the current iOS checkout.** Annotation,
   membership and saved-link merges now have second passes using their same resolution
   functions on the row's own clock: `effectiveLastModifiedAt` (lastModifiedAt or createdAt),
   lastModifiedAt or queuedAt, and dateAdded, respectively. They run with an EMPTY incoming
   list too. Equal/older rows are removed; strictly newer rows survive. Replace skips them.
   Signed trusted/own-key markers are adopted as before; unsigned/unknown signers cannot
   cause these removals. Nothing about signature policy or unknown record types changed.

   Saved links still match by exact stored address and keep the local UUID. When incoming
   link UUID B is suppressed, the same-address local link UUID A is tested against B's
   marker using A's own Date Added, not the incoming date or export date; remove A only
   when that clock is also suppressed. A deliberate later local add survives with its ID.
   The normal second pass tests retained links by their own UUID and Date Added.

   The Room apply path now hard-deletes the captured removed annotations/links/memberships,
   with equality checks protecting rows edited since capture. No new omission tombstones
   are minted for remote-deletion removals. Snapshot-only fixes would have left Room rows
   visible/exportable. Tests cover an actual import onto existing Room rows plus next
   capture, and edits made between capture and apply.

   **Swift matched:** the generic `applyTombstonesToExisting` and reading-session call quoted
   above, specifically `.suppressStaleData` and the `mode != .replaceLibrary` guard. Its
   comment explains identical repeated Replace must not restore on pass one then delete
   on pass two (`[1,1,1]` becoming `[0,0,0]`). The current Swift has NO second-pass call for
   these three types and still returns early for an empty annotations list. The literal
   new T-364 Swift call sites cannot be quoted from this checkout because they are absent.
   Brief 3bs explicitly asks for this pending shared change; the resolution/clock/Replace
   contract is recorded here for T-364. No iOS file was changed.

## Additional exact Swift matched

`Models/Models.swift:1032–1042` defines only `bookmark` and `highlight` kinds and
`yellow, green, blue, pink, purple, underline` colours. Android's `note` raw kind
still travels on live rows unchanged. Swift parking uses `original.kind` and
`original.color` rather than copying the raw storage strings:

```swift
// Models/Models.swift:1095 (initializer default, also property at 1069)
id: UUID = UUID(),
// Models/Models.swift:1122–1130
var kind: ReadingAnnotationKind {
    get { ReadingAnnotationKind(rawValue: kindRaw) ?? .bookmark }
    set { kindRaw = newValue.rawValue }
}
var color: ReadingAnnotationColor {
    get { ReadingAnnotationColor(rawValue: colorRaw) ?? .yellow }
    set { colorRaw = newValue.rawValue }
}
// KudosBackup.swift:3499–3503 (sessions even in Replace)
if mode == .merge { continue }
guard SyncMerge.shouldApplyIncoming(
    localModifiedAt: local.lastModifiedAt,
    incomingModifiedAt: archived.lastModifiedAt
) else { continue }
// KudosBackup.swift:3631–3635 (favorites even in Replace)
if mode == .merge, byID[archived.id] != nil { continue }
guard SyncMerge.shouldApplyIncoming(
    localModifiedAt: local.lastModifiedAt,
    incomingModifiedAt: archived.lastModifiedAt
) else { continue }
```

The apply additions match the same Swift context updates/deletes quoted per item;
Android's capture/refresh/apply split needs explicit Room deletes as well as the
snapshot decision. Before this change, `BackupRepository.applyStoredMerge` only
upserted tombstones/annotations, and only pruned memberships under Replace. The
local marker-first DAO entry is `AnnotationDao.deleteWithTombstone`; it changes
no entity or table, and it uses the existing tombstone DAO from the same database.

The queue edit-clock assignment retained when forcing Replace is:

```swift
// KudosBackup.swift:2932–2936
queue.dateUpdated = max(queue.dateUpdated, archived.dateUpdated)
if let archivedChangedAt = archived.lastMembershipChangedAt {
    queue.lastMembershipChangedAt = max(queue.lastMembershipChangedAt, archivedChangedAt)
}
```

## Decided without asking

- No demo fixture or golden archive changes. New merge fixtures are tiny in-memory
  snapshots with fixed whole-second clocks and UUIDs; existing mapper functions make
  the archive. URL strings in fixtures are identities only; no request is issued.
- Use the existing backup test directory: `BackupMergeParityTest.kt` for rules and
  `DeletionTransactionTest.kt` for real Room atomicity. Extend the existing
  `AnnotationTombstoneTest` for production import/apply/hiding/retention. No new
  dependency, injected transaction wrapper, helper script or stub source.
- SQLite triggers live only in the in-memory test database, not an exported Room
  schema. They throw from real DAO statements, check marker-first, and cover rollback
  after dependent deletion as well as the second write. The work-file test uses a
  real EPUB generated by the already-existing `EpubBuilder` and cleans its temp root.
- Preserve iOS's unbounded hidden-note retention; add no recovery screen, expiry rule
  or manifest field. Use its enum defaults on salvage rows and its exact-locator
  grouping on live annotations.
- Saved-link URL rematch compares the LOCAL Date Added to the incoming-ID marker;
  a strictly later local add survives. Never use the package export date as that clock.
- Live work restore and snapshot restore share the existing named retraction function
  via its pure overload; canonicalize both URLs using `WorkTags`, not a new matcher.
- Reads for apply-time membership/marker removal are batched, and made only if the
  planned removals are non-empty; changed rows keep the existing captured-row guard.
- Fix optional A3-9 purely in the two existing tests: committed exported schema 9/12
  `works` DDL, seed every column, assert no old column vanished and title/spine/fraction/
  locator survive. No migration, entity, schema JSON or production change. The two
  weak fixture bodies are replaced; existing full Room-validation tests remain.
- Leave A3-6 (unknown-type hard failure/security test), `epubDigest`, signing/trust
  policy, reading-session/favorite merge rules and all unrelated audit suspicions alone.

## Open questions

- T-364's three new Swift call sites are not in the iOS reference yet. Proceeded with
  the existing Swift resolution function, per-row clock and Replace guard, plus the
  explicit requested URL-rematch fix. T-364 should match these choices, including
  preserving a later local Date Added when an incoming same-address link is suppressed.
- Builds, KSP-generated Room transaction wrappers and red/green runtime results cannot
  be checked in this sandbox. Proceeded by reading actual constructors, DAO methods,
  mappers and apply callers; Claude must run them. No product decision was left waiting.

## Existing expectations changed

`BackupAnnotationApplyTest.appliesAnnotationsByIdWithLww` in
`backup/BackupCompatibilityTest.kt` previously selected `annotations.single()`.
It now selects the same-id live winner and also requires the displaced `"old"` text
on a pending-deletion sibling. The newer live note/kind/locator assertions remain.
The old one-row expectation directly contradicted Swift's `parkDisplacedNote`.
No A3-1/A3-2 test expectation was changed; their prior fixes remain.

The two migration tests keep their original new-column/default assertions and now
also require the full old column set and preserved title/progress sentinels. They
still call the existing production migration objects, not a replacement implementation.

## Verification and handoff

- `git diff --check` passes (rerun at handoff). Source/test symbols and all changed
  production paths were read; no Gradle or Xcode invocation, runtime test or visual
  inspection was performed. No build/compile success is claimed.
- A separate Python in-memory SQLite shape check loaded the committed schema 9
  (49 columns) and schema 12 (64 columns) and successfully seeded the full-table
  fixtures with title/progress sentinels. This verifies fixture SQL/data compatibility,
  **not** Kotlin migration-test execution or Room schema validation.
- Every item has tests written before its corresponding production edit. Core new
  regression assertions are predicted red before the change: late/unchanged dates;
  local-newer queue surviving Replace; deleted containers/markers staying; missing
  displaced text; `tombstoneMissing` instead of marker-first rollback; overwritten
  unavailability/asset IDs or duplicate marks; and retained rows after remote deletion.
  Guards (unchanged behavior, newer-row survival, unsigned/unknown markers and repeated
  Replace) intentionally also pin behavior that already passed. Red/green is not run.
- Claude should run `:app:testDebugUnitTest` for `BackupMergeParityTest`,
  `DeletionTransactionTest`, `AnnotationTombstoneTest`, `BackupAnnotationApplyTest`,
  `KudosDatabaseMigrationTest`, then the existing backup, work-lifecycle, queue and
  reader suites and Android build/lint. In particular verify Room KSP accepts the
  concrete suspend `@Transaction` method across DAOs and that trigger exceptions
  roll back all rows. Run baseline failures in a separate permitted checkout; this
  worktree's branch and user edits must stay intact.
- Still manual: actual two-device Android/iOS T-364 convergence and file cleanup after
  a process dies between DB commit and EPUB unlink. Row+tombstone atomicity is covered
  by the written Room tests; filesystem unlink cannot roll back with Room (a failed
  transaction leaves the EPUB; a crash after commit can leave an orphan file).
- No Swift/invariants conflict was found for the implemented items. Broad date wording
  was narrowed to iOS's active File Merge exception; the saved-search premise and absent
  T-364 call sites are corrected above. No Room schema, manifest key or backup version
  changed; no commit, push, branch switch or TASKS edit.

## Item table

All “fixed” below mean implementation and tests written, awaiting Claude's build/test run.
`Parity` = `backup/BackupMergeParityTest.kt`; `Atomicity` = `backup/DeletionTransactionTest.kt`;
`Apply` = `reader/AnnotationTombstoneTest.kt`.

| Item | Audit claim true? | Fixed? | Tests |
| --- | --- | --- | --- |
| 1 · A3-3 dates | Yes, with iOS's active-work File Merge exception | Yes | Parity `dateAddedAndDateCreatedKeepTheEarlierCopyRegardlessOfWinner`, `fileMergeOfDeletedWorkAlsoKeepsEarlierDateAddedWithEitherClockWinner` |
| 2 · A3-4 Replace queues | Yes | Yes | Parity `replaceLibraryTakesArchiveQueueAndMembershipRegardlessOfLocalClock`, `replaceLibraryStillPinsSystemQueueNameAndKind`, `replaceLibraryKeepsReadingSessionsAndFavouritesLastWriteWins` |
| 3 · A3-5 revival/retraction | Yes | Yes, including Room apply | Parity `fileMergeReturnsCollectionAndQueueAndClearsAllDeletionFields`, `fileMergeOnlyClearsDeletionFieldsOnContainersItActuallyReturns`, `fileMergeRetractsSavedWorkTombstonesByUuidAo3IdAndCanonicalAddress`; Apply `fileMergeRetractsWorkDeletionFromRoomAsRecentlyDeletedRestoreDoes`; existing `BackupTrustPhase2Test.retractWorkTombstoneMatchesAo3AndCanonicalUrl` and `retractWorkTombstoneMatchesCanonicalUrlWhenAo3Missing` |
| 4 · A3-7 displaced note | Yes | Yes | Parity `aWinningSameIdAnnotationParksTheDisplacedNoteWithItsOriginalAnchorAndDates`, `noteEditedBetweenCaptureAndApplyIsAlsoParkedWhenArchiveStillWins`, `parkedNoteUsesIosKindAndColourFallbacksForUnknownStoredRawValues`, `identicalEmptyAndFileMergeNotesDoNotCreateSalvageRows`; Apply `displacedNoteStaysHiddenAndExportableBeyondTheWorkRecoveryWindow`; updated `BackupAnnotationApplyTest.appliesAnnotationsByIdWithLww` |
| 5 · A3-8 atomic delete | Yes at all four sites; SavedSearch is first-marker only, not transactional | Yes at the four named sites | Atomicity `highlightDeleteIsTombstoneFirstAndRollsBackBothDaoStatements`, `queueMembershipDeleteIsTombstoneFirstAndRollsBackItsQueueAndWorkEdits`, `workHardDeleteRollsBackEveryDependentAndKeepsEpubWhenFinalDaoDeleteThrows`, `workHardDeleteRollsBackWhenItsSecondTombstoneDaoStatementThrows`, `collectionMembershipDeleteIsTombstoneFirstAndRollsBackBothDaoStatements` |
| 6a · ao3Unavailable | Yes | Yes | Parity `ao3UnavailableIsMonotonicAndAssetIdentifierOnlyFillsAnEmptyLocalValue` (both winners and both boolean directions) |
| 6b · assetIdentifier | Yes | Yes | Same test (empty/non-empty/whitespace local identifiers, both winners, reconcile/Replace) |
| 6c · same-passage annotations | Yes | Yes | Parity `sameWorkKindAndExactLocatorCollapseToNewestAndSalvageBothNotes`, `samePassageWithEmptyWinnerFillsTheNoteAndStampsTheContentEdit`, `samePassageDedupIsExactAndUsesUuidToBreakEqualClockTies`, `pendingDeletionRowsAndAnnotationsWithoutAResolvedWorkDoNotCompeteInDedup` |
| 7 · A12 existing-row deletion | Yes on both current checkouts | Android fixed, iOS T-364 pending | Parity `trustedRemoteTombstonesRemoveExistingAnnotationsMembershipsAndSavedLinksUsingRowClocks`, `tombstoneSecondPassUsesCreatedAndQueuedFallbacksAndNeverSnapshotExportTime`, `suppressedIncomingLinkRemovesSameAddressLocalIdButKeepsANewerLocalAdd`, `unknownAndUnsignedIncomingTombstonesDoNotRemoveExistingRows`, `repeatedReplaceBypassesAllThreeTombstoneSecondPasses`; Apply `remoteDeleteRemovesExistingAnnotationMembershipAndLinkFromRoomAndNextExport`, `remoteDeletionDoesNotDeleteAnnotationOrMembershipEditedSinceCapture` |
| Optional A3-9 fixtures | Yes | Two fixtures only; no production change | `KudosDatabaseMigrationTest.migrate9To10_addsHasGivenKudosDefaultingToFalse`, `migrate12To13AddsNullableDownloadedAtWithoutBackfill` |
