# D9b — Android keysync v1 pairing UI

**Branch:** `android/keysync-pairing-ui`, based on `security-fixes/tombstone-trust` @ `1369d4d`
("handoff: RC READY — all gates green (iOS 1111/1111, Android 854/0/0, lint 0, invariants OK, macOS build OK)").
**Scope:** UI + trust-store plumbing only, as instructed. No sync-service work (delete-time
signing, merge/reconcile verification, key lifecycle across devices) was touched beyond the
minimal counter needed to feed the count-only badge (see §4).
**Not pushed, no PR, as instructed.**

## 0. Where this actually lives (read this first)

The prompt described this worktree as already containing `TombstoneTrustStore` (DataStore-backed)
and pointed at `android/app/build.gradle.kts` "as of this branch." Neither was true of the branch
this worktree started on (`android/mupdf-engine`, and before that the ambient checkout had no
`android/` directory at all — that lineage is iOS-only). The actual `TombstoneTrustStore` /
`TombstoneSigning` / Phase 1+2 tombstone-trust work the prompt is describing lives on
`security-fixes/tombstone-trust`, a sibling worktree's branch (`/Users/cidy02/kudos-fix-tombstone`,
per `git worktree list`) — the "D9(a)-equivalent Android work" the prompt asked me to check for.

Since that branch was checked out elsewhere, I could not `git checkout` it directly. I created a
**new** local branch `android/keysync-pairing-ui` pointing at the same commit
(`git checkout -b android/keysync-pairing-ui security-fixes/tombstone-trust`) and built this unit
on top of it, in this isolated worktree, without touching the other worktree. This gives an
accurate base to extend and keeps this unit mergeable back into the real security-fixes lineage
rather than silently reinventing Phase 1/2 crypto that already exists and is already reviewed.

## 1. TombstoneTrustStore's actual API, confirmed before extending

`android/app/src/main/java/io/github/cidy02/kudos/backup/TombstoneTrustStore.kt` (pre-existing,
Phase 2 crypto work, DataStore-backed via `SettingsRepository`):

- `suspend fun trust(hex: String): Boolean`
- `suspend fun isTrusted(hex: String): Boolean`
- `suspend fun trustedPublicKeys(): Set<String>`

**No `remove`/`revoke` existed.** No per-key metadata (label, trusted-at timestamp) existed —
`TrustedTombstonePublicKeys` was a bare `Set<String>` in `SettingsRepository`. No denylist existed.
This unit adds all of that; see §2.

## 2. Trust-store plumbing added

`android/app/src/main/java/io/github/cidy02/kudos/backup/TombstoneTrustStore.kt`

| Line | What |
|---|---|
| 9–13 | `enum class KeyRevocationReason { STOLEN_OR_COMPROMISED, RETIRED_OR_SOLD }` |
| 15–19 | `data class TrustedDevice(publicKeyHex, label, trustedAt)` — UI-facing, local label only |
| 42–60 | `trust(hex, label = "")` — now refuses the device's own key and any denylisted (revoked-as-stolen) key; records a `TrustedDeviceRecord` (label + trusted-at) alongside the existing `Set<String>` trust flag |
| 68–79 | `trustedDevices(): List<TrustedDevice>` — newest-trusted-first, for the "Trusted Devices" list |
| 81–84 | `rename(hex, label)` — the *only* way a label is ever set after initial trust; never called from any wire/file path |
| 93–107 | `revoke(hex, reason)` — removes trust; `STOLEN_OR_COMPROMISED` additionally denylists the key (see §3) |
| 109–119 | `undoTrust(hex, now, window = 24h)` — reverts to untrusted only inside the 24h window, does **not** denylist |
| 121–123 | `unknownSignerCount()` — count-only badge source (§4) |

`android/app/src/main/java/io/github/cidy02/kudos/data/preferences/SettingsRepository.kt`

