# Brief 3ft-2: fix the review's findings on 3ft before it lands

**Write code; do not commit, push, switch branches, sign in, run Gradle or contact archiveofourown.org.** Claude builds, tests and lands it. Do not edit `TASKS.md`. Append a section "Review fixes" to your result file and write each item there as you finish it: what changed (`path:line`) and the test that fails without the fix. Hard rules as in your first brief (data and networking invariants, iOS is the source of truth at `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`, nothing lost, ICU regex). The review findings, with quotes and each verifier's reasoning, are in `docs/android-port/audits/review-3fz-3ft-3fx-3ga.json` in the lane (`/Users/cidy02/kudos-android-lane`): read the entries for your patch. This worktree still holds your 3ft changes (not landed). Claude found finding #5 (a compile
error in `KokoroTTSController.initEngine`) not real: the patch built and passed the full gate. Fix:

1. **Sync reverts local pronunciation edits (data loss).** When the remembered manifest digest is
   null (`settled` false), the next sync treats Android's own previous manifest as foreign and
   `restorePronunciations` merges it archive-wins over local edits and deletions. A device's own
   manifest must never overwrite its newer local corrections: follow iOS's rule for its own
   manifest (`Services/FolderSyncService.swift`) and the deletions it keeps.
2. **A malformed corrections file breaks every backup and sync.** `captureLibrarySnapshot` calls
   `pronunciationStore.load()` unguarded. A bad file must not fail an export, import or sync;
   do what iOS does with an unreadable store (keep the file, export nothing from it, say so).
3. **The legacy `Kudos.kudosbackup` sync path ignores `pronunciationsRestoreFailed`.** Treat it as
   the other paths do, so a failed save is not followed by an export that drops the archive's
   corrections.
