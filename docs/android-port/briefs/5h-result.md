# Brief 5h result

**Landing note (Claude, 2026-10-05).** Landed with one correction. The write-time check asked
whether the row was "unchanged since this import wrote it" by comparing it with the row the
merge had *planned*; the stored row differs from the planned one wherever the write normalizes
a field, so in a sync's last batch every queued work looked edited and its corrected EPUB was
refused (`queuePreservationFromAnEarlierBatchDoesNotRejectALaterEpub`, an existing test,
caught it). The check now compares with the row read back from the database in the same
write. Gate green (1,446 tests). With the write-time check switched off for one run, six of the
new tests fail. Not seen on a device: none of this has a screen.

Android only, on `android/agent-codex-5h`. No builds, commits, pushes, branch changes,
AO3 traffic, sign-in, TASKS edits or iOS edits. Runtime verification is pending Claude.

Read all of `5c-landing.md`, including Brief 5g, and `5g-result.md`. The sync contract
remains: always write the manifest, no pruning without a full folder view, and missing
listed files do not stop a run. The backup format and Room schema are unchanged.

## Reference and findings

- iOS `KudosBackupService` is `@MainActor`; `restore` and `restoreIsolatedContents`
  are synchronous with no suspension, so reader actions cannot interleave with this restore.
- Android `BackupRepository.applyMergeResult` formerly used `installedWorkIds` from
  5g's refreshed snapshot. That prevents EPUBs for hard-deleted rows detected by 5g,
  but cannot see a deletion after the row transaction or changed file/preservation state.
  `restoreOriginals` did not check that a remapped row still exists.
- `importV2ZipBytes`, `importPackage` and `importOriginalFiles` hold PersistenceGate.
  Sync calls these gated entry points per batch; its outgoing capture/upload also holds
  the gate. Internal `applyMergeResult` formerly assumed its caller held it; tests call
  it directly. `WorkRepository.deleteLocalEpub`, its held-copy/free-space callers,
  soft/hard deletion and WorkImporter downloads/user import/rebuild do not take the gate.
- Merge raises the row clock and normalizes queued preservation *before* asset installation.
  A write-time check must distinguish those import-owned changes from the reader's live
  state, or an untouched last batch would reject its own EPUB as already preserved.
- Font merge only plans writes into missing destinations (collisions get suffixed names).
  Fonts have no work preservation/download flag, but deletion of a missing-file font's row
  during import can still leave orphan bytes; CustomFontRepository is also ungated.

## Implementation

`BackupMergeService.merge` and `BackupRepository.applyMergeResultLocked` both call
`mayRestoreEpub`, which contains the existing mode handling and calls the original
`mayReplaceEpub`. There is one replacement rule. The in-memory merge result remembers
the sanitized clock of the entry that actually supplied each planned EPUB (important
when multiple archive identities remap onto one work). Nothing new is serialized.

After 5g's row transaction commits, apply starts a transaction for each planned EPUB,
re-reads the row and actual file existence, runs the shared rule and installs only if
allowed. It rejects hard-deleted rows, soft deletion during this import, a file removed
since capture, or a promised missing copy whose promise the reader cleared. The last
case covers Remove Copy while an EPUB is already absent. A removal observed after the
row commit also blocks installation. Replace's archive preference becomes Reconcile
for a concurrently edited row, consistent with 5g, so Replace cannot bypass a newly
preserved copy.

To avoid rejecting an untouched import's own writes, the policy comparison uses the
pre-apply effective clock when the committed clock is still the import's value. It
uses pre-apply preservation only when the whole re-read row still equals the row this
import wrote. Any subsequent edit uses live preservation. This preserves the current
last-batch queue normalization behavior and ordinary equal-clock replacement. A new
record remains new for policy purposes only while its imported row is unchanged.

The same per-file transaction samples actual disk state after installation or skip:
`hasEpub` follows that sample; a missing skipped or failed installation sets
`remoteEpubPending`; successful installation clears it. A failure still commits those
flags before throwing, retaining the existing protection against uploading old bytes
as if the failed incoming file had been installed.

Originals and records are now included in apply, so their skipped writes contribute
to the existing import message. `restoreOriginals` rechecks a remapped row and current
original/record existence per write. It never overwrites a local original or record,
does not recreate one removed since capture, and skips assets for a work deleted or
whose EPUB was removed during this import. A conversion record checks size and SHA-256
against the actual original at the record's write, rather than trusting the earlier
original loop's match. Originals are grouped by archived work ID for this check, so
records do not scan every other work's original. This retains 5e's same-original check
and late-record support. Original/record existence sets live only in the capture context.

Fonts cannot meet the EPUB keep/download fault: they have no such flags; merge only
plans unoccupied destinations, suffixing collisions, and normal user font imports
allocate new UUID filenames. They can meet the deletion/orphan variant when repairing
a missing file for a font whose row the reader deletes during import. Apply now checks
the row and destination in a transaction, skips deleted rows, and never overwrites
newly occupied names. Identical newly present bytes are already satisfied. This also
keeps late bytes safe at a planned suffixed destination. No font naming policy changed.

Skipped assets add to `concurrentRowsDeferred`, using the existing sentence:
“N item(s) you changed during the import kept your version; import again to take the
backup's”. A work's EPUB/original/record and an already-deferred row count once, using
in-memory deferred record keys from 5g; no new screen or message was introduced.

