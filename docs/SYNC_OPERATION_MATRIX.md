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
- **Entity key**: work = random UUID plus identity tiers (§2.2); other entities as in §1. **Lineage** = the original entity key and the merge target (DEC-0); an op's `observedGen` is provenance only.
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
| Asset facts | hasEPUB, remoteEPUBPending, epubDigest, assetIdentifier, freedAt | device-local: `hasEPUB`/`remoteEPUBPending` follow disk (`KB:3640-3660`); `epubDigest` deliberately **not** restored, left to the bytes-install path (`KB:6358-6374`, `RQS:1250`); `freedAt` not in backup | `hasEpub` from disk (`BMS:244-250`); `epubDigest` **the mapped nonblank digest is copied on a winning snapshot** although installed bytes and disk facts are applied separately (`BMS:852`, `244-250`); `freedAt` kept local (`BMS:836`) | X-2f |
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
- **X-2f** `epubDigest`: on a winning snapshot Android copies the **mapped** nonblank digest, a field distinct from the digest of installed bytes; iOS deliberately never restores it (table 1.1).
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

### 2.1 Principle and the retention rule

An operation is applied by **retaining a fact**. Facts are only added; the visible state is a pure function `project(S)` of the retained summaries `S(K)` of every **original key** `K`. No row inspects the projection to decide an op is "stale" and discards it; staleness is a diagnostic (§2.9). A fact that names other ops as evidence either has them as **semantic prerequisites** (buffered; the contiguous prefix does not pass it) or is **fact-first** (retained under its target, visible when the target's create fact exists). §3 says which, per row.

**DEC-0 Lineage is the merge target; generation is provenance.** The merge target of every lifecycle and content fact is the **lineage id** = the original key of the entity (the create op's entity key). `observedGen` on an op is provenance for display and diagnostics only; it never selects a register, a successor, or a winner. (Round 2 made generation a label; it must not stay normative, because every register and lifecycle fact is already lineage-scoped and a label needs its own parent evidence and encoding for no projection benefit.) Plan § C's "(owner generation, asset kind)" therefore becomes "(owner lineage, asset kind)" with generation carried as provenance (§8, plan text to change).

**Retention rule (normative).** For every original key `K` — including **fact-first targets with no create fact** (the summary is then `create = ∅` plus whatever arrived) and **reversibly hidden** entities (`purged(expired)`, an endpoint that is missing or deleted) — a checkpoint stores exactly `S(K)` below. For any cut `C` and suffix `X`: `project(S_C ⊕ X) = project(all facts of C ∪ X)`; this is the checkpoint-plus-suffix equivalence tested in `f2-v9-retention-equivalence.json`, and it must hold for every interleaving of the suffix.

| Part of `S(K)` | Retained |
|---|---|
| create | the create fact or `∅`; identity evidence set (ao3 ids, URLs) |
| registers | per `(K, group)` the winning fact; plus the **single greatest-stamp content fact of `K`** (its op id feeds diagnostics) |
| lifecycle | every **uncleared** deletion `{id, scope, deletedAt}`; for **cleared** deletions their `{id, scope}` only (needed to validate later restores and to classify late duplicates); one merged restore fact `{names = union, latestRestoreOp, observedExpiryOps}`; **all** purge facts `{op, reason, basis, scope, authority evidence, legacy evidence digest}` (explicit and expired, winning or not) |
| epochs | per endpoint (original `(queue key, work key)`): every epoch id with its removal status and the removing op ids; per **(epoch, group)** the greatest-stamp fact, a multi-epoch fact copied to **each** epoch it names; kept while the endpoint is missing or hidden |
| annotation source | add fact; per source: latest note version, **greatest-stamp nonempty note version**, latest locator, latest color, latest content stamp, delete facts naming it |
| asset versions | every version fact `{id, owner lineage, kind, digest, size, observedBase}` and every removal fact — **ancestry independent of blobs**; blob bytes are a separate store |
| settings/entries | per `(key, entry)` the winning fact including resets |
| authorization | all `writer.enroll`/`writer.revoke` facts |

Diagnostics (§2.9) are functions of these summaries and report `(kind, K, latestOpId)`; they never need discarded op ids.

### 2.2 Lifecycle (slice a)

Facts: deletion `D{id, scope, deletedAt}`, restore `R{names, scope, observedExpiry?}`, purge `P{reason, basis, scope, evidence}`; `scope` is a set of lineage ids fixed when the command was captured (below).

- **DEC-1 Validity.** (a) `R.names` and an expiry `P.basis` are **nonempty**. (b) A named deletion is valid for lineage `K` only if `K ∈ D.scope`; an invalid reference projects nothing for `K` and raises `invalidReference(K, latestOp)`. (c) An explicit `P` has a nonempty basis, **or** is the legacy-evidence-only form (empty basis, a legacy-evidence digest, a fixed scope; §4.4). (d) Facts that fail validity are retained.
- **DEC-2 Projection per lineage `K`.** `cleared(D)` iff some valid `R` names it; `U` = uncleared valid deletions. In order: (1) `purged(explicit)` iff an **authorized** valid explicit `P` has `K ∈ scope` — terminal, any order; (2) `purged(expired)` iff an authorized valid expiry `P` with `K ∈ scope` has `basis = U` (set equality) — the **witness is the greatest-stamp such P**, chosen only among authorized, currently matching bases; (3) `deleted` iff `U ≠ ∅`; (4) `live`. Expiry is reversible: a restore naming a basis deletion (authored offline *or* after observing the expiry), or a deletion the basis does not contain, makes it non-matching; a later change that makes `U` equal an old basis again **reactivates that old expiry** (`P{D1}`, then `D2`, then `R{D2}` ⇒ `U={D1}` ⇒ the first expiry is effective again). This is intended: it is the same set of facts.
- **DEC-3 Restores.** `R` names the deletions it observed (prerequisites). It records `observedExpiry` = the expiry ops visible to its author, if any. An offline restore (authored before the expiry was visible) and a command authored after observing it are both effective; they differ only in the diagnostic (`restoredAfterExpiry` vs `offlineRestoreDefeatedExpiry`). An unnamed concurrent deletion stays effective (`R{D1}` with unseen `D2` ⇒ `deleted`).
- **DEC-4 Command scope (visible merged work).** Delete, restore and purge on a visible work apply to the **observed component**: the capturing device records the component's lineage ids in `scope`. Delete ⇒ one `D` per lineage in scope (same op id, same `deletedAt`). A restore's scope is the union of the scopes of the deletions it names. An explicit purge's scope is the recorded scope of the Recently Deleted item (union of its basis deletions' scopes). Replay applies exactly that scope, never a re-derived component. A concurrent duplicate **not in the scope survives**: the component then projects `live` through it, with diagnostic `survivingDuplicate(K, latestOp)`. A separate lineage-scoped administrative op (`scope` of one lineage) exists and is used only for repair.
- **DEC-5 Deadline.** For a `deleted` component: `deadline = max(deletedAt over uncleared deletions of all members) + 90 days` (owner decision: the latest deletion starts the window). Expiry ops carry it as informational payload; no receiver compares it with its clock. The emitting sweep must hold the full `U` of every member in its scope as basis.
- **DEC-6 Content ops never change lifecycle**; edits are retained and projected whatever the lifecycle (owner decision: a restore keeps concurrent edits). Only `purged` hides them.
- **DEC-7 Held copy** (`freedAt`, `WL:17,33-75`) and "free EPUB" are device-local, never facts.
- **DEC-8 Re-acquisition.** `work.create` with `supersedes = <purge op id>`: eligible iff that **named** op is an authorized valid explicit purge whose scope contains a lineage whose identity evidence matches the new create, independent of which purge currently displays as the witness. Matching an entity projected `deleted` or `purged(expired)` emits `R` instead (reversible); matching `purged(explicit)` creates the new lineage. A purge that later becomes unauthorized (DEC-9) leaves the new lineage standing and the old one `deleted` again, with diagnostic `supersedesIneligible`.

### 2.3 Authority

- **DEC-9 Scope of authorization.** Authorization governs **purge ops (explicit and expired) and `writer.enroll`/`writer.revoke` only**. Content, lifecycle-soft (`D`, `R`) and every other fact is retained and projected from any writer admitted by the library (admission is D5). Therefore a revocation can never change which content fact wins, and a checkpoint that keeps only winners stays equivalent.
- **DEC-10 Trusted root and causal evidence.** The trusted root is the founder key set in the bootstrap descriptor. `writer.enroll{subject key}` and `writer.revoke{subject key}` each carry `authority = <enroll op id (or "root")>` naming the fact that makes their author an authorized enroller; that op is a prerequisite. A writer `w` is **authorized for an op** iff there is a chain `root → … → enroll(w)` of enroll facts each valid at its causal cut (every link names its authority as prerequisite) and **no** `writer.revoke` of any key in the chain has a stamp lesser than the op's stamp. The comparison is by stamp, so it is deterministic at any replica. A native signature proves authorship (and authenticates a purge's reason, scope, basis and op identity, DEC-11); authorization is this rule.
- **DEC-11 Envelope.** A `P` carries a signature over `(libraryID, opId, reason, sorted scope, sorted basis, identity tiers, legacyEvidenceDigest?)`. The v8 tombstone signature (`TS:48-65`) covers none of reason, scope, basis or op identity and is never authority.
- **DEC-12 Late revocation.** A revocation with a lesser stamp than a purge reverses that purge's projection when it arrives (the fact is retained). The lineage returns to `deleted`/`live` per DEC-2; a re-acquisition that cited that purge stays as an independent lineage (DEC-8). Retention keeps **all** purge facts and all authorization facts so this re-evaluation is possible at any cut.
- **DEC-13 Legacy evidence** (a verified v8 signed tombstone) is a separate retained fact with its verification result and the adopter's trust decision (recorded in the run record, §4). It projects nothing by itself.

