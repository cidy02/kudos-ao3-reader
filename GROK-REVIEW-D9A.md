# Grok review of D9(a) — tombstone trust store → Keychain

**Against:** `/Users/cidy02/kudos-fix-tombstone/D9A-KEYCHAIN-SPEC.md`  
**Commit reviewed:** `8a36f29` (`D9(a): move the tombstone trust store from UserDefaults to Keychain`)  
**Tree:** `/Users/cidy02/kudos-d9a-keychain` on `d9a-keychain`  
**Reviewer:** Grok 4.6 (did not author `8a36f29`)  
**Date:** 2026-08-16

This is an adversarial second opinion, not a rubber stamp. The five numbered points below are verdicts on **`8a36f29` as committed**. Point 4 was a real reopen of the vulnerability the fix exists to close. That is fixed in a follow-up commit on this branch; post-fix state is noted under each point and in **After this review**.

---

## Overall

| | Verdict |
|---|---|
| `8a36f29` as committed | **BLOCK** — `loadKeys()` re-imports whatever is in the UserDefaults plist on every launch that finds the key present. That is the original same-user write-vector, still live after "migration." |
| After the follow-up on this branch | **SHIP** the storage-layer change. |

The rest of `8a36f29` is the right shape: same Keychain class/accessibility/service as the private key, distinct account (`trusted-tombstone-pubs`), single JSON item, `remove(_:)` + `removeFromiCloud`, test injectability, no Android, no Settings/KVS-protocol redesign. The entitlement-missing test bug they found (`errSecMissingEntitlement` / `-34018`) is real; rejecting a production file fallback was the right call.

---

## 1. Does `keychainOverride` stay test-only?

**Verdict on `8a36f29`: FIX**  
**After follow-up: SHIP**

### Production setters: none

Every assignment of `keychainOverride` in `8a36f29` is in `KudosTests/TombstoneTrustStoreTests.swift` (`init` line 15; `testOutOfBandWriteIsReflected` line 64).

Production callers of the store, none of which touch the override:

| Site | What it does |
|---|---|
| `TombstoneSigning.sign` (`TombstoneSigning.swift:101`) | `add(pub, defaults:)` for the device key |
| `TombstoneSigning.shouldAdopt` (`TombstoneSigning.swift:131`) | `isTrusted` only |
| `SettingsView.swift:1285` | `add(trimmed)` from the paste field |
| `SettingsView.swift:1306` | `add(publicKeyHex())` on appear |
| `KudosBackup.swift:1607` | `shouldAdopt` only — never writes the store |

`KudosBackupTests` only calls `add`/`isTrusted` with an **injected** `UserDefaults` (`KudosBackupTests.swift:1957, 2018, 2115, 2121, 2196`). That path is `defaults !== UserDefaults.standard` and never consults Keychain or the override.

### Why it was still FIX, not SHIP

`keychainOverride` was an unrestricted `static var Set<String>?` on the app module (`8a36f29` `TombstoneSigning.swift:293`). Same pattern as `TombstoneSigning.keyOverride` (`TombstoneSigning.swift:14`). Any same-module file — Settings, a future pairing sheet, a leftover debug line — could assign it and silently move the authorization list into process memory. Release did not compile it out.

The suite also leaked the override: `init()` set it to `[]` and `testOutOfBandWriteIsReflected` left it as `{eeee…}`. There is no teardown. With `Scripts/test.sh` disabling parallel testing, a later suite that used `UserDefaults.standard` would have read that leftover set instead of Keychain.

### What I changed

- Wrapped the override in `#if DEBUG`, matching `Storage.fontsDirectoryOverride` (`Storage.swift:27–39`).
- Replaced the bare `Set<String>?` with a tri-state `KeychainOverride` (`absent` / `stored` / `unavailable`) so tests can tell "no item" from "empty item" — required for the point-4 fix.
- Added `KeychainOverrideReset` so each test clears the process-wide hook.

