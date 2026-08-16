# iOS Phase 1 digest — merge/reconcile tests + mutation evidence

## Files changed

- `KudosTests/KudosBackupTests.swift` — three new production-entry tests
- `IMPLEMENTATION-NOTES.md` — harness + Mutation A/B evidence (appended)
- `kudos-ao3-reader/Settings/SettingsView.swift` — compile-only: extract
  two concatenated `Text(...)` strings out of the ViewBuilder so a clean
  derived-data build type-checks (not a confirmation-UI restyle)
- `OPUS-IMPLEMENT-DIGEST.md` — this file

Not rewritten: `KudosBackupService.restore` production drop path.
`incomingUnsignedTombstonesAreNotAdoptedOnMerge` and
`replaceDoesNotLeaveStandingTombstonesThatBlockLaterMerge` left unchanged.
Android not edited. No push.

## Tests added

All call real `KudosBackupService.restore` (not a helper):

1. `fileMergeDoesNotOverwriteActiveOverlapTitleProgressOrUserTags`
   — `mode: .merge` does not overwrite active overlap title / progress /
   user tags.
2. `defaultReconcileAppliesLastWriterWinsOnOverlap`
   — default restore (omit `mode` → `.reconcile`) LWW-applies newer title
   and `lastSpineIndex`.
3. `defaultReconcileDropsIncomingUnsignedTombstonesAndStillInsertsPresentWork`
   — default restore drops incoming unsigned tombstones and still inserts
   a work present in the same snapshot.

## xcresult counts (GREEN last)

`xcrun xcresulttool get test-results summary --path /tmp/tomb-ios.xcresult --format json`

```
result: Passed
passedTests: 30
failedTests: 0
totalTestCount: 30
```

Destination: `id=C71780B1-35DE-4E5E-ABCD-2AB66BCB28B0` (no `-sdk`).
Note: `-only-testing:KudosTests/KudosBackupTests` executes **0** Swift
Testing cases; the suite is nested under `PersistenceGateSuites`. The
counts above used
`-only-testing:KudosTests/PersistenceGateSuites/KudosBackupTests`.

## Mutation A (unconditional incoming-tombstone adopt) — RED, then reverted

- `incomingUnsignedTombstonesAreNotAdoptedOnMerge()`  
  `"Incoming unsigned tombstone was persisted"`  
  **0.223s**
- `replaceDoesNotLeaveStandingTombstonesThatBlockLaterMerge()`  
  `Expectation failed: try context.fetch(FetchDescriptor<SyncTombstone>()).isEmpty`  
  **0.023s**
- `defaultReconcileDropsIncomingUnsignedTombstonesAndStillInsertsPresentWork()`  
  `"Incoming unsigned tombstone was persisted on reconcile"`  
  `"Reconcile must still insert a work present in the same remote snapshot"`  
  **0.127s**

## Mutation B (drop on `.merge`, still adopt on default `.reconcile`) — RED, then reverted

- `incomingUnsignedTombstonesAreNotAdoptedOnMerge()` stayed GREEN (**0.011s**)
- `defaultReconcileDropsIncomingUnsignedTombstonesAndStillInsertsPresentWork()`  
  `"Incoming unsigned tombstone was persisted on reconcile"`  
  `"Reconcile must still insert a work present in the same remote snapshot"`  
  **0.210s**

## Left undone

- Uncommitted concurrent tree (not this job): `KudosBackup.swift` Replace
  snapshot-wins / skip-settings / ignore-local-suppressors hunks;
  remaining `SettingsView` pause-sync / skip-theme hunks; `handoff.md`;
  Android already owned elsewhere.
- FolderSyncTests were not re-run (only `KudosBackupTests`).
- Phase 2 Ed25519 out of scope.
- Clean worktrees still need `Vendor/MuPDF.xcframework` (gitignored);
  this session used a local symlink to another checkout.
