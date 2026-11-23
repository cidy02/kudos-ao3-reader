# Sync operation matrix and legacy adapters (T-569 D4)

Status: specification, not shipped behaviour. Normative input to D5 (`docs/SYNC_JOURNAL_FORMAT.md`). Plan: `docs/DATA_ARCHITECTURE_PLAN.md` v3.1 § C, § D.
Code read at: iOS `claude/kudos-iphone-redesign-74f213` (`22aeca1a1`), Android `rd-a541a` (`7fd493a06`). Line numbers cite those trees.

Cite shorthand. iOS (under `kudos-ao3-reader/`): `KB`=Services/KudosBackup.swift, `PS`=Services/PersistenceSync.swift, `FS`=Services/FolderSyncService.swift,
`PWS`=Services/PreservedWorkService.swift, `WL`=Services/WorkLifecycle.swift, `SSC`=Services/SyncedSettingsClock.swift, `TS`=Services/TombstoneSigning.swift,
`WII`=Services/WorkIdentityIndex.swift, `RQS`=Services/ReadingQueueService.swift, `M`=Models/Models.swift. Android (under `android/app/src/main/java/io/github/cidy02/kudos/`):
`BMS`=backup/BackupMergeService.kt, `SMP`=backup/SyncManifestPassthrough.kt, `SR`=backup/SyncRepository.kt, `BV`=backup/BackupValidator.kt, `BMap`=backup/BackupMappers.kt,
`BM`=backup/BackupManifest.kt, `KPS`=reader/speech/KokoroPronunciationStore.kt, `ENT`=data/local/entity/*.kt.
Labels: **X-n** iOS/Android disagreement today; **N-n** a defect or gap both platforms share today; **DEC-n** a decision this document makes; **Q-n** open question (§6).

## 0. Vocabulary (v9, semantic only; byte layout is D5)

- **Stamp** `(logicalCounter, writerIncarnation, seq)`, compared lexicographically (counter numeric, incarnation by byte order of its lowercase canonical text, seq numeric). The greater stamp wins. A writer's own stamps are always distinct. Wall dates are payload and never decide a conflict.
- **Entity key**: work = random UUID plus identity tiers (§2.2); other entities as in §1. **Generation** = lifecycle epoch of an entity: `g0` is the create op id; a restore starts generation `r(sorted referenced deletion op ids)` (DEC-3).
- **Value group**: fields that only ever change together (atomic under one stamp). **Absent** = the op does not mention the group (no effect). **Null** = group carried with an explicit "no value" (a reset). **Reset op** = explicit clear with its own stamp. Legacy "absent key" (older build, Android) is never promoted to a reset by the adapter.
- **Prerequisite** = a cross-writer op id that must be applied (or covered by an installed checkpoint) first; same-writer order is implied by the contiguous prefix. Missing prerequisite → op stays pending.
- **Checkpoint state** = merge metadata a checkpoint must retain so the row can be evaluated after the segments behind it are gone.
- **Normalized logical state** (used by fixtures): entity maps keyed by survivor key, fields per value group, lifecycle, alias table, pending set, applied cut. No storage ids, no wall clocks.

## 1. Inventory of synced entities and fields

Reading guide: "today" = v8 snapshot merge (`KudosBackupService.restore`, default mode `reconcile`, `KB:3197`; Merge/Replace from `SettingsBackupPage.swift:176,182`). Android = `BackupMergeService.merge` (`BMS:43`), which rebuilds Room state from a merged snapshot; fields Android does not model ride in its raw-JSON overlay (`SMP:194-242`, "opaque") and are merged only as whole records (`SMP:697`, newer record stamp wins; tie keeps both sides' keys).

### 1.1 SavedWork (`M:140`; Android `ENT/WorkEntity.kt`, `BM:51-103`)

| Value group | Fields | iOS today | Android today | Differ |
|---|---|---|---|---|
| Identity | `id`, `ao3WorkID`, `sourceURL`(canonical) | tiers AO3 id → canonical URL → UUID (`WII:39-53`); `ao3WorkID` fill-only (`KB:6286`) | same tiers (`works/WorkIdentityIndex.kt:96-111`); fill-only (`BMS:846-848`) | no |
| Lifecycle | `isPendingDeletion`, `deletedAt`, `permanentDeletionScheduledAt` | flag taken only when `incomingWins`; schedule never copied from archive: `archivedDeletionState` (`KB:6147-6164`, `6270-6277`); `deletedAt` = newest of both (`KB:6277`) | flag via `restored.copy` when incomingWins; schedule via `keptDeletionSchedule`/`restoredDeletionState` (`BMap:98-117`, `BMS:812-816`) | schedule uses wall `Instant.now()` on Android (`BMap:103`) (X-21) |
| Text metadata | title, author, summary, sourceURL, rating, language, datePublished, dateUpdated, chapters, seriesTitle, seriesURL | `mergedText`: blank incoming never overwrites; else incomingWins or local empty (`KB:6417-6421`) | incomingWins: whole `restored` copy, blank archive text overwrites except datePublished/dateUpdated (`BMS:812-856`) | **X-2** |
| Counters | wordCount, kudos, comments, bookmarks, hits, seriesPosition, knownChapterCount | `mergedPositive`: ≤0 incoming ignored (`KB:6423-6426`, `6293-6313`) | kudos/wordCount from archive even 0; comments/hits/bookmarks/knownChapterCount `?:` guarded (`BMS:848-852`) | **X-2** |
| Flags | isFavorite, isSaved, isFinished, isComplete | `incomingWins`-gated assign (`KB:6244-6258`) | same via `restored` (`BMS:812-820`) | no |
| Monotonic | hasGivenKudos; ao3Unavailable; workTagsFetched; isQueuedForLater | OR (`KB:6248`, `6340-6342`) | hasGivenKudos OR (`BMS:834`); ao3Unavailable OR (`BMS:880`); workTagsFetched OR only on the local-wins branch (`BMS:900`), can regress when archive wins | X-2b |
| Reading status (stopped/abandon/stack) | readingStatusRaw, stopReasonRaw, stopTag, stopNote, stackThreshold, stackBaselineChapterCount, statusWasRecorded, statusChangedAt, stoppedAt, keepInProgressOverride, hiddenFromHistoryAt | incomingWins, key present only (`KB:6252-6270`) | not modelled except keepInProgressOverride/hiddenFromHistoryAt (`BMS:830-833`); rest opaque | opaque |
| Progress (atomic) | lastSpineIndex, lastScrollFraction, readiumLocator, lastReadDate, progressModifiedAt, legacyReaderProgress | `SyncMerge.applyProgress` (`PS:716-760`): own clock `progressModifiedAt ?? lastReadDate`, absent locator ≠ reset, empty string = reset, keyless-moved heuristic (`PS:764-770`) | `applyProgressLww` (`BMS:938-1009`) same shape | no |
| Tag lists | workTags/Fandoms/Characters/Relationships/Freeforms/Warnings/Categories | union (`TagMerge.merged`, `KB:6316-6321`) whoever wins | union (`BMS:827-834`, `2344`) | no |
| User tags | `Tag` rows linked to work | union only, never removed by absence (`KB:3563-3585`); Replace reads `userTags` as given | union; Replace = archive set (`BMS:271-282`) | iOS Replace does not drop local-only user tags (X-5b) |
| Preservation | epubPreservationStatusRaw, metadataSyncStatusRaw, preservedAt, lastPreservationAttemptAt, lastAvailabilityCheck | `.preserved` never demoted (`KB:6350-6362`); dates `newest` (`KB:6376-6380`) | same (`BMS:905-930`) | no |
| Cover pin | coverRecipeJSON (own `pinnedAt` clock) | adopt by `pinnedAt` only, never by work clock (`KB:6400-6414`, `6322-6330`) | opaque | opaque |
| Insights provenance | importSourceRaw/Since, kudos/hits/bookmarksAtSave, statsSavedAt, ageDaysAtSave, fandomWorksAtSave | set-once (`mergeProvenance`, `KB:6166-6187`) | opaque | opaque |
| Chapter word counts | chapterWordCountsJSON, wordUnitRaw | adopt when valid and (empty or incomingWins) (`KB:6332-6337`) | opaque | opaque |
| Asset facts | hasEPUB, remoteEPUBPending, epubDigest, assetIdentifier, freedAt | device-local: `hasEPUB`/`remoteEPUBPending` follow disk (`KB:3640-3660`); `epubDigest` never restored (`KB:6364-6374`); `freedAt` not in backup | `hasEpub` from disk (`BMS:244-250`); `epubDigest` blank-guarded copy (`BMS:852`); `freedAt` kept local (`BMS:836`) | no |
| Authors | authorIdentitiesJSON | fill or newer wins; absent never clears (`KB:6272-6276`) | Android never takes it (`BMS:836`) | **X-2c** |
| Derived/device | searchText, searchIndexVersion, syncStatusRaw, lastSyncAttemptAt, lastSyncError, lastTagRefreshAttemptAt, SavedSeries | never synced (`DATA_AND_PERSISTENCE_INVARIANTS.md` Source of truth) | `lastTagRefreshAttemptAt` is in the entity only | no |
| Record clock | lastModifiedAt | `max(local, incoming)`; new record adopts archive's (`KB:6425-6431`) | `maxInstant` (`BMS:822`) | no |

### 1.2 Memberships, order, structure

| Entity | Fields | iOS today | Android today | Differ |
|---|---|---|---|---|
| ReadingQueue (`M:1082`; `ENT/ReadingQueueEntity.kt`) | name, kindRaw, sortOrder, hue/colorHex, isPinned, keepsWorksOffline, notes, smartRulesJSON, tags, searchSources | LWW on `effectiveQueueModifiedAt` incl. membership clocks (`PS:679-695`, `KB:4040-4120`); colour fill-only pair (`PS:656-666`); pin/offline/notes fill unless wins; smart rules fill-only; tags union (Replace: exact) | same clock (`BMS:1676-1700`), `fillQueueFields` (`BMS:1914-1950`); smart rules and searchSources opaque; Saved for Later matched by kind (`BMS:1700-1712`) | no |
| Queue lifecycle | isPendingDeletion, deletedAt, schedule | `archivedDeletionState` when wins (`KB:4118-4128`) | `restoredDeletionState` (`BMS:1769-1777`) | schedule clock (X-21) |
| Queue membership (`M:1277`) | id, queue, work, queuedAt, sortOrderInQueue, note, state/stateWasRecorded, origin, lastModifiedAt | matched by **(queue, work)**, keeps local membership id; wins only by membership clock (Replace always; Merge never) (`KB:4182-4222`); orphan (no queue) → "Restored Queue" (`KB:4160-4178`) | keyed by **membership id** (`BMS:1815-1875`); whole membership replaced when wins; state/origin opaque; no (queue, work) dedupe (`ENT/ReadingQueueEntity.kt` index non-unique) | **X-4** |
| Membership removal | tombstone `.readingQueueMembership` | `applyTombstonesToExisting` on own clock (`KB:4240-4258`) | `entries.removeAll` on own clock (`BMS:1877-1884`) | no |
| WorkCollection (`M:949`; `ENT/CollectionEntity.kt`) | name, hue/colorHex, keepsWorksOffline, showsOnHome, workOrderRaw, description, sortOrder, works (set), lifecycle | LWW by `lastModifiedAt`; fill-only for colour/offline/order; membership **union**, then drops those a trusted membership tombstone (newer than `lastMembershipChangedAt ?? lastModifiedAt`) removed unless the archive affirms (`KB:3671-3875`) | same (`BMS:1315-1535`); duplicate name gets "(Restored)" suffix (`BMS:1370-1380`, `2334-2342`) | X-12 (names) |
| Collection membership removal | tombstone `.workCollectionMembership`, id = `collectionMembershipID` XOR-UUID (`PS:602-615`) | `suppressesCollectionMembership` ≥ (`KB:6018-6029`) | `collectionMembershipRecordId` (`BMS:2693-2699`) | no |
| Rank | `sortOrderInQueue`; collection order = `workOrderRaw` string | rank travels with whole membership record | same | no |
| SavedSearch + QueueSavedSearchLink | name, filters, lastOpenedAt; link lastCheckedAt/newResultCount; queue.searchSourcesModifiedAt | overwritten in all modes (no LWW) (`KB:4290-4306`); links by stamp (`KB:4312-4345`) | overwritten (`BMS:1586-1600`); links opaque; name made unique on insert (`BMS:1560-1575`) | X-12 |
| Bookmark (saved AO3 link) | title, url, dateAdded | keyed by URL; overwritten (`KB:4363-4400`) | keyed by URL (`BMS:1016-1090`) | no |

### 1.3 Annotations, sessions, favorites, watermarks

| Entity | Fields | iOS today | Android today | Differ |
|---|---|---|---|---|
| ReadingAnnotation (`M:1408`; `ENT/AnnotationEntity.kt`) | kind, colorRaw, locatorString, selectedText, note, progression, spineIndex, chapterTitle, createdAt, lastModifiedAt, deleted flags | by id; LWW; Merge add-only; a displaced non-empty local note is parked on a hidden sibling with a **random** id (`KB:5470-5520`, `5582-5625`); sweep deleted-elsewhere first (`KB:5421-5435`); same-passage dedupe `(work, kind, exact locator)` incl. **empty** locator, rank `lastModifiedAt` desc then id (`KB:5627-5737`); loser gets signed tombstone `samePassageDeduped` | same (`BMS:2174-2328`); dedupe skips blank locators (`BMS:2301`); also random sibling id (`BMS:2278`) | **X-10**, N-2 (random sibling id) |
| ReadingSession (`ReadingSession.swift:9`; `ENT/ReadingLogEntities.kt`) | id, workID, timing, progress, mode, deviceID, rulesVersion, metadata snapshot, chapter timing | by id; Merge never updates; fill-only chapter timing (`KB:4783-4870`); `workID` rewritten to surviving work; tombstone class "immediate delete" | by id; same shape (`BMS:1952-2024`); D7/metadata fields not modelled (opaque) | no |
| ReadingFavorite | kindRaw, targetKey, displayName, createdAt | by id then by `(kind, targetKey)`; work target re-keyed (`KB:4991-5083`) | same (`BMS:2026-2106`) | no |
| FandomReadWatermark | fandomName, lastVisitedAt, newestWorkIDSeen/Title | by id then name (`KB:5085-5159`) | same (`BMS:2108-2172`) | no |
| FollowedTag (`FollowedTag.swift:10`) | ao3TagID, name, flags, seen ids, timestamps | typed merge, 20-tag cap, by id then ao3TagID (`KB:5161-5282`) | not modelled; opaque top-level key | **X-8** |
| TagAlias (`TagAlias.swift:261`) | name, canonicalName, kind, parentFandoms | typed merge, natural key, parent union (`KB:5283-5400`) | not modelled; opaque | **X-8** |

### 1.4 Non-model sources

| Source | iOS today | Android today | Differ |
|---|---|---|---|
| Settings (named + `extras`) | per-setting stamps `SyncedSettingsClock`; incoming wins only when newer, inferred stamps never beat real (`SSC:139-145`, `KB:2628-2850`); voice id+name pair; reset = absent with sender's own stamp (`KB:2780-2850`); maps merge entry-wise (`KB:2663-2690`) | typed fields assigned wholesale on non-Replace (`BMS:449-461`); raw `modifiedAt`/`extras` merged by stamp at manifest-fold level (`SMP:550-660`); no local stamping | **X-9** |
| Pronunciations | entry stamps; newer wins; removal = stamp with no value (`KB:853-935`) | archive wins, local-only kept, no removal (`KPS:19-23`; `BMS:463`) | **X-9** |
| Writing recovery, mail/subscription documents | add or replace only with newer; never remove (`KB:4750-4751`, `BackupAppState.swift:25-140`) | not modelled; opaque | opaque |
| Fonts | by file name; validate batch first; collision → `-restored-N`; reader font follows rename (`KB:4451-4580`) | same family (`BMS:1091-1245`) | no |
| Originals (`Originals/<UUID>.ext`, `.conversion.json`) | never overwrite or sit beside a local original (`KB:4629-4660`); folder write byte-compares (`FS:1042-1054`) | folder write compares **size only** (`SR:938-946`) | **X-16** |
| EPUB asset | `Works/<UUID>.epub`, rewritten in place every sync-up when bytes differ (`FS:1013-1015`); read side: size then digest (`FS:837-854`); install gated by `mayReplaceEPUB` (`KB:6116-6130`) with metadata clock as freshness proxy | same (`SR:867-873`, `BMS:2775-2797`) | no |
| Tombstones (`M:78`) | signed Ed25519, payload = type, ao3 id, canonical URL, record id, createdAt (whole seconds), signer (`TS:48-65`); `deletionReason`, device id, `lastModifiedAt` unsigned; adopted only from trusted signer (`TS:128-132`); newest wins, tie → permanent reason (`PS:424-433`, `KB:3410-3436`) | same payload (`backup/TombstoneSigning.kt:108-125`); held row replaced only by same-identity strictly later (`BMS:113-123`); tie keeps first (`BMS:2755-2765`); no followedTag/tagAlias type (`BMS:2626`) | **X-7**, X-8 |

### 1.5 Disagreements and shared defects found

- **X-1** Future dates. iOS clamps to `now+24h` at decode, tombstones also to `exportedAt` (`KB:554-577`, `3403`). Android throws on `> now+24h` (`BV:196-198`), caps every parsed date at `exportedAt` (`BV:200`) and treats a future work clock as no clock, so it loses every LWW (`BMS:2359-2367`, `SyncMerge.shouldApplyIncoming(_, null)=false` `BMS:2538`).
- **X-2** Work text/counter overwrite when the archive wins (table 1.1); `workTagsFetched` can regress on Android.
- **X-4** Queue membership identity (table 1.2).
- **X-5** Replace omission. iOS soft-deletes omitted collections/queues into Recently Deleted unless the key is absent (`KB:4660-4705`), hides omitted annotations (`KB:4707-4715`), tombstones omitted searches/bookmarks/sessions/favorites/watermarks/followed tags only when the key is present. Android hard-removes omitted collections (`BMS:1286-1313`), queues (`BMS:1850-1866`), annotations (`BMS:2256-2262`) and sweeps sessions/favorites/watermarks/searches/bookmarks even for a key the archive never carried: every list defaults to `[]` and there is no omitted-keys record (`BM:21-37`) so **T-563 is not implemented on Android**.
- **X-6** An archive's Recently Deleted work on a device with no local copy: iOS restores it into Recently Deleted while its window is open (`KB:5876-5889`); Android suppresses it (`BMS:2644-2662`).
- **X-7** Tombstone ties and adoption (table 1.4).
- **X-8** Followed tags and tag aliases: typed on iOS, opaque on Android (tombstones for them are ignored on Android).
- **X-9** Settings and pronunciations (table 1.4).
- **X-10** Annotation dedupe: empty anchors, Replace omission (X-5).
- **X-12** Android renames duplicate collection/saved-search names on insert; iOS keeps the incoming name (`KB:4286-4289`).
- **X-16** Original publication compares size only on Android.
- **X-21** Android reads `Instant.now()` inside merge helpers (`BMap:103`); iOS reads `Date()` in `clampedArchiveDate`, `archivedDeletionState`, `parkDisplacedNote` and Replace omission (`KB:558`, `6150`, `5590`, `4666`). Neither has a fixed operation clock.
- **N-1** A permanent delete never reaches a device that still holds the work: no pass applies `savedWork`, collection or queue tombstones to existing local rows (only memberships, annotations, searches, bookmarks, sessions, favorites, watermarks do: `KB:4256`, `4356`, `4428`, `4875`, `5055`, `5141`; Android `BMS:2626`). The deleting device only stops the work coming back.
- **N-2** Parked-note siblings and same-passage losers get random ids, so two devices deduping the same pair mint different rows.
- **N-3** No survivor convergence for duplicate identity: each device keeps its own UUID and re-homes the other's (`KB:3469`, `WII:39-53` last-indexed-wins), so the manifest ping-pongs ids.
- **N-4** A late edit revives a deleted work: any record with a newer `lastModifiedAt` carries `isPendingDeletion=false`, and `incomingWins` assigns it (`KB:6279-6291`).
- **N-5** Metadata clock stands in for asset freshness (`KB:6100-6115`): a restore of an older book re-stamps the work and replaces newer bytes on the next sync; `Works/<UUID>.epub` is rewritten in place by whichever device syncs up last (`FS:1013-1015`, `SR:565-580`).
