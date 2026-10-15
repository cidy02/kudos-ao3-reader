# Brief 3fi: A56's Library, queue and reading-record faults

Rules (binding): work only in this worktree (`~/kudos-agent-codex`, branch
`android/agent-codex-3fi`, at the lane's HEAD named in the dispatch); don't commit, push, or
switch branches; never sign in and never contact archiveofourown.org; no stub files; no helper
scripts or `.orig` files left behind; **don't edit `TASKS.md`**. **No Room schema change and no
backup-format change** without saying so first in your result and stopping (Claude must then
ask the owner). Your sandbox can't run Gradle: Claude builds, tests and commits afterwards.
End with `docs/android-port/briefs/3fi-result.md`: what you changed, file by file, what each
test proves, what you could not check. Binding: `docs/DATA_AND_PERSISTENCE_INVARIANTS.md`.

Your A56 (`docs/android-port/audits/A56-result.md`, "The missing ones worth fixing first").
Claude fixed #1 and #2 in 3fh (hard deletes from Recently Deleted and the sweeps take
`onlyIfStillDeleted = true`; the launch sweeps run under the persistence gate); leave those.
For each below: confirm it against the code at the dispatch commit, fix it as iOS does
(`/Users/cidy02/kudos-ios-polish/`, read-only) with a test porting the iOS assertion, or say
why it is not real and leave it. Most harmful first; stop where you run out of time and say
where.

1. **(#3)** Revive a matched local work before queueing or resolving it (Work Details' existing-
   local branch): `addToSavedForLaterRevivesRecentlyDeletedWork`,
   `resolveLocalWorkRevivesASoftDeletedWorkWithoutMaskingAMissingEPUB`.
2. **(#4)** Recognize the same source-less EPUB on re-import (`userEPUBImportRevivesRecentlyDeletedDuplicate`).
3. **(#5)** Match canonical identities on both sides of acquisition (`/downloads/<id>` against
   `/works/<id>`): the two canonical-URL acquisition rows.
4. **(#6)** Queue deletion and normalization bookkeeping: tombstone removed memberships, clear
   a stale queued flag after the last queue goes, reconcile preservation status on add/remove.
5. **(#7)** A non-destructive queue removal: removing a work from its last queue must not
   soft-delete it by default (`removeLastQueueMembershipDoesNotDeleteWorkByDefault`). Find every
   caller of the current `removeWork` and say which behaviour each should have.
6. **(#8)** A collection's membership clock, independent of renames
   (`renamingACollectionDoesNotOverrideARemovalElsewhere`). If this needs a new stored field
   or backup key, **stop and say so** (no schema change in this brief).
7. **(#13)** Adding membership stamps the work as well as the collection (`addStampsBothSidesModified`).
8. **(#9)** The delete confirmation warns when the last copy is no longer on AO3.
9. **(#10)** Collection pickers offer unkept reading/history works, per iOS's eligibility rule.
10. **(#11)** Colliding tag renames consolidate globally (`collidingTagRenameCollapsesTheTwoTags`).
11. **(#12)** A fandom visit records its newest work (`markVisitedUpdatesExistingWatermark`).
12. **(#14)** Section display defaults: only History and Favorites default to ledger rows.