### 2.4 Identity components (slice b)

- **DEC-14 Components, AO3-id first.** Over non-`purged(explicit)` lineages (recomputed on every projection, so after expiry, restore, purge or new evidence): (1) an entity with two different ao3 ids is `identity.conflict` and alone; (2) **ID groups**: entities sharing an ao3 id; (3) a **URL-only** entity (no ao3 id) attaches to an ID group iff the full set of its URL evidence touches **exactly one** ID group; touching two or more ⇒ it stays separate with diagnostic `identity.ambiguousUrl`; touching none ⇒ it groups with other URL-only entities sharing a URL; (4) two entities with different ao3 ids and a shared URL stay separate, diagnostic `identity.urlMismatch` (even when each carries a single id). The legacy route keeps the shipped tier-1-first outcome. Survivor = lowest canonical UUID in the component. Owner decision: automatic, with a diagnostic, no review screen.
- **DEC-15 Mapping, originals, splits.** Every lineage keeps its own lifecycle and register facts. A component's lifecycle: `live` if any member is `live`; else `deleted` if any member is `deleted`; else `purged`. Content group = greatest-stamp fact over members; identity = union. Work-scoped references store the **original key** and project through the *current* component of that key; after a purge or a split they project to whatever component now holds the key, or to the key alone (purged keys: the reference is retained, hidden for work-scoped content, and kept visible for independent classes: sessions, favorites, watermarks, work-layer pronunciation entries).

