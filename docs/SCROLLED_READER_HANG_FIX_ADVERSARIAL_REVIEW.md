# Adversarial review — T-98 scrolled-reader hang fix

**Branch:** `reader-scrolled-hang-diagnosis`  
**Base:** local `release-fixes` @ `374aa29`  
**Reviewed commits:** `3a6ce10` (diagnosis) · `c2156b2` (fix) · review follow-up  
**Method:** `docs/ADVERSARIAL_REVIEW_TEMPLATE.md` — tree-first, try to refute, failure scenarios only  

---

## Scope under review

| Path | Role |
|---|---|
| `Features/ReaderReadium/ReadiumProgressPersistence.swift` | Debounce decision + trailing write |
| `Features/ReaderReadium/ReadiumReaderView.swift` | Wire stream / flush / completion |
| `Models/Models.swift` | `applyDebouncedReadiumLocator` |
| `App/ContentView.swift` | folder-sync token quantize |
| `KudosTests/ReadiumProgressPersistenceTests.swift` | Unit coverage |
| Docs / `TASKS.md` / diagnosis note | Policy text |

**Not in scope:** macOS `ReaderProgressBridge` behavior (unchanged aside from shared model helper).

---

## Claims → verdicts

| Claim | Verdict | Notes |
|---|---|---|
| Unthrottled save-on-locator was the hang hot path | **PLAUSIBLE → strongly supported** | Code path confirmed; Instruments not re-run this review |
| Debounce removes that hot path | **CONFIRMED in code** | Stream uses `note` → at most ~2s / delta |
| Force-quit safety preserved | **PLAUSIBLE** | Background + disappear flush; pure SIGKILL mid-window can lose ≤ debounce (accepted) |
| Continue Reading still updates | **CONFIRMED** | Open + shelf-stamp flush call `markProgressModified` |
| Completion true-end (A7-F1) intact | **CONFIRMED** | Separate rising-edge path; not gated on debounce |
| Folder-sync not thrashed mid-scroll | **CONFIRMED after fix** | No `lastModifiedAt` mid-session; `markDirty()` only (no immediate syncUp) |
| No regressions to macOS progress | **CONFIRMED** | macOS still uses `markProgressModified` / bridge |

---

## Findings

### F1 — **real-bug (fixed)** — completion path skipped `progressModifiedAt`

**Where:** `ReadiumReaderView.openBook` `onReachedPublicationEnd` (pre-fix-up).

**Scenario:** User reaches true end of a WIP (or a complete work before finish stamp). Code set `readiumLocator` and `markPersisted` but did **not** advance `progressModifiedAt`. Multi-device merge (`SyncMerge.applyProgress`) keys off `progressModifiedAt ?? lastReadDate` — a peer with a *stale* locator but newer `progressModifiedAt` could win and rewind position.

**Fix applied:** use `applyDebouncedReadiumLocator` before save; on actual auto-finish use full `markProgressModified`.

---

### F2 — **real-bug (fixed)** — trailing write armed on noise-only notes

**Where:** `ReadiumProgressPersistence.note`.

**Scenario:** After a real persist, continuous micro-jitter (`Δprogression < 0.001`) called `scheduleTrailingWrite` every settle, cancelling/recreating a `Task` ~every 0.3s. Wasteful; also risked resetting a trailing timer that was waiting for a *meaningful* settle if logic were reordered later.

**Fix applied:** arm trailing **only** when `isMeaningfullyChanged()`; noise must not cancel an existing trailing commit of a real move. Tests added.

---

### F3 — **real-bug (fixed)** — debounced writes never marked folder-sync dirty

**Where:** `onDebouncedWrite` / position-only flush.

**Scenario:** User reads for minutes (debounced saves land locally), force-quits without a shelf-stamp flush path that updates `lastModifiedAt`. `folderSyncChangeToken` never moved → `isDirty` never set → next launch “catch up dirty” skipped → peer devices never saw progress until some other edit.

