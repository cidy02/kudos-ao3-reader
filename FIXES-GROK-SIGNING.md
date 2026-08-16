# FIXES-GROK-SIGNING.md — WP-D WPD-1..8 on `rc-fix/signing`

**Worktree:** `/Users/cidy02/kudos-rcfix-signing`  
**Branch:** `rc-fix/signing` (off `security-fixes/rc`)  
**Implementer:** Grok 4.6  
**Commit:** `9a6c510` `Qualify macOS Release entitlements so iOS keeps Keychain`  
**Not pushed.** No remote branch, no PR.

Scope touched (and nothing else):

- `AO3_App_OpenSource.xcodeproj/project.pbxproj`
- `kudos-ao3-reader/Kudos.entitlements`
- `Scripts/check-macos-release-entitlements.sh`
- `Scripts/build-macos.sh`
- `Scripts/verify.sh`
- `.github/workflows/ci.yml`
- `KudosTests/EntitlementReleasePinTests.swift` (new)

`kudos-ao3-reader/Services/AO3SessionVault.swift` was **not** edited.

---

## What changed

### WPD-3 (most important) — pin is macOS-only

On the five-platform app target Release block:

```
"CODE_SIGN_ENTITLEMENTS[sdk=macosx*]" = "kudos-ao3-reader/Kudos.entitlements";
"CODE_SIGN_INJECT_BASE_ENTITLEMENTS[sdk=macosx*]" = NO;
```

Unqualified, both settings applied to iOS. `INJECT_BASE=NO` strips profile-derived `application-identifier` / `keychain-access-groups`; `Kudos.entitlements` supplies none of them. `CascadingAO3SessionVault.save` (`AO3SessionVault.swift:277-289`) treats `errSecMissingEntitlement` as the signal to persist to `FileAO3SessionVault` — so a signing-hardening change was about to ship iOS Release onto the plaintext file vault. Qualifying the pin removes that downgrade. iOS Release again uses the default injected Keychain entitlements.

The guard now **fails** if either setting appears without `sdk=macosx`.

### WPD-8 — folder sync entitlements

`Kudos.entitlements` is the whole macOS Release set (`INJECT_BASE=NO`). It now declares only what shipped folder-sync code needs:

| Key | Why |
|---|---|
| `com.apple.security.app-sandbox` | already required |
| `com.apple.security.network.client` | already required (AO3) |
| `com.apple.security.files.bookmarks.app-scope` | `FolderSyncService.bookmarkData` / `resolveBookmarkData` use `.withSecurityScope` (`:560-564`, `:576-580`) |
| `com.apple.security.files.user-selected.read-write` | sync-up writes the user-selected folder (`writeIfChanged` `:828`, manifest `:797-799`, `removeItem` `:847`) |

`files.user-selected.read-only` was removed (read-write supersedes it). Release `ENABLE_USER_SELECTED_FILES` is `readwrite` (`project.pbxproj:623`). Debug is still `readonly` — see residuals.

No hardened-runtime exceptions (`cs.disable-library-validation`, `allow-unsigned-executable-memory`, `allow-jit`, `disable-executable-page-protection`) were added.

### WPD-1 — the guard reads the entitlements file

`Scripts/check-macos-release-entitlements.sh` parses `CODE_SIGN_ENTITLEMENTS[sdk=macosx*]` and opens that file. Writing `com.apple.security.get-task-allow` into `Kudos.entitlements` now fails. It also requires `app-sandbox`, the two folder-sync keys, and rejects HR exception entitlements.

### WPD-2 — the product assertion actually runs

Previously the only caller was dormant CI with no `$1`, and nothing in the repo built Release.

- `Scripts/verify.sh` step 4 runs the config half.
- `Scripts/build-macos.sh` runs the config half, keeps the Debug build, **builds Release**, then invokes the product half on `.build/release-macos/Build/Products/Release/Kudos.app`.
- `.github/workflows/ci.yml` still runs the config half (runners cannot build this SDK); the comment now says what that half actually checks.

