# Brief 5f result

**Landing note (Claude, 2026-10-05).** Landed as written, all three parts. It compiled and
passed first time: gate 1,379, fifteen new tests. One proof was added by hand: with the old
sweep of saved links put back, `aBookmarkCreatedOrChangedAfterCaptureSurvivesReplace` fails.
The `TASKS.md` edit in the worktree was not taken. `5c-landing.md` has the summary and the
risks noted below, for a later brief.

**iOS issue left unchanged:** its colliding-font restore still allocates another
`-restored-N` file on each repeat (`KudosBackupService.restoreIsolatedContents`, validated
font loop). It checks only the original folded filename, not an earlier suffixed copy.
Android intentionally differs here under Part 3's instruction.

**Other data-loss risks noticed, outside this brief:** `BackupRepository.applyMergeResult`
still upserts captured retained rows unconditionally, so edits to an overlapping row made
after capture can be overwritten. Also, Replace's `mintImmediateTombstone` runs at merge
time: a captured bookmark/search that the new equality guard keeps after an edit still has
an omission tombstone in `merge.snapshot.tombstones`. A later tombstone-aware reconcile can
suppress that kept row (saved searches are actively swept by tombstones). These pre-existing
paths were left unchanged; this brief guards the absence sweep and outright deletion only.

Android only. No Gradle/Xcode, sign-in, AO3 contact, branch changes,
commits or pushes. Compilation and runtime claims require Claude's test run.

## Part 1

The Android merge already soft-deletes captured omitted works in its result. Its apply-time
live sweep redundantly repeats that decision and wrongly targets rows created after capture.
Saved searches already have a captured removal list with equality checks. Reuse both paths.
Other omissions are passed explicitly from merge to apply.

The iOS reference (`KudosBackupService`, `@MainActor`) performs `restore` and
`restoreIsolatedContents` synchronously, with no `await`. Its Replace loops use fetched
collections of rows (annotations fetched late). Main-actor reader edits cannot interleave
with that synchronous restore, so this Android coroutine capture/apply race does not apply
there. No iOS change is needed for this finding.

Implemented Part 1: `BackupMergeResult` carries captured omitted bookmarks, collections,
custom queues and annotations from `BackupMergeService.merge`. Apply visits only those
IDs; bookmarks use full captured-row equality inside a Room transaction. Saved searches
retain their existing transaction/equality check, with no second sweep. Work omissions
remain solely in the merge result. Collections/queues retain their 90-day window and
memberships; annotations retain pending deletion. No backup or Room schema changes.

Six new `BackupTrustPhase2Test` cases each cover a late-created row surviving and an
unchanged omitted captured row retaining today's removal behavior. Bookmark/search cases
also cover a captured row changed before apply. Written, not run.

## Part 2

Implemented in `SyncRepository.runSyncLocked` and `carryUnknownRecordKeys`: carry from
`manifestBytesAtRead` only when `decodedLive != null`, with the existing live-byte change
guard still before the write. All twelve record lists are covered. Known keys come from each
record serializer's descriptor, including nullable fields omitted from output. Known values
are never overwritten; only outgoing records receive extras, so removed records cannot return.

IDs use `BackupPaths.normalizeIdForComparison`. Bookmarks use their exact URL, fonts their
existing folded composed-name key (prefer exact name, avoid ambiguous fallback), watermarks
ID then exact fandom name, favorites ID then kind/target, Saved for Later queues their kind.
Works reuse `WorkIdentityIndex` for AO3/URL/UUID rematching. Extra JSON values are kept intact.
This covers only the first level of a record. It does not merge inside known nested objects
(e.g. saved-search filters), nor parse JSON stored as strings.

Tombstones are included: Android `TombstoneSigning.payloadUtf8` and iOS
`TombstoneSigning.payload(for:)` sign record type, AO3 work ID, canonical source URL, record ID,
createdAt (whole seconds), signer public key. Neither signs arbitrary JSON keys. Adding an
unknown key therefore changes neither signature payload. No key names/version/path changed.

