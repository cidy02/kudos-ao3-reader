# Scrolled Reader Hang — Diagnosis

**Branch:** `reader-scrolled-hang-diagnosis` (from local `release-fixes` @ `374aa29`)
**Scope:** Diagnosis complete; **fix implemented on this branch only** (not merged to `release-fixes` / `main`).
**Platform under study:** iOS/iPadOS Readium reader (`BookReaderView` → `ReadiumReaderView`). macOS uses the legacy WKWebView reader and is covered only as a contrast (it already debounces progress writes).
**Date:** 2026-07-14

### Fix status (implemented on this branch)

| Change | Where |
|---|---|
| Debounced locator persistence (~2s, progression delta, trailing write) | `ReadiumProgressPersistence.swift` |
| Reader wiring: open stamp, stream note, flush on dismiss/disappear/background | `ReadiumReaderView.swift` |
| Mid-session stamp without shelf/sync thrash | `SavedWork.applyDebouncedReadiumLocator` |
| Viewport end-state only on flip | `ReadiumBook.navigator(_:viewportDidChange:)` |
| Folder-sync token second-line defense (whole-second quantize) | `ContentView.folderSyncChangeToken` |
| Tests | `ReadiumProgressPersistenceTests.swift` |

---

## 1. Executive summary

The strongest evidence points to a **main-thread work cascade on every settled scroll position update in Scrolled mode**, not to a single Readium rendering bug:

1. Readium’s reflowable scroll view notifies “pages changed” **~300 ms after scroll activity settles** (and again after brief pauses during slow scrolling).
2. That notification drives `locationDidChange` → Kudos mutates `SavedWork` **and immediately `modelContext.save()`** with **no debounce/throttle**.
3. Each save stamps `lastReadDate` / `lastModifiedAt`, which refreshes **root `@Query` surfaces still mounted under the reader** (Home, Library, ContentView folder-sync watchers) and can reschedule folder sync.

Scrolled mode is uniquely exposed because position updates are **continuous/settle-frequent**. Paged mode only emits on page turns, so the same unthrottled save path is usually tolerable.

**Regression status:** The unthrottled save-on-`locationDidChange` path has existed since the Phase‑2 Readium integration (`4c5de9fd`). It is **not introduced by T‑94**, but T‑94 **adds a second per-update `@Observable` write** (`viewportDidChange`) and **documents the asymmetry**: macOS got `ReaderProgressBridge` debouncing while iOS did not.

---

## 2. Reproduction steps (for human / Instruments validation)

### Setup

1. Build/run **iOS** target on iPhone and iPad simulators (or devices).
2. Ensure **Display → Reading mode = Scrolled** (`@AppStorage("readerMode")`).
3. Open a **short** chapter work and a **very long** multi-chapter / multi‑100k-word AO3 EPUB.
4. Optionally enable **Library Sync Folder + Auto Sync** (amplifies the cascade).
5. Optional control: same works in **Paged** mode for A/B.

### Gestures to exercise

| Scenario | How | Expected if hypothesis holds |
|---|---|---|
| Continuous slow scroll | Finger drag slowly for 10–30 s with micro-pauses | Hang / hitch after short use; main thread spikes every ~0.3 s+ pause |
| Rapid fling | Fling repeatedly, reverse direction often | Hitch on settle more than mid-fling |
| Direction changes | Scroll down/up repeatedly | Same settle cascade |
| Image-heavy chapter | Chapter with many `<img>` | Extra WebKit cost *plus* same save cascade on settle |
| Light text chapter | Plain prose | Cascade still present; lower WebKit baseline |
| Long session | Scroll for several minutes | Accumulating `@Query`/save cost; memory growth separate |
| Paged control | Same book, paged mode | Far fewer hitches (page-turn-only callbacks) |

### Diagnostic probes (temporary; not landed)

Recommended OSSignposts / logs around:

