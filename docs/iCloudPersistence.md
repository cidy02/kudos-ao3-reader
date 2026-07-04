# iCloud Persistence and Backup Strategy

Kudos is local-first. The app must remain usable offline, and AO3 refreshes or
remote sync gaps must never delete user-owned data. Manual `.kudosbackup` files
remain a secondary escape hatch; they are not the primary durability design.

## Current Persistence Architecture

Inspected files/classes:

- `kudos-ao3-reader/App/MyApp.swift` creates the SwiftData container with
  `SavedWork`, `Tag`, `Bookmark`, `CustomFont`, `WorkCollection`, `ReadingQueue`,
  `ReadingQueueMembership`, `SavedSearch`, and `SyncTombstone`.
- `kudos-ao3-reader/Models/Models.swift` stores library works, AO3 metadata,
  reading progress, collections, queues, queue memberships, and sync-prep fields.
- `kudos-ao3-reader/Services/Storage.swift` stores EPUBs and fonts in Application
  Support, reader unzip scratch data and AO3 metadata cache in Caches, and temp
  downloads in Caches/Downloads.
- `kudos-ao3-reader/Services/WorkImporter.swift` imports AO3/user EPUBs, deduping
  by AO3 work ID or title/author/file size for user-selected EPUBs.
- `kudos-ao3-reader/Services/ReadingQueueService.swift` owns reading queue
  membership, queue-preserved EPUB lifecycle, paced series preservation, and
  recoverable missing-file states.
- `kudos-ao3-reader/Services/WorkLifecycle.swift` owns saved/finished/free/delete
  transitions for `SavedWork`.
- `kudos-ao3-reader/Services/WorkMetadataRefresh.swift` and `WorkTags.swift` merge
  AO3 metadata/tags without treating AO3 failure as a delete signal.
- `kudos-ao3-reader/Services/KudosBackup.swift` exports/imports `.kudosbackup`
  packages containing a JSON manifest plus `Works/` EPUBs and `Fonts/` files.
- `kudos-ao3-reader/Settings/SettingsView.swift` exposes backup import/export,
  EPUB import, queue storage/migration, and iCloud sync-prep status.

Reading progress is stored on `SavedWork`: macOS legacy reader uses
`lastSpineIndex` and `lastScrollFraction`; iOS Readium stores `readiumLocator`.
Both stamp `lastReadDate` and now `progressModifiedAt`.

## Chosen Architecture

Chosen approach: hybrid, metadata-first.

- Structured user data should eventually sync through a private CloudKit-backed
  store, ideally SwiftData + CloudKit if the model is made fully compatible.
- EPUB binaries are large assets and must remain separate from metadata. They
  should use local Application Support first, then an iCloud Documents/ubiquity
  asset layer or explicit CloudKit assets only after real-device quota/network
  testing.
- Every `SavedWork` now stores a stable `assetIdentifier` for the EPUB file. The
  current identifier preserves the existing `UUID.epub` layout, so migration does
  not move files. Future iCloud asset lookup should use `assetIdentifier`, never
  mutable title/author/download order.

SwiftData + CloudKit is not enabled in this pass because the project does not yet
have an iCloud entitlement/container configured here, and the current model still
has CloudKit-risky pieces (`@Attribute(.unique)` on `Tag`, Codable transformable
filters on `SavedSearch`, and relationship-heavy models). Enabling CloudKit
without a signed iCloud build and real-device migration test would risk data
loss or launch failures. This pass makes metadata sync-ready and visible without
claiming live iCloud sync is complete.

## Migration Behavior

`PersistenceMigrationService` is idempotent and uses these states:

- `notStarted`
- `inProgress`
- `metadataMigrated`
- `assetsQueuedOrMigrated`
- `completed`
- `failedRecoverable`

On launch, `ContentView` runs `runIfNeeded`. Settings can retry manually. The
migration:

- fills missing `assetIdentifier` values with the stable `SavedWork.id` EPUB name;
- derives missing AO3 work IDs from source URLs;
- initializes created/modified/progress timestamps conservatively;
- marks local records as pending for future sync;
- checks only expected EPUB paths, without reading or reconciling every file;
- marks missing EPUB assets as recoverable (`hasEPUB = false`, preservation
  `missingFile` where applicable) instead of deleting metadata.

