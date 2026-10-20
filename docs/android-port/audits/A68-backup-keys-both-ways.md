# A68: every backup and sync field, iOS against Android, both ways (an index; Claude verifies)

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Create `docs/android-port/audits/A68-result.md` FIRST with an empty
"Gaps" list, then write each section into it the moment it is done. Leave no other file behind.

Data parity (LIVING-PROMPT §7, last row) was proven by cross-platform tests built on 2026-10-08
(`android/app/src/test/resources/cross-platform/`, iOS `KudosTests/Fixtures/cross-platform/`).
Fields have been added on either side since. Owner rule (binding): "a backup file from iOS must
be loadable in android with all info imported intact and vice versa."

1. iOS (read-only: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`): list every key the backup
   manifest encodes and decodes — `Services/KudosBackup.swift` and `KudosBackupExport.swift`, every
   nested `Codable` record (works, queues, memberships, collections, annotations, sessions,
   favourites, watermarks, saved searches, saved links, tombstones, settings, fonts,
   pronunciations, …) — and every key the folder sync writes (`Services/*Sync*.swift`). Quote
   `path:line` for each.
2. Android (this worktree, `android/app/src/main/java/io/github/cidy02/kudos/backup/`): for each key,
   say **read and written**, **read only**, **written only**, **passed through untouched**, or
   **dropped**, quoting `path:line`. Then the other way: keys Android writes that iOS does not read.
3. For each record type, whether the cross-platform fixtures and tests cover the key (name the
   fixture and the test assertion, or say "not covered").

## Report
First the **Gaps** list: every key dropped, read-only, written-only or not covered by a test, most
harmful first (user-made data that cannot be rebuilt: notes, highlights, queue notes, colours,
reading places, pronunciations; then settings; then caches). Then the full tables. Quote both sides
or mark the row **unsure**.