| Line | What |
|---|---|
| 26–37 | `@Serializable data class TrustedDeviceRecord(publicKeyHex, label, trustedAtEpochMs)` |
| 39–50 | JSON encode/decode helpers, `kotlinx.serialization.json.Json` (already a project dependency — `implementation(libs.kotlinx.serialization.json)`, `android/app/build.gradle.kts:118`; no new JSON dependency added) |
| 241–247 | `untrustTombstonePublicKey(hex)` — did not exist before |
| 255–292 | `trustedTombstoneDeviceRecords` flow + snapshot/upsert/remove/rename over the new metadata |
| 295–309 | `revokedTombstonePublicKeys` flow + snapshot/add — the denylist |
| 316–330 | `unknownSignerTombstoneIds` flow + snapshot/record — self-healing pending set for the badge |
| 446–448 | Three new DataStore keys: `trustedTombstoneDeviceRecords` (string/JSON), `revokedTombstonePublicKeys` (string set), `unknownSignerTombstoneIds` (string set) |

The pre-existing `TrustedTombstonePublicKeys: Set<String>` key — the one
`BackupMergeService`/`BackupRepository` actually gate tombstone adoption on — is **untouched**
in shape or semantics. Everything above is additive metadata beside it, so Phase 1/2 merge
behavior (and its existing tests, `BackupTrustPhase1Test`, `BackupTrustPhase2Test`,
`TombstoneSigningTest`) did not need to change.

## 3. Revoke: ask why, and the D9(a)-equivalent denylist

Checked first, per instructions: no revoke-denylist (or any revoke path at all) existed anywhere
in the Android trust store before this unit — so there was nothing to reuse from a prior D9(a)
pass. I built it as part of this unit's own scope (`TombstoneTrustStore.kt:93–107`,
`SettingsRepository.kt:295–309`):

- **"Stolen or compromised"** (default/pre-selected — `PairingSheet.kt:407–410`, `RadioButton`
  selected by default) removes trust **and** adds the key to `revokedTombstonePublicKeys`.
  `trust()` checks that set first (`TombstoneTrustStore.kt:44`) and refuses to re-add it — a
  re-paste of the exact same key can never silently re-trust it. Covered by
  `TombstoneTrustStorePairingTest.revokeStolenDenylistsTheKeySoItCanNeverBeReTrusted`.
- **"Retired or sold"** removes trust without denylisting — the same key can be paired again
  later (e.g. the device was reset and handed to someone else). Covered by
  `TombstoneTrustStorePairingTest.revokeRetiredRemovesTrustButAllowsReTrusting`.

**Restore rows that key was responsible for.** The per-record "deleted by this key" provenance
field already exists — `SyncTombstoneEntity.signerPublicKey`
(`android/app/src/main/java/io/github/cidy02/kudos/data/local/entity/SyncTombstoneEntity.kt`,
also `deletedOnDeviceID` on the same row, and on the domain model
`core/model/SyncModels.kt:89–91`). I used `signerPublicKey` (the real Phase 2 cryptographic
identity) rather than `deletedOnDeviceID` (a weaker, pre-crypto per-device string) since it's the
field the task description pointed at ("signer tracking") and the one that can't be spoofed.

New, minimal:
- `SyncTombstoneDao.getBySigner(signerPublicKey, recordType)` —
  `data/local/dao/SyncTombstoneDao.kt` (new query, ~5 lines).
- `KeyRevocationService` (new file,
  `android/app/src/main/java/io/github/cidy02/kudos/backup/KeyRevocationService.kt`) —
  `worksDeletedByCount(hex)` for the "Restore N work(s)?" prompt, `revoke(hex, reason)` delegating
  to the trust store, `restoreWorksDeletedBy(hex)` which calls the **existing**
  `WorkRepository.restoreFromRecentlyDeleted(recordId)` (`WorkRepository.kt:226`, unmodified) for
  every matching row — that method already both undeletes the work and retracts its tombstone, so
  no new undelete logic was written.

Best-effort by design: a row already past its Recently-Deleted recovery window (permanently
swept) has nothing left to restore — `restoreFromRecentlyDeleted` returns `null` for it and it's
silently skipped, counted correctly (0 restored) rather than erroring.

Covered by `KeyRevocationServiceTest` (3 tests): count query, stolen-revoke-then-restore
round trip including tombstone retraction, retired-revoke still reports the count without the UI
offering restore (the UI, not the service, decides whether to show the prompt based on reason —
`PairingSheet.kt:186–196`).

## 4. Count-only unknown-signer badge

Found the shouldAdopt/TombstoneIndex-equivalent: `BackupMergeService.merge()`
(`android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt:56–66`) — the
loop that already does `if (!TombstoneSigning.verify(incoming)) return@forEach` then
`if (!TombstoneSigning.isTrustedSigner(...)) return@forEach`. Before this unit, the untrusted
branch just silently dropped the tombstone with nothing counted anywhere.

