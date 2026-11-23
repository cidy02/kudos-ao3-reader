# Data storage and sync architecture — plan v1

Owner, 2026-11-22: "build the most architecturally sound data storage and sync possible … design incremental sync … implement
it, all of it" — not to store all of AO3, but so no part of storage, sync or backup has a ceiling a real reader can hit.
Scale requirement (`docs/REDESIGN_DECISIONS.md`): design target 50,000 works and 30 years of history (≈300k reading sessions);
test points 15k / 50k, plus an opt-in 1M-work run to show which costs grow with the library. Devices up to 2 TB.
Tasks: T-568 (scale), T-567/A-567 (manifest streaming, `docs/MANIFEST_STREAMING_PLAN.md`), T-569 (incremental sync), T-570
(incremental backup), T-571 (data layer). Platforms: iOS/iPadOS/macOS (SwiftData) and Android (Room); one wire format.

## Principles (every task is reviewed against these)

1. **No whole-library work on the main thread; no memory that grows with the library** beyond what is on screen or in one
   bounded batch. Lists page from the store; filters, sorts and counts are store queries with indexes.
2. **Derived data is maintained incrementally** (counts, shelves, Insights aggregates, search index) from the change that
   caused it — never recomputed by a scan on the hot path. A rebuild exists, runs in bounded batches in the background, and is
   the repair path, not the normal path.
3. **Sync moves only what changed.** Cost of a sync is proportional to the changes since the last one, not to the library.
4. **Every write that crosses a device is atomic and recoverable**: publish by rename, never partial; a crash leaves the old
   state or the new, never a mix; recovery is tested by kill/restart.
5. **One merge semantics everywhere** (restore, sync, journal): today's rules in `docs/DATA_AND_PERSISTENCE_INVARIANTS.md`
   § Merge rules, moved from whole-record timestamps to per-field stamps without changing outcomes for existing data.
6. **Measured, not assumed**: every task ships with its benchmark at 15k/50k on device, before and after.

## Current state (what we build on)

- Folder Sync today writes a **complete snapshot** each time: assets first, `manifest.json` (v8) last as the commit point,
  coordinated reads, `.bak` recovery, conflict folding, prune only with a current view (`FolderSyncService`, Android
  `SyncRepository`). Merge is record-level `SyncMerge.shouldApplyIncoming` + tombstones (`SyncTombstone`, signed deletion
  witnesses) + per-setting stamps (`SyncedSettingsClock`, T-541). Identity: AO3 ID → canonical URL → UUID (`WorkIdentityIndex`).
  `PersistenceOperationGate` serialises migration, import, sync and sweeps.
- Its costs: every sync reads and writes the whole manifest; every device's write conflicts on one file (iCloud conflict copies,
  SAF in-place writes); memory and time grow with the library (T-567 P1: iOS restore 9.7 GiB at a 512 MiB manifest; Android
  ~300 MiB peak at 8 MiB).
- T-568 audits (`kudos-redesign-work/out/t568-audit-*.md`): 8 BLOCKER, 25 HIGH, 9 MEDIUM whole-library hot paths.

## Architecture

### A. Store layer (T-571 — decided by measurement)
- **Android: Room stays.** P1 proved a staged Replace applies in one transaction with flat heap (≤ 20 MiB to 512 MiB).
  All list screens move to paged queries (Paging 3 or keyset paging over Room), never `List<Work>` of the library.
- **iOS: decision gate on T-567 P1b.** P1 showed a single-save Replace retains ~5.5 KB per row. P1b tests (a) a fresh
  `ModelContext` per bounded batch and (b) a shadow-store build + atomic swap. **If (a) bounds memory and (b) works, SwiftData
  stays**, with bulk operations always batched on fresh contexts and UI lists on fetch-limited / paged descriptors. **If not,**
  the alternative is SQLite directly under a thin store layer (no new dependency unless approved; GRDB would be the candidate),
  migrated model by model behind the existing service APIs. This is the largest fork in the plan; it is decided on P1b's
  numbers and Codex review, and the owner is told before a migration starts.

### B. Change capture (T-569a)
- Every mutation of synced data produces **change records** with **per-field stamps** from a **hybrid logical clock** (HLC:
  wall time + counter + device id, monotonic per device, merges forward on read) — immune to clock skew between devices.
- iOS: SwiftData persistent history (`fetchHistory`, iOS 18+) as the capture source, translated to change records in a local
  outbox table; Android: SQLite triggers on the synced Room tables writing to an outbox table in the same transaction.
- Not captured: derived/rebuildable fields (search text, caches), per-device wiring, sign-in data (same exclusions as today's
  snapshot rule).