- `ReadiumBook.navigator(_:locationDidChange:)`
- `onLocatorChange` body (JSON serialize, `markProgressModified`, `modelContext.save`)
- `navigator(_:viewportDidChange:)`
- `ContentView.folderSyncChangeToken` / `scheduleFolderSyncUp`
- Main-thread `Time Profiler` + `SwiftUI` / `View Body` instruments

Suggested temporary counters (pseudo):

```text
[ReaderDiag] locationDidChange t=… href=… progression=…
[ReaderDiag] persist begin → jsonMs=… markMs=… saveMs=… totalMs=…
[ReaderDiag] viewportDidChange resources=… atEnd=…
[ReaderDiag] folderSync token changed → markDirty + reschedule
```

---

## 3. Was the issue successfully reproduced?

| Method | Result |
|---|---|
| Interactive simulator hang capture | **Not completed in this session** (no owner-driven UI session / Instruments recording attached). |
| Static code-path + Readium 3.9.0 source trace | **Completed** with high confidence on the hot path. |
| A/B vs macOS debounce design | **Confirmed in code**: macOS debounces; iOS does not. |
| Commit bisect to a single hang-introducing commit | **No single hang-only commit**; pathological iOS path is long-standing; T‑94 adds secondary cost. |

**Verdict:** Root cause is **strongly supported by code evidence**, pending human Instruments confirmation of wall-time distribution (save vs WebKit vs SwiftUI).

---

## 4. Confirmed architecture of the scrolled event path

### 4.1 Readium (swift-toolkit 3.9.0)

Source (local checkout used for this diagnosis):
`build/DerivedData/SourcePackages/checkouts/swift-toolkit/Sources/Navigator/EPUB/`

```
User vertical scroll (WKWebView UIScrollView)
  → EPUBReflowableSpreadView.scrollViewDidScroll
  → setNeedsNotifyPagesDidChange()
       // cancel previous; perform afterDelay: 0.3
  → notifyPagesDidChange()   // only if progression changed
  → EPUBNavigatorViewController.spreadViewPagesDidChange
  → updateCurrentLocation()  // execute(when: state==.idle, pollingInterval: 0.1)
  → computeCurrentLocationAndViewport()   // async MainActor work
  → currentLocation / viewport assignment
  → delegate.navigator(_:locationDidChange:)
  → viewport didSet → delegate.navigator(_:viewportDidChange:)   // if viewport != old
```

Key Readium details:

| Mechanism | Location | Behavior |
|---|---|---|
| Scroll settle debounce | `EPUBReflowableSpreadView.setNeedsNotifyPagesDidChange` | **0.3 s** after last scroll/progression event |
| Idle gate + poll | `EPUBNavigatorViewController.updateCurrentLocation` | Runs only when `state == .idle`; polls every **0.1 s** while waiting |
| Dedup | `notifiedCurrentLocation` | Skips identical `Locator` |
| Viewport observer | `viewport` `didSet` | Fires `viewportDidChange` when viewport value changes |

**Implication for “continuous scroll”:** mid-fling with no pause, Kudos may receive **no** `locationDidChange` until the finger/scroll settles for ≥ ~300 ms. Slow scrolling with micro-pauses can still fire **several times per second**.

### 4.2 Kudos iOS (`ReadiumReaderView.swift`)

```
locationDidChange(locator)
  → ReadiumBook.currentLocator = locator          // @Observable → progress pill / readingPosition
  → onLocatorChange?(locator)
       → locator.persistenceString                 // JSONSerialization on MainActor
       → work.readiumLocator = …
       → work.markProgressModified(Date())         // lastReadDate, progressModifiedAt, lastModifiedAt, syncStatus
       → try? modelContext.save()                  // FORCE save every time — NO debounce

viewportDidChange(viewport)                        // T-94
  → currentViewport = viewport                     // @Observable
  → isAtPublicationEnd = ReadiumReaderCompletion.isAtEnd(...)
  → onReachedPublicationEnd?() only on rising edge // rare; may save once at true end
```