Repeated runs do not duplicate records or move assets. Partial failure records a
recoverable Settings status and leaves all local data in place.

## Conflict and Merge Rules

Core rules implemented or documented for future cloud merge:

- Remote absence is never a delete.
- AO3 refresh failure is never a delete.
- Explicit local deletes create `SyncTombstone` records before local records are
  removed. `.kudosbackup` import already honors them (see below); future cloud
  merge code must honor them the same way. Deleting a work also tombstones the
  queue memberships its cascade delete removes.
- Non-empty local metadata is preserved over empty imported metadata.
- Backup import uses `lastModifiedAt` and `progressModifiedAt` where available.
- Reading progress only advances to an incoming snapshot when its modified time
  is newer than the local progress time.
- Queue ordering uses explicit `sortOrderInQueue`, then `queuedAt`, then UUID as
  deterministic tie-breakers.
- Collections and queue memberships are preserved unless explicitly removed.
- Imported EPUBs remain valid local records even if AO3 enrichment fails.

## EPUB Asset Strategy

Current implementation remains local-first:

- EPUBs live in Application Support `Works/`.
- The metadata record is useful even when an EPUB is absent on this device.
- Missing files are marked recoverable and can be restored by existing
  re-download/preservation paths where AO3/source data permits.
- Imported EPUBs are copied into local storage and do not depend on AO3 metadata.
- No background process uploads, downloads, or re-downloads large EPUB assets.

Future asset sync should add an explicit iCloud Documents or CloudKit asset layer
keyed by `SavedWork.assetIdentifier`, with user-aware download controls and
real-device quota/cellular testing.

## `.kudosbackup`

Backups remain manual and merge-only:

- Export is local and network-independent.
- Manifest version 4 includes sync-prep timestamps, progress timestamps, delete
  state, queue membership freshness, and `assetIdentifier` while still decoding
  versions 1, 2, and 3.
- Import merges by AO3 work ID, canonical AO3 URL, then UUID.
- Import does not delete unrelated local records.
- Import honors `SyncTombstone` records: a work the user explicitly deleted here
  is not resurrected unless the archived snapshot is newer than the newest
  matching deletion. Deleted queues and memberships are matched by exact UUID
  and resolved by timestamp: newer queue metadata, newer membership activity, or
  a newer restore can revive an older queue tombstone; stale snapshots remain
  suppressed; ambiguous conflicts preserve data and are reported. Members of a
  suppressed queue are dropped with it, never re-homed into Saved for Later.
- Older backup progress cannot overwrite newer local progress. The same
  timestamp rule guards isFavorite/isSaved/isFinished/isComplete: an older
  archive cannot resurrect a flag the user changed more recently, while a work
  new to this device adopts the archive's flags as-is.
- EPUB files in the package restore the local asset when present; missing EPUBs
  leave metadata intact and mark preserved items as `missingFile`.

## User-Facing Status

Settings shows an iCloud Sync section with:

- local metadata migration state;
- basic iCloud account availability using `ubiquityIdentityToken`;
- last sync-prep check time;
- a retry/check action;
- disclosure that EPUBs remain local in this build and full private iCloud sync
  requires an iCloud-enabled signed build and real-device testing.

Core reading, queue management, import, and library browsing do not depend on
iCloud availability.

## Real-Device iCloud Checklist

Simulator-verifiable:

- builds and unit tests;
- local metadata migration/idempotency;
- missing EPUB recoverable state;
- conservative backup import;
- Settings status row rendering.

Requires real hardware and a signed iCloud-enabled build:

- create an iCloud container/entitlement without changing the public bundle/team
  settings accidentally;
- validate SwiftData + CloudKit schema compatibility or implement custom CloudKit
  records if SwiftData rejects the model;
- save works, queue items, collections, and progress, then update the app and
  confirm persistence;
- delete/reinstall and confirm metadata restoration behavior;
- test a second device on the same iCloud account;
- test iCloud disabled, not signed in, restricted, full quota, poor network, and
  large-library/large-EPUB conditions;
- verify no large EPUB upload/download happens without user intent.