### C. Journal sync format v9 (T-569b spec, T-569c implementation)
```
KudosLibrary/
  manifest.json            v8 snapshot = the checkpoint (streamed, T-567), with a per-device HLC watermark it covers
  journal/<deviceID>/<seq>.jsonl   immutable, append-only change segments, one per sync-up batch, published by rename
  devices/<deviceID>.json  device record: name, platform, last seq, schema version, checkpoint it last read
  Works/ Fonts/ Originals/ ...     assets as today (per-UUID); change records reference asset hashes
```
- **Write (sync-up):** drain the outbox into a new segment (temp + rename), upload assets first, then publish the segment.
  Each device only ever writes its own directory, so **two devices never write the same file** → no iCloud conflict copies,
  no SAF in-place race on shared state.
- **Read (sync-down):** list `journal/*/`, read segments past this device's per-device cursor in HLC order, apply each change
  through the shared merge rules (per-field last-writer-wins by HLC; deletes are tombstone changes), advance cursors only after
  the store commit. Cost ∝ new changes.
- **Checkpoint / compaction (T-569d):** when the journal grows past a threshold, one device (lease file with expiry) writes a
  new streamed checkpoint `manifest.json` recording the watermark it covers; segments below every device's acknowledged
  cursor *and* the checkpoint watermark are deleted after a grace period. A new or long-offline device reads the checkpoint,
  then segments after its watermark.
- **Compatibility with v8-only builds:** until both platforms ship v9, the checkpoint manifest stays a valid v8 snapshot and is
  refreshed on a schedule, so an older build still syncs (coarsely). A v8 build that rewrites `manifest.json` is detected
  (watermark missing/older) and its snapshot is ingested as one large change set. Removing v8 write support is a later,
  owner-approved step.
- **Integrity:** segments carry a header (format version, device, seq range, HLC range) and a trailer checksum; a segment
  without its trailer is incomplete and ignored; seq gaps are detected and waited on, never skipped.

### D. Incremental backup (T-570)
- A `.kudosbackup` stays a complete, self-contained, streamed snapshot (T-567).
- New: **backup chains** to a user-chosen folder — a base snapshot plus journal segments since it, in the v9 layout, so a
  nightly backup of a 15k-work library writes only the day's changes and the new assets. Restore = base + segments, through the
  same apply path as sync. A chain is consolidated into a new base on a schedule.

### E. Derived data (T-568 + T-569a)
- Counts, shelf membership, Insights daily aggregates and the search index are updated from change records (local and synced)
  in the same transaction or a follow-up bounded batch; each has a background rebuild for repair and migration.

## Phases (each its own task, branch, gate, Codex review; benchmarks at 15k/50k on iPhone and Pixel)

| Phase | Work | Depends on |
|---|---|---|
| D0 | Archivist fixture (15k/50k/1M opt-in) seeded into the real stores + device benchmark harness for launch, Library scroll/filter/sort, search, Home, Insights, History, queue/collection open, import, delete/sweep, backup, sync. | — (starts now) |
| D1 | Scale BLOCKER fixes from the T-568 audits, each proven by D0's benchmark before/after. | D0 |
| D2 | Manifest streaming P1b → P6 (`MANIFEST_STREAMING_PLAN.md`). | in progress |
| D3 | Store-layer decision (T-571) from P1b; if SQLite on iOS, a migration plan reviewed before any code. | P1b |
| D4 | HLC + change capture + outbox on both platforms (no sync behaviour change; outbox verified against snapshot diffs). | D3 |
| D5 | v9 journal spec (`docs/SYNC_JOURNAL_FORMAT.md`) with cross-platform fixtures, reviewed. | D4 |
| D6 | Journal sync read/write, cursors, v8 compatibility mode; kill/restart, offline, conflict, clock-skew and gap tests. | D5, D2 checkpoint writer |
| D7 | Checkpoint + compaction + lease. | D6 |
| D8 | Incremental backup chains. | D6 |
| D9 | HIGH/MEDIUM scale fixes, derived-data incremental maintenance, then remove caps (streaming P6). | D1–D7 |

## Open questions for review
1. SwiftData persistent history as the iOS capture source — retention, cost at 300k sessions, and whether it records the
   field-level changes we need; fallback is explicit outbox writes in the service layer.
2. HLC vs per-field wall-clock stamps (today's `SyncedSettingsClock`) — migration of existing stamps.
3. Lease for compaction on iCloud Drive / SAF where file locks don't exist.
4. Exactly which v8 behaviours the compatibility mode must preserve, and when it can be retired.