Minimal surfacing (not new sync-service logic — the check already existed, this only records its
outcome):

- `BackupMergeService.kt:60,65`: collect dropped ids into `unknownSignerIds` in the existing loop.
- `BackupMergeService.kt:322–324` / `KudosBackup.kt:97–100`: two new fields on
  `BackupMergeResult` — `unknownSignerTombstoneIds` (dropped this run) and
  `adoptedIncomingTombstoneIds` (adopted this run, i.e. signer *is* trusted).
- `BackupRepository.kt:118–123` (`mergePackage`, the single choke point both
  `importV2ZipBytes` and `importPackage` go through): persists via
  `settingsRepository.recordUnknownSignerTombstoneIds(newIds, adoptedIds)` — a union-then-remove
  op (`SettingsRepository.kt:326–330`), not an accumulating counter, so it self-heals: once a
  signer becomes trusted and a later sync/import adopts that tombstone, its id drops out of the
  pending set on its own. Covered by
  `BackupTrustPhase2Test.importPackageRecordsUnknownSignerTombstoneIdForTheCountOnlyBadge` and
  `...ClearsUnknownSignerIdOnceSignerBecomesTrusted`.

UI: `PairingCard` in `PairingSheet.kt:99–110` — an `AssistChip` showing only a count
("N deletions skipped from an unpaired device"), no key list, no names, no Trust affordance. Its
only `onClick` opens the same pairing sheet (`showSheet = true`).

## 5. Pairing sheet UI

All new: `android/app/src/main/java/io/github/cidy02/kudos/backup/PairingSheet.kt`.

- `PairingCard` (line 57) — entry point card in the Backup screen: the badge (§4), the trusted-
  devices list, "Pair a device" button.
