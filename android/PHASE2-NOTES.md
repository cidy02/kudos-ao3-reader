# Android Phase 2 — signed tombstones

Local-only work on `security-fixes/tombstone-trust`. There is no Phase 3.
Deletes can cross devices again when the incoming tombstone verifies and the
signer public key is already in this device’s trust store.

## Files

- `android/app/src/main/java/io/github/cidy02/kudos/backup/TombstoneSigning.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/TombstoneTrustStore.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/TombstoneLocalMigration.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMergeService.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupRepository.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupScreen.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupManifest.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupMappers.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/works/WorkRepository.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/library/ReadingQueueRepository.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/data/local/{KudosDatabase,KudosDatabaseMigrations}.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/data/local/entity/SyncTombstoneEntity.kt`
- `android/app/src/main/java/io/github/cidy02/kudos/data/preferences/SettingsRepository.kt`
- `android/app/src/test/java/io/github/cidy02/kudos/backup/{TombstoneSigningTest,BackupTrustPhase2Test}.kt`
- `android/app/schemas/io.github.cidy02.kudos.data.local.KudosDatabase/9.json`

## Behaviour

- Device Ed25519 key via Tink `AndroidKeysetManager` + Android Keystore (seed
  fallback in EncryptedSharedPreferences). Public key is 64-char lowercase hex.
  Wire signatures are raw 64-byte Ed25519 (128-char hex), no Tink prefix.
- Payload: `recordType`, `ao3WorkID`, `WorkTags.canonicalAO3WorkURL`, lowercase
  `recordID`, `deletedAt` from `createdAt` as `yyyy-MM-dd'T'HH:mm:ss'Z'`,
  `signerPublicKey`. UTF-8, `\n` between fields, no trailing newline.
- Trust store is a DataStore string set. `trust(hex)` / `isTrusted(hex)`. Own
  pub is always trusted. File / ZIP / folder import never writes the set.
- Backup screen shows this device hex (copy + paste). No QR library added.
- Room v9 adds `signerPublicKey` + `signature` (empty on old rows).
- Local inserts (works, collections, memberships, queues) are signed at write.
- `BackupMergeService.merge`: unsigned still drop. Adopt into `tombstonesById`
  and this batch’s `TombstoneIndex` only if verify OK **and** pub trusted.
  Replace still does not mint tombstones for omitted works.
- One-time `tombstoneMigrationComplete`: re-sign local unsigned Room rows at
  app start and first `importPackage`.
- `retractWorkTombstone` matches recordID **or** ao3WorkID **or** canonical URL.

## Tests

Production entries: `BackupMergeService.merge`, `BackupRepository.importPackage`.

- Existing Phase 1 unsigned-drop tests stay GREEN.
- Trusted signed incoming is adopted and suppresses the work.
- Untrusted valid signature dropped.
- Forged signature (trusted pub, flipped bit) dropped.
- `importPackage` does not add the file’s pub to the trust store.
- Retract by ao3 / canonical URL.

GREEN last (`:app:testDebugUnitTest`): **814 tests, 0 failures, 0 errors**.

## Gaps / leftover

- iOS Phase 2 is out of this pass (do not edit Swift).
- No QR encode/decode (no QR lib in the project).
- Trust keys are device-local only (no iCloud / account sync on Android).
- Safety backup path and Replace UI tests unchanged from Phase 1.
