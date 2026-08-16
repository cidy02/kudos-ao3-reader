# FIXES-GROK-BACKUP.md — WP-C lazy backup + RC pre-confirm

**Worktree:** `/Users/cidy02/kudos-rcfix-backup`  
**Branch:** `rc-fix/backup` (off `security-fixes/rc`)  
**Implementer:** Grok 4.6  
**Scope:** `KudosBackup.swift`, `SettingsView.swift`, `KudosBackupTests.swift`, `BackupLazyReadTests.swift`  
**Not pushed.** Local commits only.

Reviewed `REVIEW-GROK-WPC.md` against this RC before editing. FIX-1, FIX-2, FIX-3, and FIX-5 were still live. FIX-4 (`.orig` / revert patches) was already removed on RC (WPC-1). The conductor’s recorded Settings pre-confirm regression was also live: `importBackup` called `KudosBackupContents.read(from:)` and held a decoded `KudosBackupContents` in `@State`.

---

## Commits

| SHA | What |
|---|---|
| `9911f03` | Directory + ZIP-font laziness; `fontData(for:)`; restore uses it; `SourceIdentity` |
| `88b3915` | Settings holds `SecurityScopedURL` + manifest; execute reads via `readForConfirmedImport` |
| `51a6534` | Production-entry laziness / TOCTOU tests; archive round-trip uses `fontData` |

---

## What changed

### FIX-2 — directory import is lazy (was the live M4 hole)

`readLegacyDirectory` / `read(from:)` no longer copies every `Works/*.epub` (or font payload) into `[UUID: Data]`. It keeps `directoryURL` and lets `epubData(for:)` / `fontData(for:)` read one file.

Font **caps** still run at read time from `fileSize` metadata (or a discarded bounded read if size is missing), so `legacyDirectoryOversizedEntryIsRejectedBeforeRead` still throws without keeping the bytes.

`init(fileWrapper:)` is unchanged (legacy test / unused Settings path). Folder-sync’s `readChangedRemoteAssets` still eagerly loads the *changed* subset — that is the pre-existing residual named in REVIEW-GROK-WPC, and `FolderSyncService.swift` is out of scope.

### FIX-3 — ZIP fonts are not extracted at `init(zipData:)`

Size-check via `uncompressedSize` remains (so `zipOversizedEntryIsRejectedBeforeExtraction` / aggregate still throw). Payloads are not inflated until `fontData(for:)` / restore. Restore now calls `fontData(for:)` instead of `fontFiles[name]`.

### FIX-1 — laziness tests prove unread-until-access

ZIP extracts go through a `ZipSource` box that records entry names. After `read(from:)` / `init(zipData:)` the recorded names are only `["manifest.json"]`. `Works/` and `Fonts/` appear only when the matching accessor runs. Public `epubFiles` / `fontFiles` stay empty (no memoisation).

Directory proof: `chmod 000` on `Works/` (or `Fonts/`), `read(from:)` succeeds, accessor returns nil; `chmod 755`, **the same contents object** then returns the bytes. Reverting to eager `Data(contentsOf:)` without `directoryURL` leaves `epubData` nil after the tree is reopened.

Tests live as `extension PersistenceGateSuites.KudosBackupTests` in `BackupLazyReadTests.swift` so the RC filter `KudosTests/PersistenceGateSuites/KudosBackupTests` actually runs them. A sibling suite named `BackupLazyReadTests` would match **zero** cases under that filter and still exit 0.

`archiveRoundTripPreservesManifestAndAssets` still checks the same font **bytes** with `==`. The lookup moved from `fontFiles[name]` to `fontData(for:)` (same operator, same bytes) and gained `fontFiles.isEmpty`. That is the same adaptation WP-C already did for EPUBs; it is not a loosened assertion.

### FIX-5 — confirm-time TOCTOU, closed as far as is proportionate

Settings no longer holds decoded contents across the alert. It snapshots `SourceIdentity` (root size + mtime via `attributesOfItem`, plus listed asset sizes for a directory) and execute calls `readForConfirmedImport`, which refuses a mismatch with `KudosBackupError.sourceChanged`.

`URL.resourceValues` was **not** used for the snapshot: it can return a cached size after the file is replaced (the first swap test was green-on-revert until this was fixed).

