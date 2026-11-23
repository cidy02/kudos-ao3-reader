# Data storage and sync architecture — plan v2

Owner, 2026-11-22: "build the most architecturally sound data storage and sync possible … design incremental sync … implement
it, all of it" — not to store all of AO3, but so no part of storage, sync or backup has a ceiling a real reader can hit.
Scale requirement (`docs/REDESIGN_DECISIONS.md`): release gate at 15k and 50k works with ≈300k reading sessions (sessions scaled
independently of works) and representative asset volumes; an opt-in 1M-work run is a diagnostic only. Devices up to 2 TB.
Tasks: T-568 (scale), T-567/A-567 (manifest streaming, `docs/MANIFEST_STREAMING_PLAN.md`), T-569 (incremental sync), T-570
(backup restore points), T-571 (store layer). One wire format for iOS/iPadOS/macOS (SwiftData) and Android (Room).
v1 was reviewed by Codex (`kudos-redesign-work/out/codex-data-arch-review1.md`, RETHINK); v2 applies every finding (§ Review trace).

## Principles

1. **No whole-library work on the main thread; no memory that grows with the library** beyond what is on screen or in one bounded
   batch. Exports, fresh bootstrap and checkpoint creation legitimately visit the whole dataset — in bounded batches, off the main
   thread, with progress and cancellation.
2. **Derived data is maintained from the change that caused it**, each with a durable progress watermark, a recoverable rebuild,
   and a stated freshness target (how stale a count or shelf may be, and for how long).
3. **Measured steady-state budgets** (§ Budgets), not "cost ∝ changes" as a slogan: no-op sync, normal delta, bootstrap,
   year-offline catch-up and one permanently lagging device each have listing / open / byte / disk / time budgets.
4. **Immutable publication**: anything another device reads is written once, content-hashed, published by rename, verified on
   read; a crash leaves the old state or the new; recovery is tested by kill/restart.
5. **Merge outcomes are specified, not inherited**: explicit per-route legacy adapters reproduce today's v8 results; a normative
   v9 operation matrix (§ D) defines concurrent outcomes; golden fixtures prove both.
6. **Every task ships with its device benchmark** at 15k/50k (iPhone and Pixel), before and after. Static audit estimates and host
   (simulator / desktop JVM) results are labelled as such.

## Current state

- Folder Sync writes a **complete v8 snapshot** each time: assets first, `manifest.json` last as the commit point, coordinated
  reads, `.bak` recovery, conflict folding, orphan prune only with a current view (`FolderSyncService.swift:1019`, Android
  `SyncRepository.kt:570`). Merge: record-level `SyncMerge.shouldApplyIncoming` plus route rules (booleans gated by incoming-wins,
  fill-only metadata, positive-counter handling, monotonic `hasGivenKudos`, clamped dates — `KudosBackup.swift:558, 6202, 6417`,
  Android `BackupMergeService.kt:806`), tombstones with a newer-snapshot escape hatch and retraction on restore
  (`KudosBackup.swift:5390`, `PreservedWorkService.swift:180`, `BackupMergeService.kt:2560`), signed deletion witnesses,
  per-setting stamps (`SyncedSettingsClock`), identity AO3 ID → canonical URL → UUID (`WorkIdentityIndex.swift:13`), annotation
  passage dedupe (`KudosBackup.swift:5538, 5622`, `BackupMergeService.kt:1825, 2291`), Android opaque overlays (A-541a).
- Measurements (all host, not device unless stated): iOS simulator restore peak 9.7 GiB at a 512 MiB manifest and a batched
  SwiftData control that still grew; Android desktop-JVM ~300 MiB peak at 8 MiB and a flat-heap Room staged Replace; Pixel results
  cover the parser only (`out/t567p1-ios-baseline.md`, `out/a567p1-android-baseline.md`). Scale audits are **static estimates**:
  8 BLOCKER, 25 HIGH, 9 MEDIUM (`out/t568-audit-*.md`).

## A. Store layer (T-571 — an end-to-end gate, not a micro-benchmark)

