# A52: iOS's backup, sync and restore rules that Android has no test for: does Android's code keep them?

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/A52-result.md`. **Leave no other file behind.** Do not edit `TASKS.md`.

Read the Android code as it stands on `android/redesign-parity` at `4870ad9c` (in
`~/kudos-android-lane`, read-only). iOS is `/Users/cidy02/kudos-ios-polish/` (read-only):
the app in `kudos-ao3-reader/`, its tests in `KudosTests/`. The data rules are binding:
`docs/DATA_AND_PERSISTENCE_INVARIANTS.md` (both apps must read and write the same backup and
sync folder; nothing a reader made may be lost on a restore, a merge or a sync).

## The question

`docs/android-port/audits/A25-result.md` (a Gemini index; usable as a list of leads, often
wrong in detail) lists iOS test rules marked `[uncovered: …]`: Android has no test of that
name. A second pass (A29) that was to check them against Android's **code** was unusable. Do
that pass, for these sections of A25 only:
`CustomFontBackupCompatibilityTests` through `StaleSyncUpKeepsRemoteAssetsTests` (backup,
restore, folder sync, originals, reading log, annotations), and every tombstone and
`CanonicalWorkMerge` rule anywhere in the file (`NewestTombstoneWinsTests`,
`TombstoneSweepsExistingRecordsTests`, `TombstoneTrustStoreTests`, `CanonicalWorkMergeTests`).
Skip the AO3 page-parsing sections and the Kokoro ones.

For each `uncovered` rule:
1. Read the iOS test itself (find it in `KudosTests/`; quote the assertion with `file:line`)
   and say in one line what it guarantees a reader.
2. Find where Android does the same thing and decide: **kept** (quote the Kotlin with
   `path:line` that keeps it), **missing** (Android does the thing but not this rule: quote
   the code that breaks it and say what a reader loses), **not applicable** (Android has no
   such feature: say which), or **unsure** (say what you could not find).
3. A25 may name a rule that does not exist or misdescribe it; say so and move on.

Without a quote on both sides, a row is a lead, not a finding: mark it **unsure**.

## Report

A table per A25 section (rule, iOS quote, verdict, Android quote, what a reader loses), then
**the missing ones worth fixing first**, one line each, most data lost first. Stop where you
run out of time and say where. Say plainly where Android's code is right.
