# Sync operation matrix and legacy adapters (T-569 D4)

Status: specification, not shipped behaviour (round 2, after Codex review `out/codex-t569d4-review.md`). Normative input to D5 (`docs/SYNC_JOURNAL_FORMAT.md`). Plan: `docs/DATA_ARCHITECTURE_PLAN.md` v3.1 § C, § D.
**Governing rule (round 2):** no row decides staleness from the current projection and then discards an operation. Every operation is retained as a *fact*; every visible outcome is a deterministic projection over the retained facts (§2.1), so any arrival order and any checkpoint cut gives the same state.
Code read at: iOS `claude/kudos-iphone-redesign-74f213` (`22aeca1a1`), Android `rd-a541a` (`7fd493a06`). Line numbers cite those trees.

Cite shorthand. iOS (under `kudos-ao3-reader/`): `KB`=Services/KudosBackup.swift, `PS`=Services/PersistenceSync.swift, `FS`=Services/FolderSyncService.swift,
`PWS`=Services/PreservedWorkService.swift, `WL`=Services/WorkLifecycle.swift, `SSC`=Services/SyncedSettingsClock.swift, `TS`=Services/TombstoneSigning.swift,
`WII`=Services/WorkIdentityIndex.swift, `RQS`=Services/ReadingQueueService.swift, `M`=Models/Models.swift. Android (under `android/app/src/main/java/io/github/cidy02/kudos/`):
`BMS`=backup/BackupMergeService.kt, `SMP`=backup/SyncManifestPassthrough.kt, `SR`=backup/SyncRepository.kt, `BV`=backup/BackupValidator.kt, `BMap`=backup/BackupMappers.kt,
`BM`=backup/BackupManifest.kt, `KPS`=reader/speech/KokoroPronunciationStore.kt, `ENT`=data/local/entity/*.kt.
Labels: **X-n** iOS/Android disagreement today; **N-n** a defect or gap both platforms share today; **DEC-n** a decision this document makes; **Q-n** open question (§6).

## 0. Vocabulary (v9, semantic only; byte layout is D5)

- **Stamp** `(logicalCounter, writerIncarnation, seq)`, compared lexicographically (counter numeric, incarnation by byte order of its lowercase canonical text, seq numeric). The greater stamp wins. A writer's own stamps are always distinct. Wall dates are payload and never decide a conflict.
- **Entity key**: work = random UUID plus identity tiers (§2.2); other entities as in §1. **Generation** = a *label* (§2.2): `g0` is the create op id, `succ(p) = "r("+p+")"`; content registers are lineage-scoped.
- **Value group**: fields that only ever change together (atomic under one stamp). **Absent** = the op does not mention the group (no effect). **Null** = group carried with an explicit "no value" (a reset). **Reset op** = explicit clear with its own stamp. Legacy "absent key" (older build, Android) is never promoted to a reset by the adapter.
- **Prerequisite** = a cross-writer op id that must be applied (or covered by an installed checkpoint) first; same-writer order is implied by the contiguous prefix. Missing prerequisite → op stays pending.
- **Checkpoint state** = merge metadata a checkpoint must retain so the row can be evaluated after the segments behind it are gone.
- **Normalized logical state** (used by fixtures): entity maps keyed by survivor key, fields per value group, lifecycle, alias table, pending set, applied cut. No storage ids, no wall clocks.

## 1. Inventory of synced entities and fields

Reading guide: "today" = v8 snapshot merge (`KudosBackupService.restore`, default mode `reconcile`, `KB:3197`; Merge/Replace from `SettingsBackupPage.swift:176,182`). Android = `BackupMergeService.merge` (`BMS:43`), which rebuilds Room state from a merged snapshot; fields Android does not model ride in its raw-JSON overlay (`SMP:194-242`, "opaque") and are merged only as whole records (`SMP:697`, newer record stamp wins; tie keeps both sides' keys).

### 1.1 SavedWork (`M:140`; Android `ENT/WorkEntity.kt`, `BM:51-103`)

| Value group | Fields | iOS today | Android today | Differ |
|---|---|---|---|---|
| Identity | `id`, `ao3WorkID`, `sourceURL`(canonical) | tiers AO3 id → canonical URL → UUID (`WII:39-53`); `ao3WorkID` **local-first**: `work.ao3WorkID ?? archived.ao3WorkID ?? derived from URL` (`KB:6286`) | same tiers (`works/WorkIdentityIndex.kt:96-111`); on an archive win **archive-first**: `archived.ao3WorkID ?: existing.ao3WorkID` (`BMS:812-856`, `846`); local-wins branch is existing-first | X-2d |
| Lifecycle | `isPendingDeletion`, `deletedAt`, `permanentDeletionScheduledAt` | flag taken only when `incomingWins`; schedule never copied from archive: `archivedDeletionState` (`KB:6147-6164`, `6270-6277`); `deletedAt` = `newest(local, archived)`, so a winning **live** record can keep an old `deletedAt` (`KB:6277`) | flag via `restored.copy` when incomingWins; a live mapped row clears `deletedAt` (`BMap:294-302`); schedule via `keptDeletionSchedule`/`restoredDeletionState` (`BMap:98-117`, `BMS:812-816`) | X-21; X-2e (`deletedAt` retention) |
| Text metadata | title, author, summary, sourceURL, rating, language, datePublished, dateUpdated, chapters, seriesTitle, seriesURL | `mergedText`: blank incoming never overwrites; else incomingWins or local empty (`KB:6417-6421`) | incomingWins: whole `restored` copy, blank archive text overwrites except datePublished/dateUpdated (`BMS:812-856`) | **X-2** |
| Counters | wordCount, kudos, comments, bookmarks, hits, seriesPosition, knownChapterCount | `mergedPositive`: ≤0 incoming ignored (`KB:6423-6426`, `6293-6313`) | kudos/wordCount from archive even 0; comments/hits/bookmarks/knownChapterCount `?:` guarded (`BMS:848-852`) | **X-2** |
| Flags | isFavorite, isSaved, isFinished, isComplete | `incomingWins`-gated assign (`KB:6244-6258`) | same via `restored` (`BMS:812-820`) | no |
| Monotonic | hasGivenKudos; ao3Unavailable; workTagsFetched; isQueuedForLater | OR (`KB:6248`, `6340-6342`) | hasGivenKudos OR (`BMS:834`); ao3Unavailable OR in the post-copy block (`BMS:880`); workTagsFetched OR only on the local-wins branch (`BMS:812-880`), can regress when archive wins | X-2b |
| Reading status (stopped/abandon/stack) | readingStatusRaw, stopReasonRaw, stopTag, stopNote, stackThreshold, stackBaselineChapterCount, statusWasRecorded, statusChangedAt, stoppedAt, keepInProgressOverride, hiddenFromHistoryAt | incomingWins, key present only (`KB:6252-6270`) | not modelled except keepInProgressOverride/hiddenFromHistoryAt (`BMS:830-833`); rest opaque | opaque |
| Progress (atomic) | lastSpineIndex, lastScrollFraction, readiumLocator, lastReadDate, progressModifiedAt, legacyReaderProgress | `SyncMerge.applyProgress` (`PS:716-760`): own clock `progressModifiedAt ?? lastReadDate`, absent locator ≠ reset, empty string = reset, keyless-moved heuristic (`PS:764-770`) | `applyProgressLww` (`BMS:938-1009`) same shape | no |
| Tag lists | workTags/Fandoms/Characters/Relationships/Freeforms/Warnings/Categories | union (`TagMerge.merged`, `KB:6316-6321`) whoever wins | union (`BMS:827-834`, `2344`) | no |
| User tags | `Tag` rows linked to work | union in every mode, never removed by absence (`KB:3563-3580`) | Reconcile union; Replace takes the incoming set for matched works (`BMS:258-268`); omitted works are parked and keep their tags (`BMS:272-282`) | X-5b |
| Preservation | epubPreservationStatusRaw, metadataSyncStatusRaw, preservedAt, lastPreservationAttemptAt, lastAvailabilityCheck | `.preserved` never demoted (`KB:6350-6362`); dates `newest` (`KB:6376-6380`) | same (`BMS:905-930`) | no |
| Cover pin | coverRecipeJSON (own `pinnedAt` clock) | adopt by `pinnedAt` only, never by work clock (`KB:6400-6414`, `6322-6330`) | opaque | opaque |
| Insights provenance | importSourceRaw/Since, kudos/hits/bookmarksAtSave, statsSavedAt, ageDaysAtSave, fandomWorksAtSave | set-once (`mergeProvenance`, `KB:6166-6187`) | opaque | opaque |
| Chapter word counts | chapterWordCountsJSON, wordUnitRaw | adopt when valid and (empty or incomingWins) (`KB:6332-6337`) | opaque | opaque |
| Asset facts | hasEPUB, remoteEPUBPending, epubDigest, assetIdentifier, freedAt | device-local: `hasEPUB`/`remoteEPUBPending` follow disk (`KB:3640-3660`); `epubDigest` deliberately **not** restored, left to the bytes-install path (`KB:6358-6374`, `RQS:1250`); `freedAt` not in backup | `hasEpub` from disk (`BMS:244-250`); `epubDigest` **copied when nonblank** from the archive although disk facts are applied separately (`BMS:852`); `freedAt` kept local (`BMS:836`) | X-2f |
| Authors | authorIdentitiesJSON | insert: archive value; overlap: nonempty archive value if newer or local empty; absent never clears (`KB:6272-6276`) | insert: mapped archive record (`BMS:196-210`); overlap: keeps local (`BMS:836`) | **X-2c** (overlap only) |
| Download date | downloadedAt | insert: archive; Merge overlap: untouched; Reconcile: archive if newer or local nil (`KB:6208-6213`) | insert: archive; **Merge overlap fills a nil local value** (`BMS:231-232`); Reconcile as iOS (`BMS:884-890`) | **X-3** |
| Derived/device | searchText, searchIndexVersion, syncStatusRaw, lastSyncAttemptAt, lastSyncError, lastTagRefreshAttemptAt, SavedSeries | never synced (`DATA_AND_PERSISTENCE_INVARIANTS.md` Source of truth) | `lastTagRefreshAttemptAt` is in the entity only | no |
| Record clock | lastModifiedAt | `max(local, incoming)`; new record adopts archive's (`KB:6425-6431`) | `maxInstant` (`BMS:822`) | no |

### 1.2 Memberships, order, structure

| Entity | Fields | iOS today | Android today | Differ |
|---|---|---|---|---|
| ReadingQueue (`M:1082`; `ENT/ReadingQueueEntity.kt`) | name, kindRaw, sortOrder, hue/colorHex, isPinned, keepsWorksOffline, notes, smartRulesJSON, tags, searchSources | LWW on `effectiveQueueModifiedAt` incl. membership clocks (`PS:679-695`, `KB:4040-4120`); colour fill-only pair (`PS:656-666`); pin/offline/notes fill unless wins; smart rules fill-only; tags union (Replace: exact) | same clock (`BMS:1676-1700`), `fillQueueFields` (`BMS:1914-1950`); smart rules and searchSources opaque; Saved for Later matched by kind (`BMS:1700-1712`) | no |
| Queue lifecycle | isPendingDeletion, deletedAt, schedule | `archivedDeletionState` when wins (`KB:4118-4128`) | `restoredDeletionState` (`BMS:1769-1777`) | schedule clock (X-21) |
| Queue membership (`M:1277`) | id, queue, work, queuedAt, sortOrderInQueue, note, state/stateWasRecorded, origin, lastModifiedAt | matched by **(queue, work)**, keeps local membership id; wins only by membership clock (Replace always; Merge never) (`KB:4182-4222`); orphan (no queue) → "Restored Queue" (`KB:4160-4178`) | keyed by **membership id** (`BMS:1815-1864`); whole membership replaced when wins; state/origin opaque; no (queue, work) dedupe (`ENT/ReadingQueueEntity.kt` index non-unique); removal sweep `BMS:1866-1872` | **X-4** |
| Membership removal | tombstone `.readingQueueMembership` | `applyTombstonesToExisting` on own clock (`KB:4240-4258`) | `entries.removeAll` on own clock (`BMS:1866-1872`) | no |
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
| EPUB asset | `Works/<UUID>.epub`, rewritten in place every sync-up when bytes differ (`FS:1003`); read side: size then digest (`FS:837-854`); install gated by `mayReplaceEPUB` (`KB:6116-6130`) with metadata clock as freshness proxy | same (`SR:867-873`, `BMS:2775-2797`) | no |
| Tombstones (`M:78`) | signed Ed25519, payload = type, ao3 id, canonical URL, record id, createdAt (whole seconds), signer (`TS:48-65`); `deletionReason`, device id, `lastModifiedAt` unsigned; adopted only from trusted signer (`TS:128-132`); newest wins, tie → permanent reason (`PS:424-433`, `KB:3410-3436`) | same payload (`backup/TombstoneSigning.kt:108-125`); held row replaced only by same-identity strictly later (`BMS:113-123`); tie keeps first (`BMS:2755-2765`); no followedTag/tagAlias type (`BMS:2626`) | **X-7**, X-8 |

### 1.5 Disagreements and shared defects found

**Index.** Used: X-1, X-2, X-2b, X-2c, X-2d, X-2e, X-2f, X-3, X-4, X-5, X-5b, X-6, X-7, X-8, X-9, X-10, X-12, X-16, X-21; N-1 to N-5. **Intentionally unused (not renumbered, so earlier references stay valid):** X-11 (moved to N-2), X-13 to X-15, X-17 to X-20.

- **X-1 Dates (partly)** Three Android paths, one iOS path. iOS clamps decoded dates to `now+24h` (`KB:554-577`) and caps only *adopted tombstones* at `exportedAt` (`KB:3403`). Android's validator rejects a date over `now+24h` and caps at an `exportedAt` it is given (`BV:75-87`, `181-200`); optional merge parsing catches the error (`BMS:2348-2358`) and `sanitizeArchivedLastModifiedAt` returns null for a future work clock (`BMS:2359-2367`), which loses every `shouldApplyIncoming` (`BMS:2538`). The export cap exists only where an export bound is supplied.
- **X-2 Work text and counters (confirmed)** iOS guards text (`mergedText`, `KB:6417-6421`) and positive counters (`mergedPositive`, `KB:6423-6426`; `wordCount`, `kudos`, `comments`, `bookmarks`, `hits`). `seriesPosition` is a guarded max (`KB:6314-6316`). Android's winning copy takes blank/zero for `title`, `author`, `summary`, `sourceUrl`, `rating`, `language`, `chapters`, `seriesTitle`, `seriesUrl`, `wordCount`, `kudos`; it guards `datePublished`, `dateUpdated`, `epubDigest`(blank only), and uses `?:` for `comments`, `hits`, `bookmarks`, `knownChapterCount`, `ao3SeriesID`, `ao3WorkID` (`BMS:812-856`). A present `0` in `knownChapterCount` is accepted on Android and ignored by iOS' `== 0` fill (`KB:6318-6322`).
- **X-2b** `workTagsFetched`: iOS ORs always (`KB:6340-6342`); Android only on the local-wins branch (`BMS:812-880`).
- **X-2c** `authorIdentitiesJSON`: Android keeps local bylines on overlap (`BMS:836`) but takes the mapped archive record on insert (`BMS:196-210`); iOS takes a nonempty byline when newer or local empty (`KB:6272-6276`).
- **X-2d** `ao3WorkID` ownership on an archive win (table 1.1).
- **X-2e** `deletedAt` after a winning live record (table 1.1).
- **X-2f** `epubDigest` copied by Android, deliberately not restored on iOS (table 1.1).
- **X-3** Android fills a missing `downloadedAt` on an overlapping File Merge (`BMS:231-232`); iOS' Merge overlap branch exits before applying archive metadata (`KB:3470-3527`). In Reconcile both update `downloadedAt` when newer or local is nil, so "fill-only" is a Merge-route property.
- **X-4 Membership identity (confirmed)** iOS matches `(queue, work)` and keeps the local membership id (`KB:4182-4222`); Android matches membership id (`BMS:1815-1864`), removal sweep `BMS:1866-1872`.
- **X-5 Replace omission (confirmed)** iOS guards at `KB:4681-4711` and `4880-4884` (sessions: `4873-4877`). Android lists default to `[]` (`BM:21-37`, no omitted-key record), so it drops omitted collections (`BMS:1286-1313`) and queues (`BMS:1874ff`), removes omitted annotations (`BMS:2256-2262`) and mints omitted-session/favorite/watermark tombstones even for an absent key (`BMS:2004-2021`). An absent top-level collection key is distinct from a per-work `userTags` presence rule.
- **X-5b** Work user tags in Replace: iOS union (`KB:3563-3580`); Android incoming set for matched works, omitted works parked with tags kept (`BMS:258-282`).
- **X-6 Recently Deleted copy (partly)** True for a *trusted, non-permanent, at-least-as-new* tombstone: iOS has a recovery-window exception (`KB:5861-5890`: tombstone ≤ `max(archivedModifiedAt, deletedAt)+120 s`, scheduled > now; the *archive's* schedule participates though it is not installed); Android suppresses when the matched tombstone is at least as new (`BMS:2644-2662`). With no suppressing tombstone Android imports the pending record.
- **X-7 Tombstone ties (confirmed, two stages)** Adoption: iOS keys by `(type, recordID)`, newest wins, permanent reason wins an equal time (`KB:3365-3437`, `PS:430-433`); Android replaces a held row only for the same signed identity and strictly later (`BMS:83-127`). Suppression indexes: iOS `SyncTombstones.replaces` (permanent wins ties); Android `indexNewest` keeps the first on a tie (`BMS:2755-2765`).
- **X-8 Followed tags and tag aliases (confirmed)** iOS applies them typed (`KB:5161-5400`); Android has no typed suppression branch (`BMS:2600-2639`) and ignores their tombstones for typed application; whether they are preserved opaquely is a separate matter (`SMP:194-242`).
- **X-9 Settings and pronunciations (confirmed, two stages)** iOS applies per-setting and per-entry clocks (`KB:853-935`, `2628-2850`). Android *typed application* assigns normalized settings in non-Replace and merges pronunciations "archive wins" (`BMS:449-463`); the separate *raw fold* merges `modifiedAt`/`extras` by stamp (`SMP:550-660`).
- **X-10 Annotation dedupe anchors (confirmed)** iOS groups even empty locators (`KB:5633-5645`); Android excludes whitespace-only locators (`BMS:2300-2306`). Fixture `b3` covers blank, whitespace-only and present-empty anchors, and Replace omission.
- **X-12 Names (confirmed, scoped)** Android renames a *new live* collection or saved search whose name collides (`BMS:1370-1380`, `1560-1575`); iOS keeps the archive name (`KB:3713`, `4300`).
- **X-16 Originals (confirmed, two paths)** Upload: Android skips equal length (`SR:935-946`), iOS compares bytes (`FS:1042-1054`). Download: Android's original/sidecar read has its own size shortcut (`SR:808-833`).
- **X-21 Clock injection (partly)** A shared gap, not different semantics: both read wall time for recovery scheduling and both can keep an existing countdown. Wall reads: iOS `clampedArchiveDate` default `now` (`KB:558`), `archivedDeletionState` (`KB:6147-6164`), the resurrection exception `scheduled > Date()` (`KB:5884-5887`), `parkDisplacedNote` default (`KB:5582-5600`), Replace omission `now` (`KB:4671`), settings `now` (`KB:860`, `2640`); Android `restoredDeletionState` (`BMap:98-117`), `merge(now = Instant.now())` default (`BMS:46`, passed through), `parseInstant` default (`BV:181`).
- **N-1 Held row not swept (confirmed)** Adopting a permanent tombstone does not remove an already-held work, collection or queue: the work path only suppresses a *new* insert (`KB:3469ff`, `BMS:154-164`); the sweeps exist for memberships, annotations, searches, bookmarks, sessions, favorites and watermarks (`KB:4256`, `4356`, `4428`, `4875`, `5055`, `5141`; `BMS:2003-2008`).
- **N-2 Parked siblings** Parked-note siblings get fresh random ids on both platforms (`KB:5582-5607`, `BMS:2278-2286`). The same-passage *loser keeps its own annotation id* and the tombstone names it (`KB:5667-5674`, `BMS:2318-2324`).
- **N-3 Divergent survivor ids (partly)** Both keep the existing local key when matching an incoming duplicate and remap the archived key to it (`KB:3469`, `3560-3561`; `BMS:154-164`, `206-210`), so each device ends with its own key. Whether the manifest then alternates keys needs a publication trace; fixture `b1r` records the reverse direction instead of asserting it.
- **N-4 Edit revives (confirmed, scoped)** A winning live snapshot of an eligible overlapping record clears pending deletion in Reconcile (`KB:6282-6291`, `BMS:812ff`, `BMap:294-302`).
- **N-5 Freshness proxy (partly)** Both gate replacement of an existing *ordinary* EPUB on record freshness and both protect a present preserved copy (`KB:6116-6127`, `BMS:2775-2797`). Folder publication (`FS:1003`, `SR:565-580`) and local install are separate paths; the overwrite example is fixed in `c1` to the actual receiving device.

## 2. v9 model: retained facts and deterministic projection

### 2.1 Principle

An operation is applied by **retaining a fact**. Facts are only ever added; the visible state is a pure function `project(facts)` of the *set* of retained facts, never of arrival order, applied prefix or the previous projection. Consequences, used by every row in §3:

1. No row inspects the current projection to decide that an op is "stale" and drop it. Staleness is a *diagnostic computed from the final projection* (§2.9).
2. A fact that names another op as evidence (a restore naming deletions, a move naming add epochs, a replacement naming its observed base) either has that op as a **semantic prerequisite** (the receiver buffers it, contiguous prefix does not pass it) or is **fact-first**: it carries no prerequisite, is retained keyed by its target, and becomes visible when the target's create fact exists. "Prerequisite" in §3 always says which: named op ids, or `fact-first`. Neither mechanism uses a vague "presence" or "work key" test.
3. A checkpoint is a retained-fact snapshot for a cut (table below). Replaying any suffix over it gives the same projection as replaying all history.
4. Wall dates are payload. Stamps (§0) order facts inside registers; they never gate admission.

| Fact kind | Contents | What a checkpoint retains |
|---|---|---|
| Register fact | `(entity, group, opId, stamp, value or null, observed refs)` | per register: the winning fact; for epoch-scoped, version-graph and set-once registers also the facts listed below |
| Lifecycle facts | `D{id, observedGen, deletedAt}`, `R{id, observedGen, names}`, `P{id, reason, basis, envelope}` | all D/R/P facts of every entity not yet reclaimed (D8) with their stamps |
| Identity evidence | `(entity, ao3WorkID?, canonicalURL?)`, write-once, set union | the evidence set per entity |
| Epoch facts | `add{id=epoch, endpoints}`, `remove{names epochs}`, epoch-scoped register facts | every epoch id, every removal naming it, the winning register fact per live epoch and per register |
| Annotation source facts | `add{id, work, kind, locator, …}`, note versions `(sourceId, stamp, text)`, `delete{names sources}` | every source add fact, every note version's latest per source plus the version used for any parked sibling, every delete |
| Asset version facts | `write{owner, kind, digest, size, observedBase, stamp}`, `remove{names versions}` | every version that is a head or an ancestor of a head's closure needed for `observedBase` evidence |
| Authorization facts | `writer.enroll`, `writer.revoke` | all of them |
| Witnesses | winning purge witness and legacy evidence (§2.3) | per lineage |

### 2.2 Lifecycle (slice a)

Facts per entity (work, collection, queue): deletion `D`, restore `R`, purge `P`. **Generation** is a *label*: `g0` is the create op id and `succ(p) = "r(" + p + ")"` for the parent generation `p`. Every restore that observed generation `p` yields the same successor, so competing restores converge on one label. A `D` and an `R` record the generation they observed; content registers are **lineage-scoped** `(entity, group)`, not generation-scoped, so an edit never needs "inheriting": `d1,e1,r1`, `d1,r1,e1` and `e1,d1,r1` retain the same facts.

- **DEC-1 Lifecycle projection.** `cleared(D)` iff some `R` names `D`. Let `U` = uncleared deletions.
  1. `purged(explicit)` iff an authorized explicit `P` exists (terminal, wins over every restore, any order).
  2. else `purged(expired)` iff an authorized expiry `P` exists whose basis `B` satisfies **`B = U`** (an unseen concurrent deletion `D2 ∉ B` makes `U ⊋ B`, which invalidates the expiry; a restore naming any `D ∈ B`, whenever it was authored, makes `B ⊄ U`, which defeats it). This projection is reversible: the facts stay.
  3. else `deleted` iff `U ≠ ∅`; else `live`.
- **DEC-2 Restore authority.** `R` names the deletions it observed; they are its prerequisites (the receiver buffers `R` until each named `D` is applied or covered by a checkpoint that retains deletion evidence). An unnamed concurrent deletion stays effective: `R{D1}` with a concurrent `D2` projects `deleted` (recoverable, nothing lost), and a restore naming `D2` clears it. `R{D1,D2}` and `R{D2}`+`R{D1}` agree.
- **DEC-3 Deadline.** `deadline = max(deletedAt over D ∈ U) + 90 days`. It is derived, never stored from the file (`KB:6147-6164`). Expiry facts carry it as informational payload; no receiver compares it with its clock (plan § C: apply eligibility independent of receiver wall time). The emitting sweep alone is gated by its own clock and must hold the full `U` as basis.
- **DEC-4 Purge.** `P{reason ∈ explicit|expired, basis ⊆ D ids}`; basis ids are prerequisites. An explicit purge is terminal regardless of an unseen `D2` or a later restore. Winning witness: explicit beats expired; among equal reasons, the greatest stamp. **Cascade by type** (projection, nothing is deleted from the fact set): work → its annotations, memberships, user tags, asset references and cover/progress groups are not projected; sessions, favorites, watermarks and work-layer pronunciation entries stay (history independent, `INVARIANTS` Never lose; `WL:178-215` does not touch them); queue → its memberships and search links; collection → its membership edges; the entity's identity evidence stays as witness for `supersedes`.
- **DEC-5 Content ops never change lifecycle** (DEC-2 of round 1 kept): `work.edit` and asset writes are retained and projected whatever the lifecycle; only `purged` hides them.
- **DEC-6 Held copy** (`freedAt`, 60 days, `WL:17,33-75`) and "free EPUB" are device-local, never facts.
- **DEC-7 Re-acquisition.** An acquisition matching a work that projects `deleted` emits `R` naming its uncleared deletions; matching only a `purged(explicit)` lineage creates a new entity `g0` with `supersedes = witness id`; matching `purged(expired)` emits `R` (reversible). Purged lineages never join identity components (§2.4).

### 2.3 Authority for terminal operations

- **DEC-8 v9 envelope.** Every op is authenticated by its writer's native key; a `P` additionally carries a signature over `(libraryID, opId, reason, entity key, observedGen, sorted basis, identity tiers, legacyEvidenceDigest?)`. The v8 tombstone signature (`TS:48-65`) covers none of reason, generation, basis or op identity, so it is **never** authority for a terminal op.
- **DEC-9 Shared authorization.** Authorization is itself retained facts: `writer.enroll` (bootstrap descriptor names the founders) and `writer.revoke`. An op by writer `w` is authorized iff an enrollment of `w` with a lesser stamp exists and no revocation of `w` has a lesser stamp than the op. Because authorization is a projection over facts, two replicas at the same applied cut agree; a late-arriving enrollment retroactively authorizes (deterministically, reversible); an unauthorized `P` is retained, projects nothing, and shows as diagnostic `unauthorizedPurge`.
- **DEC-10 Legacy evidence** (a verified v8 signed tombstone) is stored as a separate `legacyEvidence` fact with its verification result and the adapter's trust decision recorded in the run record (§4). It does not project anything. An authorized adopter must mint a native `P` citing the evidence digest; replay never re-evaluates the legacy trust store.

### 2.4 Identity components (slice b)

- **DEC-11 Alias is a projection, not an op.** Identity evidence facts `(entity, ao3WorkID?, canonicalURL?)` are write-once sets. Edges between **non-purged** entities: tier 1 = equal `ao3WorkID`; tier 2 = equal canonical URL **only when neither entity has a different `ao3WorkID`**. An entity with two different ao3 ids in its evidence is `identity.conflict`: no edges, diagnostic. Components are connected components; survivor = lowest canonical (lowercase hyphenated) UUID. (Equal to v8 tier order `WII:39-53`; the legacy route keeps v8's tier-1-first outcome, §4.)
- **DEC-12 Mapping.** Every original `(key, generation)` keeps its own lifecycle facts. Component lifecycle: `live` if any member is `live`; else `deleted` if any member is `deleted`; else `purged`. Each content group of the component = the max-stamp register fact over all members (identity: union). Purging a member removes it from components in the projection and with it that member's contributions, whichever order alias and purge facts were observed. Work-scoped references (annotations, sessions, `.work` favorites, asset refs, memberships, and `works`-layer pronunciation/settings entries keyed by work UUID) store the **original** key and are mapped to the survivor at projection time; collisions of the same entry in the layer resolve by greatest stamp.
- **DEC-13 Reacquisition** after an explicit purge is a new entity (DEC-7); two devices doing so independently form a component by DEC-11 like any other duplicate.

### 2.5 Membership epochs

- **DEC-14** Queue and collection memberships are keyed by canonical endpoints `(queue, work component)`, never by a membership UUID. `add{epoch = opId}` starts an epoch; `remove{names epochs}` ends exactly the epochs it observed (prerequisites: the named adds). Presence = any epoch not named by a removal. Concurrent initial adds from two devices are **distinct epochs that both live** and share the endpoint; the rule is identical before and after alias projection and survives endpoint purges (a purged work endpoint drops only its own epochs).
- **DEC-15** `move`, `note`, `state`, `origin` carry `observedEpochs` and are registers **scoped to those epochs**; each add carries the epoch's initial `rank`/`note` as its first register fact (stamp = the add's). Projection of a register for an endpoint = max stamp among register facts whose observed epochs intersect the live epochs. An old-epoch move with a huge stamp cannot affect a re-added epoch or an absent member. Equal rank across members orders by `(rank, canonical work survivor key)`.

### 2.6 Annotations

- **DEC-16 Source facts.** Each annotation id is a *source*; its add fact (work, kind, color, locator, selectedText, createdAt) and each note edit (a version `(sourceId, stamp, text)`) are retained. A user delete names the **observed group** of sources the user saw as one visible annotation; it deletes exactly those sources. Sources the deleting device had not seen stay live, and may become visible.
- **DEC-17 Dedupe is a projection.** Candidates = non-deleted sources whose work maps to the same component, same kind, same **non-blank exact** locator. Winner = greatest stamp of the source's latest add/content fact. The loser mints no tombstone and no alias op (distinct from a user delete). Effective winner note = winner's latest non-empty note version, else the non-empty version with the greatest stamp among losers (empty-note fallback). **Parked notes** (one per loser source whose latest non-empty version differs from the effective winner note) are hidden siblings with id `UUIDv5(ns, sourceId ‖ noteVersionId)` — a function of source facts, not of arrival or of which winner existed at the time. Post-dedupe edits name their *source id* (the UI addresses the visible winner's id); an edit to a loser source updates that source's versions and may change winner or fallback.
- **DEC-18** Blank or whitespace-only locators never dedupe (X-10 resolved toward Android).

### 2.7 Assets

- **DEC-19 Version facts.** An asset write is `{owner (work entity, generation label, or font), kind, digest, size, observedBase = id of the version fact it replaced or null, stamp}` (plan v3.1: reference keyed by `(owner generation, asset kind)`; here the owner's generation label is carried in the fact, the register is lineage-scoped by DEC-5). A fact is **superseded** if another fact has it in its `observedBase` ancestry. **Heads** = unsuperseded facts. Winner = head with the greatest stamp. **Alternates** = the other heads (competing branches). An observed-base successor never makes its ancestor an alternate. A same-digest write is still a fact, observes the current winner as base and therefore advances the winner's stamp.
- **DEC-20 Bundles.** `original` and its `conversionRecord` are one register whose value is a bundle `{original digest+ext, record digest or null}` written as one fact; set-once = the bundle with the **lowest stamp** is current, others are alternates (never pairs files from different imports). Shared removal names version facts; a blob stays referenced while any head or retained ancestor needs it (reclaim is disabled in D7).
- **DEC-21 Fonts.** Font identity = add fact id; names are projected: fonts with equal case-folded `fileName` and different digests are ordered by add stamp; the first keeps the name, the n-th gets `-restored-<n-1>` (extension kept); equal digests are one font. `removeFont` names add ids.
- **DEC-22 Pending references.** A write commits metadata immediately; `available` is device-local, set only after size/digest verification and recoverable installation (plan § C, D5 atomic groups). It is never a fact.

### 2.8 Registers, absence, reset, ties

| Register kind | Selection | Reset | Used for |
|---|---|---|---|
| LWW | greatest stamp | `null` fact with its own stamp (retained) | flags, text, progress, colour, pin, rank, note |
| Set-once | lowest stamp | none; later differing values are alternates | provenance, originals, import source |
| Grow-only set | union | none (v8 has no tag removal) | tag lists, monotonic flags (OR) |
| Value-ordered | greatest by a fixed value comparator, then canonical JSON bytes | none | cover pin (v8 `pinnedAt`/rank rule `KB:6400-6414`) |
| Epoch-scoped | §2.5 | remove names epochs | membership rank/note/state/origin, user-tag presence |
| Entry presence | per `(key, entry)` LWW with retained resets | reset fact | settings maps, pronunciations |

Stamps are unique, so max/min selections never tie; value-ordered registers tie-break on bytes. **DEC-23** Group absent from an op = no effect; `null` = reset; malformed values are dropped with a diagnostic and never read as reset (`KB:2740-2780`); unknown groups and ops pass through opaque.

**DEC-24 Fixed operation clock** (legacy adapter only, §4): `norm(d) = min(d, E)`, `E = min(exportedAt, opClock + 24h)` for v9 import of v8 dates; the shipped-route baseline keeps shipped behaviour.

### 2.9 Diagnostics

Diagnostics are computed from the final projection, sorted by op id, and are part of a golden state: `unauthorizedPurge(P)`, `restoreAfterExplicitPurge(R)`, `editToPurgedLineage(op)`, `expiryInvalidated(P, reason)`, `assetConflict(owner, kind, heads)`, `identity.conflict(entity)`. They never depend on arrival order.

## 3. The matrix

Columns follow plan § D4: (1) command and capture intent; (2) target identity and generation; (3) value group; (4) absence/null/reset; (5) prerequisites (named op ids or `fact-first`, §2.1); (6) concurrent outcome and tie-break; (7) stale/duplicate; (8) checkpoint state.
"Stale/duplicate" columns state the *projection* result; nothing is discarded. A duplicate op id is an idempotent no-op on the fact set.

### 3.1 Work lifecycle, content and assets (slices a and c)

| Op | Command / capture intent | Target / gen | Value group | Absence · null · reset | Prerequisite | Concurrent outcome · tie-break | Stale / duplicate | Checkpoint state |
|---|---|---|---|---|---|---|---|---|
| **W1 work.create** | Save/import/download with no identity match (`importEPUB` re-check, `INVARIANTS` Identity). One op initialises every group of §3.1b with a register fact each. | new entity, `g0` = op id | all groups of §3.1b + identity evidence | absent group = no fact | none | same entity key twice impossible; identity match with another entity → component (DEC-11) | duplicate op: no-op | all initial register facts; evidence |
| **W2 work.delete** | `PWS.softDelete` (`PWS:116`): deletion fact `D`, EPUB kept, memberships stay. Today also a signed tombstone (`PS:435`). | entity, `observedGen` | lifecycle | none | none (fact-first on the entity create) | DEC-1: any uncleared `D` ⇒ deleted; two `D`s both retained, deadline from the max `deletedAt` | `D` after explicit purge: retained, projects nothing (diagnostic) | all D facts with stamps and `deletedAt` |
| **W3 work.restore** | `PWS.restore` (`PWS:175`), Recently Deleted Restore, DEC-7 re-acquisition, Merge undo of parking (`KB:3470-3490`) | entity, `observedGen`; successor label `succ(observedGen)` | lifecycle | none | **the named deletion ops** (all must be applied/covered) | clears exactly the named `D`; concurrent `R{D1}`/`R{D2}` converge on one successor; unnamed `D` stays effective | `R` after explicit purge: retained, projects nothing | all R facts with names |
| **W4 work.purge(explicit)** | Delete Permanently / `WL.hardDelete` (`WL:178`); native envelope (DEC-8) | lineage | lifecycle | none | the named basis deletions | terminal, wins any order; two explicit purges: greatest stamp is the witness | duplicate: no-op; unauthorized: retained, ignored | witness + basis + envelope |
| **W4x work.purge(expired)** | Sweep after `deadline` (`PWS:296`), emitter holds full `U` | lineage | lifecycle | none | basis deletions | valid iff basis = `U` (DEC-1.2); loses to any restore naming a basis deletion or to an unseen deletion | invalid expiry: retained, projects nothing | expiry facts + basis |
| **W5 work.acquire** | Any acquisition path with identity match | matched entity or new `g0` + `supersedes` | lifecycle/asset via W2/W3/W8 | — | purge witness id only when `supersedes` | DEC-7 | — | `supersedes` link |
| **W6 heldCopy** (local) | `WL:33-75` | — | `freedAt` | — | — | — | — | none |
| **W7 work.edit** | A user or refresh edit of one or more groups of §3.1b (one fact per group, same op) | entity (lineage-scoped), `observedGen` recorded | one or more content groups | absent group = no effect; `null` = reset only where §3.1b allows | none (fact-first) | per group by register kind; across delete/restore/purge DEC-5 | edit to purged lineage: retained, not projected, diagnostic | per register winner |
| **W8 asset.write** | `replaceEPUB` (`RQS:1227`), user re-import, update refresh. Fact per DEC-19 | `(owner, kind)` | `asset.epub` | no remove for ordinary replace | its `observedBase` version fact (named) | heads/alternates by DEC-19; same-digest write advances stamp; concurrent branches: greatest-stamp head wins, others alternates | duplicate digest + higher stamp: new winner fact (not a no-op); older stamp: kept as superseded/alternate by ancestry | version facts per DEC-19 |

#### 3.1b W1 initial groups and native update policies

| Group | Fields | Register kind (v8 rule mirrored) | Reset |
|---|---|---|---|
| identity | id, ao3WorkID, canonical URL | grow-only evidence (`WII:39-53`) | none |
| text metadata | title, author, summary, rating, language, datePublished, dateUpdated, chapters, seriesTitle, seriesURL | LWW per field; capture never emits blank (v8 `mergedText`, `KB:6417`) | none |
| counters | wordCount, kudos, comments, bookmarks, hits, seriesPosition, knownChapterCount | LWW per field; capture never emits ≤0 (v8 `mergedPositive`, `KB:6423`; series position max) | none |
| flags | isFavorite, isSaved, isFinished, isComplete | LWW | explicit false is a value |
| monotonic | hasGivenKudos, ao3Unavailable, workTagsFetched, isQueuedForLater (derived from memberships) | grow-only OR (`KB:6248`, `6340-6342`) | none |
| reading status | status, stop*, stack*, statusWasRecorded, statusChangedAt, stoppedAt (atomic) + keepInProgressOverride + hiddenFromHistoryAt | LWW per atomic group (`KB:6252-6270`) | `hiddenFromHistoryAt` null |
| progress | lastSpineIndex, lastScrollFraction, readiumLocator, lastReadDate, progressModifiedAt, legacyReaderProgress (atomic) | LWW on its own stamp; `locator ""` = reset, absent = unchanged (`PS:716-760`) | `legacyReaderProgress` null |
| cover pin | coverRecipeJSON | value-ordered (`KB:6400-6414`) | none |
| provenance | importSource*, *AtSave, statsSavedAt | set-once (lowest stamp) (`KB:6166-6187`) | none |
| preservation | status (rank: preserved > others), preservedAt, attempt dates | monotonic rank / max date (`KB:6350-6380`) | none |
| tag lists | warnings, categories, tags, fandoms, characters, relationships, freeforms | grow-only union (`TagMerge`) | none |
| user tags | Tag names attached to the work | epoch-scoped presence (T1) | detach |
| chapter data | chapterWordCountsJSON + wordUnitRaw | LWW pair, paired with `asset.epub` digest of the write that produced it | none |
| authors | authorIdentitiesJSON | LWW, nonempty only (`KB:6272`) | none |
| download date | downloadedAt | LWW | none |
| asset | `asset.epub`, `asset.original` bundle | DEC-19/20 | none |

### 3.2 Identity, memberships, annotations, sessions, favorites

| Op | Command / capture intent | Target / gen | Value group | Absence · null · reset | Prerequisite | Concurrent outcome · tie-break | Stale / duplicate | Checkpoint state |
|---|---|---|---|---|---|---|---|---|
| **I1 identity.evidence** (replaces the round-1 alias op) | Carried by W1 and by a later `work.edit` that fills `ao3WorkID`/URL; no separate op | entity | identity | grow-only | none | components by DEC-11; survivor lowest UUID | duplicate: set union | evidence per entity |
| **M1 membership.add** | `ReadingQueueService` add; endpoints `(queue, work)`; epoch = op id; carries initial rank/note | `(queue, work)` | epoch + first register facts | — | none (fact-first on both endpoints) | two adds = two live epochs (DEC-14) | add after remove: a new epoch, live | epoch ids |
| **M1r membership.remove** | remove from queue (`PS:476`) | the observed epochs | presence | — | the named add ops | ends exactly named epochs; an unseen epoch stays live | remove of an unknown epoch: waits (prerequisite) | removals naming epochs |
| **M2 membership.move** | reorder (`RQS:1270`): one fact per moved member naming observed epochs | epoch-scoped | `rank` | — | named epochs (add ops) | max stamp among facts hitting a live epoch; equal ranks by `(rank, work key)` | move naming only dead epochs: retained, not projected | per live epoch register |
| **M3 membership.note/state/origin** | note, state, origin edits | epoch-scoped | three groups | note `""` is a value; origin null = reset | named epochs | as M2 per group | as M2 | per group |
| **M4 collection.membership add/remove** | same epoch rule, no rank (`PS:602`) | `(collection, work)` | presence | — | as M1/M1r | as M1 | — | epochs |
| **A1 annotation.add** | In-book bookmark/highlight/note | source id | source add fact + note version 0 | `note ""` is a version | none (fact-first on work) | DEC-17 dedupe projection | duplicate id: no-op | source facts |
| **A2 annotation.edit** | note / color / locator edit | source id | note version (source-addressed) / color | absent unchanged | none | per DEC-16/17: edit to a loser source feeds fallback/parked sets | — | note versions retained |
| **A3 annotation.delete** | delete one visible annotation (`PS:489`) | observed group of sources | lifecycle of each named source | — | the named source adds | deletes exactly the named sources; unseen concurrent member stays and may become visible | delete of a source added later: waits | delete facts |
| **S1 session.append** | `ReadingSession` finalize (`ReadingSession.swift:9`); id is the uniqueness key | session id | full row; timing groups (`chapterSeconds/Words/skimmed*`, `endedAtChapterEnd`, `peekedAtEnding`) are set-once (lowest stamp) | old rows keep nil, never backfilled | none (fact-first on work) | two appends with the same id and different row bytes: same-writer impossible; cross-writer same id = repair condition `sessionIdCollision`; fill-only groups: lowest stamp wins deterministically | duplicate: no-op | session row + set-once groups |
| **S2 session.delete** | immediate-delete (`PS:530`) | id | lifecycle | — | none | delete holds | — | delete fact |
| **F1 favorite.set / clear** | star/unstar (`PS:545`) | `(kind, target)`; `.work` target = original work key mapped at projection | presence + displayName (LWW) | clear = stamped null | none | LWW by stamp | alias collapses duplicate keys by projection | per key |
| **F2 watermark.set / clear** | `PS:558` | fandom name | `{lastVisitedAt, newestWorkIDSeen, title}` atomic | clear stamp | none | LWW (not max-date) | — | per name |

### 3.3 Settings, tags, queues and collections, recovery, fonts, originals, authorization

| Op | Command / capture intent | Target / gen | Value group | Absence · null · reset | Prerequisite | Concurrent outcome · tie-break | Stale / duplicate | Checkpoint state |
|---|---|---|---|---|---|---|---|---|
| **P1 setting.set/reset** | named/extras setting (`SSC.noteLocalChanges`, `KB:2628`); explicit stamps only | setting key | one group per key; voice id+name and hue+hex are pairs | absent unchanged; reset = null fact; malformed ignored | none | LWW | — | winner or reset |
| **P2 setting.entry.set/reset** | map settings (drafts, Posting As) | `(key, entry)` | entry presence | reset retained | none | per entry LWW | — | per-entry fact incl. resets |
| **P3 pronunciation.set/reset** | `KB:853-935`; work layer key = original work key mapped by DEC-12 | `(layer, word)` | entry presence | reset retained | none | LWW | — | per-entry incl. resets |
| **T1 userTag.attach/detach** | user tag on a work (`Tag.name`, `M:887`) | `(work component, tag)` | epoch-scoped presence | detach names attach epochs | named attaches | as memberships (§2.5). v8 had union only; adapter never infers detach from absence | — | epochs |
| **T2 queue/collection.edit** | name; colour{hue,hex}; pin; keepsWorksOffline; notes; smartRules; searchSources + searchSourcesModifiedAt; **queue tags** (grow-only + detach, T1 rule); **collection description**; **collection sortOrder**; showsOnHome; workOrderRaw | queue/collection entity | one group each | colour hue null never clears; others reset by null | none | LWW per group (colour pair by `SyncMerge.chosenColor`, `PS:656-666`: hue fills, hex travels with the winning hue) | — | per group |
| **Q1 queue/collection.create/delete/restore/purge** | as W1-W4x for entities `queue`/`collection`; Saved for Later is matched by kind and never deleted or aliased by id (`BMS:1700`, `KB:3950`). Each entity has its own `g0`; memberships stay attached while deleted; purge cascades per DEC-4 | entity | lifecycle | — | named deletions | DEC-1 | — | as W2-W4x |
| **R1 recoveryDoc.put** | writing recovery copy or `documents` file (`BackupAppState.swift:25-140`). Key = **file name** (already digest of account/target/field + session id, so equal key ⇔ same session) | file name | `{entry, savedAt payload}` register | never removed | none | LWW by stamp (v8: replace only with newer save of the same session; never remove) | — | per name |
| **FN1 font.add / FN2 font.remove** | `M:923` | font id (add op id) | asset version + display name | remove names add ids | blob for `available` only | DEC-21 collision mapping | — | adds, removals |
| **O1 original.set** | converted import original + sidecar | `(work, original)` | bundle (DEC-20) | — | none | set-once: lowest-stamp bundle current | — | all bundles |
| **L1a savedSearch.put/delete** | `PS:517` | id | content LWW (name, filters, lastOpenedAt) | delete = lifecycle fact | none | LWW; delete holds | — | per id |
| **L1b bookmark.put/delete** | `PS:504` | URL (natural key) | title, dateAdded LWW | delete names URL | none | two ids for one URL collapse by URL; delete scope = URL | — | per URL |
| **L1c followedTag.put/delete** | `PS:571` | `ao3TagID` (natural key) | flags LWW, seen ids grow-only | delete | none | 20-cap: survivors ordered by earliest follow stamp, the rest are retained facts not projected | — | per tag |
| **L1d tagAlias.put/delete** | `PS:585` | natural key `(normalized name, kind)` | canonicalName LWW, parentFandoms grow-only | delete | none | LWW | — | per key |
| **E1 writer.enroll/revoke** | pairing/revocation UI (`TombstoneTrustStore`), founders in bootstrap | writer key | authorization | — | none | DEC-9 | — | all |

Smart (derived) memberships are never ops (`INVARIANTS` Queues); the adapter skips `kind=smart` as `KB:4194-4203` does.

## 4. Legacy route table and adapters

A **legacy adapter** turns a v8 manifest (and its assets) into v9 operations. It runs in three separate steps so that "what today's app would do" is never confused with "what v9 additionally changes":

1. **Accept via the named shipped route.** Run the route exactly as the shipped build on the importing device does (iOS `KudosBackupService.restore`, Android `BackupMergeService.merge`), including its date, fill, dedupe, tombstone and membership behaviour. The only injection is the clock value the shipped code already takes (`now`) and the trust set; the adapter records both. Result = the **accepted result** (post-merge normalized state).
2. **Apply explicitly approved migration changes.** A fixed list of named changes `MC-n` (§4.3), each independently approved by the owner or engineering default; a change not approved is not applied. Default list = empty, so step 2 is the identity.
3. **Translate to defined v9 ops** (§4.4): ordinary operation kinds of §3, diffed against the **accepted baseline cut**, in a defined order, with reserved ids and bytes. Never per-field history reconstructed from a record's `lastModifiedAt`.

Routes: **Merge** (file import, add-only), **Reconcile** (folder sync-down, conflict-version folds, the pre-2026 package fold; default mode), **Replace** (file import, snapshot), **v8 folder import** (seed of the v9 library, and the explicit reviewed import of post-handoff v8 edits; plan § C Namespace and cutover). Both platforms expose the same three modes (`KB:3086`, `KudosBackup.kt:59-75`); sync-down is Reconcile on both (`FS:371`, `SR:784`).

### 4.1 Shipped rules per route (what step 1 reproduces)

| Rule | iOS (cite) | Android (cite) |
|---|---|---|
| Record wins | `incoming >= local` (`PS:668-672`); ties go to incoming | `!incoming.isBefore(local)` (`BMS:2538-2542`) |
| Missing record clock | `lastModifiedAt ?? dateAdded` (`KB:6196`) | blank → `dateAdded`; a future date → null, which loses (`BMS:2375-2385`) |
| Future date | clamp to `now+24h` at decode (`KB:554-577`) | validator rejects (`BV:181-201`), merge parse drops (`BMS:2348-2367`) |
| New record | adopts archive values and clock (`KB:3555-3560`, `6425-6431`) | same (`BMS:206-210`) |
| Text, counters | fill-only on blank/≤0 (`KB:6417-6426`) | whole-copy take for a subset (X-2) |
| Monotonic | `hasGivenKudos`, `ao3Unavailable`, `workTagsFetched`, preservation never demoted (`KB:6248`, `6340`, `6350`) | all but `workTagsFetched` on an archive win |
| Tombstone adopt | trusted verified signer; `lastModifiedAt = min(createdAt, exportedAt)`; newest per record wins, tie → permanent (`KB:3365-3437`, `PS:430`) | trusted verified; held row replaced only for same identity and strictly later; suppression index keeps first on a tie (`BMS:83-127`, `2755`) |
| Newer-snapshot escape hatch | `tombstoneResolution`: incoming `>` tombstone revives; `==`/older suppresses; no incoming clock = ambiguous, keep (`PS:697-704`); works `suppressesResurrection` `>=` (`KB:5861-5890`) | same shape (`BMS:2553-2565`, `2644-2662`) |
| Recently Deleted copy | restored pending while window open, tombstone ≤ `max(modified, deletedAt)+120 s`, not permanent (`KB:5861-5890`; collections/queues `5928-5937`) | suppressed when tombstone ≥ record (X-6) |
| Retraction on restore | `retractTombstone` deletes the row (`PWS:216-241`); File Merge only for a live archive copy (`KB:3470-3490`) | `retractWorkTombstone` in the Merge path (`BMS:213-229`) |
| Deletion schedule | never from the archive (`KB:6147-6164`) | `keptDeletionSchedule` (`BMap:115`) |
| Progress | `applyProgress` (`PS:716-760`); Replace forces (`KB:6375-6385`) | `applyProgressLww` (`BMS:938`) |
| Membership match / winner | `(queue, work)`; Replace always, Reconcile by clock, Merge never (`KB:4182-4222`) | by id (X-4); same winner rule (`BMS:1815-1875`) |
| Annotations | Merge add-only; Reconcile/Replace LWW; displaced note parked (`KB:5470-5520`) | same (`BMS:2230-2250`) |
| Settings | per-key stamps, inferred stamps never beat real (`SSC:139`); Replace leaves settings (`KB:4724-4737`) | wholesale typed + raw stamp fold (X-9); Replace leaves settings (`BMS:449`) |

### 4.2 Route summary

| Route | iOS | Android |
|---|---|---|
| Merge | existing overlap untouched except revive of Replace-parked live copy and missing EPUB bytes (`KB:3470-3527`); new records adopt; collections/queues/annotations add-only | same plus `downloadedAt` fill (X-3) (`BMS:231-232`) |
| Reconcile | LWW per group; unions for tags and memberships | same with X-2/X-4 differences |
| Replace | snapshot: forces progress and cover pin; omission §4.5; settings untouched; pronunciations, recovery docs and documents still applied (`KB:4737-4751`) | snapshot; settings untouched (`BMS:449`) |
| v8 folder import | = Reconcile per manifest version including folded conflicts and the pre-2026 package (`FS:519-615`, `SR:340-400`); assets read when size or digest differ (`FS:837-854`, `SR:867`) | same |

### 4.3 Migration changes (step 2), all proposed and **off by default**

| ID | Change | Resolves | Needs |
|---|---|---|---|
| MC-1 | Date normalization `min(d, min(exportedAt, opClock+24h))`, never reject | X-1, X-21 | owner (Android whole-import rejection becomes a clamp, Q-5) |
| MC-2 | Never replace known text/counters with blank/zero | X-2 | owner (Android manual import acceptance, Q-6) |
| MC-3 | Match memberships by `(queue, work)` | X-4 | engineering |
| MC-4 | Record omitted keys before defaulting; omitted ⇒ no delete (T-563) | X-5 | owner for a shipped Android Replace change (Q-7); required for the v9 adapter |
| MC-5 | Import an archive's Recently Deleted copy per the iOS rule | X-6 | engineering |
| MC-6 | Tombstone tie: newest, permanent wins | X-7 | engineering |
| MC-7 | Mint a native purge from *verified permanent* legacy evidence when the adopter is authorized (DEC-10) | N-1 | owner (Q-8 wording) |
| MC-8 | Blank/whitespace anchors never dedupe | X-10 | engineering |
| MC-9 | Never rename on collision | X-12 | engineering |
| MC-10 | Compare originals by bytes on publish | X-16 | engineering |

### 4.4 Translation (step 3)

Inputs: accepted result (after step 2) and the local v9 projection at the **accepted baseline cut**. Output ordered list of ops; for each entity (sorted by canonical key) and each group (fixed order of §3.1b, then memberships, annotations, sessions/favorites/watermarks, settings, assets) emit an op only where accepted ≠ baseline. Replace is "forced" in acceptance, so differences are more frequent, but equal values emit nothing.

| Accepted transition | Op |
|---|---|
| new entity | W1 create (+ evidence); archive record dates are payload only |
| group value differs | W7 edit of that group, or the kind's own op (P1, F1, L1…); no per-field history |
| live → deleted | W2 delete with `deletedAt` from the archive record |
| deleted → live (newer snapshot, Merge undo of parking) | W3 restore naming **every uncleared deletion fact in the baseline**; a deletion that is not a fact cannot exist in a v9 library (the seed run created deletion facts from the archive's own `isDeleted`/`deletedAt`), so no deletion evidence is ever fabricated |
| revival of an entity projected `purged(expired)` | W3 restore |
| revival of an entity projected `purged(explicit)` | W5 acquire (new entity, `supersedes`) |
| verified permanent legacy tombstone, adopter authorized, MC-7 on | W4 purge(explicit) citing the legacy evidence digest; otherwise the evidence is stored and nothing else happens (v8 behaviour, N-1) |
| membership present/ranked/removed | M1 add, M2 move, M1r remove naming baseline epochs |
| annotation new/changed/hidden | A1, A2 (source-addressed), A3 naming the observed source group; the accepted same-passage dedupe is **not** translated (projection) |
| EPUB bytes installed (digest differs) | W8 with `observedBase` = current winner version; bytes staged to the blob pool |
| original + sidecar installed | O1 bundle |
| Replace omission | explicit delete ops per §4.5 only for keys the archive carries |

### 4.5 Durability, ordering, local edits

A **run record** is stored durably before anything is published: route, shipped build id, trust set, `opClock`, `sourceManifestDigest`, **baseline cut** (applied cut + checkpoint id), `acceptedResultDigest`, approved MC ids, the **ordered translation list** and, per op, the **reserved op id `(writer, seq)` with its content hash**, plus **asset inputs** `{workKey, digest, size, stagedBlobPath}`. Publishing retries the same bytes (plan § C Operations). A crash after acceptance resumes from the record and never re-runs step 1 against moved local state.

**Stamps are assigned at reservation** (counter above everything applied and everything already reserved). A **local edit that commits after reservation** therefore carries a greater stamp and wins every LWW/epoch register against the migration op; a **local edit that committed between acceptance and reservation** is detected at reservation by comparing each `(entity, group)` register with the baseline cut: if local facts exist beyond the baseline, that group's translation is dropped and recorded `localEditWins`; a local delete in that window stays uncleared because W3 names only deletions known at the baseline cut. The seed run is the same pipeline with an empty baseline. Unknown manifest keys are preserved verbatim as opaque facts (Android overlay rule becomes universal).

### 4.6 Replace-only omission rules

| Collection | iOS today | Android today | Translated op (with MC-4) |
|---|---|---|---|
| works | soft-delete, no tombstone (`KB:4664-4669`) | same (`BMS:258-275`) | W2 delete (`reason=replaceOmitted`) |
| collections, queues (not Saved for Later) | soft-delete unless key omitted (`KB:4681-4695`) | hard remove, key absent or not (X-5) | W2 delete, only when the key is present |
| annotations | hidden (`isPendingDeletion`), no tombstone; key omitted → skipped (`KB:4707-4715`, `5542-5553`) | hard remove | A3 delete naming local sources, key present only |
| saved searches, bookmarks | tombstone + hard delete when present (`KB:4358-4366`, `4417-4426`) | tombstone + remove even when absent | L1a/L1b delete, key present only |
| sessions, favorites, watermarks, followed tags, tag aliases | tombstone + delete only if key non-nil (T-563) (`KB:4873-4884`, `5063`, `5150`, `5236`, `5395`) | tombstone for first three even when absent; last two opaque | S2/F1/F2/L1c/L1d delete, key present only, `[]` replaces |
| memberships | not swept (`KB:4140`) | removes non-incoming except system queue (`BMS:1840-1865`) | M1r only for queues the archive lists with the key present |
| tags | union; queue tags exact (`KB:3882-3905`) | work tags exact (`BMS:258-268`) | T1 detach under Replace with key present |
| settings | untouched | untouched | none |

## 5. Fixtures

### 5.1 Contract

All fixtures are JSON with `"schema": "kudos.sync-fixture/2"`, validated by `docs/sync-fixtures/_schema.json`. Two kinds, deliberately separate:

- **`v8-compat`** (today's results, verified by reading code). Fields: `route`, `harness` (`opClock`, `trust` signer list, `signatureValid`, `preserved` per work, asset bytes by digest), `ids` (symbolic name → fixed UUID), `local` and `incoming` as **manifest-fragment specs** (`_v8-builder.json`: records name only what they vary; required v8 fields get deterministic defaults), `expected.ios` / `expected.android` (normalized post-merge state), `agree`, `disagreement`, `v9Outcome`. Both platform results are stated for every case, including where they agree. They are not yet executed; D5/A-569 must run each against the real route with the clock substituted inside Android's mapper (`BMap:98-117`) and iOS' `archivedDeletionState` before the fixture is frozen.
- **`v9-concurrency`**. Fields: `ids`, `universes[]`. A **universe** is one valid operation set: `initial` (full `createHistory` of ops, or a `checkpoint` with cut and retained facts), `authorization` (enroll facts), `ops[]` with `id`, `writer`, `seq` (contiguous per writer, never reused within a universe), `stamp` (`counter` strictly above the counter of every op it names or follows), `kind`, `target`, `observed` (named gen/deletions/epochs/base/sources), `payload`, `requires` (semantic prerequisites only; same-writer order is implicit and is **not** repeated), `events[]` (blob visibility), `schedules`: `orders` (explicit lists or `"allInterleavings"`, same-writer order fixed), `duplicates` (each op delivered twice, positions given), `restarts` (kill and reload after listed steps), `missingPrerequisite` (withheld ops and the pending set expected at each prefix), `checkpoints` (`cutAfter`, then `thenOrder`), and one `expected` with `state` (normalized projection: `works`, `components` (derived), `memberships`, `annotations`, `assets`, `settings`, `pronunciations`, `witnesses`), `appliedCut`, `pending`, `diagnostics` (derived from final facts, sorted). Every schedule of a universe must produce the same `expected` for its final cut; `missingPrerequisite` schedules assert only the stated intermediate `pending`.
- **Normalized projections**: identities as survivor keys, lifecycle label, group values, version heads/alternates, epoch-level facts for memberships, no storage ids, no wall clocks, derived ids as symbolic expressions (`uuidv5(ns, sourceId|noteVersionId)`).

### 5.2 Files

| File | Slice | Kind | Round-2 variants |
|---|---|---|---|
| `a1-v8-softdelete-propagation.json` | a | v8 | harness clock substitution stated |
| `a2-v8-recently-deleted-copy-new-device.json` | a | v8 (X-6) | trust/signature as harness inputs; control with no tombstone |
| `a3-v8-permanent-delete-holder.json` | a | v8 (N-1) | v9 outcome with named deletion and authorized witness |
| `a4-v9-lifecycle.json` | a | v9 | edit orders across restore; distinct-subset competing restores; equal-max deletion lists; expiry vs restore; expiry basis extension; checkpoint before restore |
| `a5-v9-reacquire-after-purge.json` | a | v9 | purge with named deletion, authorized witness, derived diagnostics |
| `b1-v8-duplicate-identity.json` | b | v8 (X-4) | nonblank locator only |
| `b1r-v8-duplicate-identity-reverse.json` | b | v8 (N-3) | opposite direction |
| `b2-v9-duplicate-identity.json` | b | v9 | no alias op; late loser-addressed ops across a checkpoint; annotation salvage orders; purge-after-alias vs before |
| `b3-v8-annotation-anchors.json` | b | v8 (X-10) | blank, whitespace-only, present-empty; Replace omission |
| `c1-v8-asset-replace-vs-delete.json` | c | v8 (N-5) | corrected receiver; preserved and ordinary controls |
| `c2-v9-asset-versions.json` | c | v9 | separate universes for purge and restore; two concurrent replacements; repeated digest with higher stamp; bundle |
| `c3-v9-pending-asset-reference.json` | c | v9 | bad blob prefix; materialization separate from journal pending |
| `d1-v9-membership-epochs.json` | ext. | v9 | old-epoch high-stamp move; concurrent initial adds; checkpoint of removed state |
| `d2-v9-setting-entry-reset.json` | ext. | v9 | final cut and pending asserted |
| `e1-v8-replace-omission-absent-key.json` | ext. | v8 (X-5) | key physically omitted, and separate `[]` case |

## 6. Open questions

Dispositions follow the Codex review (round 2). **Resolved by engineering decision (no owner input needed):** Q-2 (reclamation stays disabled; offline restores of non-retired devices stay eligible; D8 sets the bound, the earlier "90 days plus margin" claim is withdrawn), Q-4 (lowest canonical UUID, DEC-11), Q-5 (shipped validator behaviour is the v8 baseline; v9 import date handling is MC-1, separate), Q-6 (platform blank/zero acceptance stays in v8 results; MC-2 is the opt-in change), Q-7 (v9 adapter captures omitted keys, MC-4; shipped Android Replace stays in compatibility fixtures), Q-11 (a new incarnation sorts by its own id; arbitrary but identical everywhere, DEC-9 stamps), Q-12 (v9 assets are digest-addressed; legacy file names matter only for the seed run).

**Owner questions**, each with the recommendation:

- **Q-1 (policy)** Should an edit made while a work sits in Recently Deleted come back when it is restored? *Recommend yes (DEC-5): content edits are retained and shown after restore; only an explicit permanent delete discards them.*
- **Q-3 (UI)** Tier-1 and tier-2 identity disagree (different AO3 ids, same URL): *recommend a diagnostic now, no review UI; the legacy route keeps the shipped tier-1 outcome (DEC-11).* Does the owner want a "possible duplicate" review flow later?
- **Q-8 (wording)** An explicit Delete Permanently on one device now removes the item from every device's Recently Deleted (v8 never did, N-1). *Recommend adopting it with confirmation copy that names every device ("also on your other devices"), and an undo window equal to none (it is terminal) — owner to approve the wording and whether the 90-day Recently Deleted entry should show "deleted permanently on <device>" instead of vanishing.*
- **Q-9 (policy)** Recovery deadline: *recommend the latest effective deletion date plus 90 days (DEC-3), so a second device's later delete extends, never shortens, recovery time.* The expiry basis rule (DEC-1.2) is the matching mechanism.
- **Q-10 (enrollment UX)** How does a v9 device become an authorized writer and how is revocation shown? *Recommend reusing the pairing flow (QR/trust list, `TombstoneTrustStore`, Android `TombstoneTrustStore.kt`): scanning a founder or already-enrolled device's code emits `writer.enroll`; revocation emits `writer.revoke` with the stolen/retired distinction already in the UI. Semantics (shared authorization facts, DEC-9) are engineering; only the pairing wording is owner's.*