`Scripts/check-invariants.sh` was **not** wired — that file is out of this unit's scope. Local DoD still hits the guard via `verify.sh` / `build-macos.sh`.

### WPD-4 — ad-hoc identity and HR-off overrides

The pbxproj half no longer matches a single literal.

- Any `CODE_SIGN_IDENTITY … = "-"` (qualified or not) fails. Unqualified `CODE_SIGN_IDENTITY = "-";` and `"CODE_SIGN_IDENTITY[sdk=macosx*]" = "-";` both fail.
- Any `ENABLE_HARDENED_RUNTIME … = NO;` fails, including `"ENABLE_HARDENED_RUNTIME[sdk=macosx*]" = NO;` sitting next to an inert `= YES`. The first regex used `[^=]*=`, which stopped at the `=` inside `[sdk=macosx*]` and let B2 through; it is now `.*= *NO;`.
- Missing `ENABLE_HARDENED_RUNTIME = YES` still fails.

### WPD-6 — `set -e` no longer skips product assertions

The codesign-details `grep` is `|| true`. Against an unsigned bundle the script still printed and evaluated:

- `FAIL: codesign -d --entitlements failed`
- `FAIL: Release product is missing com.apple.security.app-sandbox`
- `FAIL: … missing …bookmarks.app-scope`
- `FAIL: … missing …user-selected.read-write`
- `FAIL: Release product is missing the hardened-runtime flag`

### WPD-7 — no predictable `/tmp` path

Work goes to `mktemp -d "${TMPDIR:-/tmp}/kudos-macos-entitlements.XXXXXX"` with `trap cleanup EXIT INT HUP TERM`. After a clean run, `/tmp/kudos-macos-release-xcconfig.txt` does not exist.

### WPD-5 — confirmed present, not re-done

`AO3SessionVault.swift` was left untouched. On this RC tip:

| Invariant | Where |
|---|---|
| `updateItemAttributes` re-asserts `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` | `:157-161`, used from `save` at `:129` |
| `persistedCookieNames` allow-list at **install** | `AO3CookieBridge.install` `:334` → `persistableStoredCookies` `:383-384` |
| same allow-list at **capture** | `captureAO3Cookies` `:365-367` → `persistableCookies` `:374-379` |
| `isExcludedFromBackup` on directory **and** file after every save | `:220-221`, `:226-230` |

`grep -c 'updateItemAttributes\|persistableStoredCookies\|excludeFromBackup'` → **7** (review asked for ≥ 4).

---

## Mutation evidence

Production entry is `Scripts/check-macos-release-entitlements.sh` (what CI and `verify.sh` run) plus `KudosTests/EntitlementReleasePinTests`, which reads the live `project.pbxproj` / `Kudos.entitlements` and execs that script. Suite filter that actually runs cases: `-only-testing:KudosTests/EntitlementReleasePinTests`. A method-level filter matches **0** Swift Testing cases (same trap as `KudosTests/KudosBackupTests`).

### Guard script (config half) — quoted FAIL lines, non-zero duration

Clean tree, after the fix:

```
check-macos-release-entitlements: OK
real 0.06
exit=0
```

