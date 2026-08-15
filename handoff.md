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
| **Opus 4.6** | iOS/macOS: three-mode restore (`reconcile` / `merge` / `replaceLibrary`) + Phase 1 tombstone drop on **file restore and folder-sync restore** + Settings Merge vs Replace UX + tests |
| **Grok / subagents** | Android: same three-mode split + Phase 1 tombstone drop on `BackupMergeService` / `importPackage` / folder sync; file-import Merge vs Replace UX; Android `exportedAt` clamp + canonical `sourceURL` (ledger companions) + tests |
| **Then** | Grok reviews Opus. Opus reviews Grok/subagent Android work. |

Phase 2 (Ed25519, per-tombstone signatures, iCloud pubs, QR) is **specified below but not implemented in this session**.

---

## 1. The vulnerability

A `.kudosbackup` is attacker-controlled (AirDrop, email, “curated backup”). Importing one that contains a `savedWork` tombstone for a work the user never deleted:

- Permanently suppresses that work from later backups (`suppressesResurrection` / `worksSuppressed`).
- Propagates through the Library Sync Folder to every peer.
- Never expires.

**Pre-Phase-1 code (true at `c241d2f`):**

- iOS `KudosBackup.swift` `restore` inserted every incoming manifest tombstone not already keyed `recordTypeRaw|recordID`, then used that expanded set to skip works.
- Android `BackupMergeService.kt` unconditionally upserted incoming tombstones, then suppressed.
- Match order: `ao3WorkID` → canonical `sourceURL` → `recordID`. A fresh/forged `lastModifiedAt` wins.

---

## 2. Locked product (owner + three-model discussion)

### Phase 1 (this session — no cryptography)

**Incoming unsigned tombstones are dropped** on:

- File import Merge
- File import Replace
- Folder sync ingest (`reconcile`)

Owner chose **short inconsistency**: your own deletions will **not** cross devices until Phase 2. That is acceptable. Do **not** leave folder sync applying unsigned incoming tombstones.

**Three restore modes — do not collapse Merge and folder sync:**

| Mode | Who uses it | Meaning |
|---|---|---|
| **reconcile** | Folder sync / default `restore` / default `importPackage` | Last-writer-wins on overlap. Add missing works. Do **not** delete local works omitted from the snapshot. Drop incoming tombstones. Local tombstones still suppress resurrection. |
| **merge** | File import **Merge** button | Add-only. Insert works not already in the active library. Undelete Recently Deleted / pending-delete if the file has that work. Do **not** overwrite an existing active work’s progress, tags, notes, or EPUB. Drop incoming tombstones. |
| **replaceLibrary** | File import **Replace Library** after extra step | This device’s library (works, progress, collections, queues, annotations) becomes the snapshot. Fonts, appearance, AO3 login, and (later) trusted keys stay. Soft-delete / DAO-delete omissions **without** minting `SyncTombstone`. Drop incoming tombstones. |

**Why three modes:** “Merge” as the owner’s file-import verb is add-only. Folder sync must keep LWW so progress and metadata still cross devices. Using file Merge for folder sync would freeze overlap on every peer. Using folder LWW for file Merge would let a hostile file overwrite local notes/progress.

**Replace extra step (required):**

1. Show the delta: works in library, works in file, will add, will remove, in both.
2. If removals ≫ additions, amber: “This backup is much smaller than your library.”
3. Red **Replace Library** stays disabled until the user checks: **“Remove N works that are not in this backup.”**
4. Button enables after the check **and** ~1–2 seconds.
5. If Library Sync is on: “Sync will put removed works back. Pause sync for this device?” Default **Pause**. Do **not** offer to wipe the sync folder.
6. Before execute: write a timestamped `.kudosbackup` of the current library (Documents). Confirmation names that file.

**Empty library / first run:** skip Merge vs Replace. One **Restore from Backup** button (functionally Merge into empty).

**Folder sync** stays implicit **reconcile** forever. No Replace-via-sync.

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

1. **Do not insert incoming tombstones** into `SyncTombstone` (file restore and any folder-sync caller of `restore`).
2. **Do not** use incoming tombstones to populate `TombstoneIndex` for this batch. Local tombstones that were already on the device still apply (the user deleted them *here*).
3. Modes:
   - **reconcile (default):** existing LWW `apply` on overlap. Incoming tombstones dropped. Folder sync must call this (or omit `mode` so it defaults here). Existing FolderSync / restore tests that expect LWW on default restore must keep passing.
   - **merge:** if `workIndex.existingWork(for:)` hits an *active* work, **skip `apply`** (local overlap unchanged). If the hit is `isPendingDeletion`, undelete then apply. Only insert + apply new works. Still create collections/queues from the file when they introduce new works (so added works are not orphaned). Do not remove local works.
   - **replaceLibrary:** existing works / collections / queues / annotations that are not in the snapshot are removed from *this* store (Recently Deleted / existing deletion machinery if that is how the app already deletes — do not invent a new hard-delete). Load the snapshot’s works via existing `apply`. Still do **not** insert the file’s tombstones. Soft-delete must **not** create a `SyncTombstone`.