**Residual (accepted, documented on `SourceIdentity`):** a replacement with the same size and the same `contentModificationDate` is indistinguishable. A directory import that swaps one EPUB for another of equal size also lands. Closing that fully means hashing every payload at confirm time, which is the M4 bomb again.

### RC pre-confirm regression

`pendingBackup: KudosBackupContents?` is gone. Confirm UI holds `PendingBackupImport` (`SecurityScopedURL` + `KudosBackupManifest` + `SourceIdentity`). `ReplaceLibraryConfirmationView` takes `manifest` only (`BackupReplaceWorkDelta.classify` still uses `manifest.works`).

Three-mode product is unchanged:

- Empty library → one “Restore from Backup” alert (`.merge`)
- Non-empty → Merge vs Replace Library
- Replace extra step: counts, amber if much smaller, checkbox, 1.5s delay, pause-sync default, pre-replace safety `.kudosbackup`

`restorePendingBackup` captures the scoped URL into the `Task` so clearing `@State` does not drop security-scoped access before the execute read.

---

## Mutation evidence

Each mutant was applied, rebuilt, run through `KudosTests/PersistenceGateSuites/KudosBackupTests`, then reverted with `git checkout`. Durations are from the Swift Testing runner (non-zero). `0.000s` did not occur.

### FIX-1 — eager `Works/*` extract in `init(zipData:)`

Re-introduced a loop that pulled every work via `ZipSource.data(named:)` into `epubFiles`.

`zipReadDoesNotExtractWorksUntilAccessed` — **RED, 0.075s**

> Expectation failed: `(contents.epubFiles → […: 6 bytes, …: 6 bytes]).isEmpty → false`

> Expectation failed: `(contents.extractedZipEntryNames → ["manifest.json", "Works/….epub", "Works/….epub"]) == ["manifest.json"]`

`backupArchiveIsLazy` — **RED, 0.001s** (non-zero)

> Expectation failed: `(contents.epubFiles → […: 5 bytes]).isEmpty → false`  
> `Extraction is lazy: epubFiles dictionary should not be pre-populated`

Restored. Both tests **GREEN** on the final run (`zipRead…` 0.015s, `backupArchiveIsLazy` 0.001s).

### FIX-2 — eager directory EPUB read, no `directoryURL`

Put back `Data(contentsOf:)` of every `Works/*.epub` and returned `directoryURL: nil`.

`directoryReadDoesNotMaterializeEPUBs` — **RED, 0.070s**

> Expectation failed: `(contents.directoryURL → nil) != nil`

> Expectation failed: `(contents.epubData(for: work.id) → nil) == (epub → 8 bytes)`

That second line is the unread-until-access proof: after `chmod 755`, a lazy contents object can read the file; an eager `try?` that ran while the tree was `000` cannot.

Restored. **GREEN, 0.012s**.

### FIX-3 — eager ZIP font extract in `init(zipData:)`

Put back `source.data(named: "Fonts/…")` into `fontFiles`.

`zipReadDoesNotExtractFontsUntilAccessed` — **RED, 0.011s**

> Expectation failed: `(contents.fontFiles → ["lazy-….ttf": 12 bytes]).isEmpty → false`

> Expectation failed: `(contents.extractedZipEntryNames.filter { $0.hasPrefix("Fonts/") } → ["Fonts/lazy-….ttf"]).isEmpty → false`  
> `read(from:) must not extract Fonts/* until fontData is called`

`archiveRoundTripPreservesManifestAndAssets` also went RED on the new `fontFiles.isEmpty` check (0.065s) — the adapted assertion is a revert-catcher, not a weaken.

Restored. **GREEN**.

### FIX-5 — skip `assertSourceUnchanged` in `readForConfirmedImport`

`swappedZipIsRejectedAtConfirmedImport` — **RED, 0.004s**

> Expectation failed: `an error was expected but none was thrown`

`swappedDirectoryAssetIsRejectedAtConfirmedImport` — **RED, 0.009s**

> Expectation failed: `an error was expected but none was thrown`

Restored. Both **GREEN** (0.005s / 0.002s).

---

## Gate results

