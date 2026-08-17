# Phase 2 tombstone signatures — shared contract

There is **no Phase 3**. This is the last locked tombstone-trust phase.

Local commits only. Do **not** push. Do not mint signed tombstones from Replace
for the Recently Deleted class (works / collections / queues). Immediate-delete
types (`readingAnnotation`, `bookmark`, `savedSearch`) mint a signed tombstone
at the same moment as the hard-delete — including Replace-mode omission of
bookmarks and saved searches, which is an explicit user-confirmed Settings
action, not background folder sync.

## Payload (UTF-8, `\n` between fields, no trailing newline after last field)

```
recordType
ao3WorkID
canonicalSourceURL
recordID
deletedAt
signerPublicKey
```

| Field | Encoding |
|---|---|
| `recordType` | raw string (`savedWork`, `workCollection`, …) |
| `ao3WorkID` | decimal integer, or empty if none |
| `canonicalSourceURL` | `WorkTags.canonicalAO3WorkURL(sourceURL)` or empty |
| `recordID` | lowercase UUID string |
| `deletedAt` | UTC `yyyy-MM-dd'T'HH:mm:ss'Z'` (no fractional seconds). Use the tombstone’s `createdAt`. |
| `signerPublicKey` | **64-char lowercase hex** of the 32-byte Ed25519 public key |

Signature: 64-byte Ed25519 signature of that payload, stored as **128-char lowercase hex**.

Private key never leaves the device. Algorithm: Ed25519 (iOS `CryptoKit.Curve25519.Signing`; Android Tink `Ed25519Sign` / `Ed25519Verify` — minSdk 26, do not require API 33).

## Adopt rule (file Merge, Replace, folder-sync reconcile)

1. Unsigned incoming tombstones **still drop** (Phase 1).
2. Signature must verify over the payload built from the **incoming fields**, not from local state.
3. `signerPublicKey` must already be in the device trust store. **Own device pub is always trusted.** A file / ZIP / sync folder **never** adds a trusted key.
4. Forged or untrusted signatures drop. Do not insert. Do not suppress from them.
5. Verified + trusted: insert into the local tombstone store **and** include in this batch’s `TombstoneIndex` (deletes cross devices again).
6. Replace still does **not** mint tombstones for omitted works (or collections /
   queues). It **does** mint immediate-delete tombstones for omitted bookmarks
   and saved searches — same class as in-app delete of those types, not a
   standing unsigned clock.
7. 24h `lastModifiedAt` clamp stays a pre-filter, not authorization.

## Trust store

- **iOS:** Keychain holds the private key. `NSUbiquitousKeyValueStore` publishes **public** keys only (same Apple ID auto-trusts). Also persist a local trusted-pub set so restore works offline. Settings: show this device’s hex pub; accept paste of another device’s hex pub (QR-able string). A `.kudosbackup` must not write the trust store.
- **Android:** Encrypted / app-private store for the private key (Tink keyset or Android Keystore wrap). Local trusted-pub set. Settings / backup screen: show hex pub as text (and QR if a QR lib is already in the project — do **not** add a QR library just for this; hex paste is enough if QR is heavy). Accept paste of a hex pub. File import never adds a key.

## Local re-sign (once)

Flag `tombstoneMigrationComplete` (UserDefaults / DataStore). First Phase 2 launch: sign every **local** tombstone that lacks a signature with this device’s key. Incoming unsigned still drop.

## Identity-aware retract

`retractWorkTombstone` / `retractTombstone` must delete local `savedWork` tombstones matching **ao3WorkID or canonical sourceURL or recordID**, not UUID-only.

## Wire / schema

Add optional fields to `SyncTombstone` / Room entity / `KudosBackupTombstone` / `BackupTombstone`:

- `signerPublicKey: String` (default `""`)
- `signature: String` (default `""`)

Old archives without these fields decode as empty → unsigned → drop. Room needs a real migration.

## Tests (production entry: `restore` / `importPackage` / folder-sync ingest)

Do **not** weaken Phase 1 assertions (unsigned still drop).

1. Unsigned incoming still not adopted (existing tests stay GREEN).
2. Trusted + valid signature **is** adopted; that work is suppressed on the same restore if the snapshot also tries to insert it **or** on a later restore of that work.
3. Valid signature from an **untrusted** pub is dropped.
4. Forged signature (trusted pub, flipped bit) is dropped.
5. File import does not add the file’s pub to the trust store.
6. Retract by ao3 / canonical URL, not only record UUID.

Quote GREEN last. iOS filter: `KudosTests/PersistenceGateSuites/KudosBackupTests`. Never `-sdk iphonesimulator` with a UDID. Android: `JAVA_HOME` = Android Studio JBR.
