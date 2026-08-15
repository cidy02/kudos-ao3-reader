# Backup trust — handoff (locked)

**Workspace:** `/Users/cidy02/kudos-fix-tombstone`  
**Branch:** `security-fixes/tombstone-trust` (from `c241d2f` / `origin/hig-review`)  
**Embargo:** local only. Do **not** push, merge, open a PR, or create a remote branch.  
**Do not** run git in `/Users/cidy02/Documents/AO3_App_OpenSource`.  
**Discussion:** `/Users/cidy02/kudos-fix-tombstone/backup-trust-design-discussion.md`

**This document supersedes the earlier “trust tombstones only on first empty-device restore” design.** The owner rejected that. What follows is the locked product + Phase 1 implementation spec.

---

## 0. Split of work (this session)

| Who | Owns |
|---|---|
| **Opus 4.6** | iOS/macOS: Merge vs Replace Library import UX + Phase 1 tombstone drop on **file restore and folder-sync restore** + tests |
| **Grok / subagents** | Android: same Phase 1 tombstone drop on `BackupMergeService` / `importPackage` / folder sync; Android import UX if a file-import sheet already exists; Android `exportedAt` clamp + canonical `sourceURL` (ledger companions) + tests |
| **Then** | Grok reviews Opus. Opus reviews Grok/subagent Android work. |

Phase 2 (Ed25519, per-tombstone signatures, iCloud pubs, QR) is **specified below but not implemented in this session**.

---

## 1. The vulnerability

A `.kudosbackup` is attacker-controlled (AirDrop, email, “curated backup”). Importing one that contains a `savedWork` tombstone for a work the user never deleted:

- Permanently suppresses that work from later backups (`suppressesResurrection` / `worksSuppressed`).
- Propagates through the Library Sync Folder to every peer.
- Never expires.

**Current code (still true at `c241d2f`):**

- iOS `KudosBackup.swift` `restore` (~1182–1204) inserts every incoming manifest tombstone not already keyed `recordTypeRaw|recordID`, then uses that expanded set to skip works (~1219).
- Android `BackupMergeService.kt` (~42–44) unconditionally upserts incoming tombstones, then suppresses (~61–62).
- Match order: `ao3WorkID` → canonical `sourceURL` → `recordID`. A fresh/forged `lastModifiedAt` wins.

---

## 2. Locked product (owner + three-model discussion)

### Phase 1 (this session — no cryptography)

**Incoming unsigned tombstones are dropped** on:

- File import Merge
- File import Replace
- Folder sync ingest

Owner chose **short inconsistency**: your own deletions will **not** cross devices until Phase 2. That is acceptable. Do **not** leave folder sync applying unsigned incoming tombstones.

**File import is two verbs:**

| Verb | Meaning |
|---|---|
| **Merge** (default) | Add works in the backup that are **not** already in the library. Do not delete anything present. Do not overwrite an existing work’s progress, tags, or notes. Drop incoming tombstones. |
| **Replace Library** | This device’s library (works, progress, collections, queues, annotations) becomes the snapshot. Fonts, appearance, AO3 login, and (later) trusted keys stay. |

**Replace extra step (required):**

1. Show the delta: works in library, works in file, will add, will remove, in both.
2. If removals ≫ additions, amber: “This backup is much smaller than your library.”
3. Red **Replace Library** stays disabled until the user checks: **“Remove N works that are not in this backup.”**
4. Button enables after the check **and** ~1–2 seconds.
5. If Library Sync is on: “Sync will put removed works back. Pause sync for this device?” Default **Pause**. Do **not** offer to wipe the sync folder.
6. Before execute: write a timestamped `.kudosbackup` of the current library (Documents). Confirmation names that file.

**Empty library / first run:** skip Merge vs Replace. One **Restore from Backup** button (functionally Merge into empty).

**Folder sync** stays implicit Merge forever. No Replace-via-sync.

**Replace does not persist the file’s unsigned tombstones.** Absence in the snapshot is enough for *this* load. Do **not** mint new standing tombstones for works Replace removed (that would be a signed fleet wipe in Phase 2).

**Replace is this device only.** Other phones are untouched.

### Phase 2 (specified, not this session)

- Ed25519, platform-native (`CryptoKit.Curve25519.Signing` / Tink or API 33 Ed25519). No GPG.
- Sign each tombstone at delete time. Payload, UTF-8 fields joined by `\n`: `recordType`, `ao3WorkID`, `canonicalSourceURL`, `recordID`, `deletedAt` (`2026-08-15T16:00:00Z`), `signerPublicKey`.
- `canonicalSourceURL` must match `WorkTags.canonicalAO3WorkURL` on both platforms.
- Private key never leaves the creating device. iCloud publishes **public** keys; same Apple ID auto-trusts those pubs. Android: QR once.
- A file never adds a trusted key. Merge applies a tombstone only if the signer is already trusted.
- First Phase 2 launch: one-time local re-sign of tombstones already in *this* store (`tombstoneMigrationComplete`). Incoming unsigned still drop.
- 24h clock clamp stays as a pre-filter, not authorization.