| Mutation | Expected | Actual (quoted) | Duration |
|---|---|---|---|
| WPD-1: add `com.apple.security.get-task-allow` to `Kudos.entitlements` | FAIL | `FAIL: kudos-ao3-reader/Kudos.entitlements declares com.apple.security.get-task-allow (Release is the whole set: INJECT_BASE=NO).` | **real 0.13** |
| WPD-4 B2: `"ENABLE_HARDENED_RUNTIME[sdk=macosx*]" = NO;` next to `= YES` | FAIL | `FAIL: Release has an ENABLE_HARDENED_RUNTIME override set to NO.` | **real 0.04** (after the `.*=` regex fix; first regex let this through — see above) |
| WPD-4 B1: unqualified `CODE_SIGN_IDENTITY = "-";` | FAIL | `FAIL: Release sets a CODE_SIGN_IDENTITY of "-" (ad-hoc), qualified or not.` | **real 0.29** |
| WPD-4: `"CODE_SIGN_IDENTITY[sdk=macosx*]" = "-";` | FAIL | same ad-hoc message | **real 0.04** |
| WPD-4: delete `ENABLE_HARDENED_RUNTIME = YES;` | FAIL | `FAIL: Release is missing ENABLE_HARDENED_RUNTIME = YES.` | **real 0.04** |
| WPD-3: unqualify both pins | FAIL | `FAIL: Release CODE_SIGN_INJECT_BASE_ENTITLEMENTS is not confined to [sdk=macosx*] (unqualified NO drops iOS Keychain entitlements).` plus four sibling FAILs for the missing qualified forms / unparseable path | **real 0.21** |
| WPD-8: drop bookmarks + revert read-write to read-only | FAIL | `FAIL: Release sets ENABLE_USER_SELECTED_FILES = readonly; …` and `FAIL: kudos-ao3-reader/Kudos.entitlements is missing com.apple.security.files.bookmarks.app-scope …` and `… missing …user-selected.read-write …` | **real 0.11** |
| WPD-6: unsigned `/tmp/WPDUnsigned.app` | FAIL, but **assertions still run** | sandbox / bookmarks / read-write / runtime FAILs printed after the details grep miss | **real 0.40** |
| WPD-7: clean run | no `/tmp/kudos-macos-release-xcconfig.txt` | `OK: /tmp/kudos-macos-release-xcconfig.txt does not exist after a clean run` | — |

Files were restored after each mutation (`diff` clean vs pre-mutation copies). Final re-run: `check-macos-release-entitlements: OK`.

### Swift suite — GREEN, then RED, then restored

**GREEN** (`/tmp/signing-ent-green.xcresult`, `xcrun xcresulttool get test-results summary`):

```
result: Passed
passedTests: 4
failedTests: 0
totalTestCount: 4
```

Swift Testing durations: `injectBase…` **0.013s**, `kudosEntitlements…` **0.001s**, `releaseConfig…` **0.004s**, `checkMacOSReleaseEntitlementsScriptAcceptsThisTree` **0.268s**.

**RED — get-task-allow in `Kudos.entitlements`** (`/tmp/signing-ent-red-get-task.xcresult`):

```
result: Failed
passedTests: 2
failedTests: 2
totalTestCount: 4
```

- `kudosEntitlementsCoverFolderSyncAndExcludeDebugger` **failed after 0.036 seconds**: `Expectation failed: (dict["com.apple.security.get-task-allow"] → 1) == nil: Release entitlements must not declare get-task-allow`
- `checkMacOSReleaseEntitlementsScriptAcceptsThisTree` **failed after 0.198 seconds**: `check-macos-release-entitlements.sh exited 1: FAIL: kudos-ao3-reader/Kudos.entitlements declares com.apple.security.get-task-allow (Release is the whole set: INJECT_BASE=NO).`

**RED — unqualify the pin (WPD-3 revert)** (`/tmp/signing-ent-red-unqual.xcresult`):

```
result: Failed
passedTests: 2
failedTests: 2
totalTestCount: 4
```

- `injectBaseAndEntitlementsPinAreMacOSQualified` **failed after 0.029 seconds**: `Release CODE_SIGN_ENTITLEMENTS must be sdk=macosx* qualified so iOS keeps Keychain entitlements`
- script test **failed after 0.196 seconds**, quoting `FAIL: Release CODE_SIGN_INJECT_BASE_ENTITLEMENTS is not confined to [sdk=macosx*] (unqualified NO drops iOS Keychain entitlements).`

**RED — qualified HR = NO (WPD-4 B2)** (`/tmp/signing-ent-red-hr.xcresult`):

```
result: Failed
passedTests: 2
failedTests: 2
totalTestCount: 4
```

