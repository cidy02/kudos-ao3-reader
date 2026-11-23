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
| EPUB asset | `Works/<UUID>.epub`, rewritten in place every sync-up when bytes differ (`FS:1003`); read side: size then digest (`FS:837-854`); install gated by `mayReplaceEPUB` (`KB:6116-6130`) with metadata clock as freshness proxy | same (`SR:867-873`, `BMS:2775-2797`) | no |
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
- **X-12** Android renames duplicate collection/saved-search names on insert; iOS keeps the incoming name (`KB:4271`).
- **X-16** Original publication compares size only on Android.
- **X-21** Android reads `Instant.now()` inside merge helpers (`BMap:103`); iOS reads `Date()` in `clampedArchiveDate`, `archivedDeletionState`, `parkDisplacedNote` and Replace omission (`KB:558`, `6150`, `5590`, `4666`). Neither has a fixed operation clock.
- **N-1** A permanent delete never reaches a device that still holds the work: no pass applies `savedWork`, collection or queue tombstones to existing local rows (only memberships, annotations, searches, bookmarks, sessions, favorites, watermarks do: `KB:4256`, `4356`, `4428`, `4875`, `5055`, `5141`; Android `BMS:2626`). The deleting device only stops the work coming back.
- **N-2** Parked-note siblings and same-passage losers get random ids, so two devices deduping the same pair mint different rows.
- **N-3** No survivor convergence for duplicate identity: each device keeps its own UUID and re-homes the other's (`KB:3469`, `WII:39-53` last-indexed-wins), so the manifest ping-pongs ids.
- **N-4** A late edit revives a deleted work: any record with a newer `lastModifiedAt` carries `isPendingDeletion=false`, and `incomingWins` assigns it (`KB:6282-6291`).
- **N-5** Metadata clock stands in for asset freshness (`KB:6100-6115`): a restore of an older book re-stamps the work and replaces newer bytes on the next sync; `Works/<UUID>.epub` is rewritten in place by whichever device syncs up last (`FS:1003`, `SR:565-580`).

## 2. v9 conventions (decisions this matrix rests on)

### 2.1 Lifecycle, generations, purge (slice a)

