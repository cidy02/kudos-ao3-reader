# Streaming `manifest.json` on iOS and Android — plan v2

Owner, 2026-11-22: "raise the limit and plan a change to stream the manifest on both platforms", then "once streaming is
proven, no cap on either", then "once you are both satisfied [Claude and Codex], implement".
Tasks: T-567 (iOS), A-567 (Android). v1 was reviewed by Codex (`kudos-redesign-work/out/codex-streaming-plan-review.md`,
verdict RETHINK); v2 answers each finding (§ "Review trace" at the end).

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
   `version` / `exportedAt` come after the arrays. It enforces the decoder contract (§ Contract), rejects duplicate keys,
   malformed tokens, trailing content, invalid UTF-8, wrong section kinds. It decodes each record with the existing typed
   decoder at record boundaries (iOS `JSONDecoder` on the record's bytes; Android `decodeFromJsonElement` on the record's
   tree) so record-level semantics (defaults, timestamp clamping, unknown keys) stay the existing code's.
   - Parser choice is a P1 prototype decision: Android — the platform `android.util.JsonReader` (token stream, no new
     dependency) vs a hand-written byte scanner; iOS — no streaming JSON parser exists in Foundation or our package lockfile,
     so a hand-written tokenizer over a mapped / spooled file, **differentially tested against `JSONSerialization` and the
     current `JSONDecoder` path** on every fixture plus a malformed-input corpus.
2. **Staging DB** (private, per import/sync run, deleted after): one table per section with the record's bytes, source
   order, section presence (missing / null / present), and **the natural keys each consumer matches on** (record ID,
   canonical work ID, AO3 identity, URL, case-folded font name, fandom name, favorite target, annotation passage, tombstone
   key + stamp), indexed. Android adds the A-541a overlay schema (match keys, stamps, source precedence, opaque values).
   SQLite is available without a new dependency on both (iOS `libsqlite3`, Android `android.database.sqlite`).
3. **Resolve**: the merge/Replace/tombstone/remap decisions run as indexed queries over staging + the live store, in
   dependency order (tombstones → works → dependents), producing an apply plan in staging. Same rules as today, moved from
   arrays to tables; the existing merge tests are the oracle.
4. **Apply**: one outer store transaction, iterating the plan in bounded batches. Atomic boundary stated explicitly (rows +
   EPUB/original file undo all-or-nothing; settings, pronunciations, recovery documents and Android overlays keep today's
   separate, best-effort publication and are listed as such).
   - **Room**: staging validated *outside* the write transaction; apply inside one outer transaction with concurrency
     revalidation and the existing recoverable file undo.
   - **SwiftData**: today iOS flushes pending changes, disables autosave, saves once, and rolls back models and displaced
     EPUBs on failure (`KudosBackup.swift:3197–3234, 4715–4751`). Dirty models are retained until that one save, so batched
     fetches alone don't bound memory. **P1 measures this on a large Replace.** If it scales past budget, the gate is a
     separately reviewed atomic-publication design (e.g. Replace into a fresh store file + atomic swap) before uncapping.
5. **Export / publication**: batched fetches from the store, record-by-record writer into a temp file, then each platform's
   **existing** protocol, kept as is:
   - **iOS Folder Sync**: assets first, manifest published atomically, prune only with a current view
     (`FolderSyncService.swift:410–488, 1014–1037`).
   - **Android Folder Sync (SAF)**: copy the validated prior live bytes to `.bak`, write an existing live document in place,
     temp-and-rename only for first publication (`SyncRepository.kt:491–572, 880–925`). Stream the precommit fingerprint and
     the outgoing hash independently; spool the exact validated input for `.bak`; update digest bookkeeping only after
     successful publication (Android digests the exact bytes it wrote, so a format change does not by itself cause a
     spurious change).

## Contract (both platforms; written as a table in P2 and tested)

Per top-level key: required / optional; missing vs `null` vs `[]` meaning; lossy or strict elements; unknown keys.
Known today: the four `omittedKeys` arrays (collections, readingQueues, annotations, savedSearches) — missing **and**
`null` suppress Replace sweeps, present `[]` authorizes them; three Insights log arrays optional; `writingRecovery` and
`documents` tolerate an undecodable section and skip bad elements in otherwise valid JSON; a malformed JSON token is a
different failure; required fields still fail when missing; Android's accepting decoder is lenient while its sync recovery
predicate is strict; iOS first checks the live document parses before typed decode (`KudosBackup.swift:478–483,
750–792`, `FolderSyncService.swift:756–766`; Android `BackupJson.kt:7–11`, `BackupValidator.kt:53–76`,
`BackupVersion.kt:18–32`, `SyncRepository.kt:669–692`). Outcomes are distinct: invalid document, unsupported version,
I/O failure, resource exhaustion — only "invalid document" may authorize `.bak` recovery; none authorizes publication.

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