- `releaseConfigKeepsHardenedRuntimeAndRejectsAdHocIdentity` **failed after 0.003 seconds**: `Release has an ENABLE_HARDENED_RUNTIME override set to NO`
- script test **failed after 0.084 seconds**, same FAIL line

None of those are 0.000s setup throws. Tree restored; guard OK.

---

## Gate results

### macOS build + product half — GREEN

`./Scripts/build-macos.sh` (Debug build + Release build + product dump):

- Config half: `check-macos-release-entitlements: OK`
- Debug `xcodebuild build -destination 'platform=macOS'`: **BUILD SUCCEEDED**
- Release `xcodebuild build -configuration Release -derivedDataPath .build/release-macos`: **BUILD SUCCEEDED**
- Product half against `.build/release-macos/Build/Products/Release/Kudos.app` (replayed after the commit, same output):

```
[Key] com.apple.security.app-sandbox              [Bool] true
[Key] com.apple.security.files.bookmarks.app-scope [Bool] true
[Key] com.apple.security.files.user-selected.read-write [Bool] true
[Key] com.apple.security.network.client           [Bool] true
Identifier=com.cidy02.Kudos
Format=app bundle with Mach-O thin (arm64)
CodeDirectory v=20500 size=89372 flags=0x10000(runtime) hashes=2782+7 location=embedded
Authority=Apple Development: yan.cid@icloud.com (<REDACTED-TEAM-ID>)
TeamIdentifier=NQH85H7343
check-macos-release-entitlements: OK
```

No `get-task-allow`. No `Signature=adhoc`. This is still an Apple Development sign, not Developer ID (G8).

### Entitlement Swift tests — GREEN (counts from xcresult)

`totalTestCount: 4`, `passedTests: 4`, `failedTests: 0`. Destination `platform=macOS`. `#if os(macOS)` so they do not run inside the iOS suite (they need the host checkout + the guard script).

### iOS `KudosBackupTests` — 43 passed / 1 failed / 44 ran (not a 0-count)

Command used (no `-sdk iphonesimulator`, specified UDID):

```
xcodebuild test \
  -project AO3_App_OpenSource.xcodeproj \
  -scheme AO3_App_OpenSource \
  -destination "id=B2D7F1A0-CAE2-44D9-8F65-C097264A1E32" \
  -only-testing:KudosTests/PersistenceGateSuites/KudosBackupTests \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath /tmp/dd-signing \
  -parallel-testing-enabled NO \
  -resultBundlePath /tmp/signing-ios-backup.xcresult
```

Simulator: iPhone 17e (`B2D7F1A0-…`), freshly booted. Filter was the nested path; **44** Swift Testing cases ran (not the 0-count trap).

The one failure, reproduced on three independent runs:

```
failedRestoreLeavesNoSwiftDataMutationsVisibleAfterCallerAutosave
Expectation failed: (restoreError?.code → 4) == 512
failed after 0.018 seconds   (also 0.026s on the cold run)
Test run with 44 tests in 2 suites failed after 0.717 seconds with 1 issue.
```

That test (`KudosBackupTests.swift:287`) forces a font write onto a path that is a directory and asserts Cocoa `NSFileWriteFailureError` (**512**). On this simulator `FileManager` surfaces **4** (`NSFileNoSuchFileError`) instead. The rest of the suite — including every tombstone / Merge / Replace / reconcile production-entry test — passed.

This is **not** caused by the signing pin:

- Tests run with `CODE_SIGNING_ALLOWED=NO`.
- The entitlements file is now macosx-qualified; iOS does not consume it.
- `Storage.fontsDirectory` is inside the app container, not a user-selected folder.
- I did not touch `KudosBackup.swift` or `KudosBackupTests.swift` (out of scope; another agent owns those files).

