# Brief 5g result

**Landing note (Claude, 2026-10-05).** Landed with three changes. One test's premise was wrong
(a work is matched by the AO3 number in its address, not by the `ao3WorkID` field alone; the
test now gives the work an address), and with that it exercises the captured identity as
intended. The import's message was put in plain words and cut to the one line a reader can act
on: "N item(s) you changed during the import kept your version; import again to take the
backup's". Gate green (1,406 tests). With the new re-check switched off for one run, eleven of
the class's forty tests fail; with it on, all pass. Not measured: the cost of reading the
library a second time inside the write, on a large library. Not seen on a device.

Additional data-loss risk found: Replace's queue-membership absence cleanup scans the live
table and can delete memberships created or reordered after capture. The apply guard now
restricts this cleanup to unchanged captured memberships as part of protecting queue edits.

Separate existing asset risk, left out of this row brief: EPUB write eligibility is planned
from the captured preservation/file state. A work preserved or a download changed after
capture can still receive the planned bytes; this patch guards database rows, not file-write
planning. `WorkRepository.deleteLocalEpub` can change the file outside the import gate.

No new iOS finding. Read-only reference: `/Users/cidy02/kudos-ios-polish/`.
`KudosBackupService` is `@MainActor`; `restore` and `restoreIsolatedContents` are synchronous
and contain no suspension, so reader edits cannot interleave with its restore.

## Part 1 — implementation and tests written; runtime verification pending

Apply compares whole stored rows with the captured snapshot inside one Room transaction that
also encloses the existing per-kind transactions and all snapshot row writes. Whole-row comparison
also catches equal-tick edits and progress saves that leave the metadata clock unchanged.
Changed clocked rows reuse the existing merge with the original archive, using its existing
clocks. Equal-clock conflicts on changed rows keep the live row (using existing missing-field
fills for works, collections and queues); untouched rows retain the usual archive-wins tie.
The re-merge is lazy (at most once), has no asset bytes, does not adopt tombstones a
second time, and does not allocate restored-font identities. Assets and DataStore are outside
the database transaction. Unchanged rows keep the original mode's behavior.
The re-merge retains the original sync batch's preservation-normalization decision and
accounts for its already-planned validated EPUB writes; it does not change queued-flag policy.

For every clocked kind below, an archive losing the existing LWW decision is the normal
conflict outcome, acceptable for sync and file import: the newer value wins, with existing
non-destructive fills where that kind supports them. Replace's changed rows use Reconcile
instead of forcing the archive over a fresh reader edit. Forced progress retention,
equal-clock reader precedence and clockless skips can defer an archive conflict; these are
reported in the returned summary, so a one-off file is not silently treated as fully applied.

