# Brief 3gb: A66's backup and pairing fixes, and three owed tests (Android)

**Write code; do not commit, push, switch branches, sign in, run Gradle or contact
archiveofourown.org.** Claude builds, tests and lands it. Do not edit `TASKS.md`. Create
`docs/android-port/briefs/3gb-result.md` first; write each item into it as you finish it: what
changed (`path:line`), the iOS code followed (`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`,
read-only), the test added (it must fail with the fix taken out).

Hard rules: `docs/DATA_AND_PERSISTENCE_INVARIANTS.md` (a restore, Replace or sync never loses data
either app keeps; Room migrations additive only; backup manifest v8, additive keys);
`docs/AO3_NETWORKING_POLICY.md`; iOS is the source of truth; nothing Android has may be lost.

Each A66 item was checked by a verifier; its quotes and suggested fix are in
`docs/android-port/audits/A66-verified.json` (by `id`). Follow it unless the code shows it wrong.

1. **#3** Replace Library is offered whenever there is anything Replace would remove (works,
   saved links, saved searches, live collections, queues other than Saved for Later), as iOS
   `hasAnythingReplaceWouldRemove` (`Settings/SettingsBackupPage.swift:74`), not only when there
   are works.
2. **#8** Settings › Backup opens the exporter/importer in one tap, as iOS: no second page in
   between (`settings/SettingsPages2.kt` `SettingsBackupPageWrapper`). Keep every row that page
   has (Reset settings to defaults and its confirmation move onto the Backup screen).
3. **#9** Replace's checks as iOS: "far fewer works" uses iOS's threshold and shows only while
   Replace is being reviewed; the undo copy is written as iOS does (attempt names, three tries:
   3fy already gave it iOS's names; check what is left).
4. **#10** Tapping "N deletion(s) skipped from an unpaired device" clears the count, as iOS; and
   Revoke ("Stolen or compromised") does not restore works from Recently Deleted on Android
   only — follow iOS exactly (`Settings/PairingSheet.swift`).
5. **Tests for three fixes Claude made on top of 3fy** (commit `c30bb605`):
   (a) `WorkRepository.rebuildSearchIndexIfNeeded` writes search text from the row as it is at
   save time: change a work's title between batches, assert the stored `searchText` has the new
   title; (b) `WorkRepository.sweepHeldCopies` decides on the fresh row: release a later work's
   hold while an earlier copy is being freed, assert its file stays; (c) `SyncRepository` export
   after Replace paused sync: an automatic run that waited on the gate publishes nothing and
   prunes nothing.