Tests added to `SyncRepositoryTest` with its existing fake provider: three records with exact
extra JSON values plus a locally newer work's metadata/progress; second-sync byte equality and
own-manifest digest; a tombstoned search does not return; a coercible malformed list does not
stop sync. Direct carry-step tests cover all twelve lists, identity rematches, malformed
record/list shapes, known nullable fields absent from output, and signature verification
after carrying a tombstone key. Written, not run.

**Malformed-input boundary / brief conflict:** a non-object element in a known record list,
or a non-array non-null list, fails typed manifest decoding before carry is reached. Both
`SyncRepository.runSyncLocked` and iOS reject whole JSON they cannot decode; 5c-landing
explicitly requires that protection. This patch keeps it. Carry itself skips malformed
entries/lists without throwing; the integration test uses a null list which the existing
`coerceInputValues` can decode. The requested successful sync of a truly undecodable known
record cannot coexist with `decodedLive != null`; no decoder/validation rule was weakened.

This does **not** cover `.kudosbackup` exports from Android: no previous manifest is available.
It also does not cover Android fields unknown to iOS. Comparing Android `BackupManifest.kt`
and the reference's `KudosBackupManifest`/record/settings types: Android always writes the
top-level `exportedBy` object (app/platform/appVersion/schemaVersion), absent from iOS's
manifest/CodingKeys. `BackupWork` also declares `readiumLocatorPlatform`,
`readiumLocatorEngine`, `readiumLocatorVersion`, absent from iOS's work/CodingKeys; today's
`SavedWork.toBackupWork` leaves these null, so they are currently omitted by `BackupJson`.
No other Android-only record/settings field was found. iOS is unchanged.

## Part 3

Implemented the remaining repeated-collision case. `BackupPaths.restoredFontFileName` is
shared by collision naming and `isRestoredFontFileName`, preserving the existing filename
and 128-character truncation rules. `FontFileStore.readAllFontFiles` checks same-family
suffixed candidates by file size first, reads at most incoming size + 1 (within the existing
per-file font limit), then compares `BackupPaths.sha256`. It retains the incoming byte array
for identical files, so multiple identical candidates do not add retained blob copies to
the snapshot. Failed candidate reads still reserve the filename.

`BackupRepository` passes incoming font bytes to capture for both ZIP and package restore.
`BackupMergeService.mergeFonts.restoreWithSuffix` reuses an identical existing suffix instead
of allocating/writing another, adopts an orphan file if needed, and populates `renamedFonts`
so `readerFontID` still names the existing file. Original-name comparisons also check size
before digest. No unrelated font family is content-deduplicated.

Two `SyncRepositoryTest` ZIP-restore tests: twice on an empty device leaves one font file;
twice with a different original font keeps that original plus exactly one incoming suffixed
copy, with the retained local selector and every DB font filename resolving to a file. A direct
repeat-merge assertion also checks that the incoming settings payload retargets to the
existing suffix and schedules no file write. `SettingsRepository.replaceAll` deliberately
keeps the device's current font selector; that behavior is unchanged. `BackupPathsTest`
checks suffix-family matching against the actual naming function, Unicode and length caps. Written, not run.
iOS's synchronous font loop checks identical bytes at the base name, but never searches the
suffix family; repeated colliding restores still add copies. Left unchanged as instructed.

## Verification and handoff

All three implementation parts and their tests are written. Part 2 retains the
undecodable-manifest exception described above. No Room schema, manifest version/key names,
backup/sync folder paths, screens, queued-flag logic or held findings were changed.

Static review used the actual DAOs, models, mappers, serializers, file stores and iOS
reference; `git diff --check` passes. No Gradle/Xcode/build/test execution was attempted.
Claude must compile and run `BackupTrustPhase2Test`, `SyncRepositoryTest`, `BackupPathsTest`,
the existing font-collision/restore suites, and the full Android gate before claiming these
behaviors verified. Real SAF/cloud-provider behavior remains unverified.

No commit, push, branch change, sign-in, AO3 request, helper script, stub or `.orig` file.
Changes are left uncommitted on `android/agent-codex-5f` for Claude to review/build/test/commit.