- **Android: Room stays**, provisionally — the flat-heap result is desktop-JVM; it is re-proven on the Pixel in D0/D1. List screens
  move to paged/keyset queries.
- **iOS: compare two complete designs under the same gate** (atomicity, memory, disk, latency, crash recovery, migration restart,
  rollback, UI reopening, concurrent-edit handling, WAL/sidecar lifecycle; on iPhone, iPad and Mac):
  1. **SwiftData generation switch** — bulk work in bounded batches on fresh contexts into a new store generation, then an atomic
     switch with a durable marker; must show no lost concurrent edits, no live-context invalidation surprises, database and asset
     generations in step (T-567 P1b is its first half).
  2. **SQLite under a thin store layer** — requires, before any code, a reviewed migration and cutover design: bounded logical copy
     from the old store, stable UUIDs and relationship verification, a recoverable cutover with one authoritative writer, old-store
     retention through acceptance; it touches `ModelContainer` (`MyApp.swift:25`), `@Query`/observation, model-backed editing and
     relationships, reader and session writes, identity and search indexes, sweeps, backup and sync. No new dependency without owner
     approval (GRDB is the candidate).
  The choice is made on the gate's numbers and a Codex review; the owner is told before a migration starts.

## B. Change capture (T-569a)

- **iOS default: a same-store transactional outbox.** Every supported mutation command writes its outbox rows (operation, entity,
  field group, before/after values as needed, origin) in the **same save** as the change. SwiftData persistent history is only a
  feasibility and coverage probe (dirty hints, audits), because it cannot reliably recover exact committed values, intent or old
  relationship keys, and a separately committed outbox has a history-token retention problem. Before claiming coverage, inventory
  every write path: direct `ModelContext` writes, autosave, imports, reader checkpoints, sweeps, migrations, remote apply
  (`FolderSyncObserver.swift:12`).
- **Android: SQLite triggers** on synced Room tables writing the outbox in the same transaction, tested for old/new null-safe
  diffs, `REPLACE`, cascades, join-table rank changes, bulk paths, fresh installs and every supported migration
  (`CollectionDao.kt:24`).
- **Origin and grouping** are transaction-scoped: remote apply never echoes back out; a user restore still emits intentional changes.
- **Sources outside the model tables** (preferences, pronunciation maps, drafts, recovery documents, assets, Android opaque overlay
  data) each get durable capture with an interruption and reconciliation contract.

## C. Journal sync v9 (T-569b spec, T-569c+ implementation)

**Namespace.** v9 lives in its own directory, outside every legacy prune path (`KudosLibrary/v9/`). The v8 `manifest.json` and its
assets are never written by v9 code after cutover.

**Operations.** Each operation has an id `(libraryID, writerIncarnation, seq)`. A writer's operations form **contiguous sequence
ranges**; each published range is bound to a content hash. A restored or reinstalled device gets a **new writer incarnation**
(historical session device ids are kept as data). Outbound ranges are reserved durably before publishing; an ambiguous publish is
retried with **the same bytes**.

**Causality.** HLCs order competing values; they do not define a log prefix. Operations that depend on others (edit-after-create,
alias-after-merge, restore-after-delete, rank-move-after-membership) carry explicit dependencies; an operation is applied only when
its dependencies are present, otherwise held pending. Commuting operations are listed in the matrix. A receiver persists its
per-writer cursors, accepted clock state and the merge result **in one store transaction**.

**Clock admission.** An HLC more than a fixed bound ahead of the receiver's admitted clock is **quarantined deterministically**
(same decision on every receiver), never clamped per receiver; the affected writer has a documented recovery (re-stamp on rejoin).

**Segments.** Immutable `segments/<incarnation>/<firstSeq>-<lastSeq>-<hash>.seg`: header (format version, library, incarnation,
seq range, HLC range, dependency summary), records, trailer checksum. A segment without a valid trailer, a seq gap, or a missing
dependency is **pending**, never skipped.