### 2.5 Membership epochs

- **DEC-16 Endpoints.** Original endpoint = `(queue key, work key)`; projection groups original endpoints by `(queue, component of work)`. Saved for Later has the fixed queue key `queue:savedForLater`, not the platform UUID (matched by kind, `BMS:1700`, `KB:3950`).
- **DEC-17 Epochs.** `add{epoch=opId}` starts an epoch; `remove{names epochs}` ends exactly those. Presence = any epoch not named by a removal, **after endpoint filtering** (a purged work or queue endpoint drops only its own epochs). Concurrent initial adds are two live epochs.
- **DEC-18 Per-epoch group maxima.** A `move/note/state/origin` fact naming `{a,b}` is stored as one fact for `(a, group)` and one for `(b, group)`. For each original epoch and group the greatest stamp is retained, **while its endpoint is missing, deleted or expiry-hidden**. Projection of a group for a member = greatest stamp among the per-epoch maxima of its live epochs. So a move naming `{a,b}` still wins for `b` after `a` is removed, even if a newer move names only `a`. Equal ranks order by `(rank, canonical work survivor key)`. Same rule before and after alias projection.

### 2.6 Annotations

- **DEC-19 Sources.** Each annotation id is a source. Per source the retained facts are in §2.1: add fact, latest note, **greatest-stamp nonempty note**, latest locator, latest color, latest content stamp, delete facts. Locator and color are LWW registers; **winner rank** = the greatest stamp over all of a source's content facts (add, note, locator, color edits).
- **DEC-20 Delete scope.** A user delete names the **observed group** of source ids and their add ops (prerequisites); it deletes exactly those sources. Unseen concurrent members stay and may become visible.
- **DEC-21 Dedupe projection.** Candidates = non-deleted sources, same component, same kind, same **non-blank exact** current locator (blank/whitespace-only never dedupe, DEC-24). Winner = greatest rank. Effective winner note = winner's latest note; if empty, the **greatest-stamp nonempty note among loser sources' greatest nonempty notes** (fill, as v8). A loser **parks** its greatest nonempty note iff it differs from the effective winner note; parked sibling id = `UUIDv5(NS, bytes)` with `NS = 6c1f3b7e-6f1a-4a6e-9d34-0a3b8b0e5c11` and `bytes` = UTF-8 of `lower(sourceId) 0x1F canonOpId(noteVersion)`, where `canonOpId = lower(libraryID) "/" lower(incarnation) "/" decimal(seq)`. An explicit clear does **not** suppress older text for fallback and parking (intended: salvaged text is never lost); it does change the source's own visible note. No tombstone, no alias op.
- **DEC-22** Edits name their **source id**; the UI addresses the visible winner's id. An edit to a loser source updates its facts and may change winner, fallback or parked set.

### 2.7 Assets