Debug app builds still contain the hook (tests need it). Release does not.

---

## 2. Was rejecting a production file-fallback the right call?

**Verdict: SHIP** (agree with the commit message)

A file next to `tombstone-ed25519.key` (`TombstoneSigning.swift:217–234`) is the same-user-writable path the private key already uses when Keychain returns `errSecMissingEntitlement` / `errSecNotAvailable`. For the *private* key that is a liveness fallback (this device must still be able to sign). For the *trust list* it is the authorization set — exactly the secret `8a36f29` is moving off the plist.

A disk fallback would reopen the vulnerability the moment Keychain failed for any reason, entitlement or otherwise. I agree there is no safe production file fallback.

Safer middle ground, which is **not** a file fallback:

1. Fail closed when Keychain is unavailable (own device key still trusted via `isTrusted`; peers are not).
2. Do **not** destroy the UserDefaults source until a Keychain persist actually succeeds.
3. Once a Keychain item exists — including an empty sentinel planted on first launch — never import UserDefaults again; just strip the plist so it cannot be a write-vector.

`8a36f29` did (1) implicitly (a failed `SecItemAdd` was ignored and the next load returned `[]`) but violated (2) and (3). That is point 4.

I did **not** add a file fallback.

---

## 3. Is the `iCloudStore` default change (`nil` instead of `.default`) safe?

**Verdict on `8a36f29`: SHIP** (behavior) / **FIX** (observer latch — addressed)

### Nothing in production depends on it being non-nil

`iCloudStore` is only referenced inside `TombstoneTrustStore` (`TombstoneSigning.swift`). Every KVS helper already no-ops when it is nil:

- `refreshFromiCloudIfNeeded` — `guard … let store = iCloudStore else { return }`
- `mergeFromiCloud` — same
- `publishToiCloud` — same
- `removeFromiCloud` — same

`KudosBackup.swift` never reads `iCloudStore`. It only asks `TombstoneSigning.shouldAdopt` (`KudosBackup.swift:1607`), which is local-store `isTrusted`.

`SettingsView.swift` never reads `iCloudStore`. The deletion-signing footer (`SettingsView.swift:1301–1303`) still says other devices on the same Apple ID pick the key up automatically. That copy is now aspirational until D9(b) assigns `.default` and adds the entitlement. The spec forbade touching Settings in this unit; leaving the footer is correct.

No other Swift file references `iCloudStore`.