| Kind written by apply | Concurrent change rule and archive-data outcome |
|---|---|
| Work | Whole row check; existing `mergeWork` applies metadata `lastModifiedAt` and progress clocks against the fresh row. Any position changed since capture is explicitly retained, including same-tick locator changes. Independent archive metadata and non-destructive fills still merge. Archive progress conflicting with an in-flight reader save is deliberately deferred; next sync reconciles clocks; a one-off backup must be imported again if that position is desired. |
| Collection, including work memberships | Whole domain row (including work IDs) check; re-merge uses `lastModifiedAt` / `dateAdded`, existing missing-field/color fills and membership rules. Concurrent rename survives an older archive; a legitimately newer archive wins the existing LWW conflict. No blanket skip of archive-only fills. |
| Queue | Whole row check; re-merge uses existing `dateUpdated`, `lastMembershipChangedAt` and membership-clock conflict rules, plus existing missing-field fills. |
| Queue membership | Whole row check; re-merge uses `lastModifiedAt` / `queuedAt`, preserving newer local order/note and taking genuinely newer archive rows. Replace's absence cleanup also requires an unchanged captured membership. |
| Annotation | Whole row check; re-merge uses `lastModifiedAt` / `createdAt`. A newer reader note wins, as does a genuinely newer archive under existing LWW. |
| Reading session, favorite, fandom watermark | Whole entity check; re-merge uses their existing `lastModifiedAt` and existing identity/remap rules. Changed omission targets are kept. |
| Saved link, saved search, custom font | No edit clock: whole-row equality; changed rows keep the fresh value. Their existing merge unconditionally overwrites overlap, so rerunning it would overwrite the edit again. Deferring archive conflict is acceptable for recurring sync, but a one-off file will not retry automatically. Its returned summary explicitly says archive records were deferred and to import again; the original archive remains available. |
| Tombstone | Whole row check for captured/local rows; a concurrently changed stored tombstone is kept instead of overwritten with captured deletion state. Verified adopted archive deletions are persisted unchanged. The conflict is reported. Part 2 separately handles records minted by this Replace. |
| User tags and queue tags | Compare captured and fresh name lists; retain fresh names and add archive additions absent from capture. This keeps concurrent additions/removals out of Replace's stale cross-reference sweep without changing peer deletion policy (F19). |
| Settings | Existing behavior retained; outside Room, no row/edit clock. Concurrent settings changes are outside this brief's row scope. |

The first five requested cases are paired with untouched controls in
`assertKeptRowEdits`, exercised in Reconcile, Replace and Merge. All check counts/identities
for duplicates. A separate test covers a same-clock-tick progress save. File Merge's unchanged
work/collection/annotation/membership overlaps remain add-only: the brief's request that
every untouched row take a newer archive disagrees with iOS here, so iOS's existing semantics
win. Unedited searches still take the archive in all modes, as before.
Another paired test gives the archive the same clock as the reader edits and checks that the
reader's values survive while a missing collection color still comes from the archive.

## Part 2 — implementation and tests written; runtime verification pending

The five kinds that mint immediate Replace-omission records are saved links, saved searches,
reading sessions, favorites and fandom watermarks. The merge records the IDs added after
captured/adopted tombstones were assembled, before omission cleanup. Apply filters only
those IDs when the corresponding omission target is still present and changed. No stored
deletion record is deleted; captured records, another device's records and verified archive
records (including signatures) remain unchanged by this cancellation.

The existing saved-link/search Replace tests now assert that the edited row has no omission
record, the unchanged row is removed and retains its exact record, and the edited row survives
a second Reconcile. New tests exercise the same rule for sessions/favorites/watermarks and
preserve a signed archive deletion and an already-stored deletion for the same edited search.
Additional tests cover clockless kept links/fonts and Replace's membership absence cleanup.
An identity regression covers two different archived work IDs resolving to one local work,
whose AO3 identity is edited after capture. Apply reuses the captured remap without rewriting
archive IDs or duplicating the local work.

## Verification

No Gradle or Xcode run: forbidden by this brief. Compilation and test claims remain pending
Claude's build and test run. No commits, pushes, branch changes, AO3 requests or sign-in.

Static verification: real domain constructors, DAO getters/upserts, entity mappers, backup
DTOs, all merge/apply callers and iOS restore/merge branches were read. `git diff --check`
passes. The backup manifest DTO/version, wire keys, file names, folder names, Room entities,
database version and migrations are untouched. Sync manifest-writing/pruning policy is
untouched; this brief introduces no folder deletes. `TASKS.md` and iOS are untouched.

Claude should run `BackupTrustPhase2Test` first, then the full Android unit gate and Android
build. All new survival, untouched-control, no-duplication, tombstone-provenance and same-tick
claims need that run. In particular, verify the broader Room transaction under Robolectric
and the existing failed-asset-write regressions: database rows now commit together before
file installation, which remains separately fallible as before. No device/UI verification
was performed. No screen/layout files changed; the existing import summary now reports
concurrent and deferred records. Ten new tests and two extended tests await execution.