- **DEC-23 Version facts and heads.** `asset.write{owner lineage, kind, digest, size, observedBase}`. The `observedBase` must be a version of the **same owner lineage and kind** (validated; else `invalidReference`, retained, not projected). A replacement therefore writes to the owner of the version it replaces; `owner` is derived from the base when one is named. A version is **superseded** if another version has it in its `observedBase` ancestry. **Heads** of a lineage = unsuperseded, unremoved versions. A component's winner = greatest-stamp head over all member lineages; alternates = every other head, per lineage (`assetConflict(owner, kind, heads)` diagnostic when more than one). After a split each lineage keeps its own heads. A same-digest write is still a fact and advances the winner's stamp.
- **DEC-24 Shared removal.** `asset.remove{names version ids}` (named versions are prerequisites) **hides the named versions and permanently preserves the supersession they established**: for `v1 → v2`, removing `v2` leaves **no reference** (`v1` stays superseded). A future write may name a removed version as base. Shared reference removal is this row; ordinary eviction stays device-local (plan § C).
- **DEC-25 Bundles, chapter data, pending.** `original` + `conversionRecord` = one bundle fact; set-once = lowest stamp is current, others alternates. Chapter metadata (`chapterWordCountsJSON`, `wordUnitRaw`) is a register whose facts carry `forDigest`; the projection selects the greatest-stamp fact whose `forDigest` equals the winning digest, else none (recomputed locally). `available` is device-local, set after size/digest verification and recoverable install; the verified previous file stays readable until the new one is installed.
- **DEC-26 Fonts.** Font identity = the set of add facts with equal digest and case-folded name (coalesced). Names: reserve every literal case-folded name first; fonts sharing a folded name but with different digests are ordered by their greatest-add stamp ascending: the first keeps the literal name, the n-th takes `-restored-k` with the smallest `k ≥ 1` whose folded name is not reserved. `font.remove` names **all add ids its device observed** in the coalesced font; the font stays while any add is unremoved.

### 2.8 Registers, absence, reset, ties

| Register kind | Selection | Reset | Used for |
|---|---|---|---|
| LWW | greatest stamp | `null` fact with its own stamp (retained) | flags, text, progress, colour, pin, rank, note, locator, color |
| Set-once | lowest stamp | none; later differing values are alternates | provenance, originals |
| Grow-only set | union | none | tag lists, monotonic flags (OR) |
| Max-rank | greatest by a fixed comparator | none | preservation status (`notPreserved < queued < preserving < preserved`), `seriesPosition` (max), dates (max) |
| Value-ordered | greatest by a fixed value comparator, then canonical bytes | none | cover pin (`KB:6400-6414`) |
| Epoch-scoped | §2.5 | remove names epochs | membership groups, user-tag presence, queue tags (observed-remove set), immediate-delete classes' put/delete (below) |
| Entry presence | per `(key, entry)` LWW with retained resets | reset fact | settings maps, pronunciations |

Stamps are unique so max/min never tie; value-ordered registers tie-break on canonical JSON bytes. **DEC-27** Absent group = no effect; `null` = reset; malformed values dropped with a diagnostic, never read as reset (`KB:2740-2780`); unknown groups and ops pass through opaque. **DEC-28** Immediate-delete classes (saved searches, bookmarks, followed tags, tag aliases, sessions, favorites, watermarks): `put` starts an epoch, `delete` names observed epochs; re-adding after a delete is a new epoch and is live. **DEC-29** Fixed operation clock and date normalization are legacy-adapter concerns (§4): `norm(d) = min(d, min(exportedAt, opClock+24h))`.

### 2.9 Diagnostics

Computed from the retained summaries, sorted, as `(kind, K, latestOpId)`: `unauthorizedPurge`, `restoreAfterExplicitPurge`, `editToPurgedLineage`, `assetToPurgedLineage`, `invalidReference`, `expiryInvalidated(reason ∈ restored|unseenDeletion)`, `restoredAfterExpiry`, `offlineRestoreDefeatedExpiry`, `survivingDuplicate`, `supersedesIneligible`, `assetConflict`, `identity.conflict|ambiguousUrl|urlMismatch`, `sessionIdCollision`. They never depend on arrival order or on discarded op ids.

## 3. The matrix

Columns follow plan § D4: (1) command and capture intent; (2) target identity and lineage; (3) value group; (4) absence/null/reset; (5) prerequisites (named op ids or `fact-first`, §2.1); (6) concurrent outcome and tie-break; (7) stale/duplicate; (8) checkpoint state (`S(K)` parts of §2.1).
"Stale/duplicate" states the *projection* result; nothing is discarded. A duplicate op id is an idempotent no-op on the fact set. `scope` is the set of lineage ids captured with a command (DEC-4).

### 3.1 Work lifecycle, content and assets (slices a and c)

