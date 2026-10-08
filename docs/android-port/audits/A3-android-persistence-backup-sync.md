# Audit A3: bug hunt in Android's persistence, backup and folder sync

**Read-only.** Work only in this worktree. Change no source file. Do not build, commit, push,
switch branches, sign in or contact archiveofourown.org. Write exactly one file:
`docs/android-port/audits/A3-result.md`. No helper scripts left behind.

You are hunting for **bugs that lose or corrupt a reader's data**, not style. The rules are
in `docs/DATA_AND_PERSISTENCE_INVARIANTS.md` and `docs/KUDOSBACKUP_FORMAT.md` (read both
first); iOS is the reference implementation, at
`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` (change nothing there): `Services/KudosBackup*.swift`,
`Services/*Sync*.swift`, `Services/*Tombstone*.swift`, `Models/Models.swift`.

## What to audit

Under `android/app/src/main/java/io/github/cidy02/kudos/`:

- `backup/` (all of it: manifest, mappers, exporter, importer, validator, merge service,
  folder sync worker and repository, tombstones: signing, trust store, local migration; key
  revocation; the persistence gate; the change tracker)
- `data/local/` (the Room database, its entities, DAOs and **every migration**; the schema
  files under `android/app/schemas/`)
- `data/preferences/` (what is device-local, what is backed up)
- `library/ReadingQueueRepository.kt`, `library/LibraryRepository.kt`, `reader/AnnotationRepository.kt`
  and the reading-session writers, where they write rows that the backup carries

## What counts as a finding

1. **A migration that is not additive**, or that differs from the schema file for its
   version; a column dropped, renamed or retyped; a default that changes an existing row's
   meaning; a migration path from any released version that does not reach the current one.
2. **Backup round trip**: a field iOS's manifest carries that Android drops on import or
   leaves out on export, so that iOS → Android → iOS loses it (check `BackupManifest.kt` and
   `BackupMappers.kt` field by field against iOS's `KudosBackup` structures; an unknown key
   must survive or be harmlessly ignored, never fail the restore); a manifest version other
   than 8; a key that is not additive.
3. **Merge**: a newer local row overwritten by an older incoming one, or the reverse of the
   rule iOS applies (name the rule and both lines); a deleted row resurrected; a tombstone
   ignored, applied twice, or applied to the wrong row; a tombstone accepted without the
   signature check iOS makes; a clock comparison that breaks across time zones or on equal
   timestamps.
4. **Folder sync**: two devices writing at once; a partial file read as complete; a failure
   half-way that leaves the database changed and the folder not, or the reverse; work done on
   the main thread; a worker that runs without the constraint iOS's equivalent has.
5. **Local writes**: a multi-row change outside a transaction; a `modifiedAt` not bumped on a
   change the merge depends on; a soft delete that hard-deletes; reading progress,
   annotations or sessions lost on process death, rotation or a second open of the same work.
6. **Tests that prove nothing** (name the test and what would still pass if the rule broke).

Not findings: formatting, naming, "could be simpler", anything recorded as a decision in
`docs/android-port/DECISIONS.md`.

## The result file

Start with a table: id, severity (P1 loses data or sends something wrong to AO3; P2 wrong
behaviour a user meets; P3 the rest), file and line, one-line statement. Then one section per
finding: the exact code (quote it, with `path:line`), the iOS code it is checked against
(`path:line`), **a concrete failing case** (inputs or taps, then what happens and what should),
and the smallest fix you would make. If you could not confirm a suspicion by reading, put it
under "Unconfirmed" with what would confirm it; do not present it as a finding. End with what
you did not read.

Quality over count. Twenty real findings with exact lines are worth more than a hundred
guesses; a wrong file or line makes the whole report untrustworthy.
