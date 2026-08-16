# M15a/M15b Codex implementation report

Branch/worktree inspected: `security-fixes/wp-a` at starting HEAD `06a6e4c`,
`/Users/cidy02/kudos-fix-wp-a`.

## Changes

- `kudos-ao3-reader/Services/KudosBackup.swift:1248-1266` — the public
  `KudosBackupService.restore` now saves any pre-existing caller changes, creates a
  new `ModelContext` over the caller's `ModelContainer`, disables autosave on that
  restore context, and delegates the entire merge to it. This preserves unrelated
  caller edits without using `rollback()` and ensures restore mutations do not enter
  the autosaving caller context.
- `kudos-ao3-reader/Services/KudosBackup.swift:1271-1275,1756-1788` — the existing
  linear merge is private to the isolated context. Its only `save()` remains after
  every model mutation and asset write; settings still apply only after that save.
  A throw before line 1778 drops the unsaved restore context.
- `kudos-ao3-reader/Services/KudosBackup.swift:1324-1329` — documents the accepted
  M15b trade-off. Asset writes are monotonic, not atomic with SwiftData. A crash can
  leave the filesystem ahead of the database for a non-preserved work. Re-running
  restore converges through the existing replacement/preservation gates; the design
  deliberately avoids staging, journals, sweepers, or cleanup that an uncatchable
  signal can defeat. Existing `hasEPUB`/`.missingFile` reconciliation already models
  the opposite database-ahead-of-disk state.
- `KudosTests/KudosBackupTests.swift:209-288` — adds the M15a/M20 persistence
  revert-check inside the existing `PersistenceGateSuites` / serialized
  `KudosBackupTests` suite.
- `TASKS.md:24` — records T-196 and the execution/commit handoff.

`SettingsView.swift` and `FolderSyncService.swift` required no caller-specific edit:
all named paths already use the shared `KudosBackupService.restore` boundary.

## Test added

### `failedRestoreLeavesNoSwiftDataMutationsVisibleAfterCallerAutosave`

Location: `KudosTests/KudosBackupTests.swift:214`.

The fixture persists one local work, then restores a newer archive that would update
that work and insert a tag, bookmark, Saved-for-Later queue, and font row. The font
targets a UUID-named missing parent directory, forcing the expected Cocoa
`fileNoSuchFile` error at the final font-write phase. The test asserts that exact late
error so an earlier unrelated throw cannot make it pass for the wrong reason. It then
calls `context.save()` to emulate the environment context's next autosave tick and
queries from a fresh context. The original work must be unchanged and every
restore-touched model type must remain empty.

What would have to break for this test to fail: restore mutations would have to reach
the caller/store before the late throw (for example, restoring in the shared context,
leaving autosave enabled on the restore context, or moving `save()` earlier), or the
fixture would have to stop reaching the controlled late font-write failure (caught by
the error-domain/code control assertions). This is the M15a revert-check: reverting
the isolated-context wrapper makes the caller's explicit post-error save persist the
partial merge.

No preserved-bytes test was duplicated. Existing coverage remains:

- `preservedWorkWithAFileIsNeverByteReplacedByARestore`
  (`KudosTests/ArchiveTrustBoundaryTests.swift:89`) checks the direct/eager contents
  path.
- `preservedBytesSurviveARestoreDrivenFromARealZipArchive`
  (`KudosTests/ArchiveTrustBoundaryTests.swift:141`) checks the real lazy ZIP path.

## Same-container propagation and callers

The installed iOS 26.5 SwiftData module interface was inspected. `ModelContext`
exposes `init(_ container: ModelContainer)`, `container`, `autosaveEnabled`,
`hasChanges`, and `save()`. It exposes no parent-context initializer, so SwiftData
cannot provide a literal Core Data child context. A new context sharing the same
container is the nearest—and store-isolated—implementation of the agreed design.

Before creating it, the wrapper saves caller changes if `hasChanges` so the isolated
merge sees the same durable state and does not duplicate or overwrite around pending
caller objects. The isolated success-path `save()` writes to the shared container.
Existing successful-restore tests provide the required caller-observation checks when
Claude runs them, notably:

- `restoreMergesRecordsTagsAssetsAndSettings` fetches the restored work, tags, and
  bookmarks from the context passed to `restore`.
- `syncDownRestoresWorkQueueAndCollection` verifies `performSyncDown` results from its
  passed context.
- `foldConflictContentsMergesAllInputs` performs two sequential isolated restores and
  verifies both are visible through the passed context.
- The production File Provider fold at
  `kudos-ao3-reader/Services/FolderSyncService.swift:428-437` uses the same restore
  call and marks each `NSFileVersion` resolved only after it succeeds.
- Settings import at `kudos-ao3-reader/Settings/SettingsView.swift:814-817` receives
  the restore summary only after the isolated save and then applies its UI theme.

I attempted a small standalone same-container runtime probe. It could not execute
because the sandbox denied SwiftData's macro plugin server (`sandbox_apply: Operation
not permitted`; malformed macro-plugin response). No runtime propagation result is
claimed from that probe. The project tests above are the execution evidence Claude
must collect.

## Evidence gathered

- `git diff --check`: clean.
- Branch and starting HEAD matched the request; no `project.pbxproj` change exists.
- Source/API inspection confirmed all requested callers route through the shared
  restore entry point and confirmed the available SwiftData context API.
- A Foundation-only probe using redirected module caches confirmed writing into a
  missing parent produces `NSCocoaErrorDomain` code 4, the test's late-failure
  control. This is not project test evidence.

## WHAT I DID NOT VERIFY

- I did not run the new Swift Testing test, the full iOS suite, the M15a revert-check,
  `Scripts/verify.sh`, an iOS Simulator build, or the macOS build. Claude owns that
  execution evidence per the task instructions.
- I did not obtain runtime proof that a same-container save refreshes the already-live
  caller context because the sandbox denied the SwiftData macro plugin. Existing
  success-path and folder-sync tests must provide that proof.
- I did not manually exercise Settings import, real iCloud/File Provider conflicts,
  crash/signal timing, or filesystem/database torn-state recovery.
- I did not push, merge, open a PR, create a remote branch, or touch
  `/Users/cidy02/Documents/AO3_App_OpenSource`.
- I could not create the requested local commit. This linked worktree's Git index is
  under `/Users/cidy02/kudos-security-audit-1-claude/.git/worktrees/kudos-fix-wp-a`,
  outside the writable root; Git failed creating `index.lock` with `Operation not
  permitted`. Claude must commit these worktree changes locally after verification.