| Op | Command / capture intent | Target / lineage | Value group | Absence · null · reset | Prerequisite | Concurrent outcome · tie-break | Stale / duplicate | Checkpoint state |
|---|---|---|---|---|---|---|---|---|
| **W1 work.create** | Save/import/download with no identity match (`importEPUB` re-check, `INVARIANTS` Identity). One op initialises every group of §3.1b with a register fact each; may carry `supersedes` (DEC-8) | new lineage = op's entity key | all §3.1b groups + identity evidence | absent group = no fact | none; `supersedes` names a purge op (prerequisite) | identity match with another lineage → component (DEC-14) | duplicate op: no-op | create fact, evidence, registers |
| **W2 work.delete** | `PWS.softDelete` (`PWS:116`) on the **visible** work: capture the observed component's lineage ids as `scope`. Today also a signed tombstone (`PS:435`). | each lineage in `scope`; `observedGen` provenance | lifecycle | none | none (fact-first on each lineage) | DEC-2: any uncleared valid `D` ⇒ deleted; deadline = latest `deletedAt` over all members (DEC-5); a member outside `scope` survives (diagnostic) | `D` after explicit purge: retained, projects nothing | uncleared `D` `{id, scope, deletedAt}`; cleared `{id, scope}` |
| **W3 work.restore** | Recently Deleted Restore (`PWS:175`); re-acquisition of a deleted work (DEC-8); Merge undo of parking (`KB:3470-3490`). `scope` = union of the named deletions' scopes; records `observedExpiry` | each lineage in `scope` | lifecycle | none | **the named deletion ops** (nonempty; each valid for the lineage, DEC-1) | clears exactly named `D`; restore after observing expiry and offline restore both effective (DEC-3); unnamed `D` stays effective | names a deletion outside the lineage: `invalidReference`, no effect; restore after explicit purge: retained, hidden | merged restore fact (union of names, latest op, observedExpiry) |
| **W4 work.purge(explicit)** | Delete Now / Delete Permanently (`WL:178`) on a Recently Deleted item; `scope` = the item's recorded scope; v9 envelope (DEC-11). **Legacy-evidence-only form** for MC-7: empty basis, evidence digest, fixed scope, authorized adopter, **no synthetic deletion** | `scope` | lifecycle | none | basis deletions (or legacy evidence digest) | terminal, wins any order; two explicit purges: greatest stamp is the displayed witness, both retained | unauthorized: retained, ignored, diagnostic; duplicate: no-op | all purge facts with authority evidence |
| **W4x work.purge(expired)** | Sweep after the deadline (`PWS:296`), emitter holds the full `U` of every member in scope | `scope` | lifecycle | none | nonempty basis deletions | valid only while `basis = U` (DEC-2.2); reactivates if `U` returns to the basis | invalid expiry: retained, `expiryInvalidated` | all purge facts |
| **W5 re-acquire** | Any acquisition with an identity match: matched `deleted`/`purged(expired)` ⇒ W3; matched only `purged(explicit)` ⇒ W1 with `supersedes` | per DEC-8 | lifecycle / asset | — | the named purge op | DEC-8 eligibility is against the named purge | purge later unauthorized ⇒ `supersedesIneligible` | the `supersedes` link |
| **W6 heldCopy** (local) | `WL:33-75` | — | `freedAt` | — | — | — | — | none |
| **W7 work.edit** | A user or refresh edit of one or more §3.1b groups (one fact per group) | lineage | one or more groups | absent no effect; `null` resets where §3.1b allows | none (fact-first) | per register kind (§2.8) | edit to purged lineage: retained, hidden, diagnostic `editToPurgedLineage(latest)` | per-group winner + greatest content fact |
| **W8 asset.write** | `replaceEPUB` (`RQS:1227`), user re-import, update refresh | `(owner lineage, kind)`; owner derived from the base | `asset.epub` etc. | — | its `observedBase` version (named; same owner and kind, DEC-23) | heads, alternates per lineage, winner by stamp; same-digest write advances the winner | duplicate digest, higher stamp: new fact; older stamp: kept (ancestry decides) | version facts incl. ancestry |
| **W9 asset.remove** | shared reference removal (not eviction) | named versions' owner | asset version visibility | — | the named version ops | hides named versions, keeps their supersession (DEC-24) | remove of removed: no-op | removal facts |

#### 3.1b W1 initial groups and native update policies

| Group | Fields | Register kind (v8 rule mirrored) | Reset |
|---|---|---|---|
| identity | id, ao3WorkID, canonical URL | grow-only evidence (`WII:39-53`) | none |
| text metadata | title, author, summary, rating, language, datePublished, dateUpdated, chapters, seriesTitle, seriesURL | LWW per field; capture never emits blank (`KB:6417`) | none |
| counters | wordCount, kudos, comments, bookmarks, hits, knownChapterCount | LWW per field; capture never emits ≤0 (`KB:6423`) | none |
| series position | seriesPosition | max-rank, max (`KB:6314`) | none |
| flags | isFavorite, isSaved, isFinished, isComplete | LWW | explicit false is a value |
| monotonic | hasGivenKudos, ao3Unavailable, workTagsFetched, isQueuedForLater (derived) | grow-only OR (`KB:6248`, `6340`) | none |
| reading status | status, stop*, stack*, statusWasRecorded, statusChangedAt, stoppedAt (atomic) + keepInProgressOverride + hiddenFromHistoryAt | LWW per atomic group | `hiddenFromHistoryAt` null |
| progress | lastSpineIndex, lastScrollFraction, readiumLocator, lastReadDate, progressModifiedAt, legacyReaderProgress (atomic) | LWW; `locator ""` = reset, absent = unchanged (`PS:716-760`) | `legacyReaderProgress` null |
| cover pin | coverRecipeJSON | value-ordered (`KB:6400-6414`) | none |
| provenance | importSource*, *AtSave, statsSavedAt | set-once | none |
| preservation | status, preservedAt, attempt dates | max-rank: `notPreserved < queued < preserving < preserved`; dates max (`KB:6350-6380`) | none |
| tag lists | warnings, categories, tags, fandoms, characters, relationships, freeforms | grow-only union | none |
| user tags | Tag names attached | epoch-scoped presence (T1) | detach |
| chapter data | chapterWordCountsJSON + wordUnitRaw | LWW facts with `forDigest`; projected for the winning digest (DEC-25) | none |
| authors | authorIdentitiesJSON | LWW, nonempty only (`KB:6272`) | none |
| download date | downloadedAt | LWW | none |
| asset | `asset.epub`, `asset.original` bundle | DEC-23..25 | none |