**Assets.** Immutable blobs stored **by digest** (`blobs/<sha256>`); the logical asset reference (work generation → digest) is a
versioned field in the operation matrix. A segment referencing a blob not yet visible is pending; size and hash are verified before
dependent state becomes visible. Durable staging covers file install + database commit, including a cancellation reported after
commit. **Blob reclaim is disabled** until reachability is provable from retained checkpoints, segments and supported restore points.

**Checkpoints.** Immutable, hash-addressed v9 checkpoints built from a consistent store view, containing a **per-writer sequence
vector** (the exact cut), merge metadata (field stamps, generations, aliases, retained deletions and witnesses), membership and
deletion state, and the asset closure. Readers choose among checkpoints by cut; incomparable cuts are resolved by the rule in the
spec. Checkpoints are for bootstrap and catch-up first.

**Reclamation is disabled at first.** Segment and blob deletion is enabled only after a separately reviewed epoch/authority protocol
(no expiry lease as deletion authority — leases cannot fence a partitioned stale compactor on iCloud Drive/SAF). A device offline
past a retention bound is **retired** under an explicit rule and rejoins by bootstrap + a documented rebase of its pending edits.
Acknowledgements name the committed cut and distinguish "applied locally" from "seen". Deletion and alias information is kept until
stale operations can be rejected safely.

**v8 coexistence: none for writes.** Upgrade is an explicit **cutover** per sync folder from a validated v8 view, after which v8
builds can't write to it (they see a read-only projection at most, or nothing). Mixed-version writing would need its own bridge design
proving the exact baseline of each legacy write and asset safety with shipped clients; it is out of scope. Standalone `.kudosbackup`
stays v8 (streamed, T-567). Manual v8 import/export keeps working.

## D. Operation matrix and legacy adapters (normative, written before production capture)

A table, reviewed and backed by cross-platform golden fixtures and replay permutations (every arrival order) before the wire format
is frozen, covering:
- **Field groups and policies** per entity: LWW-by-HLC, fill-only, monotonic (`hasGivenKudos`), positive counters, atomic value
  groups (reading progress; deletion state + deadline; voice id + name; hue + exact colour), absent vs `null` vs reset; settings and
  pronunciation maps with entry-level presence and reset operations, explicit vs inferred stamps, malformed values, unknown passthrough.
- **Lifecycle generations**: a delete targets an entity generation and wins over ordinary concurrent edits to it; an explicit restore
  references the deletion and starts a new generation; concurrent delete/restore, permanent purge and deliberate re-acquisition
  outcomes; signed witnesses (signature scope, trusted-signer enrolment, unknown witnesses, restore authority) preserved through
  checkpoints; the 90-day Recently Deleted deadline and the device-local 60-day held-copy policy; memberships stay attached during
  soft deletion; session history independent; immediate-delete types; Replace-only omission rules.
- **Identity**: AO3 ID → canonical URL → UUID matching and ambiguity rules preserved; deterministic survivor selection; durable
  aliases; re-keying of memberships, annotations, sessions, favorites, settings references and assets with stamp merge.
- **Memberships and order**: keyed by canonical endpoints; presence separate from rank, section and notes; concurrent remove/re-add
  and move/move outcomes; deterministic rank ties; rebalance vs pending move; special queue identities; smart (derived) memberships
  never synced.
- **Annotations**: deletions filtered before passage dedupe; non-empty-note preference kept; stable ties; empty anchors; a dedupe
  alias distinct from a user deletion.
- **Legacy adapters** for Merge, Reconcile, Replace and v8 folder import: today's rules (incl. the newer-snapshot escape hatch and
  date clamping with a fixed operation clock) produce an accepted result that is translated into explicit v9 operations — never
  fabricated per-field history from a record stamp.
- Required test: two devices create the same AO3 work under different UUIDs, each with annotations and queue moves; exchange in both
  orders; identical final state.

## E. Backups (T-570)