Primary symbols / lines (current tree):

| Symbol | File | Lines (approx.) |
|---|---|---|
| `navigator(_:locationDidChange:)` | `kudos-ao3-reader/Features/ReaderReadium/ReadiumReaderView.swift` | 291–294 |
| `navigator(_:viewportDidChange:)` | same | 300–307 |
| `onLocatorChange` assignment + save | same | 885–889 |
| `persistCurrentProgress()` (dismiss flush) | same | 743–749 |
| `Locator.persistenceString` | same | 959–970 |
| `ReadiumBook.readingPosition` | same | 189–208 |
| `markProgressModified` | `kudos-ao3-reader/Models/Models.swift` | 480–484 |
| `folderSyncChangeToken` + `scheduleFolderSyncUp` | `kudos-ao3-reader/App/ContentView.swift` | 215–239, onChange 135–137 |

### 4.3 Downstream of every save

```
modelContext.save()
  → SwiftData persists SavedWork
  → @Query observers refresh while reader is pushed on NavigationStack:
       • ContentView: 7 full-table @Queries (works, bookmarks, fonts, …)
       • HomeView: all non-deleted works → re-filter/re-sort Reading Now / Recently Opened
         (sorted by lastReadDate / recency — see HomeSections.swift)
       • LibraryView: full works @Query (still in tab hierarchy)
  → ContentView.folderSyncChangeToken changes because lastModifiedAt advanced
  → FolderSyncService.markDirty()
  → scheduleFolderSyncUp() cancels/reschedules 7 s MainActor Task → eventual syncUp
```

Home still exists under the reader:

- `HomeView` / `LibraryView` use `NavigationStack` + `navigationDestination(for: LocalWorkDestination.self)` → `BookReaderView`.
- Parent views remain alive; `@Query` continues to receive store updates.

---

## 5. Why Scrolled mode specifically?

| Mode | How often Readium notifies location | Effect of unthrottled `save()` |
|---|---|---|
| **Scrolled** | After every settle / micro-pause (~0.3 s debounce, can be frequent while reading) | High main-thread save + observation load |
| **Paged** | On page / spread change only | Low frequency; same code path usually fine |

Architecture map even documents the iOS policy:

> Reader — iOS … progress saved per `locationDidChange`
> (`docs/ARCHITECTURE_MAP.md`, `docs/REGRESSION_TEST_MATRIX.md`)

macOS contrast (healthy pattern):

- Layout script is **rAF-throttled**; host uses `ReaderProgressBridge` (`minPersistInterval = 2 s`, `minPersistDelta = 0.001`).
- `persistProgressIfDue()` mutates model fields but **does not** call `modelContext.save()` on every tick; save is flush-oriented (disappear / terminate).

---

## 6. Hypotheses ranked

### H1 — **Primary (strongly supported): main-thread SwiftData save + observation storm on scroll settle**

**Evidence:**

- Unconditional `try? context.save()` in `onLocatorChange` (lines 885–889).
- `markProgressModified` always rewrites `lastReadDate` and `lastModifiedAt` (Models.swift 480–484).
- Root `@Query` + `folderSyncChangeToken` recompute on every such write.
- Scrolled mode multiplies callback frequency vs paged.
- Documented intentional design (“saved on every `locationDidChange`”) with **no** debounce, unlike macOS T‑94 bridge.

**Would present as:** intermittent freezes/hitches after short scrolled reading, worse with large libraries and/or folder sync enabled; often correlating with **pauses** during scroll rather than peak fling velocity.

### H2 — **Secondary (supported): SwiftUI invalidation of reader chrome via `@Observable ReadiumBook`**

Every `currentLocator` assignment recomputes `readingPosition` (linear scan of `positionsByReadingOrder`) and refreshes the bottom progress pill. T‑94 also writes `currentViewport` / `isAtPublicationEnd` on each viewport update.