- **DEC-1 Lifecycle is its own atomic value group** `{state ∈ live|deleted|purged, generation, deleteOpIds, deletedAt, deadline}`. Content groups (metadata, progress, flags, asset reference) are separate groups with their own stamps. Today one record clock and one flag carry both (N-4), so a late edit revives a deleted work.
- **DEC-2 Delete wins over ordinary edits, without discarding them.** `delete(g)` fixes lifecycle at `deleted` for generation `g`; a concurrent or later content op addressed to `g` is applied to the retained record but cannot change lifecycle. Restore therefore returns the work with those edits. Only purge discards content. (Reading of plan § D "a delete targets an entity generation and wins over ordinary concurrent edits to it"; Q-1.)
- **DEC-3 Restore references deletions and names the next generation.** `restore` lists the deletion op ids it observed; its generation id is a pure function of that sorted list, so two devices restoring the same deletion mint the same generation and converge. A deletion of `g` not in the list (concurrent) becomes stale: it targets a superseded generation and has no effect, whichever order the ops arrive in.
- **DEC-4 Purge is terminal for the lineage** (`g` and every generation derived from it by restore). Two reasons: `explicit` (user's Delete Permanently) beats a concurrent restore; `expired` (90-day sweep) loses to a concurrent restore, because an offline device's automatic expiry must not destroy a restore made elsewhere. A purge needs the deletion op it observed as prerequisite (v8 guard: `PWS:deletePermanently` only acts on a pending record). A purge keeps a **purge witness**: identity tiers, generation, `reason`, and the existing Ed25519 signature over the unchanged tombstone payload (`TS:48-65`) by a trusted signer; checkpoints retain it. Unknown or untrusted signer: witness kept, purge not applied, counted `unknownSigner` (matches `KB:3380-3395`). An `expired` purge releases the local file but keeps journal and blobs (reclamation is disabled in D7), so a later concurrent restore can re-materialise (Q-2).
- **DEC-5 Deadline.** `deadline = max(deletedAt payload over effective deletions of g) + 90 days`. Both are payload; apply eligibility never depends on receiver time (plan § C). Each device's sweep reads the deadline and emits `expired` purges; duplicates are idempotent. A device never copies a remote schedule over its own countdown the way v8 forbids (`KB:6130-6164`).
- **DEC-6 Held copy is device-local.** The 60-day finished/un-kept hold (`WL:17,33-75`, `freedAt`) and "free EPUB" never become ops. Restoring a held copy is an ordinary `isSaved` edit; freeing bytes is an eviction (plan § C Assets, "Ordinary download eviction is device-local").
- **DEC-7 Re-acquisition.** Matching an entity in `deleted` state → `restore` (v8 invariant "Re-acquiring revives", `DATA_AND_PERSISTENCE_INVARIANTS.md` Identity). Matching only a purged lineage → new entity, generation `g0`, `supersedes = purge witness id`; purged lineages never take part in alias matching, but their witness rejects stale ops addressed to the old lineage.

### 2.2 Identity and aliases (slice b)

- **DEC-8 Tiers unchanged:** AO3 work id → canonical AO3 URL → entity key (`WII:39-53`, Android `works/WorkIdentityIndex.kt:96-111`). When tier 1 and tier 2 name different live entities the adapter keeps the v8 outcome (tier 1) but v9-native alias ops are **not** emitted; a diagnostic `identity.ambiguous` is recorded (Q-3).
- **DEC-9 Deterministic survivor** = the entity with the lowest canonical (lowercase, hyphenated) UUID among those matched by tiers 1-2. `work.alias{loser→survivor}` has content fully determined by the pair, so concurrent detection on two devices is idempotent. Prerequisites: both create ops. Aliases are durable and retained in checkpoints; ops addressed to a loser are redirected to the survivor on apply (late ops to aliases).
- **DEC-10 Re-keying.** Memberships re-key by `(queueKey, survivor)`; annotations, sessions, `.work` favorites and asset references re-key their work reference; stamps of the re-keyed ops are kept, never regenerated.
- **DEC-11 Annotation dedupe.** After deleted rows are excluded, rows sharing `(survivor work, kind, exact non-blank locator)` collapse: winner = greatest stamp of the row's latest content op. Blank locators never dedupe (X-10 resolved toward Android). The loser records `annotation.dedupeAlias{loser→winner}`; this is **not** a deletion tombstone, so deleting the winner later does not resurrect or double-delete, and ops to the loser re-key to the winner. Non-empty differing loser note: winner empty → fill; else park on a hidden sibling whose id is `UUIDv5(ns, loserId ‖ sha256(note))` (fixes N-2).

### 2.3 Assets (slice c)

- **DEC-12 Asset reference** is a value group `asset.<kind>` on `(owner generation, asset kind) → {digest, size, baseDigest}`; kinds: `epub`, `original`, `conversionRecord`, `font:<file>`. LWW by stamp. The older-stamp digest is retained as `alternate` (its blob stays in the pool) and a diagnostic `assetConflict` is raised; bytes are never silently dropped.
- **DEC-13 Pending references.** The metadata op applies immediately; the reference is `pending` until the blob is visible, size and digest verified, and the install is recoverable; `available` is device-local state (never synced). Only D5-defined atomic groups wait for bytes (plan § C).
- **DEC-14 Asset ops follow DEC-2:** an asset replace addressed to a deleted generation updates the retained record; to a purged lineage it is stale (blob kept, reference not recorded).
- **DEC-15 Freshness is the reference's own stamp, not the metadata clock** (resolves N-5). A restore never re-stamps an asset reference it did not change. `original`/`conversionRecord` keep the v8 set-once rule: first stamp wins, a later different digest becomes `alternate` (X-16).

### 2.4 Absence, null, reset, clocks

- **DEC-16 Absence/null/reset.** Group absent = no effect. Explicit `null` = reset with its own stamp. Entry-level (settings maps, pronunciations) presence is per entry: `set(entry, value)` and `reset(entry)` each carry a stamp; the reset is retained (checkpoint) so a stale `set` cannot revive it. Malformed group values are dropped with a diagnostic and never treated as a reset (`KB:2740-2780`, `malformedNamed`). Unknown groups/ops pass through opaque and are re-emitted unchanged (Android overlay behaviour `SMP:194-242` becomes the rule on both platforms).
- **DEC-17 Fixed operation clock.** A legacy adapter run takes one instant `opClock`, persisted in its run record, replacing every `Date()`/`Instant.now()` in the legacy rules (X-21). Date normalization: `norm(d) = min(d, E)` with `E = min(manifest.exportedAt, opClock + 24h)`; a future date is clamped, never rejected and never turned into "no clock" (X-1 resolved toward iOS clamping plus Android's exportedAt cap, which only affects forged records). Normalized dates are payload only.

## 3. The matrix

Columns follow plan § D4: (1) command and capture intent; (2) target identity and generation; (3) value group; (4) absence/null/reset; (5) prerequisites; (6) concurrent outcome and tie-break; (7) stale/duplicate; (8) checkpoint state for replay. "Greater" always means greater stamp. "Same" means deterministic from the same op set regardless of arrival order.

### 3.1 Slice (a): work lifecycle

| Op | Command / capture intent | Target / gen | Value group | Absence · null · reset | Prerequisite | Concurrent outcome · tie-break | Stale / duplicate | Checkpoint state |
|---|---|---|---|---|---|---|---|---|
| **W1 work.create** | User saves/imports/downloads a work with no identity match (`importEPUB` re-check after download, `INVARIANTS` Identity). Captured with all value groups present at birth in one op. | new entity key; gen `g0` = op id | all groups; lifecycle `live` | absent group = default; no resets | none | Two creates with same tier-1/2 identity → slice (b) alias; same key twice impossible | duplicate delivery: no-op (same op id) | entity key, identity tiers, `g0`, all group stamps |
| **W2 work.softDelete** | `PreservedWorkService.softDelete` (`PWS:116`): lifecycle→deleted, `deletedAt`, EPUB kept, memberships stay attached. Today also writes a signed tombstone (`PS:435`); v9 op carries the same signature as witness. | entity, current gen `g` | lifecycle | none | none (same-writer prefix) | vs content ops: DEC-2 (delete holds, edits retained). vs delete: both effective; deadline per DEC-5. vs restore: DEC-3 | to purged lineage: stale; to superseded gen: stale (diagnostic `staleGeneration`) | lifecycle group, deleteOpIds, `deletedAt`, witness signature |
| **W3 work.restore** | `PWS.restore` (`PWS:175`), "Recently Deleted → Restore", also re-acquisition (DEC-7) and Merge undo of Replace parking (`KB:3470-3490`). v8 deletes the tombstone; v9 references the deletion. | entity, new gen `r(deleteOpIds)` | lifecycle | none | **explicit: every deletion op id it lists** (cross-writer) | vs concurrent delete of `g`: restore wins (DEC-3). vs explicit purge: purge wins. vs expired purge: restore wins. vs restore with same list: same gen, idempotent. vs restore with other list: two gens; the one referencing the greater deletion stamp wins | list names a deletion already superseded or purged: stale/no-op, surfaced to user as "deleted elsewhere" | gens, deleteOpIds seen per gen (a checkpoint at/after the deletion keeps this evidence) |
| **W4 work.purge** | Delete Permanently / `WL.hardDelete` (`WL:178`): record, EPUB, reader cache, original, annotations removed; signed permanent tombstone (`PS:419`, `PS:435-448`). Reason `explicit` or `expired` (sweep, `PWS:296`). | lineage of `g` | lifecycle → purged | none | the deletion op id it observed | explicit > restore; expired < restore (DEC-4); two purges merge (explicit if either explicit) | to purged: no-op. Content ops to purged lineage: stale, counted | purge witness (identity, gen, reason, signature, signer), deletion evidence, never dropped before D8 retention |
| **W5 work.acquire (re-acquire)** | Any acquisition (save, import, queue add, download) with a tier match (`importEPUB`; invariant "Re-acquiring revives") | matched entity, or new `g0` with `supersedes` | lifecycle (+ asset) | none | purge op id only when it created over a purged lineage and has applied it | two devices re-acquire the same purged identity independently → two new entities → alias (slice b) | acquiring a live entity: asset/metadata ops only | purge witness `supersedes` link |
| **W6 work.heldCopy** (device-local, no op) | `holdFinishedCopy`/`sweepHeldCopies` (`WL:33-75`) | — | `freedAt` excluded from backup | — | — | — | — | none |
| **W7 asset.replace** (slice c) | Re-download of an updated work, user re-import, `replaceEPUB` (`RQS:1227`); captured with new digest and `baseDigest` | `(gen, epub)` | `asset.epub` | absent = unchanged | blob visibility for `available` only (DEC-13) | greater stamp wins reference; loser digest → `alternate`; concurrent with delete: DEC-14; with restore: new gen inherits current reference; with purge: stale | same digest twice: no-op; lower stamp than current: recorded as alternate only | per-asset ref + alternates + digest; blobs retained (reclaim off) |

Slice (c) outcomes beyond the table are exercised in `docs/sync-fixtures/c-*.json`.

### 3.2 Slice (b): duplicate identity, memberships, annotations

| Op | Command / capture intent | Target / gen | Value group | Absence · null · reset | Prerequisite | Concurrent outcome · tie-break | Stale / duplicate | Checkpoint state |
|---|---|---|---|---|---|---|---|---|
| **I1 work.alias** | Emitted by any device that has applied two creates matching on tier 1/2 (DEC-8/9). v8 equivalent: `existingWork(for:)` re-homing (`KB:3469`, `WII:39-53`) | pair `(loser, survivor=min UUID)` | alias table | none | both create op ids | emitted by both devices with identical content → idempotent. Three entities → pairwise to min; transitive | loser already aliased elsewhere: re-point to min of the set | alias table; re-keyed memberships/annotations/favorites/sessions/assets |
| **M1 queue.membership.add / remove** | `ReadingQueueService` add/remove (`RQS`, `PS:476`); keyed **canonical endpoints** `(queueKey, workSurvivorKey)`, not membership UUID (fixes X-4) | key `(queue, work)`; membership gen starts at add | presence (add/remove) | remove = tombstone-with-stamp; absent = no effect | queue key and work key exist or are pending | add vs remove: greater stamp; add after remove re-adds (new presence epoch, rank/note reset to the add's values) | remove of absent key: recorded (stale-add guard) | presence + stamp per key, retained removal |
| **M2 queue.membership.move** | Reorder (`RQS:1270` index arithmetic) → emits one `rank` op per moved member | key | `rank` | absent = unchanged | presence | greater stamp wins; equal ranks across different members: order by `(rank, canonical work key)`; rebalance (renumbering) emitted as ordinary rank ops with fresh stamps, so a pending older move loses to it | move on a removed key: stale, never revives | rank per key |
| **M3 queue.membership.note/state/origin** | note, state(new/inLine), origin | key | `note`; `state`; `origin` (three groups) | note `""` is a value; absent unchanged; origin null = reset | presence | LWW per group | — | per group |
| **M4 collection.membership.add/remove** | collection edit (`PS:602`) | `(collection, work)` | presence | tombstone-with-stamp | collection, work | greater stamp; add after remove re-adds | — | presence per key; collection order `workOrderRaw` is a separate group on the collection |
| **A1 annotation.add** | In-book bookmark/highlight/note | annotation id, gen `g0` | content (kind, color, locator, selectedText, note, progression, spine, chapterTitle) | `note ""` is a value | work key | same-passage rows → DEC-11 | duplicate id: no-op | content stamps, dedupeAlias |
| **A2 annotation.edit** | note/color edit | annotation id | `note`, `color` (two groups) | absent unchanged | A1 (same writer or pending) | LWW by group; a differing non-empty displaced note is parked (DEC-11) | edit to dedupe loser: re-keyed | — |
| **A3 annotation.delete** | delete (`WL:178` cascades; single delete mints `.readingAnnotation` tombstone, `PS:489`) | id | lifecycle (immediate-delete class: no Recently Deleted) | none | none | vs edit: delete holds, edit retained and invisible; vs same-passage dedupe: dedupe applies after deleted rows are excluded (v8 audit A27-3) | edit to deleted: stale | tombstone with stamp |
| **S1 session.append** | `ReadingSession` finalized (`ReadingSession.swift:9`) | session id | full row (atomic) | old rows keep nil facts; never backfilled (`INVARIANTS` Never lose) | work key (re-keyed on alias) | no conflict (immutable once final); a later `chapterTiming` fill is fill-only | duplicate: no-op | row digest |
| **S2 session.delete** | immediate-delete class (`PS:530`) | id | lifecycle | none | none | delete beats fill | — | tombstone |
| **F1 favorite.set / clear** | ReadingFavorite star/unstar (`PS:545`) | `(kind, target)`; `.work` target = survivor key | presence + displayName | clear is a stamp | none | greater stamp; displayName LWW; alias collapses two rows to one key | — | presence per key |
| **F2 watermark.set / clear** | `FandomReadWatermark` (`PS:558`) | fandom name | `{lastVisitedAt, newestWorkIDSeen, title}` atomic | clear stamp | none | greater stamp (not max-of-date) | — | per name |

### 3.3 Settings, tags, collections/queues, recovery, fonts, originals

| Op | Command / capture intent | Target / gen | Value group | Absence · null · reset | Prerequisite | Concurrent outcome · tie-break | Stale / duplicate | Checkpoint state |
|---|---|---|---|---|---|---|---|---|
| **P1 setting.set / reset** | A named or extras setting changes (`SSC.noteLocalChanges`, `KB:2628`). Explicit stamps only: an inferred (export-time) stamp is never created in v9 | setting key | one group per key; voice id + name pair is one group; hue+hex one group | absent = unchanged; `reset` = own stamp; malformed ignored | none | greater stamp; legacy inferred-vs-real rule applies only inside the adapter | — | value or reset stamp per key (reset retained) |
| **P2 setting.entry.set / reset** | Map settings (comment drafts, Posting As) | `(key, entry)` | entry | reset stamp per entry | none | per entry greater stamp | — | per-entry stamp incl. resets |
| **P3 pronunciation.set / reset** | Correction edit (`KB:853-935`) | `(layer, word)` layers global/fandom/work | `ipa` | reset stamp | none | greater stamp; removal beats older set | — | per-entry stamp incl. resets |
| **T1 tag.attach / detach** | User tag on a work (`Tag.name` unique, case sensitive, `M:887`) | `(work, tagName)` | presence | detach stamp | work key | greater stamp. v8 has no per-tag tombstone (union only, `KB:3563`): v9 adds presence stamps; adapter never infers detach from absence | — | presence per pair |
| **T2 queue.tags / collection fields** | queue tags, colour, pin, offline, notes, name, description, sortOrder | queue/collection key | one op group each: `name`, `colour{hue,hex}`, `pin`, `offline`, `notes`, `smartRules`, `order` | colour: hue null never clears; others reset by explicit null | none | greater stamp per group | — | per group |
| **Q1 queue/collection.create/softDelete/restore/purge** | same lifecycle rules as W1-W4 with generations; memberships stay attached | key + gen | lifecycle | — | restore → deletion ids | as DEC-1..5; Saved for Later is matched by kind, never deleted, never aliased by id (`BMS:1700`, `KB:3950`) | — | as W2-W4 |
| **R1 recoveryDoc.put** | writing recovery copy / `documents` file (`BackupAppState.swift:25-140`) | file name | file content ref | never removed | none | greater stamp of the same session wins; nothing removed | — | ref per name |
| **FN1 font.add / remove** | custom font (`M:923`) | file name (folded case) | asset ref `font:<file>` + display name | remove stamp | blob | greater stamp; case-folded name collision → `-restored-N` suffix is deterministic from op order | — | ref per name |
| **O1 original.set** | converted import original + conversion record | `(work gen, original)` | asset refs (set-once, DEC-15) | — | work key | first stamp wins, later differing digest = alternate | — | refs + alternates |
| **L1 savedSearch / bookmark / followedTag / tagAlias** | immediate-delete class (`PS:504-585`) | id (bookmark by URL; followedTag also by `ao3TagID`; alias by natural key) | content groups | delete stamp | none | greater stamp; 20-tag follow cap resolved by earliest follow stamp among survivors (deterministic) | — | per id; tombstone with stamp |

Smart (derived) memberships are never ops (`INVARIANTS` Queues): the adapter skips memberships for `kind=smart`, as `KB:4194-4203` does.

## 4. Legacy route table and adapters

A **legacy adapter** reads a v8 manifest (and its assets) through today's rule set and produces v9 operations. Routes: **Merge** (file import, add-only), **Reconcile** (folder sync-down, conflict-version folds, the pre-2026 package fold; default mode), **Replace** (file import, snapshot), **v8 folder import** (the seed of the v9 library and the explicit reviewed import of post-handoff v8 edits, plan § C Namespace and cutover). Both platforms expose the same three modes (`KB:3086`, `BM`-side `KudosBackup.kt:59-75`); folder sync-down is Reconcile on both (`FS:371`, `SR:784`).

### 4.1 Adapter contract

1. **Run record** (durable, one per adapter run): `{route, platform rule set, sourceManifestDigest, opClock, status ∈ planned|accepted|published}`. `opClock` is fixed at creation (DEC-17). Retry after interruption reuses the record and the same accepted result; it never re-runs the rules against a moved local state.
2. **Accepted result** = the post-merge normalized state the v8 rules would produce, computed by the rules of §4.2 against the local v9 state at run start, with `opClock` substituted for every wall read. It is stored with the run record before any op is minted (so retries mint the same ops).
3. **Translation** (never fabricated history): for each entity and each value group where accepted ≠ local, emit one op `*.legacyAdopt` carrying the group's accepted value, `origin = {route, sourceManifestDigest}` and, as payload only, the normalized legacy record date. Its stamp is an ordinary new stamp minted by the importing writer after the adapter commits; per-field stamps are **not** reconstructed from the record's `lastModifiedAt`. Groups where accepted = local emit nothing (a stale archive overrides nothing).
4. **Lifecycle:** accepted deletion state → `softDelete` with `deletedAt` from the archive record (payload), never a schedule copied from the file; accepted restore (Merge undo of Replace parking, retraction) → `restore` referencing the deletion op if known, else a `restore` against the adapter-created deletion. Accepted tombstone adoption → `purge` only for a permanent-reason tombstone from a trusted signer whose lineage the local state holds; every adopted tombstone also stores its witness.
5. **Replace omissions** become explicit ops (§4.4); **absent is not empty**: a key the archive does not carry yields no op for that collection on either platform's v9 adapter, closing X-5.
6. **Seed run** (v8 → v9 library creation) is the same adapter with local state empty: creates, group values, aliases (by tiers), tombstone witnesses, opaque unknown keys preserved verbatim (Android overlay rule becomes universal).

### 4.2 Tie and normalization rules per route (what the adapter must reproduce)

| Rule | iOS (cite) | Android (cite) | Adapter rule |
|---|---|---|---|
| Record wins | `incoming >= local` (`PS:668-672`): ties go to incoming | `!incoming.isBefore(local)` (`BMS:2538-2542`) same | `>=` as both; missing incoming clock = lose |
| Missing record clock | `lastModifiedAt ?? dateAdded` (`KB:6196`) | `lastModifiedAt` blank → `dateAdded`; present-but-future → null (loses) (`BMS:2375-2385`) | fall back to `dateAdded`; future date clamps (DEC-17), never null |
| Future date | clamp to `now+24h` (`KB:554-577`) | reject > now+24h; cap at `exportedAt` (`BV:181-201`) | `min(d, min(exportedAt, opClock+24h))` (X-1) |
| New record | adopts archive values and clock (`KB:3555-3560`, `6425-6431`) | same (`BMS:206-210`) | same |
| Fill-only | text/counters: blank/≤0 incoming never overwrites (`KB:6417-6426`); `ao3WorkID`, `authorIdentitiesJSON`, colour hue (never clears), `smartRulesJSON`, `downloadedAt` | `?:`/`ifBlank` guards on a subset; `kudos`, `wordCount`, `title`, etc. take blanks (X-2) | iOS rule everywhere (X-2 resolved toward iOS: never replace known data with empty) |
| Positive counters | `mergedPositive` (`KB:6423`) | partial | iOS rule |
| Monotonic | `hasGivenKudos`, `ao3Unavailable`, `workTagsFetched`, preservation never demoted (`KB:6248`, `6340`, `6350`) | all but `workTagsFetched` on archive-wins | monotonic for all four |
| Tombstone adopt | trusted signer, verified; `lastModifiedAt = min(createdAt, exportedAt)`; newest per record wins, tie → permanent (`KB:3380-3436`, `PS:430`) | trusted + verified; held row replaced only by same identity strictly later; tie keeps first (`BMS:83-127`, `2755`) | iOS rule (newest wins; tie → permanent) |
| Newer-snapshot escape hatch | `tombstoneResolution`: incoming `>` tombstone revives; `==`/older suppresses; no incoming clock = ambiguous, keep (`PS:697-704`); works `suppressesResurrection` uses `>=` suppress (`KB:5861-5890`) | same shape (`BMS:2553-2565`, `2644-2662`) | same; revive = `acquire` op carrying the archive record |
| Recently Deleted copy | restored pending while window open and tombstone ≤ deletion+120 s and not permanent (`KB:5876-5889`, collections/queues `5928-5937`) | suppressed (X-6) | iOS rule |
| Retraction on restore | `retractTombstone` deletes the row (`PWS:216-241`); File Merge only for a live archive copy (`KB:3470-3490`) | `retractWorkTombstone` in Merge path (`BMS:213-229`) | `restore` op referencing the deletion; no tombstone deletion in v9 |
| Deletion schedule | never from the archive (`KB:6147-6164`) | `keptDeletionSchedule` (`BMap:115`) | derived from `deletedAt` payload (DEC-5) |
| Progress | `applyProgress` (`PS:716-760`); Replace forces (`KB:6375-6385`) | `applyProgressLww` (`BMS:938`) | iOS rule |
| Membership match | `(queue, work)` (`KB:4182`) | by id (X-4) | `(queue, work)` |
| Membership winner | Replace always, Reconcile by clock, Merge never (`KB:4194-4212`) | Replace/clock; Merge never (`BMS:1860-1875`) | same |
| Annotations | Merge add-only; Reconcile/Replace LWW; displaced note parked (`KB:5470-5520`) | same (`BMS:2230-2250`) | same, with deterministic sibling id (DEC-11) |
| Settings | per-key stamps, `fromSync` inferred (`SSC:139`) | wholesale typed + raw stamp fold (X-9) | adapter reads the sender's real stamps; absent-without-stamp = unchanged; inferred stamp never beats a real stamp; explicit restore (Merge/Replace file) takes file values but Replace never touches settings (`KB:4724-4737`, `BMS:449`) |
| Dedupe now | wall `Date()` | `now` param | `opClock` |

### 4.3 Route summary

| Route | iOS | Android | Adapter output |
|---|---|---|---|
| Merge | existing overlap untouched (revive-only for Replace-parked live copies; fill missing EPUB bytes) (`KB:3470-3527`); new records adopt; collections/queues add-only; annotations add-only; sessions/favorites/watermarks by id add-only | same, plus `downloadedAt` fill (X-3) (`BMS:231-232`) | creates, fills, memberships only; never an overwrite op |
| Reconcile | LWW per group with all rules of 4.2; unions for tags/memberships | same (with X-2/X-4 differences) | `legacyAdopt` ops per changed group; tombstone witnesses stored |
| Replace | snapshot: forces progress, cover, ties; omission rules 4.4; settings untouched; pronunciations/recovery/documents still applied (`KB:4737-4751`) | snapshot; settings untouched (`BMS:449`) | explicit deletes per 4.4; `legacyAdopt` for every group (forced) |
| v8 folder import | = Reconcile for each manifest version incl. folded conflicts and the pre-2026 package (`FS:519-615`, `SR:340-400`); assets read when size or digest differ (`FS:837-854`, `SR:867`) | same | seed (§4.1.6) or reviewed import; asset refs recorded by digest, bytes copied to blobs |

### 4.4 Replace-only omission rules

| Collection | iOS today | Android today | v9 adapter (both platforms) |
|---|---|---|---|
| works | soft-delete (Recently Deleted), no tombstone (`KB:4664-4669`) | same (`BMS:258-275`) | `softDelete` op with `reason=replaceOmitted`, deadline from `opClock` |
| collections, queues (not Saved for Later) | soft-delete unless key omitted (`KB:4681-4695`) | hard remove (X-5) | `softDelete` only when key present |
| annotations | hidden (`isPendingDeletion`), no tombstone, key omitted → skipped (`KB:4707-4715`, `5542-5553`) | hard remove (X-5) | `annotation.delete` (lifecycle) only when key present |
| saved searches, bookmarks | tombstone + hard delete when present (`KB:4358-4366`, `4417-4426`) | tombstone + remove, even when key absent | delete ops only when key present |
| sessions, favorites, watermarks, followed tags, tag aliases | tombstone + delete only if key non-nil (T-563) (`KB:4856-4864`, `5063`, `5150`, `5236`, `5395`) | tombstone for first three even when absent (X-5); other two opaque | delete ops only when key present, even `[]` replaces |
| memberships | not swept (`KB:4140`; Replace takes archive order/note for matched ones) | Replace removes non-incoming memberships except system queue (`BMS:1840-1865`) | membership remove ops only for memberships of queues the archive lists with key present |
| tags | union, queue tags exact (`KB:3882-3905`) | work tags exact (`BMS:271-282`) | per-tag detach ops only under Replace with key present |
| settings | untouched | untouched | none |

Android needs `omittedKeys` (record which top-level keys were missing before defaulting) to meet T-563. The D4 adapter assumes that is added in A-569; the matrix does not depend on Android's legacy behaviour.

## 5. Fixtures

Files under `docs/sync-fixtures/` are JSON. Two kinds, deliberately separate (plan D4):

- `kind: "v8-compat"`: `route`, `opClock`, `local`, `incoming` (a minimal normalized manifest fragment), `expected.ios`, `expected.android`, `agree` (bool), `disagreement` (X-n) and `v9Outcome`. Expected values were derived by reading the cited paths, **not by running them**; each must be re-verified against the real code by a test in D5/A-569 before the fixture is frozen.
- `kind: "v9-concurrency"`: `entities` (initial normalized state), `ops` (id, writer, stamp, kind, target, payload, prerequisites), `events` (e.g. `blobVisible`), `orders` (`"allInterleavings"` over per-writer prefix order, or an explicit list), `duplicates` (re-deliver every op once), `expected` (normalized logical state, alias table, pending set, applied cut). Every order and every duplicate pattern must give identical `expected`.

| File | Slice | Kind |
|---|---|---|
| `a1-v8-softdelete-propagation.json` | a | v8-compat |
| `a2-v8-recently-deleted-copy-new-device.json` | a | v8-compat (disagree X-6) |
| `a3-v8-permanent-delete-holder.json` | a | v8-compat (N-1) |
| `a4-v9-delete-restore-purge.json` | a | v9 |
| `a5-v9-reacquire-after-purge.json` | a | v9 |
| `b1-v8-duplicate-identity.json` | b | v8-compat (disagree X-4, X-10) |
| `b2-v9-duplicate-identity-annotations-queue.json` | b | v9 (required cross-device test) |
| `c1-v8-asset-replace-vs-delete.json` | c | v8-compat (N-5) |
| `c2-v9-asset-replace-vs-delete.json` | c | v9 |
| `c3-v9-pending-asset-reference.json` | c | v9 |
| `d1-v9-membership-remove-readd-move.json` | ext. | v9 |
| `d2-v9-setting-entry-reset.json` | ext. | v9 |
| `e1-v8-replace-omission-absent-key.json` | ext. | v8-compat (disagree X-5) |

## 6. Open questions (for the orchestrator and owner)

- **Q-1** DEC-2: should an edit concurrent with a delete be retained and returned on restore (chosen) or discarded? Retention is data-preserving; discarding is simpler.
- **Q-2** DEC-4: an `expired` purge loses to a concurrent restore, so devices must keep journal + blobs for a purged-by-expiry lineage until D8 retention is defined. How long must "restore after expiry elsewhere" stay possible? Interacts with D8's retirement bound (must be ≥ 90 days plus a margin).
- **Q-3** DEC-8: when tier 1 and tier 2 name different live entities, v8 silently takes tier 1. v9-native emits no alias and a diagnostic. Is a user-visible "possible duplicate" review wanted? The adapter keeps v8 behaviour for parity.
- **Q-4** DEC-9: survivor = lowest UUID is arbitrary but identical on both platforms. Alternative: earliest create stamp. Does the owner prefer the older record's UUID (it may match an existing `Works/<UUID>.epub` name in the legacy folder)?
- **Q-5** DEC-17: X-1 resolved by clamping both ways; Android's current rejection (a whole import fails on `InvalidDate`) would change in A-569. Acceptable?
- **Q-6** X-2: resolving the work-field difference toward iOS (never overwrite known data with empty) changes Android merge results for blank archive fields. Needs Android parity tests before the adapter ships.
- **Q-7** X-5: Android must track omitted keys (T-563) before its Replace adapter can be trusted; owner decision on whether Android Replace keeps hard-removing collections/queues until then.
- **Q-8** N-1: v9 makes a permanent purge reach every device. Owner confirmation that an explicit purge on one device deleting the Recently Deleted copy on others (a behaviour change) is intended.
- **Q-9** DEC-5: deadline uses the *latest* effective deletion's `deletedAt` (more recovery time). Alternative: earliest.
- **Q-10** Unsigned/untrusted-signer purges: the witness is kept but the purge is not applied (matches v8). Without a trusted signer a v9 library has no purge propagation; where does trusted-signer enrolment live for a v9-only device (`TombstoneTrustStore`, `TS:360-470`; Android `TombstoneTrustStore.kt`)? D5 must decide whether the journal's own authenticated writer identity replaces it.
- **Q-11** Same-key stamp tie across a restored device: a new incarnation gets a new `writerIncarnation`, so ordering never ties, but "greater incarnation wins at equal counter" is arbitrary; confirm that is acceptable for user-visible rank ties.
- **Q-12** N-3/DEC-9: re-keying a work's UUID changes `Works/<UUID>.epub` in the legacy folder. v9 assets are by digest, so this only matters for the seed run and for any v8 reader still attached.
