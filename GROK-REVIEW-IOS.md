# Grok review of iOS Phase 1 (Opus start + Grok finish)

**Against:** `handoff.md` locked spec  
**Code:** commit `a0533c1` + current `KudosBackup.swift` / `SettingsView.swift`  
**Opus implementation follow-up:** quota-blocked (`claude-opus-4-6-thinking` resets ~2h26m from 13:54 EDT). Remaining tests were handed to a Grok subagent.

Verdict after independent + subagent review: originally **BLOCK** (`FolderSyncService.setAutoSync` does not exist). That compile break, Replace settings apply, and Replace honouring local work tombstones were fixed in this session. Remaining items below are **FIX**, not BLOCK.

---

## Correct

- Incoming unsigned tombstones are not inserted. `TombstoneIndex` is built from **local** `SyncTombstone` rows only (`KudosBackup.swift` ~1218–1220).
- Folder sync calls `restore` with no mode, default `.reconcile` (`FolderSyncService.swift` 211, 298, 393, 434). File Merge cannot leak into sync.
- File Merge skips `apply` (and the EPUB path) on active overlap; undeletes `isPendingDeletion` then applies (`1232–1245`).
- Replace soft-deletes omitted works/collections/queues/annotations **without** `SyncTombstone` (`1675–1719`). Later Merge of a dropped work is not blocked by a planted suppressor (test `replaceDoesNotLeaveStandingTombstonesThatBlockLaterMerge`).
- Identity match stays `ao3WorkID` → canonical `sourceURL` → `recordID` via `WorkRestoreIndex` / `WorkIdentityIndex`.
- Replace extra step: counts, amber when `willRemove >= 20 && willRemove >= willAdd * 10`, checkbox, 1.5s arming, pause-sync default on, pre-replace `.kudosbackup` in Documents (`ReplaceLibraryConfirmationView`). Empty library is Restore-only (`.merge` into empty).
- Production-entry tests exist for “do not adopt incoming tombstones on Merge” and “Replace does not leave standing tombstones.”

---

## FIX

1. **Replace still honours local work tombstones for inserts** (`KudosBackup.swift` ~1250–1253).  
   Android clears the tombstone list on `REPLACE_LIBRARY` so the snapshot can load. iOS `else if tombstones.suppressesResurrection` runs for every mode. A work the user deleted *here* (row gone, `SyncTombstone` remains) will not come back on Replace, so this device’s library is not the snapshot.  
   **Fix:** skip `suppressesResurrection` when `mode == .replaceLibrary` (still do not *insert* incoming tombstones).

2. **Replace applies the file’s appearance settings.**  
   `restore` always `settings.apply(to: defaults)` (`1732`). Settings then also `applyRestoredTheme` after every import (`SettingsView.swift` ~848). Spec: fonts, appearance, AO3 login stay. Android already keeps `current.settings` on Replace.  
   **Fix:** do not apply incoming settings (or theme) on `.replaceLibrary`.

3. **File Merge still LWW-applies annotations / collection fields / queue memberships** on existing IDs. Work-level title/progress/tags/EPUB are protected; reader notes and collection names are not. Spec said Merge does not overwrite notes.  
   **Fix (follow-up, not ship-block):** gate `restoreAnnotations` / collection name LWW so `.merge` only *adds* missing records.

4. **Missing tests (being added by a subagent):** Merge does not overwrite active overlap; default `.reconcile` still LWW-applies and still drops incoming tombstones. Mutation A/B not yet run.

---

## Not a violation

- Bookmarks and saved searches merge-add on Replace rather than snapshot-replace. Spec listed works, progress, collections, queues, annotations.
- Fonts are added from the file, not deleted. Spec said fonts stay (not wiped).
- Local pre-existing tombstones still suppress on Merge/reconcile. Required.

---

## Attribution

Opus landed the restore fork + Settings mode choice, then quota-failed with `ReplaceLibraryConfirmationView` / `makePreReplaceBackup` referenced but missing. Grok added those, split `.reconcile` from file `.merge`, and wrote the two tombstone tests. Remaining Opus job (`20260815-135436-86101-23003`) is QUOTA_EXHAUSTED.