**Would present as:** smaller but measurable body updates concurrent with H1; unlikely sole cause of multi-second hang, can contribute jank.

### H3 — **Secondary / content-dependent: WKWebView / Readium layout cost for long or image-heavy resources**

Scrolled reflowable chapters are one continuous WebKit document. Long chapters and many images increase scroll-thread + main-thread layout/compositing cost independent of Kudos persistence.

**Would present as:** hang **during** continuous scroll (before 0.3 s settle), memory growth, worse on older devices; may co-exist with H1.

### H4 — **Amplifying: folder sync dirty + reschedule on every progress stamp**

`folderSyncChangeToken` includes `newestDate(folderSyncWorks.map(\.lastModifiedAt))`. Progress saves always advance `lastModifiedAt`, so every settle marks dirty and resets the 7 s sync-up timer. If the user rests ≥ 7 s, `syncUp` can run a full package write on the main actor behind `PersistenceOperationGate`.

**Would present as:** freeze **after stopping** for several seconds with Auto Sync + connected folder; not required for H1 hitches.

### H5 — **Unlikely primary: gesture-recognizer conflicts**

Dismiss pan uses simultaneous recognition and walks the view tree for `isAtTop` only on pan begin. Cost is occasional, not continuous during scroll.

### H6 — **Unlikely primary: completion logic runaway**

`onReachedPublicationEnd` is rising-edge only and gated by `isComplete && !isFinished`. Cannot fire every scroll frame.

### H7 — **Ruled out as sole regression source: T‑94 introducing save-on-locator**

Parent of `1b88fe3` already had:

```swift
work.readiumLocator = …
work.markProgressModified(now)
// optional finish at 0.99
try? context.save()
```

T‑94 moved finish detection to viewport true-end and **kept** the per-locator save.

---

## 7. Exact execution path believed responsible for the hang

```text
[Scrolled] UIScrollView / JS progression activity
    └─(0.3s quiet)─► notifyPagesDidChange
         └─► updateCurrentLocation (idle-gated)
              ├─► locationDidChange(Locator)                 // MainActor
              │     ├─ currentLocator = locator              // @Observable
              │     └─ onLocatorChange:
              │           ├─ JSONSerialization (persistenceString)
              │           ├─ SavedWork field writes
              │           ├─ markProgressModified(now)       // lastReadDate + lastModifiedAt
              │           └─ modelContext.save()             // ★ main-thread disk + notify
              │                 ├─ Home/Library @Query refresh + section re-sort
              │                 └─ ContentView folderSyncChangeToken change
              │                       ├─ markDirty()
              │                       └─ reschedule syncUp (7s)
              └─► viewportDidChange                          // T-94 @Observable writes
```

The **★** step is the highest-leverage main-thread cost unique to Kudos (not Readium).

---

## 8. Profiling evidence

### What was gathered

| Evidence type | Status |
|---|---|
| Time Profiler / Main Thread Checker captures | **Not run this session** |
| Memory Graph / Allocations | **Not run this session** |
| Static path analysis | **Done** |
| Readium 3.9.0 source (debounce 0.3 s, idle poll 0.1 s) | **Done** |
| Cross-platform contrast (macOS bridge) | **Done** |
| Git history (`4c5de9fd`, `1b88fe3`, macOS `ReaderProgressBridge`) | **Done** |

### What Instruments should show if H1 is correct

- Main thread samples dominated by:
  - `ModelContext.save` / SwiftData / Core Data
  - SwiftUI attribute graph / `@Query` / `HomeSectionKind.works` sort
  - Secondary: `JSONSerialization`
- Spikes **aligned with scroll settles**, not necessarily with peak scroll velocity.
- Paged mode: far fewer spikes for same reading duration.
- Disabling folder sync: may reduce post-pause freezes (H4) but not eliminate settle hitches (H1).