- Standalone `.kudosbackup` stays a complete streamed v8 snapshot (portable recovery).
- New: **restore points** in a user-chosen folder — each an immutable, complete logical manifest over a **backup-owned
  content-addressed blob pool**; a restore point writes only missing asset bytes and restores without replaying earlier points. The
  closure is verified before publication and again before restore. Backup retention is separate from sync, so nothing on the sync
  mesh can delete a backup's dependencies. Delta chains only if measured metadata cost demands them, with pinned bases, verified
  parents, and consolidation that commits a complete new base before retiring anything.

## Budgets (set from D0 device runs; tracked per release)

Listings, file opens, bytes read/written, local spool and database WAL, retained segments, metadata per entity, asset versions —
for no-op sync, normal delta, bootstrap, year-offline catch-up and a permanently lagging device. Backpressure: pending work is
reported to the reader before disk fills; small high-frequency writes (reading progress) are coalesced per segment.

## Phases

| Phase | Work | Gate / depends on |
|---|---|---|
| D0 | Archivist fixture (15k/50k + 300k sessions; 1M opt-in diagnostic) in the real stores + device benchmark harness. | running |
| D1 | Scale BLOCKER fixes from the audits, each proven by D0 before/after; then HIGH. Independent of sync. | D0 |
| D2 | Manifest streaming (P1b → P6); streaming apply gated on the store decision; cap removal on streaming P6 only. | in progress |
| D3 | Store-layer gate (§ A) on iOS; Room re-proven on Pixel. | P1b, D0 |
| D4 | Operation matrix + legacy adapters (§ D) with golden fixtures and replay permutations. | — (can start now, spec only) |
| D5 | v9 wire spec `docs/SYNC_JOURNAL_FORMAT.md` (§ C), cross-platform fixtures, reviewed. | D4 |
| D6 | Capture + outbox (§ B) on both platforms; verified against snapshot diffs; no sync behaviour change. | D3, D4 |
| D7 | Journal apply + publish + immutable bootstrap checkpoints, **reclamation disabled**, explicit v8 cutover; kill/restart, offline, permutation, clock-admission and gap tests. | D5, D6 |
| D8 | Reclamation: epoch/authority protocol, retirement and rejoin — separately reviewed and demonstrated. | D7 |
| D9 | Backup restore points (§ E). | stable blob + checkpoint interface (D7) |
| D10 | Remaining HIGH/MEDIUM scale fixes and incremental derived data with watermarks. | D1, D6 |

## Acceptance gates (replace v1's open questions)

- **G-store** (D3): one design passes § A's end-to-end gate on device.
- **G-capture** (D6): every write path in the inventory emits outbox rows with correct origin; reconciliation of a forced gap passes.
- **G-matrix** (D4/D5): golden fixtures and all replay permutations converge identically on both platforms.
- **G-journal** (D7): kill/restart at every publish/apply step, a segment before its blob, a seq gap, divergent content at the same
  seq, clock skew past the admission bound, a year-offline device and a restored device with a new incarnation — all converge or wait,
  never lose or duplicate.
- **G-reclaim** (D8): no data needed by any non-retired device or retained restore point is ever deleted.
- **G-budget**: every § Budgets row within its device threshold at 15k and 50k.

## Review trace

v1 → v2 (Codex review 1): 1 operation ids, contiguous ranges, dependencies, transactional cursors, same-bytes retry, clock admission,
new incarnation on restore → § C Operations/Causality/Clock admission. 2 checkpoints → immutable vector-cut checkpoints; reclamation
disabled; no lease authority; retirement/rejoin → § C, D8. 3 v8 writable projection → v9 namespace + explicit cutover; `.kudosbackup`
stays v8. 4 lifecycle → generations in § D. 5 identity/memberships/annotations → § D. 6 assets → digest blobs, versioned references,
pending, reclaim disabled. 7 capture → transactional outbox default, history as probe, write-path inventory, origin, non-table
sources → § B. 8 field LWW → policy table + legacy adapters + golden fixtures → § D. 9 store gate → end-to-end comparison incl.
SQLite migration design → § A. 10 backup chains → immutable restore points over a blob pool → § E. 11 budgets/backpressure/derived
watermarks; cap removal tied to streaming P6 only → § Budgets, D2, D10. 12 evidence labels and scope → Principles 6, Current state.