## Budget (what "proven" means)

Measured per entry point above, on both platforms, growing **independently**: incoming rows, local rows, conflict copies,
opaque values, assets. Sizes 8 / 32 / 128 / 256 / 512 MiB manifests. Recorded: process footprint and managed heap, peak
temporary disk and journal, elapsed time, cancellation latency. **Pass**: footprint above the app's baseline stays under
64 MiB at every size (flat, not just under a number), disk use bounded by ~2× manifest + assets, time roughly linear.
A-566's desktop-JVM `-Xmx` numbers establish the amplification on Android only; they are not the baseline.

## Limits after the change

- Removed: the manifest-specific total-byte cap (Android `MAX_MANIFEST_BYTES` in `BackupValidator`, `BackupExporter`,
  `SyncRepository`, `PickedDocumentReader`). iOS keeps no cap in Folder Sync; the manifest entry in a `.kudosbackup` is
  exempt from MiniZip's per-entry size cap once it is read incrementally.
- Stays (hostile-input protection, not a manifest cap): ZIP entry count and compression-ratio checks; MiniZip's 64 GB total
  and Android's archive limit (revisited in P5 with incremental entry I/O); EPUB/font/original per-entry caps; parser bounds
  on nesting depth and token length; a free-disk check before staging. **No per-record size cap** — v1's 1 MiB idea would
  reject valid iOS documents (recovery copies can be ~20 MiB decoded before base64).
- Documented compatibility limit: older app versions keep their caps (Android 8 MiB), so a huge manifest syncs only between
  current versions; the UI says so when an older device's read fails.

## Phases

| Phase | Platform | Work | Done when |
|---|---|---|---|
| P0 ✅ | Android | A-566: desktop-JVM amplification measured (15–17×); duplicate copies removed (−8–10%); cap stays 8 MiB. | `out/a566-measure.md`; `android/rd-a541a` `7fd493a06`. |
| P1 | both | **Measure and de-risk before building.** (a) Baseline every entry point per § Budget (iOS for the first time). (b) Prototype a large Replace on each real store: SwiftData dirty-model retention at the single save; Room apply-from-staging in one outer transaction (journal size, lock time, cancellation). (c) Parser prototypes + differential/malformed corpus. | Baseline tables; a go/no-go on SwiftData atomicity (or the swap design opened as its own reviewed task); parser chosen per platform. |
| P2 | both | Contract table; validating streaming parser into staging (no consumer change yet; existing decoders stay the oracle). | Differential tests pass on every fixture and the malformed corpus; staging equals today's decoded manifest on every fixture. |
| P3 | Android | A-541a overlay staging schema (moved ahead of Android export). | Pass-through tests unchanged; remapped work, ambiguous font, conflicting stamped map entries and a large unknown top-level value verified; overlay heap and spill measured separately. Needs A-541a landed. |
| P4 | both | Resolve + apply from staging (restore, Merge, Reconcile, Replace) in dependency order, one outer transaction. | All merge/restore/Replace tests unchanged; budget met for import at 512 MiB. |
| P5 | both | Streaming export and publication per platform protocol; MiniZip incremental entry I/O; Android ZIP/directory import incremental; coordinated local spool when the provider can't give a stable seekable source. | Budget met for export and Folder Sync at 512 MiB; interruption tests (`.bak` write, live write, external write during assets, incomplete conflicts, missing live manifest with surviving assets, failure before prune) pass; ENOSPC, cancellation, background expiry measured. |
| P6 | both | **Release gate**: remove the manifest cap; document remaining container/picker limits and the older-client limit; rollback and restart tests. | Every § Budget row flat to 512 MiB on both; owner sign-off. |

Each phase is its own task, branch, gate and adversarial review (per platform where it touches one). P4 is the largest.

## Review trace (Codex v1 review → v2)

1 logical view needed → staging + indexed resolve (Architecture 2–3). 2 transactions → explicit atomic boundary, Room and
SwiftData designs, SwiftData measured in P1 before anything depends on it. 3 inventory → § Entry-point inventory.
4 A-541a pass-through → overlay staging schema with match keys/stamps/precedence, its own phase before Android export.
5 decoder contract → § Contract, validate to EOF, distinct outcomes. 6 two publication protocols → Architecture 5, both kept.
7 cap removal → § Limits after the change, P5 archive/provider work, no per-record cap. 8 parser/storage alternatives →
P1 prototypes (platform `JsonReader`, tokenizer), SQLite as private staging; v8 JSON stays the interchange (no shards).
9 phasing/measurement → P1 measures first, budget per entry point with disk/time/cancellation; test inventory listed.
