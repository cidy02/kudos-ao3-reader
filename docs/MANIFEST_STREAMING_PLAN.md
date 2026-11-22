# Streaming `manifest.json` on iOS and Android — plan v3

Owner, 2026-11-22: "raise the limit and plan a change to stream the manifest on both platforms", then "once streaming is
proven, no cap on either", then "once you are both satisfied [Claude and Codex], implement".
Tasks: T-567 (iOS), A-567 (Android). v1 was reviewed by Codex (`kudos-redesign-work/out/codex-streaming-plan-review.md`,
verdict RETHINK); v2 answered each finding; Codex re-reviewed v2 (`out/codex-streaming-plan-review2.md`, SOUND WITH CHANGES) and v3 applies its edits (§ "Review trace").

## Goal and definition of done

Import (preview, Merge, Reconcile, Replace + its safety export), manual export, and Folder Sync (read, `.bak`/conflict
fallback, merge, upload, precommit recheck, prune) run in **bounded memory that does not grow with the library**, on both
platforms, with today's results and today's commit/recovery behaviour. Then the **manifest-specific size cap is removed on
both** (Android `BackupLimits.MAX_MANIFEST_BYTES`; iOS has none in Folder Sync). The on-disk v8 format does not change.

"Bounded" is measured, not assumed (§ Budget). "Uncapped" means only the manifest's own total-byte limit goes; container
limits that protect against hostile archives stay and are documented (§ Limits after the change).

## Why v1 was not enough

Streaming the parse removes one allocation. The consumers need a **logical view of the whole library**:

- iOS builds a tombstone index before resolving works, keeps an archive→local work map, groups memberships, and computes
  Replace's keep sets from resolved IDs (`KudosBackup.swift:3351–3445, 3520–3560, 3890–3895, 4663–4715, 4783–4791,
  4991–5001, 5085–5093`).
- Android validates canonical work-ID uniqueness across the manifest, resolves works by identity, remaps dependents and
  refreshes the whole merge result against current rows before applying (`BackupValidator.kt:60–76`,
  `BackupMergeService.kt:129–167, 273, 1952–2120, 2291–2304`, `BackupRepository.kt:581–596`).
- Favorites match by target, watermarks by fandom name, annotations dedupe by passage; Replace has different absence rules
  per collection (missing/`null`/`[]`, T-563).
- Android's A-541a pass-through matches by AO3 identity, URL and record ID, case-folds fonts, folds live/conflict/pending
  sources by stamp, and carries unknown top-level values (`SyncManifestPassthrough.kt`).

None of these rules needs the library **in RAM**; they need it **indexed**. So v2 stages to disk.

## Architecture

```
manifest bytes ──► validating streaming parser ──► staging DB (private SQLite) ──► resolve (SQL, indexes) ──► apply (one store transaction, batches)
store ──► batched fetch ──► streaming writer ──► temp file ──► platform publication protocol
```

1. **Parser** (per platform): reads the document **to EOF and validates it before anything is applied or swept**, even when
   `version` / `exportedAt` come after the arrays. It enforces the decoder contract (§ Contract) with each existing route's behaviour as the
   oracle (duplicate keys, escapes, UTF-8, trailing content and wrong kinds behave as the route does today). It decodes each record with the existing typed
   decoder at record boundaries (iOS `JSONDecoder` on the record's bytes; Android `decodeFromJsonElement` on the record's
   tree) so record-level semantics (defaults, timestamp clamping, unknown keys) stay the existing code's.
   - Parser choice is a P1 prototype decision: Android — the platform `android.util.JsonReader` (token stream, no new
     dependency) vs a hand-written byte scanner; iOS — no streaming JSON parser exists in Foundation or our package lockfile,
     so a hand-written tokenizer over a mapped / spooled file, **differentially tested against `JSONSerialization` and the
     current `JSONDecoder` path** on every fixture plus a malformed-input corpus.
2. **Staging DB** (private SQLite, per run, deleted after; no new dependency: iOS `libsqlite3`, Android
   `android.database.sqlite`). Use a private staging database with run and source IDs, section presence, source order,
   indexed natural keys (record ID, canonical work ID, AO3 identity, URL, case-folded font name, fandom name, favorite
   target, annotation passage, tombstone key + stamp), payload references, normalized relationship rows, remaps, tombstone
   decisions, and apply and keep tables. Android adds the A-541a overlay schema (P3). Payloads are stored as bounded
   chunks or references to immutable spools, never one unbounded blob.
3. **Resolve**: read live rows through supported store APIs in stable keyset batches. Stage the live projection needed for
   cross-store joins. Revalidate the projection under the persistence gate or write transaction before applying, and
   rebuild or defer stale decisions using today's rules. Use disk-backed absence checks and bounded cursors for sweeps.
   Keep private staging independent of the app store's internal schema. Decisions run in dependency order (tombstones →
   works → dependents) with today's rules; the existing merge tests are the oracle.
4. **Apply**: preserve the existing commit and failure behavior per platform and mode. iOS uses one model save, restores
   displaced EPUBs on throw, and keeps original-file installs best-effort (`KudosBackup.swift:3197, 4647`). Android Replace
   uses one outer Room transaction with undo for touched EPUBs, fonts and originals (`BackupRepository.kt:533`,
   `BackupFileUndo.kt:10`). Android Merge, Reconcile and Folder Sync retain their current row and asset boundaries and
   retry semantics. Document post-commit settings, pronunciations, recovery documents and overlays separately. Use
   disk-backed undo bookkeeping. Specify restart behavior separately from caught-error rollback. Any crash-atomic Replace
   design requires a durable commit discriminator and a kill/restart test before and after commit. If SwiftData
   dirty-model retention fails P1, block P4 for the affected paths until an atomic publication design is reviewed and
   demonstrated on the real store. The design must cover open contexts, store sidecars, assets and restart recovery.
5. **Export / publication**: batched fetches from the store, record-by-record writer into a temp file, then each platform's
   **existing** protocol, kept as is:
   - **iOS Folder Sync**: assets first, manifest published atomically, prune only with a current view
     (`FolderSyncService.swift:410–488, 1014–1037`).
   - **Android Folder Sync (SAF)**: copy the validated prior live bytes to `.bak`, write an existing live document in place,
     temp-and-rename only for first publication (`SyncRepository.kt:491–572, 880–925`). Stream the precommit fingerprint and
     the outgoing hash independently; spool the exact validated input for `.bak`; update digest bookkeeping only after
     successful publication (Android digests the exact bytes it wrote, so a format change does not by itself cause a
     spurious change).
   - Hold the existing consistency gate or use a verified generation across paged export reads. Build prune membership
     from the published view using an indexed keep table. On SAF, recheck live bytes and folder generation immediately
     before publication, require a successful first-write rename result, and preserve the existing in-place write for an
     existing live file. Treat the precommit reread as a change detector: an external writer can still race the
     subsequent write. Only after successful publication retire pending overlays and folded conflicts, update the native
     digest, and set the settled digest when the folder view is current and all required assets are settled. Exercise
     rename failure as well as interrupted writes.

## Contract (both platforms; written as a table in P2 and tested)

Per top-level key: required / optional; missing vs `null` vs `[]` meaning; lossy or strict elements; unknown keys.
Known today: the four `omittedKeys` arrays (collections, readingQueues, annotations, savedSearches) — missing **and**
`null` suppress Replace sweeps, present `[]` authorizes them; three Insights log arrays optional; `writingRecovery` and
`documents` tolerate an undecodable section and skip bad elements in otherwise valid JSON; a malformed JSON token is a
different failure; required fields still fail when missing; Android's accepting decoder is lenient while its sync recovery
predicate is strict; iOS first checks the live document parses before typed decode (`KudosBackup.swift:478–483,
750–792`, `FolderSyncService.swift:756–766`; Android `BackupJson.kt:7–11`, `BackupValidator.kt:53–76`,
`BackupVersion.kt:18–32`, `SyncRepository.kt:669–692`). Record route-specific outcomes for absent input, accepted typed input, a failed whole-document predicate, a whole document
rejected by schema or semantic validation, unsupported version, I/O failure, cancellation and resource exhaustion. Preserve
each route's evaluation order and `.bak` eligibility. A whole live document rejected by the typed decoder or validator
remains protected from overwrite. Missing-live handling, recovery publication and prune eligibility remain separate
decisions. Establish duplicate-key, escaped-key, UTF-8, trailing-content and wrong-kind behavior against each existing
route. Any deliberate compatibility change requires separate approval. Preserve lossy sections and record defaults, and
perform cross-record validation and clock checks using the final root metadata and a fixed operation clock.

## Entry-point inventory (every one moves or is explicitly left as legacy)

- **iOS reads**: Folder Sync live (`FolderSyncService.swift:742, 762–763` — today a full `JSONSerialization` object, then
  typed decode), `.bak` (`:766`), `NSFileVersion` conflicts (`:377–389`), legacy normal/conflict (`:519–552, 696–701`);
  backup preview (`KudosBackup.swift:349, 357`), confirmed import re-open (`:218–224, 331–337`), ZIP init (`:363–375`),
  legacy directory (`:172–179, 233`); callers `SettingsBackupPage.swift:300–301, 378`.
- **iOS writes**: `manifestData()` (`KudosBackup.swift:472`), `zipData()` (`:490–492`) and its Replace safety copy
  (`SettingsBackupPage.swift:459`), export (`KudosBackupExport.swift:176, 211, 251`), Folder Sync (`FolderSyncService.swift:1014`)
  plus whole-table fetches for the outgoing snapshot and prune keep sets (`:489–506, 1019–1037`).
- **Android reads**: A-541a decodes valid bytes to one `JsonObject` via `decodeFromStream` then `decodeFromJsonElement` (the
  UTF-8 `String` path is a fallback); ZIP import and legacy directory import (`BackupImporter.kt:74–117, 127–131` — the
  directory path calls `Files.readAllBytes`; ZIP reads the manifest through the 128 MiB generic entry path before the 8 MiB
  check); picker classification (`PickedDocumentReader.kt:26–50, 69`, `DocumentImportPreparation.kt:40`,
  `ArchiveWorkConverter.kt:28–29`); Settings preview/pending/execute reparse (`BackupScreen.kt:113–126, 176`,
  `BackupRepository.kt:442–444`); Folder Sync live, `.bak`, conflicts, legacy ZIP + raw re-extract, precommit comparison.
- **Android writes**: `BackupExporter.kt:38–57` (typed-only and overlay paths); Folder Sync manifest output
  (`SyncRepository.kt:499–545`, incl. the `:533–535` pending deferral) and live/`.bak`/first-write temp (`:892–925`);
  private overlay stores — manual-backup, folder-scoped, pending — incl. legacy migration, load/save, Replace aside/recovery
  (`BackupRepository.kt:60–68, 117–123, 194–264`; `SyncRepository.kt:517–522, 549–550`; `SyncManifestPassthrough.kt:725–851`).
- **Tests that build or read manifests** (migrate, or keep as legacy-format producers so interop stays independently tested):
  Apple — `KudosBackupTests`, `CrossPlatformBackupTests`, `CrossPlatformFolderSyncTests`, `CrossPlatformFixtureFields`,
  `FolderSyncTests`, `PersistenceSyncTests`, `ReplaceOmittedKeysTests`, `BackupLazyReadTests`, `ArchiveTrustBoundaryTests`,
  `MiniZip*Tests`, `KudosBackupFontRestoreTests`, `KokoroPronunciationBackupTests`, `ReadingAnnotationBackupTests`,
  `ReadingLogBackupTests`, `AnnotationNotePreservationTests`, `ArchiveDeletionScheduleTests`, `ConversionSidecarIsFetchedTests`,
  `StaleSyncUpKeepsRemoteAssetsTests`, `EqualSizeEPUBStillSyncsTests`, `EPUBDigestHonestyTests`, `InsightsD3D4PersistenceTests`,
  `InsightsP3*`; Android — `BackupCompatibilityTest`, `BackupSecurityTest`, `BackupCentralDirectoryImportTest`,
  `PickedBackupImportTest`, `PickedDocumentReaderTest`, `CrossPlatformRestoreTest`, `SyncRepositoryTest`,
  `SyncManifestPassthroughTest`, `ManifestMemoryProbe`, `BackupCacheStagingTest`, `BackupRestoreSecurityTest`,
  `BackupTrustPhase1Test`, `BackupTrustPhase2Test`, `BackupTimestampClampTest`, `BackupMergeParityTest`,
  `BackupPhase2FieldsTest`, `BackupReadingLogTest`, `BackupFontCaseRestoreTest`, `OriginalsRoundTripTest`,
  `IncomingEpubGateTest`, `QueueTombstoneMergeTest`, `MacReadingPositionMergeTest`, `ImportBackupChoicesTest`,
  `BackupReplaceOfferTest`, `RestoreAndSyncReportingTest`, `Brief3hbContentTest`.
- Track Android picker inspection and confirmation separately. Include provider directory enumeration, export snapshot
  capture, asset staging, and retained preview and undo state in the corresponding end-to-end measurements. Account for
  the Android archive, picker, generic ZIP-entry and manifest limits separately.
- Also include Apple `InsightsD5D6PersistenceTests`, `HistoryHideAndQueueNotesTests`, `OmittedFieldKeepsPreferenceTests`,
  `WorkSearchIndexTests`, `FollowedTagBackupTests`, `TagAliasBackupTests`, `QueueSourceBackupTests`,
  `SmartQueuePersistenceTests`, `ReadingQueueSectionsTests`, and Android `AnnotationTombstoneTest` and `WorkLifecycleTest`.
  Keep large fixtures opt-in and small compatibility and malformed fixtures in regular gates.

## Budget (what "proven" means)

Measured per entry point above, on both platforms, growing **independently**: incoming rows, local rows, conflict copies,
opaque values, assets. Sizes 8 / 32 / 128 / 256 / 512 MiB manifests. Recorded: process footprint and managed heap, peak
temporary disk and journal, elapsed time, cancellation latency. **Pass**: per § P1 feasibility thresholds (64 MiB incremental
footprint ceiling; ≤ 8 MiB median growth 128→512 MiB per axis; 512 MiB run ≤ 5× the 128 MiB run; a measured and enforced
per-component disk budget). Release thresholds are set from device and provider runs before P6.
A-566's desktop-JVM `-Xmx` numbers establish the amplification on Android only; they are not the baseline.

## Limits after the change

- Remove the manifest-specific total-byte check from all manifest routes (Android `MAX_MANIFEST_BYTES` in
  `BackupValidator`, `BackupExporter`, `SyncRepository`, `PickedDocumentReader`; iOS has none in Folder Sync) and exempt
  `manifest.json` from the generic ZIP entry limit on both read and write (iOS `MiniZip.Limits.backup`; Android
  `MAX_ENTRY_BYTES` incl. the ZIP writer, `BackupExporter.kt:99`).
- Retain and document platform-specific container, archive and non-manifest asset limits. Record which routes enforce
  entry counts and compression ratios today. Incremental archive I/O must check actual output, integrity and aggregate
  limits. For picked backups, use streaming or a bounded disk spool under the documented backup archive policy and retain
  the generic picked-document limit for other formats.
- Bound parser depth, buffers and decoded in-memory fields. Process large base64 and opaque values in chunks or by file
  range. Store payloads as bounded chunks or references to immutable spools. Stream oversized supported aggregate records
  field by field. Any new scalar or record limit requires an explicit compatibility decision (there is no per-record cap:
  a supported recovery copy can be ~20 MiB decoded). Reserve and account for disk throughout the operation, and treat
  ENOSPC as resource exhaustion.
- Document older-reader limits in current clients and release notes. Existing clients retain their shipped errors.

## Phases

| Phase | Platform | Work | Done when |
|---|---|---|---|
| P0 ✅ | Android | A-566: desktop-JVM amplification measured (15–17×); duplicate copies removed (−8–10%); cap stays 8 MiB. | `out/a566-measure.md`; `android/rd-a541a` `7fd493a06`. |
| P1 | both | **Baseline and feasibility** — see § P1 below. | Reproducible baseline tables; store prototypes pass or a SwiftData replacement design is opened; a parser chosen per platform by route parity, resource and large-value checks. |
| P2 | both | Contract table; validating streaming parser into staging (no consumer change yet; existing decoders stay the oracle). | Differential tests pass on every fixture and the malformed corpus; staging equals today's decoded manifest on every fixture. |
| P3 | Android | A-541a overlay staging schema. | Match the existing overlay implementation on source precedence and ties, work ID remapping, bookmark/font/watermark/favorite identity, ambiguous matches, stamped settings and pronunciation maps, unknown record fields and top-level values, folder scope, legacy migration, pending retirement, and Replace aside recovery. Compare winner selection and output values against the current implementation. Store opaque values as ranges or chunked payloads and exercise a value larger than the memory budget without materializing it. Measure managed heap and peak spill separately. Depends on A-541a and P2's payload interface; gates Android overlay-bearing export and Folder Sync. |
| P4 | both | Resolve + apply from staging (restore, Merge, Reconcile, Replace) in dependency order, one outer transaction. | All merge/restore/Replace tests unchanged; budget met for import at 512 MiB. |
| P5 | both | Streaming export and publication per platform protocol; MiniZip incremental entry I/O; Android ZIP/directory import incremental; coordinated local spool when the provider can't give a stable seekable source. | Budget met for export and Folder Sync at 512 MiB; interruption tests (`.bak` write, live write, external write during assets, incomplete conflicts, missing live manifest with surviving assets, failure before prune) pass; ENOSPC, cancellation, background expiry measured. |
| P6 | both | **Release gate**: remove the manifest cap; document remaining container/picker limits and the older-client limit; rollback and restart tests. | Every § Budget row flat to 512 MiB on both; owner sign-off. |

**Dependencies.** P4 requires P1 store feasibility and P2 staging, and proves apply from a validated staged source. Run
incremental archive and picker/provider input as a separate workstream after P2. P5 integrates that input workstream, P4,
indexed export and provider publication. Android overlay-bearing export and Folder Sync also require P3. P6 requires
end-to-end tests through production entry points at every applicable scale, including late failure, cancellation, restart
and retry. Record intentional container-limit rejections separately.

Each phase is its own task, branch, gate and adversarial review (per platform where it touches one). P4 is the largest.

## P1 — Baseline and feasibility, with production caps enabled

Pin the app revision, device and OS, provider, initial store, fixture seed and clock. Use one physical device per platform
for feasibility, a local source for repeatable timing, and a coordinated provider on iOS and SAF provider on Android for
interruption and reread checks. Run one warm-up and three measured runs per case. Record pre-operation baseline, peak and
post-cleanup process footprint, Android managed heap, SwiftData memory before and during save, temporary disk high-water by
component, wall time by stage, write-lock and main-actor stall duration, provider opens and bytes read, and cancellation
time to quiescence. Include preview idle retention. Baseline runs pass when measurements and outcomes are reproducible.
Existing cap rejections are recorded as outcomes.

**Entry points.** On iOS measure Settings backup preview, confirmed ZIP and legacy restore in Merge/Reconcile/Replace,
Replace safety export, manual export through `KudosBackupExport`, and `FolderSyncService.syncNow`, `syncDown` and `syncUp`
for live, `.bak`, conflict and legacy input, upload and prune. On Android measure picked-document inspect and confirm,
Settings preview and execute, ZIP and legacy directory import, `BackupRepository.exportV2Zip`, and `SyncRepository.runSync`
and its worker route for live, `.bak`, conflict and legacy input, upload, precommit reread and prune. Include Android
manual, folder-scoped and pending overlay load/save and Replace aside recovery. Measure actual capped routes at accepted
sizes and at their cap boundaries. Use an opt-in local harness for above-cap parser and store prototypes, and label those
results separately from end-to-end runs.

**Store prototypes.** Stage deterministic fixtures outside live mutation. On the production SwiftData schema run batched
insert, update and Replace sweep through the `KudosBackupContents.restore` save boundary with autosave disabled. Include
both populated and empty destinations, displaced EPUBs and a mode with no asset writes to isolate dirty-model retention.
On real Room, drive `BackupRepository`'s Replace transaction from bounded staged reads, include file undo and test a
concurrent edit after staging. Grow incoming and existing rows separately, using row counts derived from the
8/32/128/256/512 MiB fixtures. Check exact final rows, remaps, asset bytes and summaries against the existing
implementation at supported sizes. Force a failure before commit and during asset installation, test cancellation near
commit, inspect state after restart, and retry. Record any process-death result separately from ordinary rollback. A store
prototype fails if it retains row-proportional memory, changes required state or retry behavior, or cannot establish the
commit outcome. A SwiftData failure blocks dependent production apply work until the replacement design passes the same
gate.

**Parser and staging prototypes.** Compare Android `JsonReader` with a chunked byte tokenizer using the same corpus. On
iOS, compare a buffered tokenizer with a mapped-spool implementation using the same chunked payload interface. Select a
candidate only if it passes route parity, resource and large-value checks; measure mapped-page residency as part of
process footprint. Compare the candidates against actual manual, picker and live recovery routes through EOF. Include
root metadata after arrays, escaped and duplicate keys, malformed scalars and separators, invalid UTF-8, trailing content,
wrong section kinds, lossy typed elements, unsupported versions, and truncated live input. Include a supported 20 MiB
decoded recovery payload, a single opaque value larger than 64 MiB, a record with a growing nested array, and
independently growing conflict fan-out and asset bytes. Inject cancellation and ENOSPC during spool and staging. Pass
requires identical typed values, presence, semantic decisions and recovery eligibility on the parity corpus, plus bounded
handling of the large-value cases and no live mutation on validation failure.

**Feasibility thresholds** (proposed; no measured device baseline yet). Use 64 MiB incremental process footprint as the
provisional ceiling for each prototype and require the median incremental peak to grow by no more than 8 MiB from 128 to
512 MiB on each independently scaled axis. For local controlled runs with one axis scaled at a time, require the median
512 MiB run to take no more than 5× the 128 MiB run. Measure cancellation during parser, store and provider work
separately. In a local run, require cancellable loops to stop within one second and report rollback or commit completion
separately. Report provider latency and non-interruptible save/commit intervals separately, then set numeric release
thresholds from the representative device and provider runs before P6. Replace the fixed disk multiplier with a measured
and enforced component budget for concurrent input spools, staging and indexes, apply and undo state, database journals,
staged assets and output. Fail any run that exceeds its disk budget, leaks staging after cleanup, or mutates or publishes
after a resource failure invalidates the operation.

## Review trace (Codex v1 review → v2)

1 logical view needed → staging + indexed resolve (Architecture 2–3). 2 transactions → explicit atomic boundary, Room and
SwiftData designs, SwiftData measured in P1 before anything depends on it. 3 inventory → § Entry-point inventory.
4 A-541a pass-through → overlay staging schema with match keys/stamps/precedence, its own phase before Android export.
5 decoder contract → § Contract, validate to EOF, distinct outcomes. 6 two publication protocols → Architecture 5, both kept.
7 cap removal → § Limits after the change, P5 archive/provider work, no per-record cap. 8 parser/storage alternatives →
P1 prototypes (platform `JsonReader`, tokenizer), SQLite as private staging; v8 JSON stays the interchange (no shards).
9 phasing/measurement → P1 measures first, budget per entry point with disk/time/cancellation; test inventory listed.

**v3 (Codex review 2 → v3):** applied verbatim — staging/resolve with live projection and revalidation (1); per-platform
commit and failure behaviour, disk-backed undo, durable commit discriminator, SwiftData gate (2); inventory additions (3);
P3 operation-level criterion with chunked opaque values (4); route-specific outcomes, existing routes as oracle (5);
consistent export view, SAF recheck, rename result, post-publication bookkeeping (6); limits incl. ZIP writer exemption,
chunked large values, no new caps without a decision (7); parser comparison in P1 (8); phase dependencies, fixture
additions, P1 with thresholds (9).