`xcodebuild` consistently hung after the Swift Testing run (WebContent leftover on this sim) and never finalized `/tmp/signing-ios-backup.xcresult` (`Info.plist` missing). Counts above are from the Swift Testing runner, which printed `44 tests` on every run — not from an exit code and not from a 0-count bundle. I am **not** claiming a 44/0 xcresult I do not have.

---

## G8 — still environmental

```
security find-identity -v -p codesigning
  1) … "Apple Development: yan.cid@icloud.com (<REDACTED-TEAM-ID>)"
  2) … "Apple Development: yan.cid@icloud.com (<REDACTED-TEAM-ID>)"
     2 valid identities found

security find-identity -v -p codesigning | grep -c "Developer ID Application"
0
```

On a machine that **has** a `Developer ID Application` identity, in order:

1. `xcodebuild archive -scheme AO3_App_OpenSource -configuration Release -destination 'platform=macOS'` and export with a `developer-id` `exportOptions.plist`.
2. `Scripts/check-macos-release-entitlements.sh /path/to/Kudos.app` must print OK and the dump must show `Authority=Developer ID Application`, `TeamIdentifier=NQH85H7343`, `flags=0x10000(runtime)`, **no** `Signature=adhoc`, entitlements containing `app-sandbox` + `bookmarks.app-scope` + `user-selected.read-write` and **not** `get-task-allow`.
3. `codesign --verify --deep --strict --verbose=2 Kudos.app`. Hardened runtime requires every nested Mach-O signed by the same team with the runtime flag; `Vendor/MuPDF.xcframework` is the likely first failure. Do **not** “fix” that with `com.apple.security.cs.disable-library-validation` or `.allow-unsigned-executable-memory` — the guard will now FAIL those. Re-sign the nested binaries instead.
4. `xcrun notarytool submit Kudos.zip --wait` → `Accepted`; `xcrun stapler staple Kudos.app`; `spctl -a -vvv -t install Kudos.app` → `accepted, source=Notarized Developer ID`.
5. iOS Release archive + export separately, to confirm WPD-3: iOS must still have `application-identifier` / `keychain-access-groups` and must **not** carry the macOS sandbox entitlements file.

---

## Not closed (honest)

| Item | Status |
|---|---|
| G8 Developer ID / notarization | Environmental. Signed off in the WP-D review. Verification list above. |
| `Scripts/check-invariants.sh` hook | Out of scope (review suggested it). Wired through `verify.sh` + `build-macos.sh` + `ci.yml` instead. |
| Debug `ENABLE_USER_SELECTED_FILES = readonly` (`project.pbxproj:564`) | Left as-is. Debug still injects Xcode-generated entitlements and is not the shipping config. A sandboxed macOS **Debug** folder-sync write can still fail; shipping is Release. |
| iOS `failedRestoreLeavesNoSwiftDataMutationsVisibleAfterCallerAutosave` 4 vs 512 | Out of scope (`KudosBackupTests.swift`). Pre-existing / simulator-specific Cocoa error-code assertion. 43/44 otherwise. |
| iOS xcresult `Info.plist` | `xcodebuild` hung after the runner finished on iPhone 17e; bundle never finalized. Counts from the Swift Testing log. |
| G3 / TOMB-6 iCloud KVS entitlement | Not this unit. The iOS log still prints `Unable to find entitlement for KVS store`. |
| iOS Release archive | Not run here. WPD-3 is the code fix; a real iOS Release export still needs to be done on a signing-capable machine to *see* Keychain entitlements in the product. |

---

## Residuals / notes for the next agent

- `EntitlementReleasePinTests` is `@Suite("Entitlement Release Pin")` at the top of `KudosTests`, macOS-only. The RC backup-only filter will not run it. Use `-only-testing:KudosTests/EntitlementReleasePinTests`.
- Do not revert the `[sdk=macosx*]` qualifiers to “make iOS Release pick up the entitlements file.” That is the WPD-3 bug.
- If notarization fails on MuPDF/Readium, re-sign nested binaries. Adding a `cs.*` exception will fail the guard on purpose.