### 3.2 Identity, memberships, annotations, sessions, favorites

| Op | Command / capture intent | Target / lineage | Value group | Absence · null · reset | Prerequisite | Concurrent outcome · tie-break | Stale / duplicate | Checkpoint state |
|---|---|---|---|---|---|---|---|---|
| **I1 identity.evidence** (no op) | Carried by W1 and by a W7 that fills ao3 id/URL | lineage | identity | grow-only | none | components by DEC-14 | duplicate: set union | evidence set |
| **M1 membership.add** | `ReadingQueueService` add; original endpoint `(queue key, work key)`; epoch = op id; carries the epoch's first rank/note facts | endpoint | epoch + first facts | — | none (fact-first on both endpoints) | two adds = two live epochs (DEC-17) | add after remove: a new live epoch | epoch ids |
| **M1r membership.remove** | remove from queue (`PS:476`) | the observed epochs | presence | — | the named add ops | ends exactly named epochs; unseen epoch stays live | unknown epoch: waits | removal facts naming epochs |
| **M2 membership.move** | reorder (`RQS:1270`): one fact per moved member naming observed epochs | per original epoch | `rank` | — | named epochs | per-epoch maxima (DEC-18); equal ranks by `(rank, work key)` | move naming only dead epochs: retained | per-`(epoch, group)` max while endpoint missing/hidden |
| **M3 membership.note/state/origin** | note, state, origin edits | per original epoch | three groups | note `""` is a value; origin null = reset | named epochs | as M2 per group | as M2 | per-`(epoch, group)` max |
| **M4 collection.membership add/remove** | epoch rule, no rank (`PS:602`) | `(collection, work)` | presence | — | as M1/M1r | as M1 | — | epochs |
| **A1 annotation.add** | In-book bookmark/highlight/note | source id | source add + note version | `note ""` is a version | none (fact-first on work) | DEC-21 | duplicate id: no-op | source facts (§2.1) |
| **A2 annotation.edit** | note / color / locator edit | source id | note version; color; locator (LWW) | absent unchanged | none | LWW per register; every edit raises the source's rank (DEC-19) | — | latest + greatest-nonempty note, latest locator/color |
| **A3 annotation.delete** | delete one visible annotation (`PS:489`) | observed group of sources | lifecycle of each | — | the named source add ops | deletes exactly the named group | delete of unseen source: waits | delete facts |
| **S1 session.append** | `ReadingSession` finalize (`ReadingSession.swift:9`); id is the key | session id | full row; timing groups set-once (lowest stamp) | old rows keep nil, never backfilled | none (fact-first) | same id cross-writer ⇒ `sessionIdCollision` (repair); fill-only groups: lowest stamp | duplicate: no-op | row + set-once groups |
| **S2 session.delete** | immediate-delete (`PS:530`) | id (epoch rule, DEC-28) | lifecycle | — | named epoch | delete holds against that epoch; a later put is a new epoch | — | epochs |
| **F1 favorite.set/clear** | `PS:545` | `(kind, target)`; `.work` target = original work key | presence + displayName | clear = stamped null (epoch rule) | none | LWW; alias collapses keys by projection | — | per key |
| **F2 watermark.set/clear** | `PS:558` | fandom name | atomic `{lastVisitedAt, newestWorkIDSeen, title}` | clear stamp | none | LWW | — | per name |

### 3.3 Settings, tags, queues and collections, recovery, fonts, originals, authorization