4. Settings import UI (`SettingsView.swift`): empty library → one Restore. Non-empty → Merge vs Replace Library sheet, then Replace extra step (`ReplaceLibraryConfirmationView` + `makePreReplaceBackup()`).

### Android — `BackupMergeService` / `BackupRepository.importPackage`

Same three modes (`RECONCILE` / `MERGE` / `REPLACE_LIBRARY`).

- Default of `merge()` / `importPackage` / `importV2ZipBytes` is **RECONCILE** so folder-sync LWW stays.
- File-import UI (`BackupScreen`) must pass **MERGE** or **REPLACE_LIBRARY** explicitly.
- MERGE overlap: keep `existing` work row, do not overwrite EPUB, do not union incoming tags onto the existing work.
- RECONCILE: keep existing LWW + tag union.
- REPLACE_LIBRARY: snapshot this device; DAO-delete omissions **without** minting tombstones.
- Do not upsert incoming tombstones; do not suppress from incoming ones. Local Room tombstones still suppress (except Replace, which ignores even local suppressors so the snapshot can load).

Also (ledger companions):

- Clamp archived `lastModifiedAt` with `min(value, exportedAt)` and reject > now+24h (iOS already does).
- Canonicalize `sourceURL` like `WorkTags.canonicalAO3WorkURL`.

### Invariants to test

**File Merge (mode `.merge` / `MERGE`):**

> After `restore(A, mode: .merge)` on a library that already contains work J, a `savedWork` tombstone in A for J (or for a work K that A also contains) must **not** be in the local tombstone store, and a later `restore(B, mode: .merge)` that contains work K must still insert K. Active overlap is not overwritten (title/progress/tags/EPUB stay local).

**Replace:**

> After `restore(A, mode: .replaceLibrary)`, local works absent from A are gone from the active library, A’s works are present, and **no new** `SyncTombstone` rows exist for A’s unsigned tombstones. A later `restore(B, mode: .merge)` containing a work that was in the pre-Replace library but not in A **must insert that work** (no standing suppressor).

**Folder sync / reconcile:**

> Folder-sync ingest (default restore / `importPackage`) of a remote manifest that contains a new `savedWork` tombstone for identity I must not insert that tombstone and must not skip a work I present in the same or a later remote snapshot. Overlap still LWW-updates.

### What legitimate input is now rejected (Phase 1)

- Incoming deletion claims from a file or sync folder. **Your deletes on phone A will not appear on phone B** until Phase 2. Owner accepted this.
- Replace of an unsigned file cannot plant suppressors that block a later Merge of the user’s real backup.
- File Merge of an unsigned file cannot overwrite local overlap.

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
5. iOS: **never** `-sdk iphonesimulator` with a UDID destination. Use `KUDOS_CASEFOLD_SIMULATOR_UDID=C71780B1-35DE-4E5E-ABCD-2AB66BCB28B0` if you need that simulator. Destination is `id=<UDID>` only.
6. Do not weaken existing assertions.
7. Local commits only. No push.

---

## 6. Status (updated 2026-08-15)

**Locked:** owner decisions, three-model discussion, this spec (including reconcile vs merge).

**iOS (commit `a0533c1`):** Opus started restore + Settings fork, then hit Antigravity quota. Grok finished `ReplaceLibraryConfirmationView`, `makePreReplaceBackup`, `BackupImportMode.reconcile`, and two production-entry tests (`incomingUnsignedTombstonesAreNotAdoptedOnMerge`, `replaceDoesNotLeaveStandingTombstonesThatBlockLaterMerge`). KudosBackupTests / Mutation A/B evidence not yet produced this session.

**Android (commit `a1aa83f` + uncommitted follow-up):** Phase 1 drop + Replace UX + ledger companions committed. Gemini review required file Merge to stop LWW-overwriting overlap. Uncommitted working tree adds `BackupImportMode.RECONCILE`, MERGE skip-overlap/EPUB/tags, and `importPackage` default `RECONCILE`. File UI still passes `MERGE`. Android MERGE add-only tests and a GREEN re-run after that split are still open. Previous `:app:testDebugUnitTest` was **779 / 0 / 0** before the RECONCILE split.

**Do not treat this status block as permission to rewrite working code.** Fill gaps. Do not re-implement working restore.
