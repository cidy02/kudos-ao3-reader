# iOS Phase 1 — backup trust (Opus + Grok finish)

Opus 4.6 started `KudosBackup.restore` + Settings import fork, then hit Antigravity
quota (`claude-opus-4-6-thinking` resets ~3h). Grok finished the compile-breaking
UI, split folder-sync from file Merge, and added tests.

## Files

- `kudos-ao3-reader/Services/KudosBackup.swift` — `BackupImportMode`, no incoming tombstone adopt
- `kudos-ao3-reader/Settings/SettingsView.swift` — Merge vs Replace Library sheet
- `KudosTests/KudosBackupTests.swift` — two new production-entry tests

## Modes

- **reconcile** (default, folder sync): existing LWW `apply` on overlap. Incoming tombstones dropped.
- **merge** (file Merge): add missing / undelete Recently Deleted. Do not overwrite active overlap. Incoming tombstones dropped.
- **replaceLibrary**: snapshot this device; soft-delete omissions without `SyncTombstone`. Incoming tombstones dropped.

## What legitimate input is rejected

Incoming deletion claims from a file or sync folder. Deletes do not cross devices until Phase 2.

## Tests

- `incomingUnsignedTombstonesAreNotAdoptedOnMerge`
- `replaceDoesNotLeaveStandingTombstonesThatBlockLaterMerge`

Not yet run in this session (Opus quota; Grok has not run the iOS harness here).
Folder-sync ingest uses default `.reconcile` so existing FolderSyncTests still hit LWW apply.

## Opus leftovers Grok filled

- `ReplaceLibraryConfirmationView` + `makePreReplaceBackup` (referenced, not defined)
- `BackupImportMode.reconcile` so folder sync does not inherit add-only merge