| Op | Command / capture intent | Target / lineage | Value group | Absence · null · reset | Prerequisite | Concurrent outcome · tie-break | Stale / duplicate | Checkpoint state |
|---|---|---|---|---|---|---|---|---|
| **P1 setting.set/reset** | named/extras setting (`SSC.noteLocalChanges`, `KB:2628`); explicit stamps only | setting key | one group per key; voice id+name and hue+hex are pairs | reset = null fact; malformed ignored | none | LWW | — | winner or reset |
| **P2 setting.entry.set/reset** | map settings (drafts, Posting As) | `(key, entry)` | entry presence | reset retained | none | per-entry LWW | — | per-entry fact incl. resets |
| **P3 pronunciation.set/reset** | `KB:853-935`; work layer key = original work key, projected by DEC-15 | `(layer, word)` | entry presence | reset retained | none | LWW (counter tie → incarnation) | — | per-entry incl. resets |
| **T1 userTag.attach/detach** | user tag on a work (`Tag.name`, `M:887`) | `(work lineage, tag)` | epoch presence | detach names attach epochs | named attaches | as memberships; v8 union only: adapter never infers detach from absence | — | epochs |
| **T2 queue/collection.edit** | name; colour{hue,hex}; pin; keepsWorksOffline; notes; smartRules; searchSources (+modifiedAt); **queue tags** (observed-remove set: add epochs, remove names epochs); **collection description**; sortOrder; showsOnHome; workOrderRaw | queue/collection lineage | one group each | hue null never clears; others reset by null | none (tags: named epochs) | LWW per group; colour pair by `chosenColor` (`PS:656-666`) | — | per group; tag epochs |
| **Q1 queue/collection lifecycle** | W2–W4x rules for `queue`/`collection` lineages; Saved for Later keyed `queue:savedForLater`, never deleted or aliased by id; memberships stay attached while deleted; purge cascade DEC-2 | lineage + scope | lifecycle | — | named deletions | DEC-2 | — | as W2–W4x |
| **R1 recoveryDoc.put** | writing recovery copy or `documents` file (`BackupAppState.swift:25-140`); key = **file name** (digest of account/target/field + session id ⇒ equal key ⇔ same session) | file name | `{entry, savedAt}` register | never removed | none | LWW by stamp; v8 = replace only with a newer save of the same session | — | per name |
| **FN1 font.add / FN2 font.remove** | `M:923` | font = coalesced add facts (DEC-26) | asset version + display name | remove names all observed add ids | blob for `available` only | DEC-26 name reservation | — | adds, removals |
| **O1 original.set** | converted import original + sidecar | `(work lineage, original)` | bundle (DEC-25) | — | none | set-once, lowest stamp | — | all bundles |
| **L1a savedSearch** / **L1b bookmark** / **L1c followedTag** / **L1d tagAlias** put/delete | `PS:504-585`; natural keys: bookmark URL, followedTag `ao3TagID`, tagAlias `(normalized name, kind)`, savedSearch id | key | content LWW; grow-only seen ids / parentFandoms | delete names observed epochs; **re-add after delete = new epoch, live** (DEC-28) | named epochs | LWW; 20-tag follow cap resolved by earliest follow stamp, the rest retained not projected | — | epochs + content |
| **E1 writer.enroll/revoke** | pairing/revocation UI (`TombstoneTrustStore`); founders in bootstrap | subject key | authorization | — | `authority` enroll op or `root` | DEC-9..12 | — | all authorization facts |

Smart (derived) memberships are never ops (`INVARIANTS` Queues); the adapter skips `kind=smart` as `KB:4194-4203` does.

## 4. Legacy route table and adapters

A **legacy adapter** turns a v8 manifest (and its assets) into v9 operations. It runs in three separate steps so that "what today's app would do" is never confused with "what v9 additionally changes":

1. **Accept via the named shipped route.** Run the route exactly as the shipped build on the importing device does (iOS `KudosBackupService.restore`, Android `BackupMergeService.merge`), including its date, fill, dedupe, tombstone and membership behaviour. The only injection is the clock value the shipped code already takes (`now`) and the trust set; the adapter records both. Result = the **accepted result** (post-merge normalized state).
2. **Apply explicitly approved migration changes.** A fixed list of named changes `MC-n` (§4.3), each independently approved; a change not approved is not applied. MC-4 (omitted keys) is mandatory for v9; otherwise the default list is empty. A change that needs data the shipped route discarded is applied by **replaying the route over the retained original inputs** (§4.5), not by editing the accepted result.
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

### 4.3 Migration changes (step 2), all proposed and **off by default**, except MC-4

An approved change is **never** a transformation of the accepted result when the shipped route discarded the input. It is a **replay of the route over the retained original inputs** (the manifest fragment and the local pre-merge fragment with presence bits, §4.5) under the changed predicate, or a transformation using explicitly retained pre-loss facts.

| ID | Change | Resolves | Replay input needed | Needs |
|---|---|---|---|---|
| MC-1 | Date normalization `min(d, min(exportedAt, opClock+24h))`, never reject | X-1, X-21 | raw manifest dates | owner (Q-5 resolved: separate from shipped import) |
| MC-2 | Never replace known text/counters with blank/zero | X-2 | both sides' pre-merge values | owner for Android manual import |
| MC-3 | Match memberships by `(queue, work)` | X-4 | both membership lists | engineering |
| MC-4 | Record omitted keys before defaulting; omitted ⇒ no delete (T-563). **Mandatory for every v9 translation**; the shipped compatibility baseline (the v8 fixtures) is kept separate | X-5 | presence bits of every top-level key | required |
| MC-5 | Import an archive's Recently Deleted copy per the iOS rule (an Android-suppressed work is **recovered by replaying the work loop** from the retained fragment, not from the accepted result) | X-6 | the suppressed archive record and the tombstones | engineering |
| MC-6 | Tombstone tie: newest, permanent wins | X-7 | all tombstone candidates | engineering |
| MC-7 | Legacy-evidence-only explicit purge (below) | N-1 | verified tombstone + adopter authority | owner wording (Q-8) |
| MC-8 | Blank/whitespace anchors never dedupe (an iOS-deduped annotation is **recovered by replaying the dedupe** from the retained local and incoming annotation lists); the v9 nonblank-anchor rule itself is DEC-24 and holds even when MC-8 is off | X-10 | both annotation lists | engineering |
| MC-9 | Never rename on collision | X-12 | both name sets | engineering |
| MC-10 | Compare originals by bytes on publish | X-16 | both byte sets | engineering |