**Fix applied:** `FolderSyncService.markDirty()` on debounced write and on any flush that writes a locator. This only flips a UserDefaults flag (no immediate `syncUp`); package upload still waits for close/background/launch triggers.

---

### F4 — **minor (accepted)** — triple flush on swipe-dismiss

**Where:** `handleDismissDragEnded` → `dismissReader` → `onDisappear`.

**Scenario:** Each calls `flushProgress(shelfStamp: true)`. After the first, locator matches → subsequent calls hit the “shelf stamp only” branch and may `save()` again.

**Impact:** Extra main-thread saves on dismiss only (not during scroll). Acceptable; optimizing would need a “already flushed this session exit” flag and is easy to get wrong with cancel paths.

---

### F5 — **minor (accepted)** — open stamps Continue Reading before open succeeds

**Where:** `openBook` calls `markProgressModified` before `await book.open`.

**Scenario:** Corrupt EPUB → open fails → work still jumps to top of Continue Reading.

**Impact:** Pre-existing product smell; not introduced by debounce. Fix would be stamp after `.ready` only.

---

### F6 — **minor (accepted)** — `@Query` still refreshes on each debounced save

**Where:** `onDebouncedWrite` → `modelContext.save()` every ~2s while reading.

**Scenario:** Large library; Home still mounted under `NavigationStack`; save still invalidates queries.

**Impact:** Much better than every ~0.3s + `lastReadDate` re-sort. Residual cost, not a hang-class issue if H1 was correct. Further win would be mutate-only + autosave or a background context (higher risk).

---

### F7 — **minor (accepted)** — progression-delta gate can delay mid-session disk for very slow readers

**Where:** `minProgressionDelta = 0.001`.

**Scenario:** User moves &lt; 0.001 totalProgression from last persist for a long time; debounced path skips; only leave/background flush (string inequality) commits.

**Impact:** Force-quit without background could lose more than 2s of *tiny* motion. Flush-on-background/disappear covers normal mobile lifecycle. Aligns with macOS bridge policy.

---

### F8 — **not a bug** — inactive flush without shelf stamp

**Where:** `scenePhase == .inactive` → `flushProgress(shelfStamp: false)`.

**Rationale:** Control Center / switcher would otherwise spam `lastReadDate`. Position still flushed; dirty flag set when locator changes (F3).

---

### F9 — **not a bug** — macOS / `markProgressModified` call sites

Grep: debounced helper is Readium-only; macOS path still uses full stamps + its own bridge. No accidental behavior change on AppKit reader.

---

### F10 — **caveat** — hang root cause not re-profiled with Instruments

Static + design review only for this pass. Owner smoke (long scrolled session) remains the empirical gate.

---

## Cross-cutting critic

| Check | Result |
|---|---|
| Scope creep outside reader/progress/sync token | None |
| Conflicting double-edits of same invariant | No — stamp split is intentional and documented |
| Debug / diagnostic leftovers in production path | None |
| Docs falsified by change | ARCHITECTURE_MAP + REGRESSION_TEST_MATRIX updated |
| Platform `#if` | iOS Readium only; model helper is inert on macOS until called |
| pbxproj churn | None (FS-synced groups) |

---

## Residual risks (owner smoke)

1. Long scrolled session on device — confirm no hitch (H1 vs H3 WebKit).  
2. Kill mid-chapter after ~3s reading — resume near end of motion.  
3. Auto-finish at true end of a complete work — still finishes; EPUB free rules unchanged.  
4. Folder sync: after reading + background, peer eventually sees locator.  
5. Paged mode: no behavior surprise (same debounce, lower callback rate).

---

## Verdict

**Ship-on-branch: yes**, after review follow-up fixes (F1–F3).

Not merge to `release-fixes`/`main` until owner scrolled-mode smoke. Remaining items are accepted minors (F4–F7) or empirical caveats (F10).