- `PairingBottomSheet` (line 254, `@OptIn(ExperimentalMaterial3Api::class)`) — the actual sheet:
  - **"Show my QR code"** (primary) — generates and displays a QR of
    `PairingKeyCodec.encode(TombstoneSigning.publicKeyHex())`, i.e. `kudos-pub-v1:<64-hex>`.
  - **"Copy Key"** (secondary) — clipboard, same prefixed string.
  - **Advanced** disclosure — manual paste field + checkbox ("I got this key from my other
    device") gating the Trust button via `PairingTrustGate.canTrust` (§6) — the button is
    `enabled = PairingTrustGate.canTrust(pasteText, confirmedFromOwnDevice)`
    (`PairingSheet.kt:356`).
  - After a successful trust, a **blank** "Name this device" field — never pre-filled from the QR
    payload or pasted text (`PairingSheet.kt:365–383`). This is the "never render a name that
    arrived over any wire/file" requirement: there is no name field anywhere in the QR/paste
    payload to begin with (`PairingKeyCodec` only ever carries the hex key), and the label the UI
    writes always originates from this local text field.
- `TrustedDeviceRow` (line 192) — label (or "Unnamed device"), short fingerprint, Rename, and
  either **Undo Trust** (within 24h of `trustedAt`) or **Revoke** (after).
- `RevokeDeviceDialog` (line 404) — reason radio buttons, "Stolen or compromised" pre-selected.

Replaced the old bare-bones `TrustedDevicesCard` (raw hex paste, no checkbox gate, no naming, no
revoke, no undo — `BackupScreen.kt`, deleted ~95 lines) with `PairingCard`. Call site updated at
`BackupScreen.kt:281–285`; `BackupScreen` now takes `database`/`workRepository` params (needed by
`KeyRevocationService`), threaded from `AppNavHost.kt:689–695` via the existing
`KudosAppContainer`.

## 6. The mutation-test target: checkbox-gates-trust

`PairingTrustGate.canTrust` (`PairingKeyCodec.kt:37–39`) is the guard: the Trust button must stay
disabled until the user has **both** pasted a recognizable key **and** checked the confirmation
box. This is the primary example the task named, and the clearest single guard central to this
unit's contract, so it's the one I ran the mutation against.

**RED (guard reverted):**

```kotlin
fun canTrust(pastedText: String, confirmedFromOwnDevice: Boolean): Boolean {
    // MUTATION: guard removed for D9b mutation-test evidence.
    return PairingKeyCodec.decode(pastedText) != null   // dropped `confirmedFromOwnDevice &&`
}
```

```
PairingKeyCodecTest > canTrustIsFalseWhenCheckboxIsUncheckedEvenWithAValidKey FAILED
    java.lang.AssertionError at PairingKeyCodecTest.kt:66
11 tests completed, 1 failed
BUILD FAILED
```

From the JUnit XML (`TEST-io.github.cidy02.kudos.backup.PairingKeyCodecTest.xml`):
`<failure message="java.lang.AssertionError" type="java.lang.AssertionError">` at
`PairingKeyCodecTest.canTrustIsFalseWhenCheckboxIsUncheckedEvenWithAValidKey(PairingKeyCodecTest.kt:66)`,
`time="0.0"` on the failing case (non-zero-duration suite run: `time="0.021"` total) — a real
assertion failure, not a build/compile error.

**Guard reverted back**, then GREEN (below).

I also directly tested `revoke-denylist-prevents-readd`
(`TombstoneTrustStorePairingTest.revokeStolenDenylistsTheKeySoItCanNeverBeReTrusted`) as a second
real guard, but did not run a formal mutation pass against it — one documented mutation target
was the ask; I judged the checkbox gate the more load-bearing one to spend the RED/GREEN cycle on
since it's the primary example given.

## 7. Manual-verification-only (not faked as tests)

QR/camera UI cannot be meaningfully unit tested — noted here rather than faked:

- The rendered QR image inside `PairingBottomSheet` (`Image(bitmap = ...)`) — visual correctness
  of what's on screen, and that it's actually scannable by a phone camera at real-world
  distance/lighting, needs a device. What **is** tested (`QrCodeGeneratorTest`) is the encoding
  itself: `QrCodeGenerator.encode(payload)` produces a bitmap that zxing's own `QRCodeReader`
  decodes back to the exact original `kudos-pub-v1:<hex>` string — a real, independent round-trip
  check of the data transformation, not the on-screen rendering.
- **The actual cross-device pairing** — scanning this device's QR from an iOS device running the
  sibling scan unit, confirming the same hex arrives, confirming the checkbox/Trust flow end to
  end on a real Android device. I have no iOS scan unit to pair against in this environment.
- Bottom sheet visual layout, dark/light theme, the Revoke dialog, the Undo Trust window actually
  showing/hiding at the 24h boundary on a real clock — all manual/simulator spot-checks, not unit
  tested.
- Clipboard "Copy Key" actually landing on the system clipboard (Compose's `LocalClipboardManager`
  is exercised the same way the pre-existing `TrustedDevicesCard` used it — pattern reused, not
  newly invented — but not re-verified on-device here).

## 8. QR-generation dependency decision

**Added `com.google.zxing:core:3.5.4`** (`implementation`, `android/app/build.gradle.kts:121-125`;
version catalog entry `android/gradle/libs.versions.toml`).

Why a real dependency, and why this one:

- Checked rung 4/5 first (native platform feature, already-installed dependency). Android has no
  built-in QR generator in the framework. The project's other dependencies (Tink, Coil, OkHttp,
  Room, Readium, kotlinx.serialization) don't transitively carry a QR encoder — checked the
  existing `implementation(...)` list in `build.gradle.kts` before adding anything.
  `com.google.zxing:core` was not present, matching the task's own pre-check
  ("no zxing/mlkit/camera in `android/app/build.gradle.kts` as of this branch" — confirmed true
  on `security-fixes/tombstone-trust` too, the actual base).
- Considered hand-rolling a dependency-free pure-Kotlin QR encoder. Rejected: correct QR encoding
  requires Reed–Solomon error-correction coding and precise matrix/mask placement per the ISO spec
  — real room for a subtle bug that produces a QR image that *looks* plausible but a scanner can't
  actually decode, with no independent way to verify it inside this codebase (no scanner here to
  test against). That risk is exactly wrong for a security-adjacent pairing flow.
- **`com.google.zxing:core` is the smallest available justified choice**: zero transitive
  dependencies, pure Java, no Android-specific code, no camera/scanning integration
  (`zxing-android-embedded`, `mlkit-barcode-scanning`, and similar full-scanning-suite artifacts
  were deliberately **not** added). Only `QRCodeWriter` (encode path) is used in
  `QrCodeGenerator.kt`; the project's own test (`QrCodeGeneratorTest`) happens to also use
  zxing's `QRCodeReader` to independently verify the encoder's output, but that's test-only
  usage of a library already on the classpath, not a runtime scanning feature.
