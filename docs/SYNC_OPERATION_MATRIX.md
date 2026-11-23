# Sync operation matrix and legacy adapters (T-569 D4)

Status: specification, not shipped behaviour (round 4, after Codex reviews 1 to 3 in `out/`). Normative input to D5 (`docs/SYNC_JOURNAL_FORMAT.md`). Plan: `docs/DATA_ARCHITECTURE_PLAN.md` v3.2 § C, § D. D5 wire drafting and D6 inventory may use it; do not freeze the checkpoint format until D4 is accepted.
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

An operation is applied by **retaining a fact**. Facts are only added; the visible state is a pure function `project(S)` of the retained summaries `S(K)` of every **original key** `K`. No row inspects the projection to decide an op is "stale" and discards it; staleness is a diagnostic (§2.9). A fact that names other ops as evidence either has them as **semantic prerequisites** (buffered; the contiguous prefix does not pass it) or is **fact-first** (retained under its target, visible when the target's create fact exists). §3 says which, per row. Capture-only metadata (for example the lineages a command observed) is never a prerequisite.

**DEC-0 Lineage is the merge target; generation is provenance.** The merge target of every lifecycle and content fact is the **lineage id** = the original key of the entity. `observedGen` on an op is provenance only; it never selects a register, a successor or a winner, and it is never validated. Plan § C's asset reference is `(owner lineage, asset kind)`.

**Retention rule (normative, exhaustive by reducer).** For every original key `K` — including **fact-first targets with no create fact** (`create = ∅`) and **reversibly hidden** entities (`purged(expired)`, a missing or deleted endpoint) — a checkpoint stores exactly the entries below. **Every stamp-ordered entry keeps its stamp and op id.** For any cut `C` and suffix `X`: `project(S_C ⊕ X) = project(all facts of C ∪ X)` for the **normalized projection and the diagnostics**, under every complete suffix order; this is tested in `f2-v9-retention-equivalence.json` and by the generator on every universe.

| Reducer | Retained per original key |
|---|---|
| create / identity evidence | the create fact or `∅`; the **set** of ao3 ids and the **set** of URLs (all ids kept, so `identity.conflict` survives) |
| LWW register | per `(K, group)` the winning fact; **chapter data is keyed `(K, chapter group, forDigest)`** and keeps the greatest stamp at each key (selection for the winning digest is a projection step, DEC-25); plus the single greatest-stamp content fact of `K` |
| set-once register / bundles | **all** facts (the lowest stamp is current, the rest are the alternates the projection exposes), each with stamp and op id |
| grow-only set | the union of values per `(K, group)` with the greatest stamp seen |
| lifecycle | every deletion `{id, scope, deletedAt}`; `deletedAt` is dropped only once the deletion is cleared in **every** lineage of its scope; valid restore evidence **keyed by deletion**: per `(K, deletion id)` the greatest-stamp valid restore, and per `(K, deletion id, expiry op)` the greatest-stamp restore that observed that expiry; invalid-reference witnesses (per lineage, the op id) and invalid-command ops kept separately; **all** purge facts (any reason, winning or not) with basis, scope, signed identity, authority head and legacy-evidence digest |
| authority | all `writer.enroll`/`writer.revoke` facts with their named authority heads |
| epochs (memberships, user tags, queue tags) | per original endpoint every epoch id with its removing op ids; per `(epoch, group)` the greatest-stamp fact, a multi-epoch fact copied to **each** epoch it names; kept while the endpoint is missing, deleted or hidden |
| observed-epoch records (S1/S2, F1/F2, L1, DEC-28) | **every put with its payload and stamp**, and every delete naming put epochs; the projected value is the payload of the greatest-stamp live put, so deleting the winning epoch exposes another |
| annotation source | add fact; per source the latest note, the **greatest-stamp nonempty note**, the latest locator, the latest color, the latest content stamp; delete facts naming it |
| asset versions | every version fact `{id, owner lineage, kind, digest, size, observedBase}` and every removal fact (**ancestry independent of blobs**); a write's validity is derivable from retained facts alone |
| fonts | every add `{id, name, digest}` and every removal naming add ids |
| entries | per `(key, entry)` the winning fact including resets |
| diagnostic witnesses | the op ids named in §2.9 are each reconstructible from the entries above (greatest content fact, greatest restore per deletion, purge facts, invalid witnesses) |
| unknown / opaque facts | kept verbatim with their op id and stamp; they project nothing |

### 2.2 Lifecycle (slice a)

Facts: deletion `D{id, scope, deletedAt}`, restore `R{names, scope, observedExpiry}`, purge `P{reason, basis, scope, identity, authority, evidence}`. `scope` is a set of lineage ids fixed when the command was captured.

- **DEC-1 Scoped evidence and validity.** For lineage `K`: `names_K(R) = {d ∈ R.names | K ∈ scope(d)}` and `basis_K(P)` likewise. **Command-level malformation** (empty scope, an empty `names`/expiry basis, or a name that is not a deletion op — a wrong-kind reference) makes the whole command invalid: retained, no effect on any lineage, `invalidCommand(op)`. Otherwise validity is **per lineage**: a restore applies to `K ∈ R.scope` iff `names_K ≠ ∅`; a native purge or expiry applies to `K ∈ P.scope` iff `basis_K ≠ ∅`; a lineage in scope with an empty per-lineage set gets `invalidReference(K, op)` and no effect while the other lineages are processed independently. The legacy-evidence-only explicit purge (empty basis, §4.3) is the single exception.
- **DEC-2 Projection per lineage `K`.** `cleared(d)` iff some valid restore applies to `K` with `d ∈ names_K`; `U_K` = uncleared deletions with `K ∈ scope`. In order: (1) `purged(explicit)` iff an authorized valid explicit `P` applies to `K` — terminal, any order; (2) `purged(expired)` iff an authorized valid expiry `P` applies to `K` with `basis_K = U_K` (set equality), **evaluated independently for each lineage of a multi-lineage scope**; the witness is the greatest-stamp such `P`; (3) `deleted` iff `U_K ≠ ∅`; (4) `live`. A restore (offline or authored after observing the expiry), or a deletion the basis does not contain, makes an expiry non-matching; a later change that makes `U_K` equal an old basis again **reactivates that old expiry** (`P{D1}`, `D2`, `R{D2}` ⇒ purged again) — same facts, same answer, fixtured.
- **DEC-3 Restores.** `R` names the deletions it observed (prerequisites) and records `observedExpiry` (the expiry ops visible to its author, if any). An unnamed concurrent deletion stays effective.
- **DEC-4 Command scope (visible merged work).** Delete, restore and purge on a visible work apply to the **observed component**: the capturing device records its lineage ids in `scope` (and in capture-only metadata). Delete ⇒ one `D` per lineage in scope (same op id, same `deletedAt`). A restore's scope is the union of the named deletions' scopes; a purge's is the Recently Deleted item's recorded scope. Replay applies exactly that scope. A concurrent duplicate **outside the scope survives** (`survivingDuplicate`). A lineage-scoped administrative op (scope of one lineage) exists for repair.
- **DEC-5 Deadline.** For a `deleted` component: `deadline = max(deletedAt over the uncleared deletions of all its members) + 90 days` (owner decision). Expiry carries it as informational payload; no receiver compares it with its clock; the emitting sweep must hold every member's full `U_K` as its per-lineage basis.
- **DEC-6 Content ops never change lifecycle** (owner decision: a restore keeps concurrent edits); only `purged` hides them.
- **DEC-7 Held copy** (`freedAt`, `WL:17,33-75`) and "free EPUB" are device-local, never facts.
- **DEC-8 Re-acquisition.** A re-acquisition is an ordinary new lineage that **keeps its original lineage key and participates in DEC-14 again**. `work.create` with `supersedes = <purge op id>` is eligible iff that **named** op is an authorized valid explicit purge whose **signed identity** (the identity tiers carried in the envelope, not accumulating lineage evidence) matches the new create's ao3 id or a URL, independent of which purge currently displays as the winner. Matching an entity projected `deleted` or `purged(expired)` emits `R` instead. If the purge later becomes unauthorized (DEC-12) the old lineage returns to its DEC-2 state, the new lineage is unchanged and simply groups with it by DEC-14, and `supersedesIneligible` is raised.

### 2.3 Authority

- **DEC-9 Scope.** Authorization governs **purge ops (explicit and expired) and `writer.enroll`/`writer.revoke` only**. Content, soft lifecycle (`D`, `R`) and every other fact is retained and projected from any admitted writer (admission is D5). A revocation can never change a content winner.
- **DEC-10 Chain heads, named and signed.** Every `purge`, `enroll` and `revoke` names its author's **authority head**: `root:<founder key>` when the author is a founder, otherwise the op id of an `enroll` fact whose subject is the author. A non-root head is a **semantic prerequisite** and part of the signed envelope (DEC-11). The trusted root is the founder key set of the bootstrap descriptor.
- **DEC-10a Stamp-order evaluation.** Authorization facts are evaluated **in stamp order**: start with the founders authorized; an `enroll` is valid iff its author is authorized at its stamp and its head is valid (founder root, or a valid enroll of the author with a strictly lesser stamp); a `revoke` is valid iff its author is authorized at its stamp and its head is valid; only **valid** earlier revocations remove a key. **Founder keys cannot be revoked** (a revoke naming a founder has no effect). **A revoked key can be re-enrolled** by a new valid enroll with a greater stamp, which restores authorization from that stamp. A purge is authorized iff its author is authorized at the purge's stamp and its head is valid. Revoking an enroller does not cascade.
- **DEC-11 Envelope.** A `P` signs `(libraryID, opId, reason, sorted scope, sorted basis, identity tiers, authority head, legacyEvidenceDigest?)`. The v8 tombstone signature (`TS:48-65`) covers none of reason, scope, basis, op identity or authority and is never authority.
- **DEC-12 Late revocation.** A valid revocation with a lesser stamp than a purge reverses that purge's projection when it arrives, including **after a checkpoint** (all purge and authorization facts are retained, so this is a re-projection). `unauthorizedPurge(K, op)` is raised.
- **DEC-13 Legacy evidence** (a verified v8 signed tombstone) is a separate retained fact with its verification result and the adopter's trust decision (in the run record); it projects nothing by itself.

### 2.4 Identity components (slice b)

- **DEC-14 AO3-id-first components at component level.** Over non-`purged(explicit)` lineages, recomputed on every projection: (1) a lineage with two different ao3 ids is `identity.conflict` and alone; (2) **ID groups** = lineages sharing an ao3 id; two lineages with different ids that share a URL are `identity.urlMismatch` (separate); (3) a **URL-only** lineage attaches to an ID group iff its full URL evidence touches **exactly one** ID group; touching two or more ⇒ `identity.ambiguousUrl` (separate); (4) the **remaining unattached, unambiguous URL-only lineages** are grouped **transitively** by shared URL; conflicted and ambiguous lineages never bridge groups. Survivor = lowest canonical UUID in the component. Owner decision: automatic, with a diagnostic.
- **DEC-15 Mapping.** Every lineage keeps its own facts. A component's lifecycle: `live` if any member is `live`, else `deleted` if any is `deleted`, else `purged`. A content group = the greatest-stamp fact over members; identity = union. Work-scoped references store the **original key** and project through the current component of that key (after a purge or split, through whatever component holds it, or the key alone); sessions, favorites, watermarks and work-layer pronunciation entries stay visible for a purged key.

### 2.5 Membership epochs

- **DEC-16 Endpoints.** `(queue key, work key)`, grouped by `(queue, component of work)`. Saved for Later has the fixed key `queue:savedForLater`.
- **DEC-17 Epochs.** `add{epoch = opId}` starts an epoch; `remove{names epochs}` ends exactly those; presence = any epoch not removed, **after endpoint filtering**; concurrent initial adds are two live epochs.
- **DEC-18 Per-epoch maxima.** A fact naming `{a,b}` is stored for `(a, group)` and `(b, group)`; the greatest stamp per `(epoch, group)` is retained while its endpoint is missing, deleted or hidden; the projected group = greatest stamp over live epochs. Equal ranks order by `(rank, canonical work key)`.

### 2.6 Annotations

- **DEC-19 Sources.** Per source: add fact, latest note, **greatest-stamp nonempty note**, latest locator, latest color, latest content stamp, delete facts. Winner rank = the greatest stamp over all content facts.
- **DEC-20 Delete scope.** A user delete names the **observed group** of source ids and their add ops; it deletes exactly those sources.
- **DEC-21 Dedupe projection.** Candidates = non-deleted sources, same component, same kind, same **non-blank exact** locator (blank/whitespace-only never dedupe, holding even when MC-8 is off). Winner = greatest rank. Effective winner note = winner's latest note; if empty, the greatest-stamp nonempty note among the losers' greatest nonempty notes. A loser **parks** its greatest nonempty note iff it differs from the effective winner note; sibling id = `UUIDv5(NS, UTF-8(lower(sourceId) 0x1F canonOpId(noteVersion)))`, `NS = 6c1f3b7e-6f1a-4a6e-9d34-0a3b8b0e5c11`, `canonOpId = lower(libraryID)/lower(incarnation)/decimal(seq)`. An explicit clear does not suppress older text for fallback or parking. No tombstone, no alias op.
- **DEC-22** Edits name their **source id**; an edit to a loser may change winner, fallback or parked set.

### 2.7 Assets

- **DEC-23 Valid edges first.** `asset.write{owner lineage, kind, digest, size, observedBase}`. A write is **valid** iff its base is null, or the base exists, has the **same owner and kind**, and is itself valid. **Only a valid write can supersede its base**; an invalid write (and any write whose base is invalid) is retained, not projected and diagnosed `invalidReference`. A version is superseded if a valid write has it in its base chain. Heads of a lineage = valid, unsuperseded, unremoved versions. A component's winner = greatest-stamp head over its members; alternates = other heads (`assetConflict`). After a split each lineage keeps its own heads. A same-digest write advances the winner.
- **DEC-24 Removal ≠ eviction.** `asset.remove{names}` (named versions are prerequisites) is a **logical** removal: it hides the named versions and keeps the supersession they established (for `v1 → v2`, removing `v2` leaves no reference). A removed **valid** base remains usable as a base. A removal is a retained fact, never a deletion of bytes: **file eviction is device-local and separate**, and when a projection makes a reference logically present again (for example after the removal is superseded by a new write) normal materialization recovers its bytes from the blob pool.
- **DEC-25 Bundles, chapter data, pending.** `original` + `conversionRecord` = one bundle fact, set-once (lowest stamp current, others alternates). Chapter data is a register keyed `(K, group, forDigest)`; the projection selects the greatest-stamp fact at the **winning** digest across the component's members, else none. `available` is device-local after size/digest verification and recoverable install; the verified previous file stays readable until the new one is installed.
- **DEC-26 Fonts.** A font = the live (unremoved) adds sharing digest and case-folded name; its display spelling is the spelling of its **lowest-stamp live add**; it ranks by its **greatest live add stamp**. Fonts are processed in the **total order** `(folded literal name, rank stamp, digest)`; every literal folded name is reserved first; in each name group the first keeps its literal spelling and each later one takes `-restored-k` with the smallest `k ≥ 1` whose folded name is unreserved, **reserving each generated name as it is assigned**. `font.remove` names every add id its device observed (prerequisites); the font stays while any add is live.

### 2.8 Registers, absence, reset, ties

| Register kind | Selection | Reset | Used for |
|---|---|---|---|
| LWW | greatest stamp | `null` fact with its own stamp | flags, text, progress, colour, pin, rank, note, locator, color |
| Set-once | lowest stamp, others exposed as alternates | none | provenance, originals |
| Grow-only set | union | none | tag lists, monotonic flags (OR) |
| Max-rank | greatest by comparator | none | preservation status, `seriesPosition`, dates |
| Value-ordered | greatest by comparator, then canonical bytes | none | cover pin (`KB:6400-6414`) |
| Epoch-scoped | §2.5 | remove names epochs | membership groups, user tags, queue tags |
| Observed-epoch record | payload of the greatest-stamp live put | `delete` names put epochs | **S1/S2 sessions, F1/F2 favorites and watermarks, L1 searches/bookmarks/followed tags/aliases** (DEC-28) |
| Entry presence | per `(key, entry)` LWW with retained resets | reset fact | settings maps, pronunciations |

Stamps are unique so max/min never tie; value-ordered registers tie-break on canonical bytes. **DEC-27** absent = no effect; `null` = reset; malformed values are dropped with a diagnostic, never read as reset (`KB:2740-2780`); unknown groups and ops pass through opaque. **DEC-28** Immediate-delete classes use the **observed-epoch record reducer** everywhere (the F1/F2 "stamped clear" is a `delete` naming observed put epochs, not an LWW tombstone): a clear is not newer-wins against a concurrent put it did not observe. **DEC-29** Date normalization and the fixed operation clock are legacy-adapter concerns (§4).

### 2.9 Diagnostics

Structured records `{kind, key, witness?, detail?}` sorted by `(kind, key, witness, detail)`. Computed from retained entries, never from arrival order or discarded op ids.

| kind | key | witness | detail | qualifies when |
|---|---|---|---|---|
| `invalidCommand` | op id | the op | `restore` or `purge` | empty scope/names/basis, or a name that is not a deletion |
| `invalidReference` | lineage (or asset owner) | the op | `restore`, `purge` or `asset` | per-lineage empty `names_K`/`basis_K`; asset base invalid |
| `unauthorizedPurge` | lineage | the purge | — | author not authorized at its stamp or head invalid |
| `restoreAfterExplicitPurge` | lineage | greatest-stamp valid restore | — | explicit purge in effect |
| `editToPurgedLineage` / `assetToPurgedLineage` | lineage | greatest content / asset fact | — | explicit purge in effect |
| `expiryInvalidated` | lineage | the expiry | `restored` if `basis_K` meets a cleared deletion, else `unseenDeletion` (**restored takes precedence**) | `basis_K ≠ U_K` |
| `restoredAfterExpiry` / `offlineRestoreDefeatedExpiry` | lineage | the greatest-stamp valid restore naming a `basis_K` deletion whose `observedExpiry` contains the expiry (else the greatest naming restore) | the expiry op | basis meets a cleared deletion |
| `survivingDuplicate` | the live member | greatest-stamp deletion of a deleted member | — | component live while another member is deleted/purged |
| `supersedesIneligible` | the new lineage | the named purge | — | DEC-8 |
| `assetConflict` | owner | winning version | the other heads | more than one head |
| `identity.conflict` / `identity.urlMismatch` / `identity.ambiguousUrl` | lineage / `a+b` / lineage | — | touched groups (ambiguous) | DEC-14 |
| `sessionIdCollision` | session id | the later op | — | same id from two writers |

## 3. The matrix

Columns follow plan § D4: (1) command and capture intent; (2) target identity and lineage; (3) value group; (4) absence/null/reset; (5) prerequisites (named op ids or `fact-first`, §2.1); (6) concurrent outcome and tie-break; (7) stale/duplicate; (8) checkpoint state (`S(K)` parts of §2.1).
"Stale/duplicate" states the *projection* result; nothing is discarded. A duplicate op id is an idempotent no-op on the fact set. `scope` is the set of lineage ids captured with a command (DEC-4).

### 3.1 Work lifecycle, content and assets (slices a and c)

| Op | Command / capture intent | Target / lineage | Value group | Absence · null · reset | Prerequisite | Concurrent outcome · tie-break | Stale / duplicate | Checkpoint state |
|---|---|---|---|---|---|---|---|---|
| **W1 work.create** | Save/import/download with no identity match (`importEPUB` re-check, `INVARIANTS` Identity). One op initialises every group of §3.1b with a register fact each; may carry `supersedes` (DEC-8) | new lineage = op's entity key | all §3.1b groups + identity evidence | absent group = no fact | none; `supersedes` names a purge op (prerequisite) | identity match with another lineage → component (DEC-14) | duplicate op: no-op | create fact, evidence, registers |
| **W2 work.delete** | `PWS.softDelete` (`PWS:116`) on the **visible** work: capture the observed component's lineage ids as `scope` (also recorded as capture-only metadata, not a prerequisite). Today also a signed tombstone (`PS:435`). | each lineage in `scope`; `observedGen` provenance | lifecycle | none | none (fact-first on each lineage) | DEC-2: any uncleared valid `D` ⇒ deleted; deadline = latest `deletedAt` over all members (DEC-5); a member outside `scope` survives (diagnostic) | `D` after explicit purge: retained, projects nothing | uncleared `D` `{id, scope, deletedAt}`; cleared `{id, scope}` |
| **W3 work.restore** | Recently Deleted Restore (`PWS:175`); re-acquisition of a deleted work (DEC-8); Merge undo of parking (`KB:3470-3490`). `scope` = union of the named deletions' scopes; records `observedExpiry` | each lineage in `scope` with `names_K ≠ ∅` | lifecycle | none | **the named deletion ops** (nonempty; per-lineage `names_K`, DEC-1); a wrong-kind name is `invalidCommand` | clears exactly named `D`; restore after observing expiry and offline restore both effective (DEC-3); unnamed `D` stays effective | names a deletion outside the lineage: `invalidReference`, no effect; restore after explicit purge: retained, hidden | merged restore fact (union of names, latest op, observedExpiry) |
| **W4 work.purge(explicit)** | Delete Now / Delete Permanently (`WL:178`) on a Recently Deleted item; `scope` = the item's recorded scope; v9 envelope naming its authority head (DEC-10, DEC-11). **Legacy-evidence-only form** for MC-7: empty basis, evidence digest, fixed scope, authorized adopter, **no synthetic deletion** | `scope` | lifecycle | none | basis deletions (or legacy evidence digest) | terminal, wins any order; two explicit purges: greatest stamp is the displayed witness, both retained | unauthorized: retained, ignored, diagnostic; duplicate: no-op | all purge facts with authority evidence |
| **W4x work.purge(expired)** | Sweep after the deadline (`PWS:296`), emitter holds the full `U` of every member in scope | `scope` | lifecycle | none | nonempty basis deletions | valid only while `basis = U` (DEC-2.2); reactivates if `U` returns to the basis | invalid expiry: retained, `expiryInvalidated` | all purge facts |
| **W5 re-acquire** | Any acquisition with an identity match: matched `deleted`/`purged(expired)` ⇒ W3; matched only `purged(explicit)` ⇒ W1 with `supersedes` | per DEC-8 | lifecycle / asset | — | the named purge op | DEC-8 eligibility is against the named purge | purge later unauthorized ⇒ `supersedesIneligible` | the `supersedes` link |
| **W6 heldCopy** (local) | `WL:33-75` | — | `freedAt` | — | — | — | — | none |
| **W7 work.edit** | A user or refresh edit of one or more §3.1b groups (one fact per group) | lineage | one or more groups | absent no effect; `null` resets where §3.1b allows | none (fact-first) | per register kind (§2.8) | edit to purged lineage: retained, hidden, diagnostic `editToPurgedLineage(latest)` | per-group winner + greatest content fact |
| **W8 asset.write** | `replaceEPUB` (`RQS:1227`), user re-import, update refresh | `(owner lineage, kind)`; owner derived from the base | `asset.epub` etc. | — | its `observedBase` version (named; same owner and kind, DEC-23) | heads, alternates per lineage, winner by stamp; same-digest write advances the winner | duplicate digest, higher stamp: new fact; older stamp: kept (ancestry decides) | version facts incl. ancestry |
| **W9 asset.remove** | shared **logical** reference removal (not file eviction, DEC-24) | named versions' owner | asset version visibility | — | the named version ops | hides named versions, keeps their supersession; a removed valid base stays usable | remove of removed: no-op | removal facts |

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
| chapter data | chapterWordCountsJSON + wordUnitRaw | LWW register keyed `(lineage, group, forDigest)`; projected for the winning digest across the component (DEC-25) | none |
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
| **S1 session.append** | `ReadingSession` finalize (`ReadingSession.swift:9`); id is the key | session id | observed-epoch record: the put carries the full row; timing groups are **set-once** (lowest stamp, all facts kept) | old rows keep nil, never backfilled | none (fact-first) | same id from two writers ⇒ `sessionIdCollision` (repair); timing groups: lowest stamp current | duplicate: no-op | every put with payload and stamp; set-once facts |
| **S2 session.delete** | immediate-delete (`PS:530`) | session id | observed-epoch record (DEC-28) | — | the named put epochs | removes exactly the observed puts; a concurrent put survives | — | every put with payload and stamp, every delete |
| **F1 favorite.set/clear** | `PS:545` | `(kind, target)`; `.work` target = original work key | observed-epoch record `{displayName}` (DEC-28) | clear = `delete` naming the observed put epochs (**not** an LWW tombstone) | named put epochs for a clear | a clear does not defeat a put it did not observe; alias collapses keys by projection | — | every put with payload and stamp |
| **F2 watermark.set/clear** | `PS:558` | fandom name | observed-epoch record, atomic payload `{lastVisitedAt, newestWorkIDSeen, title}` | clear names observed put epochs | named put epochs | greatest-stamp live put | — | every put with payload and stamp |

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
| **FN1 font.add / FN2 font.remove** | `M:923` | font = live adds with equal digest and folded name (DEC-26) | asset version + display name | remove names every observed add id | **FN2: the named add ops** (prerequisites); FN1: blob for `available` only | DEC-26 total-order allocator | — | all adds and removals |
| **O1 original.set** | converted import original + sidecar | `(work lineage, original)` | bundle (DEC-25) | — | none | set-once, lowest stamp | — | all bundles |
| **L1a savedSearch** / **L1b bookmark** / **L1c followedTag** / **L1d tagAlias** put/delete | `PS:504-585`; natural keys: bookmark URL, followedTag `ao3TagID`, tagAlias `(normalized name, kind)`, savedSearch id | key | observed-epoch record (DEC-28); within a live put the payload is the whole record; seen ids / parentFandoms are grow-only sets | delete names observed put epochs; **re-add after delete = a new put epoch, live** | named put epochs | greatest-stamp live put; 20-tag follow cap resolved by earliest follow stamp, the rest retained not projected | — | every put with payload and stamp |
| **E1 writer.enroll/revoke** | pairing/revocation UI (`TombstoneTrustStore`); founders in bootstrap | subject key | authorization | — | the author's authority head: `root:<founder>` or an enroll op (prerequisite, signed) | stamp-order evaluation, founders never revoked, re-enroll allowed (DEC-10a) | — | all authorization facts |

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
| MC-8 | Blank/whitespace anchors never dedupe (an iOS-deduped annotation is **recovered by replaying the dedupe** from the retained local and incoming annotation lists); the v9 nonblank-anchor rule itself is DEC-21 and holds even when MC-8 is off | X-10 | both annotation lists | engineering |
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

**Run record, resumable across both save boundaries.** Two durable saves bracket a run, and a crash may fall on either side of each:

1. **Before acceptance resumes** the record is saved with: `runId`; route, shipped build id, trust set, `opClock`, `sourceManifestDigest`; the **immutable accepted output** (or immutable replay inputs sufficient to regenerate it byte for byte: original manifest fragment, local pre-merge fragment, presence bits of every top-level key); the **baseline** (applied cut + checkpoint id); the approved MC ids; and a **local mutation cursor** = the position in the durable **mutation journal** at baseline. The journal is an append-only, per-key record of every local lineage/endpoint/group change `(key, group, kind, local op or intent id)`; it survives checkpoint reduction, so a local write that later lost to a remote write, or was discarded by the merge summary, is still visible to the conflict check. Acceptance after a crash replays from this record; step 1 never re-runs against moved local state.
2. **At reservation**, in **one atomic save**: check the journal from the cursor for every lineage and endpoint the translation touches; persist each conflict outcome (`localEditWins` per op); then commit the **reserved op ids, exact canonical bytes** (or immutable inputs + a versioned encoder that must reproduce them) **and the staged blob references**. Publishing retries the same bytes (plan § C). A crash between the two saves resumes at step 2 with the same record.

**Multi-target operations** (a delete or restore with `scope` of several lineages, an annotation delete naming several sources, a membership op naming several epochs): every target is checked; **one conflicting target drops the whole command**, and the translation for that command is **reconstructed deterministically before reservation** from the current baseline (a smaller scope, re-observed epochs) — never after reservation, and never by editing reserved bytes.

**Stamps are assigned at reservation.** After reservation the claim is **limited to LWW ordering**: a local edit with a higher stamp wins a *last-writer-wins register*; it does **not** defeat an observed remove (an epoch removal names epochs, not stamps), and it does not change a set-once winner or an asset branch. Acceptance-to-reservation conflicts, by kind (the journal is the evidence):

| Kind | Conflict test | Result |
|---|---|---|
| scalar/LWW group | any journal entry on `(lineage, group)` after the cursor | drop that group's op, `localEditWins` |
| lifecycle | any local `D`, `R` or `P` on a scoped lineage after the cursor | drop the lifecycle op and reconstruct; a restore still names only baseline deletions |
| membership | any add/remove/move on the endpoint after the cursor, including a **removal or re-add of a named epoch** | drop the endpoint's ops and reconstruct |
| set-once / bundle | any local write to the same set-once key | drop (the translated fact would not change the winner) |
| asset | any local version fact or removal on `(lineage, kind)` after the cursor | drop W8/O1; the staged blob stays referenced by the run record |
| annotation | any local source fact, edit or delete on a named source after the cursor | drop the op |
| observed-epoch record | any local put or delete on the key after the cursor | drop the op |

The seed run is the same pipeline with an empty baseline. Unknown manifest keys are preserved verbatim as opaque facts.

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

All fixtures are JSON with `"schema": "kudos.sync-fixture/2"`, validated structurally by `docs/sync-fixtures/_schema.json` (draft-07; a fixture missing a required part fails: v8 needs `harness` and cases with `local`, `incoming` and `expected.ios`/`expected.android`; v9 needs universes with full `initial`, `authorization`, `ops`, every schedule family, `expected.state/appliedCut/pending/diagnostics`) and semantically by §5.3. Two kinds:

- **`v8-compat`**: today's results, derived by reading the code, **not executed**. `harness` supplies `opClock`, `trust`, `signatureValid`, `preserved`, `assetBytes` and an executable `clockSubstitution` (iOS `archivedDeletionState(now:)`, `clampedArchiveDate(now:)` and the resurrection test at `KB:5884-5887`; Android `restoredDeletionState` gains a `now` parameter, `BMap:98-107`, and `merge(now:)` is already injectable, `BMS:46`). `local`/`incoming` are manifest fragment specs built by `_v8-builder.json` (record defaults, deterministic ids, signing seeds and tombstone identity, deterministic EPUB bytes, wire-key map such as `locator` → `locatorString`). The string `"<absent>"` or `omitKeys` physically omits a key. Both platforms' results are stated for every case.
- **`v9-concurrency`**: `universes[]`; a universe is one valid operation set (a fixture never reuses a writer slot for different bytes; alternatives are separate universes).

### 5.2 Files

| File | Slice | Kind | Variants (round 4 additions in italics) |
|---|---|---|---|
| `a1-v8-softdelete-propagation.json` | a | v8 | executable clock hooks; older-deleted-record control |
| `a2-v8-recently-deleted-copy-new-device.json` | a | v8 (X-6) | signer seed and tombstone identity in the builder |
| `a3-v8-permanent-delete-holder.json` | a | v8 (N-1) | v9 outcome = MC-7 legacy-evidence-only purge, no deletion fact |
| `a4-v9-lifecycle.json` | a | v9 | 28 universes: edits across restore; competing restores; equal-max lists; explicit purge diagnosing the greatest edit; offline vs after-observing restore; expiry alone, unseen deletion, reissue, old-basis reactivation; command scope (unseen duplicate, all members, per-member deadline, restore scope, purge scope, administrative purge); *multi-lineage expiry with independent bases, then a new deletion on one lineage (intermediate projection asserted at the cut); purge scope missing a lineage's basis; wrong-kind reference; restore scope not covered; two restores with different expiry observations; cleared member plus unseen deletion (reason precedence); authority: late lower-stamp revocation after a checkpoint, greater-stamp revocation, re-enroll, founder not revocable* |
| `a5-v9-reacquire-after-purge.json` | a | v9 | `work.create` with `supersedes`; supersedes against the named (non-winning) purge across a checkpoint; unauthorized purge ⇒ ineligible; signed purge identity matches |
| `b1-v8-duplicate-identity.json`, `b1r-…-reverse.json` | b | v8 (X-4, N-3) | both directions with rank and provenance |
| `b2-v9-duplicate-identity.json` | b | v9 | no alias op; late loser edit across a checkpoint; salvage orders; delete scope both ways; lineage-only purge; component expiry/restore across a checkpoint; URL bridge with conflicting ids; URL-only attach |
| `b3-v8-annotation-anchors.json` | b | v8 (X-10, X-5) | blank, whitespace-only, Replace `[]` and absent |
| `c1-v8-asset-replace-vs-delete.json` | c | v8 (N-4, N-5) | correct receiver; installed digest vs record digest; preserved control |
| `c2-v9-asset-versions.json` | c | v9 | replace/delete/restore/purge; branches (assetConflict); same-digest successor; shared remove; write on removed base; foreign-owner base; chapter data per digest; bundle; fonts; *two heads with chapter data, checkpoint, then removal of the winner; invalid writes supersede nothing; logical removal vs eviction* |
| `c3-v9-pending-asset-reference.json` | c | v9 | four explicit orders with typed `{op}`/`{event}` entries, bad blob, restart/duplicate with the blob, prefix assertions |
| `d1-v9-membership-epochs.json` | ext. | v9 | creates for queue and works; old-epoch high-stamp move; per-epoch maxima; Saved for Later key; endpoint created last |
| `d2-v9-setting-entry-reset.json` | ext. | v9 | checkpoint after the winning reset; tie-break by incarnation |
| `e1-v8-replace-omission-absent-key.json` | ext. | v8 (X-5) | sessions linked to works, absent vs `[]` |
| `f1-v9-incomparable-cuts.json` | ext. | v9 | incomparable cuts: the local edit as an unreserved intent, and as already-reserved bytes replayed unchanged; `finalCut` corrected |
| `f2-v9-retention-equivalence.json` | ext. | v9 | one universe per retention rule, *plus* two concurrent puts with the winner deleted, favorite clear/re-add, session delete with grow-only tags, unknown op kind |

### 5.3 Semantic validation contract (what a harness checks before running)

1. Writer slots: per writer, `seq` is contiguous across `initial` then `ops`, `stamp = [counter, writer, seq]`, counters strictly increase per writer.
2. Prerequisites: `requires` lists only cross-writer named ops; every named op id in `observed` exists in the universe; the named op's counter is below the naming op's. `observed.gen` is provenance and is never validated.
3. Schedules: `allInterleavings` keeps same-writer order and is exhaustive; explicit `orders` list their count; every `checkpoints.cutAfter` and `thenOrder` name universe ops and are disjoint; `missingPrerequisite.expectedPendingAtEnd` is nonempty.
4. Retention: `project(retain(prefix) ⊕ suffix) = project(all)` for the normalized projection **and diagnostics**. Small universes (≤ 5 ops) are checked **exhaustively** (every permutation, every cut); larger ones by a seeded sample (seed 7, 40 orders, every cut). Each universe's `schedules.retentionEquivalence` records `mode`, `orders`, `cutsChecked` and `seed`. Checkpoint cuts must be causally closed, and `expectedAtCut` records the projection at the cut.
5. Normalization: expected states use symbolic keys from `ids`, derived ids as computed (`UUIDv5(NS, …)`), diagnostics as structured `{kind, key, witness?, detail?}` records sorted by those fields; `appliedCut` is the per-writer max seq (initial included); `pending` is empty for complete schedules.

## 6. Open questions

**Decided by the owner (2026-11-23, `docs/REDESIGN_DECISIONS.md`):** restore keeps concurrent edits (DEC-6); explicit permanent delete removes the item on every device, automatic 90-day cleanup loses to a restore (DEC-2, DEC-4, DEC-8); the latest deletion starts the 90-day window (DEC-5); AO3 id vs URL disagreements resolve automatically by the AO3-id-first rule with a diagnostic (DEC-14).

**Resolved by engineering decision:** lowest canonical UUID survivor (DEC-14); reclamation stays disabled and D8 sets any offline-writer bound; the shipped validator stays the v8 baseline and MC-1 is the opt-in v9 date rule; blank/zero handling stays a platform result in v8 and MC-2 is opt-in; omitted-key capture is mandatory for v9 (MC-4); a new incarnation sorts by its own id.

**Still open for the owner**
- **Q-8 (UI wording)** Confirmation text for Delete Now / empty Recently Deleted. *Recommend: "This also removes it from your other devices. This can't be undone." and, when another device holds a copy that an offline restore later names, a quiet note "deleted permanently on <device>".*
- **Q-10 (enrollment UX)** How a device becomes an authorized writer. *Recommend reusing the pairing flow: scanning an enrolled device's code emits `writer.enroll`; removing a device emits `writer.revoke` with the stolen/retired distinction already shown; semantics are DEC-9 to DEC-12.*
- **Q-13 (D8)** The numbers the retention contract (§7) leaves to D8: the offline-writer bound, restore-point retention, diagnostic history depth. *Recommend: offline bound ≥ the longest restore-point age so no retained restore point is orphaned; decide with D8's authority protocol.*

## 7. Retained state: growth and the retention contract (input to D8)

**Sizing scenario (illustrative, not a measurement, not a promise).** Model from the Codex review: 50,000 works, 20-35 current register facts per work, one identity row per work, 370k session/bookmark/annotation-source rows, 200k tag identities ⇒ **1.6-2.4 M rows** current state. Churn over a 30-year life (the review's counts taken as 30-year totals): two delete/restore cycles per work (+200k), ten EPUB versions per work (+500k), twenty note edits per annotation (+400k), 100k membership edges with three add/remove cycles (+600k) ⇒ **+1.7 M rows**, **3.3-4.1 M rows**, about **0.4-1.0 GB** at 120-250 bytes per row **before** indexes, text, WAL, staging, replication and restore-point costs, which must be measured. This is the unreclaimed scenario. **Half a TiB of EPUB history (50k × 10 × 1 MiB) is not an operating envelope**, and even one retained version per work is about 50 GiB. **No compacted figure is claimed:** the summaries that would shrink the rows are not yet justified (below). D7 therefore needs **explicit retained-object and byte budgets with backpressure and durable local edits** (plan § Budgets), and D8 must establish the supported envelope by **device measurements at the owner's 15k and 50k points**.

**Retention contract (inputs and constraints for D8).**
1. **No generic watermarks.** An acknowledged cut proves *application coverage*; a newly authored or reserved op can still name an older id. A cleared-deletion watermark cannot tell a deletion of A from an edit or a deletion of B; a removal watermark cannot tell a removed epoch from a live concurrent one; an asset supersession watermark cannot validate an arbitrary old base across branches. Until D8 proves that every supported writer, reserved op and restore point has stopped referencing them, the **exact typed ids are kept** (deletion ids by lineage, epoch ids by endpoint, version ids by `(owner, kind)`, purge/authorization facts).
2. **Reference fence.** Pruning typed evidence requires an explicit **fenced** transition: the membership/authority epoch that names who must acknowledge, a cut acknowledged by all of them, no reserved or unpublished op naming the id, and no retained restore point that needs it. A name that was pruned is **never** dropped from a command and replayed automatically (that silently changes a restore's scope or a write's branch); the op is rejected as `staleReference` and its author re-observes.
3. **Retirement is a fenced transition, not a timeout.** A device is retired by an explicit authority-epoch change; its rejoin is bootstrap plus a documented outcome **per intent class**: unreserved intents are re-evaluated against the merged state; reserved unpublished bytes that name only retained evidence replay unchanged; reserved bytes that name pruned evidence are rejected (`staleReference`) and re-authored; edits to LWW groups are re-evaluated; epoch operations re-observe their epochs.
4. **Restore points** protect their required closure and **cap** pruning of every fact that closure needs (the stable cut for those facts cannot advance past the oldest retained restore point that needs them).
5. **Never summarized before a separately reviewed finality rule:** purge facts and witnesses, `writer.enroll/revoke` facts, identity evidence referenced by a purge witness or `supersedes` (late revocation re-projects, DEC-12).
6. **Diagnostics** report `(kind, key, witness)`, and the witness is reconstructible from retained entries (§2.1), so diagnostics need no discarded op ids.
7. **Bounded work.** Checkpoints are built by streaming per original key from an indexed store; apply and component splits run in bounded batches; nothing needs the whole retained set in memory.
8. **Checkpoint invariant.** `project(S_C ⊕ X)` must equal the full replay in the **normalized projection, diagnostics, applied cut and pending behavior**, under every supported suffix; the installed cut must be **causally closed**; a coverage vector may release a dependency wait, but the retained evidence must still establish the dependency's kind, owner and validity; state, cut and logical clock are persisted atomically with apply and prefix advancement; fact-first and reversibly hidden keys are included.

## 8. Plan text

**Landed in plan v3.2** (previously listed here): lineage-keyed asset reference with generation as provenance; restores reference observed deletions; component-scoped deletes; per-key checkpoint retention; AO3-id-first component survivor.

**Must change again (round 4):**
- § C Checkpoints: replace "retains … deletion evidence" with the exhaustive per-reducer table of §2.1 (chapter data keyed by forDigest, per-put payloads for observed-epoch records, restore evidence keyed by deletion, purge/authorization facts, opaque facts) and add the **checkpoint invariant** of §7.8 (projection, diagnostics, applied cut, pending behaviour; causal closure; atomic state+cut+clock).
- § C Causality: a coverage vector may release a wait, but the checkpoint must also establish the dependency's kind, owner and validity.
- § C / D8 retirement: "retired under an explicit rule" → a **fenced transition** with a named authority epoch and a per-intent-class rejoin outcome (§7.3); "documented rebase" must not drop or rewrite named references.
- § D lifecycle: expiry is evaluated **independently per lineage** against `basis_K = U_K`; commands carry per-lineage evidence and malformed commands are `invalidCommand`.
- § D authority: purge, enroll and revoke each name their authority head (signed); authorization is evaluated in stamp order; founders are not revocable; re-enroll is allowed.
- § D memberships and records: observed-epoch records (sessions, favorites, watermarks, saved searches, bookmarks, followed tags, aliases) and per-epoch maxima for membership groups.
- § Budgets: D7 retained-object and byte budgets with backpressure; the 15k/50k envelope is established by device measurement (D8), not by the sizing scenario of §7.