The default change is also load-bearing for the Keychain work: constructing `NSUbiquitousKeyValueStore.default` without `com.apple.developer.ubiquity-kvstore-identifier` (this build's `Kudos.entitlements` does not have it) logs `BUG IN CLIENT OF KVS` and, per the commit, poisons in-process `SecItem*` calls. The `8a36f29` comment around that was garbled (two drafts concatenated at `TombstoneSigning.swift:263–273`); I rewrote it.

### Latent D9(b) footgun (fixed)

`registerObserverIfNeeded` (`8a36f29` `TombstoneSigning.swift:440–452`) set `didRegisterObserver = true` and registered with `object: iCloudStore` even when the store was nil. `NotificationCenter` with a nil object observes **every** poster of that name. D9(b) assigning `.default` later would find the latch already set and would not re-register against the real store.

Follow-up: skip registration and do not latch while `iCloudStore == nil`.

---

## 4. Diff correctness

**Verdict on `8a36f29`: BLOCK**  
**After follow-up: SHIP**

### BLOCK — migration is a permanent UserDefaults write-vector

`8a36f29` `TombstoneSigning.swift:371–376`:

```swift
if let legacy = defaults.stringArray(forKey: localKeysKey) {
    var keys = loadKeychainKeys() ?? []
    keys.formUnion(legacy.compactMap(normalizedPublicKey))
    saveKeychainKeys(keys)
    defaults.removeObject(forKey: localKeysKey)
    return keys
}
```

This is not a one-time migrate-then-forget. Whenever `trustedTombstonePublicKeys` is present in `UserDefaults.standard`, its contents are **unioned into Keychain**.

Concrete failure (the original threat model):

1. App launches after `8a36f29`. Keychain item exists (or is empty). UserDefaults key is gone.
2. An unsandboxed process running as the same user writes a forged 64-hex pub into `~/Library/Containers/…/Preferences/*.plist` under `trustedTombstonePublicKeys`.
3. Next `loadKeys()` sees the "legacy" array, unions it into Keychain, clears the plist.
4. Every subsequent forged tombstone signed by the matching private key verifies as trusted. Pairing, QR, and signature checks never run.

Same hole on a device that never paired: first launch plants nothing in Keychain (`8a36f29` `TombstoneSigning.swift:379` — `return loadKeychainKeys() ?? []` does not create an item). An attacker-seeded plist on the *next* launch is imported as a "first" migration.

The spec said: migrate existing installs, then clear the plist so it no longer carries the list. It did not say "treat every future plist write as a migration."

Also: `saveKeychainKeys` ignored every `OSStatus` except `errSecDuplicateItem` (`8a36f29` `TombstoneSigning.swift:353–361`). A failed persist still ran `defaults.removeObject`. Next launch: no plist, no Keychain item, trusted peer keys gone.

### FIX — `normalizedPublicKey` was not applied on the Keychain read path

`add` / `remove` / `isTrusted` / the UserDefaults branch / iCloud merge all go through `normalizedPublicKey`. `loadKeychainKeys` (`8a36f29` `TombstoneSigning.swift:342`) returned `Set(array)` raw. An uppercase or garbage string in the JSON item would sit in `trustedPublicKeys()` forever; `isTrusted` lowercases the query and would miss an uppercase stored key.

Follow-up: `compactMap(normalizedPublicKey)` on every Keychain read, including the override. Corrupt JSON is treated as `.found([])` (fail closed) rather than `.notFound` (which would re-import the plist).

### SHIP — `remove()` + iCloud publish side

`remove` (`8a36f29` `TombstoneSigning.swift:317–327`) normalizes, drops from the local set, `saveKeys`, then `removeFromiCloud` (`432–438`). `removeFromiCloud` normalizes the published KVS array, removes that one key, writes the remainder. It does **not** republish the whole local set via `publishToiCloud` (which is a `formUnion` and would not delete).

While `iCloudStore` is nil this is a no-op, which is correct for D9(a). When D9(b) turns KVS on, a *remote* device that still has the key can union it back — that is the revoke-aware merge the spec deferred. Not a defect in this unit.

`add` still returns `true` for an already-present valid key (`TombstoneSigning.swift:310–319`). Pre-existing; spec said do not silently change it. Invalid input still returns `false`. Preserved.

### FIX — add / migrate race

`8a36f29` had an `NSLock` used only by `registerObserverIfNeeded`. `add`/`remove`/`loadKeys`/`saveKeys` were unlocked read-modify-write on a single Keychain item. Concurrent `add` + first-launch migration could drop a key (last writer wins). Same class of race as the old UserDefaults code; cheaper to close now that the item is one JSON blob.

Follow-up: `NSRecursiveLock` held across the load-modify-save in `add` / `remove` / `mergeFromiCloud` / `loadKeys` / `saveKeys`.

---

## 5. Tests I actually ran

**Verdict: SHIP** — the commit's claimed GREEN is real. I do not trust the commit message for this; I ran the suite myself.

Destination: booted `iPhone 17` / iOS 26.5, UDID `77492544-056E-4D4A-ABB6-7E38CC042A4D` (`xcrun simctl list devices` — this one was already Booted). `xcode-select -p` → `/Applications/Xcode.app/Contents/Developer`. `CODE_SIGNING_ALLOWED=NO`, `-parallel-testing-enabled NO`, derived data `/tmp/dd-d9a-review`.

`KudosBackupTests` is nested under `PersistenceGateSuites`. Filtering `KudosTests/KudosBackupTests` is the 0-count trap; I used `KudosTests/PersistenceGateSuites/KudosBackupTests`.

### `8a36f29` as committed (before my edits)

```
xcodebuild test \
  -project AO3_App_OpenSource.xcodeproj \
  -scheme AO3_App_OpenSource \
  -destination "id=77492544-056E-4D4A-ABB6-7E38CC042A4D" \
  -only-testing:KudosTests/TombstoneTrustStoreTests \
  -only-testing:KudosTests/PersistenceGateSuites/KudosBackupTests \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath /tmp/dd-d9a-review \
  -parallel-testing-enabled NO \
  -resultBundlePath /tmp/d9a-review-original.xcresult
```

**TEST SUCCEEDED.** `Test run with 55 tests in 3 suites passed after 0.673 seconds.`

- `TombstoneTrustStoreTests` **4/4**
- `KudosBackupTests` **51/51** (matches the commit's 51/51 claim)

TombstoneTrustStore-dependent backup cases, all passed on this run:

- `trustedSignedIncomingTombstoneIsAdoptedAndSuppressesWork`
- `trustedSignedTombstoneForgedLastModifiedAtCannotPermanentlySuppressWork`
- `untrustedButValidSignedTombstoneIsDropped`
- `forgedSignatureOnTrustedKeyIsDropped`
- `restoreDoesNotAddIncomingSignerPublicKeyToTrustStore`

### After the follow-up

Same command, result bundle `/tmp/d9a-review-fixed.xcresult`.

**TEST SUCCEEDED.** `Test run with 59 tests in 3 suites passed after 0.715 seconds.`

- `TombstoneTrustStoreTests` **8/8** (4 original + 4 new)
- `KudosBackupTests` **51/51**

New cases (the ones that go RED if point 4 is reverted):

- `testUserDefaultsWriteAfterKeychainItemExistsIsIgnored`
- `testEmptyFirstLaunchPlantsSentinelAndIgnoresLaterUserDefaults`
- `testUnavailableKeychainDoesNotWipeUserDefaults`
- `testNormalizedPublicKeyAppliedOnEveryPath`

`Scripts/lint.sh` exit 0. No new findings in `TombstoneSigning.swift` (the `payload(…)` parameter-count warning at line 48 is pre-existing). `git diff --check` clean.

Not run (out of the requested scope): full `Scripts/verify.sh`, macOS build, device Keychain on a signed build.

---

## After this review

Follow-up on this branch (same worktree, not pushed):

- Keychain item (including empty) is source of truth; later UserDefaults writes are stripped, never imported.
- UserDefaults is removed only after a successful persist.
- Keychain unavailable → fail closed, leave the plist for a later real migration.
- `normalizedPublicKey` on every Keychain read.
- `keychainOverride` is `#if DEBUG` + tri-state; tests reset it.
- Recursive lock around the RMW.
- KVS observer is not latched while `iCloudStore` is nil.

### Still true, not in this unit

- KVS merge is still union-only. Revoke-aware merge is D9(b).
- `add` still returns `true` for an already-trusted valid key. Settings treats a `false` as "bad hex"; I did not change the contract.
- When Keychain is down, `add` can still return `true` and the next `isTrusted` is false (fail closed). Settings would flash "Trusted." The spec said do not touch Settings.
- Android `TombstoneTrustStore.kt` / DataStore was not touched (spec: out of scope).

### Manual residue

Signed-device check that `SecItemAdd` for `trusted-tombstone-pubs` succeeds with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, and that an existing `trustedTombstonePublicKeys` UserDefaults value migrates once and then ignores a later plist edit. Cannot be done in this `CODE_SIGNING_ALLOWED=NO` harness.
