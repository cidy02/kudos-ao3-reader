# Brief 3bs: Android's backup merge follows iOS's in six more places (audit A3)

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; **don't edit `TASKS.md`**. Don't change the backup format or a Room schema. Your sandbox
can't run Gradle or Xcode. Claude builds, tests and commits afterwards, so make what you write
compile by reading the real symbols you use, and say which claims need a test run.

**Android only.** iOS is the reference: read it at `/Users/cidy02/kudos-ios-polish/`, change
nothing there. **When this brief and iOS's code disagree, iOS's code wins**; say so in the
result. Decide questions about demo fixtures, test data, file placement and naming yourself and
list them under "Decided without asking". Do not stop for a question: decide it the more
sparing way (fewer reads, nothing sent that iOS does not send), write it under "Open
questions", and keep going to the end. Write `docs/android-port/briefs/3bs-result.md` as you go.

**This is the code that can lose a reader's library.** Change nothing you have not read on
both sides. Every change gets a test that fails before it and passes after, written first.
Change no rule this brief does not name, no schema, no manifest key, no migration. If iOS's
code and this brief disagree, iOS's code wins; if iOS's code and
`docs/DATA_AND_PERSISTENCE_INVARIANTS.md` disagree, **stop that item**, say so, and go on to
the next.

Read first: `docs/android-port/audits/A3-result.md` **with the triage at its foot** (A3-1 and
A3-2 are already fixed: read how, in `backup/BackupMergeService.kt`, and their tests in
`IncomingEpubGateTest`); `docs/DATA_AND_PERSISTENCE_INVARIANTS.md`,
`docs/KUDOSBACKUP_FORMAT.md`, `docs/REGRESSION_TEST_MATRIX.md`; iOS's
`Services/KudosBackup.swift` at the lines each finding cites; the existing tests under
`android/app/src/test/java/io/github/cidy02/kudos/backup/` (how a merge is tested:
`BackupMergeService.merge(current, backup, mode)` on snapshots, no database needed for most).

## The six items

For each: quote iOS's lines and Android's lines in the result, say whether the audit's claim
is true (it was written by another agent: **verify it, do not assume it**), then fix it or
say why not.

1. **A3-3: Date Added and a queue's Date Created are the earlier of the two copies, on every
   branch that keeps an existing row** (works whose local clock wins; collections in every
   mode; queues when the local clock wins and in File Merge). T-353 in `DECISIONS.md` is the
   rule; iOS applies `min` unconditionally.
2. **A3-4: Replace Library takes the archive's queue and its memberships** without asking
   which is newer, as it already does for works, collections and annotations (iOS:
   `incomingWins` is `true` for `.replaceLibrary`). The system queue's name and kind stay
   pinned. Reading sessions and favourites stay last-write-wins, as on iOS.
3. **A3-5: File Merge returns a collection or a queue from Recently Deleted** (clears the
   three deletion fields, as it does for a work), **and returning a work retracts its
   saved-work tombstone** (by its id, AO3 work id and canonical address, as iOS's
   `PreservedWorkService.retractTombstone`), so the next export does not tell another device
   to refuse it. Find how Android retracts a tombstone when a reader restores a work from
   Recently Deleted and use the same function.
4. **A3-7: a note displaced by a newer copy of the same highlight is kept**, as iOS's
   `parkDisplacedNote` keeps it (a pending-deletion sibling carrying the old note; quote
   exactly what iOS writes: id, kind, dates, locator, colour) and
   `docs/REGRESSION_TEST_MATRIX.md` requires. Say whether Android's Recently Deleted or any
   screen shows such a row, and what happens to it after the recovery window.
5. **A3-8: a delete and its tombstone are one transaction, tombstone first**, at the four
   sites the audit lists (a highlight, a queue membership, a work's hard delete with its
   dependents, a collection membership), as `SavedSearchRepository.delete` already does.
   Keep each function's signature. Say how you tested atomicity (a DAO that throws on the
   second statement leaves both or neither).
6. **The audit's unconfirmed suspicions that touch a merge rule**: `ao3Unavailable` (iOS ORs
   it; Android takes the winner's), `assetIdentifier` (iOS fills only an empty one; Android
   replaces it when the archive wins), and two live annotations with the same work, kind and
   locator (iOS `dedupeSamePassageAnnotations` collapses them). For each: is it true, what
   can a reader lose, and fix it only if iOS's rule is unambiguous in the code.

**Not in this brief** (decided, or waiting for the owner): A3-6 (an unknown tombstone type
fails the merge: a security test pins it, owner question 18), A3-9 (test quality: fix the two
migration tests' fixtures only if it takes no production change), `epubDigest`.

## Tests

One or more per item, named for the rule, each built on the smallest snapshots that show it,
with clocks chosen so that **both** outcomes of the local-versus-archive comparison are
covered. Where an existing test pinned the old behaviour, change its expectation and say in
the result which and why (as `BackupTrustPhase1Test.replaceLibraryRemovesLocalOnlyWorkWithoutMintingTombstones`
was for A3-2). Finish the result with a table: item, true or not, fixed or not, the tests.