Simulator: `D1429654-5A7E-4B8A-B613-7F1E809E4D27` (iPhone 17 Pro Max).  
`CODE_SIGNING_ALLOWED=NO`. Derived data `/tmp/dd-backup`.  
Filters: `KudosTests/PersistenceGateSuites/KudosBackupTests` **and** `KudosTests/PersistenceGateSuites/FolderSyncTests`.  
Never `-sdk iphonesimulator` with the UDID.

**Swift Testing runner (final restored tree, case-sensitive volume mounted):**

```
✔ Suite FolderSyncTests passed after 1.073 seconds.
✘ Test failedRestoreLeavesNoSwiftDataMutationsVisibleAfterCallerAutosave()
    Expectation failed: (restoreError?.code → 4) == 512
    failed after 0.017 seconds
✘ Test run with 78 tests in 3 suites failed after 1.626 seconds with 1 issue.
```

| Suite | Result |
|---|---|
| FolderSyncTests | **27/27 GREEN** (including both case-fold tests, volume mounted) |
| KudosBackupTests | **50/51** — every new laziness/TOCTOU test GREEN; one pre-existing M15 assertion RED (below) |
| Total | **78 tests, 77 passed, 1 failed** (`totalTestCount` ≠ 0) |

I could **not** read `/tmp/rb-backup.xcresult` with `xcresulttool`: after the runner prints totals, `xcodebuild test-without-building` hangs and never writes `Info.plist`. SIGINT after 90s still left a Data/Staging-only bundle. Counts above are from the runner log, not from a result-bundle summary. I am not treating the hung xcodebuild exit as a pass.

`Scripts/lint.sh` exit **0**. Zero errors. CI `--strict` still flags two **pre-existing** issues in `KudosBackup.swift` (function_parameter_count at the restore helper, line_length 138 on a comment-adjacent line I did not touch) and the pre-existing `large_tuple` on `BackupReplaceWorkDelta.classify`. The `swiftlint:disable:next cyclomatic_complexity function_body_length` on `restoreIsolatedContents` is still flush against the function declaration.

Android gate not run (this unit is iOS-only).

---

## What I could NOT close

1. **`failedRestoreLeavesNoSwiftDataMutationsVisibleAfterCallerAutosave` expects Cocoa 512; this simulator returns 4.**  
   Isolated reproduction (that test alone, no prior tests):  
   `NSCocoaErrorDomain code=4`  
   `The file “…-restored-1.ttf” doesn’t exist.`  
   Path is the directory the test creates so the late font write fails. The production write is still `data.write(to: font.fileURL, options: .atomic)` — I did not change it. Switching the lookup from `fontFiles[name]` to `fontData(for:)` returns the same in-memory bytes on this fixture. I did **not** loosen the `== 512` assertion. This looks like Foundation-on-iOS-27 mapping an atomic replace of a *directory* to `NSFileNoSuchFileError` instead of `NSFileWriteFailure` (512). M15 rollback is not what this failure is measuring; the code path still throws before `save`. Honest gap.

2. **FIX-5 residual.** Same-size + same-mtime swap of a ZIP, or equal-size swap of one directory EPUB, is not detected. Hashing payloads at confirm is M4.

3. **MiniZip extract counter is out of scope.** `MiniZip.swift` is not mine. A private eager cache that calls `MiniZip.data(named:)` directly, never through `ZipSource` and never into public `epubFiles`, would still be silent. The natural revert (the old init loop) goes RED on both the name probe and `epubFiles.isEmpty`.

4. **Folder-sync changed-asset batch** still materialises every *changed* remote EPUB at once (`FolderSyncService.readChangedRemoteAssets`). Pre-existing; file out of scope.

5. **Android import** still eager. Out of scope.

6. **Settings UI not driven in the simulator.** No SwiftUI harness (handoff R6 SKIP). Pre-confirm / three-mode wiring is from source. `readForConfirmedImport` is the execute entry Settings now calls.

7. **Result bundle.** Hung `xcodebuild` never finalized `Info.plist` on the last runs. Do not take “exit 0” from a killed `test-without-building` as a gate pass.

---

## Three-mode product check

Not re-litigated. Empty → Restore. Non-empty → Merge vs Replace extra step (counts, amber, checkbox, delay, pause-sync via `setAutoSyncEnabled`, safety backup). Replace still does not apply appearance. Incoming unsigned tombstones still drop (untouched restore policy).