- Android's pairing role stays QR-**generate**-only per the design discussion — no camera
  permission, no `CameraX`/`ML Kit` dependency, confirmed absent from `AndroidManifest.xml`
  before and after this change.

## 9. Gate results

Run from this worktree (`/Users/cidy02/Documents/AO3_App_OpenSource/.claude/worktrees/wf_c02e49a5-636-2`),
`JAVA_HOME=.../Android Studio.app/.../jbr`, `ANDROID_HOME=$HOME/Library/Android/sdk`:

| Gate | Result |
|---|---|
| `Scripts/check-invariants.sh` | `check-invariants: OK` |
| `:app:compileDebugKotlin` | `BUILD SUCCESSFUL` |
| `:app:compileDebugUnitTestKotlin` | `BUILD SUCCESSFUL` |
| `:app:assembleDebug` | `BUILD SUCCESSFUL in 2m 50s` (real APK, no manifest/dependency conflicts) |
| Mutation RED (`canTrust`, guard removed) | `PairingKeyCodecTest`: 1 failed / 11, real `AssertionError`, non-zero duration — see §6 |
| Mutation GREEN (guard restored) | `PairingKeyCodecTest`: 11/11 |
| **Full `:app:testDebugUnitTest`, GREEN last** | **841 tests, 0 failures, 0 errors, 0 skipped, across 228 suite files** (tallied from the JUnit XML in `android/app/build/test-results/testDebugUnitTest`, per this project's convention — not Gradle's summary line) |

Per-suite counts for every file touched or added this unit (from the same JUnit XML):

| Suite | Tests | Failures |
|---|---|---|
| `PairingKeyCodecTest` (new) | 11 | 0 |
| `TombstoneTrustStorePairingTest` (new) | 9 | 0 |
| `QrCodeGeneratorTest` (new) | 2 | 0 |
| `KeyRevocationServiceTest` (new) | 3 | 0 |
| `BackupTrustPhase2Test` (extended, +2) | 9 | 0 |
| `BackupTrustPhase1Test` (unmodified, re-run as a regression check) | 16 | 0 |
| `TombstoneSigningTest` (unmodified, re-run as a regression check) | 4 | 0 |

Note on the "854" figure in `security-fixes/tombstone-trust`'s handoff.md ("RC READY... Android
854/0/0"): that number reflects that branch's own state at the moment it was written, which
includes review-cycle work not present at the commit this branch forked from (five parallel
Grok agents' fixes were still pending merge into RC per that handoff — task #31 in this session's
list). 841 here is this branch's own true count with this unit's tests added (814 baseline + 27
new: 11+9+2+3 new suites, +2 added to `BackupTrustPhase2Test`). The two numbers describe different
branch snapshots, not a discrepancy to reconcile — reconciling the branches is outside this
unit's scope.

## 10. Non-negotiable invariant re-checked

`grep -n "\.trust(" BackupMergeService.kt BackupRepository.kt SyncRepository.kt
FolderSyncWorker.kt` — no matches. Nothing added by this unit calls `TombstoneTrustStore.trust()`
from any merge/import/sync path. The only callers of `trust()` are the pairing sheet's Trust
button (`PairingSheet.kt:349`, gated by §6) and test code. A `.kudosbackup` file, ZIP, or sync
folder still cannot add a trusted key — confirmed unchanged, not just asserted.

## 11. Files touched

**New:**
- `android/app/src/main/java/io/github/cidy02/kudos/backup/PairingKeyCodec.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/QrCodeGenerator.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/KeyRevocationService.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/PairingSheet.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/backup/PairingKeyCodecTest.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/backup/TombstoneTrustStorePairingTest.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/backup/QrCodeGeneratorTest.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/backup/KeyRevocationServiceTest.kt`

**Modified:**
- `android/app/src/main/java/io/github/cidy02/kudos/backup/TombstoneTrustStore.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/data/preferences/SettingsRepository.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupRepository.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/KudosBackup.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/data/local/dao/SyncTombstoneDao.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupScreen.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/app/AppNavHost.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/backup/BackupTrustPhase2Test.kt`
- `android/app/build.gradle.kts`, `android/gradle/libs.versions.toml`
