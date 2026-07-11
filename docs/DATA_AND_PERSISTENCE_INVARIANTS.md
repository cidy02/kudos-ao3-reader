# DATA_AND_PERSISTENCE_INVARIANTS.md

Rules that protect user data. Breaking any of these is a regression even if tests pass. Confirmed as of 2026-07-10.

## Never lose

- A saved work's **EPUB file**, **reading progress** (`readiumLocator`, `lastSpineIndex`, `lastScrollFraction`, `progressModifiedAt`), user flags (`isFavorite`/`isSaved`/`isFinished`), tags, queues, collections, bookmarks.
- **No network outcome may delete local data.** AO3 404 → set `ao3Unavailable = true`, keep everything (`WorkTags.refreshFromAO3`). 429/403/5xx/offline → keep prior state; list refreshes keep previously loaded content on failure.
- Deletion is user-initiated only, and lands in **Recently Deleted for 90 days** first (`PreservedWorkService.softDelete` — sets `isPendingDeletion`/`deletedAt`/`permanentDeletionScheduledAt`, records a tombstone, keeps the EPUB). Only `sweepExpired`/explicit "Delete Permanently" hard-deletes (`WorkLifecycle.hardDelete`). Sweep is gated behind `PersistenceOperationGate`.

## Source of truth vs derived vs transport

| Layer | Role | Rules |
|---|---|---|
| SwiftData store (`Models.swift`) + EPUB files (`Storage.workAssetURL`) | **Source of truth** | Application Support; included in device backups. |
| `searchText`/`searchIndexVersion` | Derived, rebuildable | Never in backups (test-asserted); `reindex` never calls `markModified`; version-stamped launch rebuild (`WorkSearchIndex.rebuildIfNeeded`). |
| `authorIdentitiesJSON` | AO3-derived enrichment | Additive default-empty SwiftData field. Persist only identities parsed from AO3 links; never infer from `SavedWork.author`. Intentionally omitted from `.kudosbackup`, so restored legacy text remains visible but non-tappable until a later AO3 refresh. |
| `.kudosbackup` package | Transport/backup | Manifest v7 + EPUB/font blobs. Carries source-of-truth fields incl. progress, flags, tombstones, settings, collections, queues+memberships. Versioned decode v1–v7; **fractional-second date encoder with whole-second decode fallback** — never regress either side. |
| Folder sync (`FolderSyncService`) | Transport over iCloud Drive | Same package, one file `KudosLibrary.kudosbackup` in a user-picked folder (security-scoped bookmark in UserDefaults — dies on reinstall, file survives). No CloudKit/entitlements. `lastTagRefreshAttemptAt` is deliberately device-local (not in backups). |

## Identity & duplicates

- Identity tiers: **AO3 work ID → canonical AO3 URL → record UUID** — only via `WorkIdentityIndex`. Never write a new matcher.
- No DB-level uniqueness on `SavedWork`; dedup is application-level. `importEPUB` re-checks `existingWork(forSource:)` **after** the awaited download and merges (fill-only) into any match — keep this; it closes the TOCTOU race.
- **Re-acquiring revives**: any acquisition path (save, import, queue add, download) that matches a Recently-Deleted record must `PreservedWorkService.restore` it, never duplicate it or mutate it while hidden.
- Author display text is not an AO3 identifier. Only `AO3AuthorIdentity.route` may drive native profile navigation; anonymous/deleted/guest text and old local imports stay non-navigable.

## Merge rules (backup restore + folder sync share them)

- Timestamp-aware: `incomingWins` = `SyncMerge.shouldApplyIncoming(local:incoming:)`; new records always adopt archive values.
- Booleans (`isFavorite`, `isSaved`, `isFinished`, `isComplete`, `isPendingDeletion`) are `incomingWins`-gated — never OR/AND-merged blindly.
- Tombstones travel in the manifest, merge before conflict resolution, suppress resurrection with a newer-snapshot escape hatch; `restore()` **retracts** the tombstone rather than racing timestamps.
- Membership removal has tombstones too (`.readingQueueMembership`, `.workCollectionMembership` with composite ID `SyncTombstone.collectionMembershipID`).
- Restore reindexes each restored work; suppressed works' EPUBs are never written (no orphans from suppression).

## Folder sync safety

- Writes: stage to `itemReplacementDirectory` (same volume) → `replaceItemAt` — the remote package must survive any failed write. Never remove-then-write.
- Reads: skip when coordinated `contentModificationDate` matches the stored stamp (updated after restores AND own writes) — but **never skip while `NSFileVersion` unresolved conflicts exist**.
- All package I/O under `NSFileCoordinator`; conflicts folded by restoring each version then resolving.
- Everything gated by `PersistenceOperationGate` (process-wide; migration / backup import / folder sync / sweep never interleave).

## Queues / collections / library behavior

- Removing a work from a queue is non-destructive; queue-only works auto-soft-delete (not hard) when leaving their last queue unsaved/unfavorited.
- Soft-deleted works keep memberships/collection links (restore re-joins) but are **filtered at render time** everywhere (`isPendingDeletion` exclusions in every list `@Query` + relationship-derived listings).
- Queue-preserved EPUBs (`epubPreservationStatus`) are protected from history-clearing paths.

## Migration / schema safety

- New `@Model` fields: **additive with defaults only** (lightweight migration). Follow `permanentDeletionScheduledAt` / `searchText` precedents.
- Never name a model property `isDeleted` (CoreData collision — silently resets). Check reserved `NSManagedObject` names for any new flag.
- One-time data fixups go in `PersistenceMigrationService` stages (yield every `yieldInterval`, `modelContext != nil` guards, gate-protected, stage-aware errors). `reconcileAssets` heals hasEPUB-vs-file drift.
- Manifest changes: bump `KudosBackupManifest.currentVersion`, extend `supportedVersions`, decode-if-present with defaults, add a round-trip test.

## Known accepted risks (don't "fix" silently — they have designs pending)

- Folder sync ships all EPUB blobs both directions (full-package model); metadata+sidecar redesign is planned, own branch.
- Orphaned EPUB files (file exists, no record) are not swept.
- All list surfaces `@Query` the full table; fine to low thousands.