**MC-7 policy.** For a *verified permanent* legacy tombstone the adopter, **if authorized**, may mint one explicit purge in the **legacy-evidence-only form**: empty basis, `legacyEvidenceDigest`, and a `scope` fixed at the baseline cut to the lineages whose identity evidence matches the tombstone. No deletion fact is fabricated. If MC-7 is off, or the adopter is not authorized, the outcome is **held-live**: the evidence is stored, the work stays (shipped behaviour, N-1), and diagnostic `legacyPurgeNotAdopted` is raised.

### 4.4 Translation (step 3)

Inputs: accepted result (after step 2) and the local v9 projection at the **accepted baseline cut**. Output: an ordered list of ops; for each lineage (sorted by canonical key) and each group (order of §3.1b, then memberships, annotations, sessions/favorites/watermarks, settings, assets) emit an op only where accepted ≠ baseline. Replace is forced at acceptance, so differences are more frequent, but equal values emit nothing.

| Accepted transition | Op |
|---|---|
| new entity | W1 create (+ evidence); archive dates are payload only |
| group value differs | W7 edit of that group, or the kind's own op (P1, F1, L1…); no per-field history |
| live → deleted | W2 delete, `scope` = the lineages the accepted result deleted, `deletedAt` from the archive record |
| deleted → live (newer snapshot, Merge undo of parking) | W3 restore naming **every uncleared deletion fact of those lineages at the baseline** (nonempty); a deleted lineage always has a deletion fact (the seed run created it from the archive's own `isDeleted`/`deletedAt`), so no evidence is fabricated; with none, no restore is emitted |
| revival of a lineage projected `purged(expired)` | W3 restore |
| revival of a lineage projected `purged(explicit)` | W1 create with `supersedes` |
| verified permanent legacy tombstone | MC-7 only, per the policy above; otherwise nothing |
| membership present/ranked/removed | M1, M2, M1r naming baseline epochs |
| annotation new/changed/hidden | A1, A2, A3 naming the observed source group; accepted same-passage dedupe is **not** translated (projection) |
| EPUB bytes installed | W8 with `observedBase` = the baseline winner version of that lineage; bytes staged to the pool |
| original + sidecar installed | O1 bundle |
| Replace omission | delete ops per §4.6, only for keys the archive carries (MC-4) |

### 4.5 Durability, ordering, conflicts

A **run record** is stored durably before anything is published: route, shipped build id, trust set, `opClock`, `sourceManifestDigest`, **baseline cut** (applied cut + checkpoint id), **the original fragments and presence bits** (manifest fragment, local pre-merge fragment, which top-level keys were present), `acceptedResultDigest`, approved MC ids, the **ordered translation list**, and per op the **reserved op id `(writer, seq)` with its exact canonical bytes** (not only a hash; if an encoder version is stored instead, the immutable inputs plus that versioned encoder must reproduce identical bytes), and the **asset inputs** `{lineage, digest, size, stagedBlobPath}`. Publishing retries the same bytes (plan § C). A crash after acceptance resumes from the record; step 1 never re-runs against moved local state.

**Stamps are assigned at reservation.** A local edit committed after reservation has a greater stamp and wins registers and epochs against the migration op. A local change committed **between acceptance and reservation** is detected at reservation, per kind, by comparing local facts beyond the baseline cut with the translation:

| Kind | Conflict test | Result |
|---|---|---|
| scalar/LWW group | a local fact on `(lineage, group)` beyond baseline | drop that group's op, diagnostic `localEditWins` |
| lifecycle | any local `D`, `R` or `P` on the lineage beyond baseline | drop the lifecycle op; a restore still names only baseline deletions, so a newer local delete stays uncleared |
| membership | a local add/remove/move on the endpoint beyond baseline, or a named baseline epoch no longer live | drop the op for that endpoint |
| asset | a local version fact on `(lineage, kind)` beyond baseline | drop the W8/O1; the staged blob stays referenced by the run record |
| annotation | a local source fact or delete on a named source beyond baseline | drop the op |

The seed run is the same pipeline with an empty baseline. Unknown manifest keys are preserved verbatim as opaque facts (Android overlay rule becomes universal).

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
