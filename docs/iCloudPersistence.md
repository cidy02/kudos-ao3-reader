# Library Sync Folder and Backup Strategy

Kudos is local-first. The app must remain usable offline, and AO3 refreshes,
folder-provider delays, or sync conflicts must never delete user-owned data.
Manual `.kudosbackup` export/import remains available as a secondary escape
hatch; the automatic path uses the same backup package format.

## Current Persistence Architecture

Inspected files/classes:

- `kudos-ao3-reader/App/MyApp.swift` creates the SwiftData container with
  `SavedWork`, `Tag`, `Bookmark`, `CustomFont`, `WorkCollection`, `ReadingQueue`,
  `ReadingQueueMembership`, `SavedSearch`, and `SyncTombstone`.
- `kudos-ao3-reader/Models/Models.swift` stores library works, AO3 metadata,
  reading progress, collections, queues, queue memberships, and sync metadata.
- `kudos-ao3-reader/Services/Storage.swift` stores EPUBs and fonts in Application
  Support, reader unzip scratch data and AO3 metadata cache in Caches, and temp
  downloads in Caches/Downloads.
- `kudos-ao3-reader/Services/KudosBackup.swift` exports/imports `.kudosbackup`
  packages containing a JSON manifest plus `Works/` EPUBs and `Fonts/` files.
- `kudos-ao3-reader/Services/FolderSyncService.swift` reads and writes one
  coordinated `KudosLibrary.kudosbackup` package in a user-chosen folder.
- `kudos-ao3-reader/Services/PersistenceSync.swift` owns the local migration,
  sync timestamps, tombstones, merge helpers, and operation gate.
- `kudos-ao3-reader/Settings/SettingsView.swift` exposes manual backup controls,
  Library Sync Folder controls, and local metadata readiness.

Reading progress is stored on `SavedWork`: macOS legacy reader uses
`lastSpineIndex` and `lastScrollFraction`; iOS Readium stores `readiumLocator`.
Both stamp `lastReadDate` and `progressModifiedAt`.

## Chosen Architecture

Chosen approach: no-entitlement folder sync.

- The user chooses a Library Sync Folder in Settings, usually inside iCloud
  Drive. Kudos stores a security-scoped bookmark to that folder.
- Kudos reads and writes exactly one package in that folder:
  `KudosLibrary.kudosbackup`.
- Reads and writes use `NSFileCoordinator` so file-provider updates and package
  replacement are coordinated with the system.
- Sync down restores the remote package with the same merge rules as manual
  backup import. Sync up writes the current local library as a fresh package.
- File-provider conflict versions are folded by restoring each unresolved
  conflict package, then resolving the conflict version after a successful merge.
- There is a process-wide persistence operation gate, so migration, backup
  import, and folder sync do not interleave.

This does not enable CloudKit, SwiftData cloud mirroring, an iCloud entitlement,
or an app-owned iCloud container. iCloud Drive can sync the chosen folder between
devices, but Kudos treats it as a folder provider, not as real-time database
sync.

## Automatic Sync Triggers

Kudos syncs conservatively:

- app launch: run the local metadata migration, then sync down if a folder is
  connected;
- scene becomes active: sync down;
- scene becomes inactive/background: sync up;
- local library data changes: debounce briefly, then sync up.

The debounce watches works, bookmarks, custom fonts, collections, reading
queues, queue memberships, and tombstones. If no folder is connected, these
triggers are no-ops.

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
- marks local records as pending for folder sync;
- checks only expected EPUB paths, without reading or reconciling every file;
- marks missing EPUB assets as recoverable (`hasEPUB = false`, preservation
  `missingFile` where applicable) instead of deleting metadata.

Repeated runs do not duplicate records or move assets. Partial failure records a
recoverable Settings status and leaves all local data in place.

## Conflict and Merge Rules

Core rules:

- Remote absence is never a delete.
- AO3 refresh failure is never a delete.
- Explicit local deletes create `SyncTombstone` records before local records are
  removed. Deleting a work also tombstones the queue memberships its cascade
  delete removes.
- Non-empty local metadata is preserved over empty imported metadata.
- Folder sync and backup import use `lastModifiedAt` and `progressModifiedAt`
  where available.
- Reading progress only advances to an incoming snapshot when its modified time
  is newer than the local progress time.
- Queue ordering uses explicit `sortOrderInQueue`, then `queuedAt`, then UUID as
  deterministic tie-breakers.
- Queue tombstones suppress stale queue/member snapshots, revive newer queue
  metadata or membership activity, and preserve/report ambiguous conflicts.
- Members of a suppressed queue are dropped with it, never re-homed into Saved
  for Later.
- Collections are exported in manifest version 6 and restore by UUID with
  timestamp/tombstone handling.
- Imported EPUBs remain valid local records even if AO3 enrichment fails.

## EPUB Asset Strategy

Current implementation remains local-first:

- EPUBs live in Application Support `Works/`.
- A metadata record remains useful even when an EPUB is absent on this device.
- Missing files are marked recoverable and can be restored by existing
  re-download/preservation paths where AO3/source data permits.
- Imported EPUBs are copied into local storage and do not depend on AO3 metadata.
- Folder sync writes EPUB bytes into `KudosLibrary.kudosbackup` when they are
  present locally; missing EPUB bytes leave metadata intact on restore.

## `.kudosbackup`

Backups are merge-only, whether imported manually or transported by the Library
Sync Folder:

- Export is local and network-independent.
- Manifest version 6 includes sync timestamps, progress timestamps, delete state,
  collection membership, queue membership freshness, `assetIdentifier`, and
  `SyncTombstone` records, while still decoding versions 1 through 5.
- Import merges by AO3 work ID, canonical AO3 URL, then UUID.
- Import does not delete unrelated local records.
- Tombstones travel with the backup, so a fresh install/reinstall inherits the
  source device's deletion history.
- An explicitly deleted work is not resurrected unless the archived snapshot is
  newer than the newest matching deletion.
- Older backup progress cannot overwrite newer local progress. The same timestamp
  rule guards `isFavorite`, `isSaved`, `isFinished`, and `isComplete`.
- EPUB files in the package restore the local asset when present; missing EPUBs
  leave metadata intact and mark preserved items as `missingFile`.

## User-Facing Status

Settings shows a Library Sync Folder section with:

- local metadata readiness;
- connected folder name/path;
- Choose Sync Folder, Sync Now, and Disconnect actions;
- last metadata check and last folder sync timestamps;
- the latest folder sync error, if any;
- disclosure that this is folder-based sync using the existing backup format, not
  real-time CloudKit sync.

Core reading, queue management, import, and library browsing do not depend on
the selected folder or on iCloud availability.

## Verification

Simulator-verifiable:

- builds and unit tests;
- local metadata migration/idempotency;
- missing EPUB recoverable state;
- conservative backup import;
- folder sync into temporary directories;
- missing remote sync file no-op behavior;
- conflict-content folding through the backup restore path;
- sync-up timestamp stability;
- Settings status row rendering by build/type-check.

Requires manual device testing:

- choose an iCloud Drive folder in Settings and confirm
  `KudosLibrary.kudosbackup` appears;
- install on a second device, choose the same folder, and confirm works,
  progress, collections, queues, bookmarks, fonts, settings, and tombstones merge;
- edit on both devices while offline, reconnect, and confirm conflict versions
  fold without duplicate works or queue data loss;
- delete works/queues/collections on one device and confirm older packages do not
  resurrect stale data;
- test iCloud Drive disabled, not signed in, restricted, full quota, poor
  network, large library, and large EPUB conditions.
