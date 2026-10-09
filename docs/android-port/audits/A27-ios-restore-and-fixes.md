# Audit A27: iOS's unreviewed fixes of 2026-10-08 and 10-09 (T-366, T-369, T-370), and the restore's deletion records as a whole

**Read-only.** Work only in this worktree. Change no source file. Do not build, commit, push,
switch branches, sign in or contact archiveofourown.org. Write exactly one file:
`docs/android-port/audits/A27-result.md`. No helper scripts left behind.

You are hunting for **bugs**, not style. The code under audit is **iOS**, read at
`/Users/cidy02/kudos-ios-polish/` (branch `claude/polish-loop`); change nothing there. Android
(this worktree, `android/`) is only the comparison where a rule was settled there first.

## What to audit

Three iOS commits nobody has reviewed (`git -C /Users/cidy02/kudos-ios-polish show <hash>`),
each with its `TASKS.md` row, which says what it claims:

- **T-366 `d18a313e`**: `kudos-ao3-reader/Services/KudosBackup.swift`, three new calls of
  `applyTombstonesToExisting` (saved links, queue memberships, annotations) and
  `KudosTests/TombstoneSweepsExistingRecordsTests.swift`. Android's same rule is
  `android/.../backup/BackupMergeService.kt` (brief result `briefs/3bs-result.md` item 7).
  Then read **the whole restore for every record type that has a deletion record**
  (`SyncTombstoneRecordType` in `Models/Models.swift`; `SyncMerge` in
  `Services/PersistenceSync.swift`): for each type, in Merge and in Replace, with a trusted, an
  untrusted and an unsigned record, say whether (a) an incoming record is suppressed, (b) the
  copy already here is removed, (c) on which clock, (d) whether this device's next export still
  carries the deletion, and (e) whether a copy newer than the deletion survives on both
  devices. Name every type where a deletion cannot settle, or where a copy the reader made
  after the deletion is lost. Look hard at: a saved link matched by address whose local id
  differs from the archive's; an annotation whose work is not in the archive; a membership
  whose queue or work was itself deleted or is in Recently Deleted; the order of the passes
  (is anything fetched before a pass deletes it and used after?); `dedupeSamePassageAnnotations`
  running before the new pass.
- **T-370 `af328f7c`**: six fixes from audit A20 (`docs/android-port/audits/A20-result.md`
  with its triage): `CommentDraftIdentity` and `CommentDraftStore.move`, the hand-over in
  `verifySession`, the account list's `loadToken`, the filter revert through `loadedFilters`,
  Work Detail's series rows under the privacy blur, the comment page reload after a reply, the
  Home skeleton. For each: does it close the case A20 named, on every path that reaches it,
  and what does it break? A20-1's first fix only ran with a comments screen open; check the
  second does not have a sibling of that fault.
- **T-369 `2d968a55`**: log privacy. Any `os_log`/`Logger` call left in the app that writes an
  address, a work id, a username, a file name or a search text as public (numbers default to
  public), in `kudos-ao3-reader/` as it stands now.

Then two leads nobody has followed:

- `Features/Account/AccountShortcuts.swift`: its editor's footer says what happens when the
  reader removes every shortcut; does the decoder do that, or does choosing none bring the
  default grid back on next launch?
- A sent write on iOS: Android's audit A26 (`audits/A26-result.md`) quotes iOS as wording
  every write "AO3 replied but didn't confirm" once the request has gone out. Is that true of
  **every** write in `Services/AO3WorkActions.swift`, `AO3CollectionActions*.swift`,
  `AO3ChallengeActions*.swift` and the comment and bookmark writes: name any that reports a
  cancellation, a session sentence or nothing at all after its POST returned, or leaves its
  control busy.

Do not re-file what `audits/A12-result.md`, `A19-result.md`, `A20-result.md` and
`A21-result.md` already hold.

## What counts as a finding

1. **Wrong behaviour**: the fix does not close the case its comment or its `TASKS.md` row
   names, closes it on one path and not on another, or breaks something that worked.
2. **Data loss or corruption**: a record a restore deletes that the reader still wanted, or
   keeps after it was deleted elsewhere; a deletion that can never settle between two devices;
   a draft or a typed text lost or shown to another account.
3. **Network**: a read or write `docs/AO3_NETWORKING_POLICY.md` does not allow; a request that
   is repeated, retried, made on opening when it should wait, or made for a viewer AO3 will
   refuse; a POST to an address that is not AO3's; a token reused where iOS reads a fresh one.
4. **State and concurrency**: a task that outlives its view and writes state; a race between
   a load and a session change; a `@State` that is reset or kept when it should not be.
5. **Crashes**: a force unwrap, an unchecked index, a SwiftData fetch or delete on a deleted
   model, a duplicate key in `Dictionary(uniqueKeysWithValues:)`.
6. **Tests that prove nothing**: a test whose assertion cannot fail, or that does not exercise
   the rule its name states. Name the test and say what would still pass if the rule broke.

Not findings: formatting, naming, missing comments, "could be simpler", anything already
listed as left out or as a decision.

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