### What Instruments should show if H3 dominates

- WebKit / `WKWebView` / compositing / image decode high **during** active scrolling.
- Hang severity tracks chapter length / image count more than library size.

---

## 9. Commit / regression attribution

| Change | Commit | Relation to hang |
|---|---|---|
| iOS save on every `locationDidChange` | Phase 2 Readium (`4c5de9fd` lineage) | **Root pattern** — still present |
| Continue Reading / `markProgressModified` | T‑40 era (`24105aa2` and follow-ons) | Increases observation cost (stamps `lastReadDate`) |
| Folder-sync dirty token on work `lastModifiedAt` | Folder-sync feature | **Amplifier** of every progress save |
| Compact progress pill / readingPosition | `2fe9213` et al. | Minor per-locator SwiftUI cost |
| Swipe-dismiss gestures | `cbc4ab0` / `f9ff032` | Unlikely continuous cost |
| **T‑94 reader completion + macOS progress** | `1b88fe3` on `release-fixes` | **Does not add** iOS save; **does add** viewport `@Observable` updates; **macOS only** gets debounce (`ReaderProgressBridge`) — iOS asymmetry made more obvious |

**Conclusion:** Not a clean “T‑94 broke scrolling” regression. It is a **long-standing iOS design** (persist every locator) that becomes pathological under scrolled-mode settle frequency + library/sync observers. T‑94 improved macOS and slightly increased iOS per-update observable writes.

---

## 10. Recommended fix (for review — **do not implement until approved**)

### Preferred approach (mirror macOS; minimal behavior change)

1. **Introduce an iOS progress bridge** (reuse or share `ReaderProgressBridge` ideas):
   - Keep latest `Locator` in memory on every `locationDidChange`.
   - **Debounce / throttle** durable writes (e.g. `minPersistInterval ≈ 2 s` and/or delta on `totalProgression`).
   - Always **flush** on: disappear, dismiss drag success, scene background, app terminate, chapter jump if needed.
2. **Split “UI locator” from “persisted locator”:**
   - Update `currentLocator` for the progress pill freely (or throttle pill to 10 Hz).
   - Do **not** call `markProgressModified` + `save` on every tick.
3. **Optional:** only stamp `lastReadDate` once per reader session open (or at most every N minutes), not every progress byte — Continue Reading order does not need sub-second resolution.
4. **Optional:** exclude pure progress field changes from `folderSyncChangeToken` (or debounce dirty with a longer window dedicated to progress) so reading does not mark the whole library dirty every settle.
5. **Do not** block on `FolderSyncService.syncUp` during reading; keep close-path 1.5 s task, but avoid dirty thrash mid-scroll.

### Suggested API sketch (implementation later)

```swift
// Pseudo — not landed
final class ReadiumProgressPersistence {
  static let minInterval: TimeInterval = 2
  private var lastSaved: Locator?
  private var lastSavedAt: Date?
  private var latest: Locator?

  func note(_ locator: Locator) { latest = locator /* maybe UI callback */ }
  func saveIfDue(to work: SavedWork, context: ModelContext) { /* interval + delta */ }
  func flush(to work: SavedWork, context: ModelContext) { /* always if dirty */ }
}
```

### Explicit non-goals for the first fix

- Rewriting Readium.
- Changing completion true-end rules (A7‑F1).
- Removing force-quit safety (flush on background/disappear preserves it).

---

## 11. Risks and possible regressions from the proposed fix

| Risk | Mitigation |
|---|---|
| Force-quit loses more progress | Flush on `scenePhase` background / resign active / terminate; keep disappear flush |
| Continue Reading shelf feels “stale” mid-session | Acceptable; update `lastReadDate` on open + flush + debounced saves |
| Folder sync less aggressive during reading | Still dirty on flush; 7 s schedule after last durable write |
| Progress pill jumps if UI also throttled | Prefer keeping UI locator live; only throttle persistence |
| Tests / matrix text (“saved on every locationDidChange”) | Update `REGRESSION_TEST_MATRIX.md` + ARCHITECTURE_MAP when implementing |
| Over-sharing macOS bridge types | Keep platform-neutral pure debounce logic testable in `KudosTests` |