## Retry and gate boundaries

A removed download is absent for this apply, but a promised incoming EPUB remains
owed. `SavedWork.toBackupWork` already publishes `hasEPUB = hasEpub || remoteEpubPending`.
`SyncRepository.runSync` already withholds its own-manifest digest while any work is
pending. Therefore sync publishes the promise, keeps the listed folder EPUB, and the
next run looks for it again. A fresh capture on that run has no removed-since-capture
file and the ordinary missing-file rule permits installation. Originals remain listed
by work identity, so the existing originals fetch also retries missing originals or
records on a later run. A one-off archive remains available for the reader to re-import.

| Caller/path | Gate after this patch |
|---|---|
| Backup ZIP import and package import | Hold PersistenceGate across capture, merge, row apply, assets and settings; call private `applyMergeResultLocked` to avoid nesting the non-reentrant mutex. |
| Direct internal `applyMergeResult` (the deterministic tests' entry point) | Now takes PersistenceGate itself. |
| Sync manifest/asset batches | Call the gated import entry points; the whole run's single-flight lock is separate. Sync's outgoing capture/upload holds PersistenceGate. |
| Sync originals-only batches | `importOriginalFiles` holds PersistenceGate, re-resolves identity, and uses the same per-file row/asset checks. |
| WorkRepository `deleteLocalEpub` / `freeHeldCopy` / `sweepHeldCopies` / `freeFinishedCopies` | Ungated. `deleteLocalEpub` deletes bytes before upserting its updated row. |
| WorkRepository soft/hard deletion; WorkImporter download, user import, rebuild | Ungated. WorkImporter writes bytes before its row upsert. |
| CustomFontRepository import/delete | Ungated. Files precede row writes/deletion. |

The check and file installation share the import gate and a Room transaction, so
other gated restores cannot interleave, and other Room writers cannot change the row
between this per-file check and its flag write. **A filesystem window remains:** the
ungated callers above can delete/replace bytes while this transaction is suspended in
file I/O, before they request their own database write. They can also change bytes
immediately after the final disk sample. Room cannot lock the filesystem. This patch
does not retrofit all ordinary import/delete callers onto the gate, so it does not
claim to eliminate those races. The before-merge/after-merge regressions below are
deterministic; a true simultaneous ungated file mutation remains unverified.

## Tests written (not run)

Twelve new tests in `BackupTrustPhase2Test` cover:

- Marked preserved between merge and apply, in Reconcile and Replace: original bytes,
  actual flags and exactly one held-back item.
- Download removed in that interval, in Reconcile and Replace: no file, `hasEpub=false`,
  `remoteEpubPending=true`, backup still promises a copy, exactly one held-back item.
- Hard deletion in that interval: no row, EPUB, original or conversion record.
- Soft deletion in that interval: old EPUB retained, no new original or record.
- Untouched overlap in Reconcile and Replace, and missing-file overlap in File Merge:
  exact incoming EPUB/original/record, flags settled, no held-back count.
- Untouched queued work: its own final normalization does not reject the planned bytes.
- Different original installed meanwhile: keep its bytes and extension, skip the other
  original's record, report the held-back work.
- Missing-file font row deleted meanwhile: no orphan font bytes.
- New work in all three modes: exact bytes and settled flags.
- Newer local EPUB installed meanwhile: keep the newer local bytes.
- Reader clears an already-missing copy's promise meanwhile: stay absent for this apply,
  then retain the incoming promise for retry.
- Original and conversion record removed meanwhile: neither recreated this apply.

One new `SyncRepositoryTest`,
`aSyncAfterAWriteSkippedForRemovalFetchesTheStillPromisedFile`, uses the existing fake
SAF provider. It plans an incoming file, removes the local download, applies and asserts
pending absence, writes the resulting promised manifest (modeling the first run's
sync-up), then runs real `runSync` and checks exact fetched bytes and cleared pending
state. This is a retry integration test, not an assertion that an entire first sync
with a precisely timed concurrent edit was exercised.

## Verification / handoff

`git diff --check` passes. Static review read the real DAO getters/upserts, entity/domain
mappers, merge modes, timestamp sanitizer, normalizer, asset stores, WorkImporter and
WorkRepository file callers, CustomFontRepository, sync fetch/upload/stamp/pruning paths,
and the iOS restore/preservation/originals code. No Gradle, Xcode, test or build ran.
All compilation and runtime claims above require Claude's verification.

Run `BackupTrustPhase2Test` and `SyncRepositoryTest` first, then the full Android unit
gate and Android build. In particular, check the per-file Room transactions across
suspending file I/O under Robolectric, gate non-reentrancy, 5g row conflict tests,
5e asset-batch/late-record tests, font collision tests, and existing failed-installation
regressions. The additional original/record existence probes during capture and the
per-asset transactions have not been performance-measured on a large library. No device
or UI verification was performed; no screen changed.

Changed files: `BackupRepository.kt`, `BackupMergeService.kt`, `KudosBackup.kt` (only
non-serialized snapshot/merge context), the two test classes above, and this result.
Manifest version/DTO keys, file/folder names, Room entities/database/migrations, sync
manifest-writing/pruning policy, settings conflict behavior, F19/F25/F26/F27 and queued
flag policy are untouched. TASKS and the read-only iOS worktree are untouched. No stub,
helper script or `.orig` artifact was added. No commit/push/branch switch or AO3 access.