---

## 3. Implementation notes (Phase 1)

### iOS — `KudosBackup.restore`

Today it always: adopt all new tombstones → skip suppressed works → `apply` on new **and** existing works.

Change:

1. **Do not insert incoming tombstones** into `SyncTombstone` (file restore and any folder-sync caller of `restore`).
2. **Do not** use incoming tombstones to populate `TombstoneIndex` for this batch. Local tombstones that were already on the device still apply (the user deleted them *here*).
3. Add a mode: `enum BackupImportMode { case merge, replaceLibrary }`.
   - **merge:** if `workIndex.existingWork(for:)` hits, **skip `apply`** (local overlap unchanged). Only insert + apply new works. Still create collections/queues from the file when they introduce new works (so added works are not orphaned). Do not remove local works.
   - **replaceLibrary:** existing works / collections / queues / annotations that are not in the snapshot are removed from *this* store (Recently Deleted / existing deletion machinery if that is how the app already deletes — do not invent a new hard-delete). Load the snapshot’s works via existing `apply`. Still do **not** insert the file’s tombstones.
4. Folder sync continues to call restore as **merge**.
5. Settings import UI (`SettingsView.swift` ~773 `restorePendingBackup`): present Merge vs Replace Library when `SavedWork` count > 0. Empty → Restore only.

**Invariant to test (file Merge):**

> After `restore(A, mode: .merge)` on a library that already contains work J, a `savedWork` tombstone in A for J (or for a work K that A also contains) must **not** be in the local tombstone store, and a later `restore(B, mode: .merge)` that contains work K must still insert K.

**Invariant to test (Replace):**

> After `restore(A, mode: .replaceLibrary)`, local works absent from A are gone from the active library, A’s works are present, and **no new** `SyncTombstone` rows exist for A’s unsigned tombstones. A later `restore(B, mode: .merge)` containing a work that was in the pre-Replace library but not in A **must insert that work** (no standing suppressor).

**Invariant to test (folder sync):**

> Folder-sync ingest of a remote manifest that contains a new `savedWork` tombstone for identity I must not insert that tombstone and must not skip a work I present in the same or a later remote snapshot.

### Android — `BackupMergeService` / `BackupRepository.importPackage`

Same tombstone rule: do not upsert incoming tombstones; do not suppress from incoming ones. Local tombstones already in Room still suppress.

If there is already a file-import UI, add Merge vs Replace Library with the same extra step. If import is only “always merge,” implement the merge-side tombstone drop now and a `replaceLibrary` flag on `merge` / `importPackage` even if the sheet comes a follow-up — the API must exist.

Also (ledger companions, this session if cheap):

- Clamp archived `lastModifiedAt` with `min(value, exportedAt)` and reject > now+24h (iOS already does).
- Canonicalize `sourceURL` like `WorkTags.canonicalAO3WorkURL`.

### What legitimate input is now rejected (Phase 1)

- Incoming deletion claims from a file or sync folder. **Your deletes on phone A will not appear on phone B** until Phase 2. Owner accepted this.
- Replace of an unsigned file cannot plant suppressors that block a later Merge of the user’s real backup.

---

## 4. Explicitly out of scope (this session)

- Ed25519, QR, iCloud pub publishing (Phase 2).
- Collection/queue/annotation tombstone *types* as a separate product (same drop rule applies if they arrive in the incoming list — do not adopt *any* incoming tombstone in Phase 1).
- Identity-aware `retractWorkTombstone`.
- Clearing or rewriting the sync folder from Replace.
- GPG / OpenPGP.

---

## 5. Definition of done

Per platform:

1. Production-entry-point test (real `restore` / `importPackage` / folder-sync ingest — not a helper).
2. Mutation A: restore unconditional tombstone adopt → RED, quoted assertion, duration > 0.
3. Mutation B: weaker substitute (e.g. drop tombstones on file import but still adopt on folder sync) → RED.
4. GREEN last; counts from the result bundle / Gradle. `totalTestCount` 0 is a fail.
5. iOS: **never** `-sdk iphonesimulator` with a UDID destination.
6. Do not weaken existing assertions.
7. Local commits only. No push.

---

## 6. Status

**Done:** owner decisions, three-model discussion, this spec.  
**Not done until the implementers finish:** code, tests, mutation evidence, cross-review.