---

## 12. Focused validation plan (post-fix)

### Automated

1. Unit tests for iOS progress debounce (interval, delta, flush-always, no save when unchanged).
2. Ensure completion true-end still independent of debounce (A7‑F1 tests unchanged).
3. `Scripts/verify.sh` green (iOS suite + macOS build).

### Manual / Instruments

1. **Time Profiler** scrolled vs paged, same long work, 60 s scroll — compare main-thread `%` in `ModelContext.save` / SwiftUI.
2. **Main Thread Checker** on.
3. Library sizes: empty vs 500+ works — hang should track library size if H1.
4. Folder sync on vs off — post-pause freezes if H4.
5. Kill app mid-chapter after only debounced window — resume within acceptable loss (≤ debounce interval of reading).
6. iPhone + iPad layouts; image-heavy chapter for H3 residual.
7. Confirm dismiss / background still restores exact last viewport.

### Acceptance criteria

- No multi-hundred-ms main-thread hitch correlated with settle saves during slow scroll.
- Progress loss on kill ≤ debounce interval.
- No regression in auto-finish at true publication end.
- Paged mode unchanged or improved.

---

## 13. Temporary diagnostic instrumentation (allowed; **not landed**)

If a follow-up session adds probes, keep them behind a compile flag, e.g.:

```swift
#if DEBUG && KUDOS_READER_DIAG
// OSSignposter intervals around save / locationDidChange
#endif
```

Do **not** merge diagnostic logging into release without removal. Prefer Instruments first.

---

## 14. Remaining uncertainty

1. **Wall-clock split** between H1 (save/query) and H3 (WebKit) without Instruments is unknown; both can contribute.
2. **Interactive hang severity** not captured on device in this session.
3. Whether **autosave** would have been cheaper than explicit `save()` (likely still notifies `@Query`; explicit save forces synchronous work).
4. Exact frequency of Readium callbacks on real AO3 EPUBs (positions density, multi-resource spreads) not measured live.
5. Whether `JSONSerialization` of locators is measurable vs SwiftData (expected minor).
6. iPad two-column / multitasking may change idle state timing in Readium’s `execute(when: idle)` gate.

---

## 15. Files to touch in a future fix (preview)

| File | Change |
|---|---|
| `Features/ReaderReadium/ReadiumReaderView.swift` | Debounced persistence; flush points; maybe thinner `@Observable` viewport writes |
| `Features/Reader/ReaderProgressBridge.swift` (or new shared type) | Generalize for Locator / Readium |
| `Models/Models.swift` | Possibly session-scoped `lastReadDate` policy |
| `App/ContentView.swift` | Consider not dirty-syncing on pure progress timestamps mid-read |
| `KudosTests/*Progress*` | Debounce + flush coverage |
| `docs/ARCHITECTURE_MAP.md`, `docs/REGRESSION_TEST_MATRIX.md` | Policy text: no longer “save every locationDidChange” |

---

## 16. Bottom line

**Most strongly supported root cause:**
On iOS Scrolled mode, each Readium settle (`locationDidChange`, ~0.3 s after scroll activity) performs **unthrottled MainActor SwiftData mutation + `save()`**, which refreshes large still-mounted `@Query` graphs and folder-sync dirty tracking. That is a classic high-frequency callback → expensive synchronous work hang. macOS already avoids this; iOS should adopt the same debounce/flush pattern without waiting for a speculative Readium rewrite.

**Next step for humans:** run Instruments Time Profiler on the repro matrix in §2 and confirm samples land in `ModelContext.save` / SwiftUI query updates; then approve the §10 fix for implementation on a dedicated branch.
