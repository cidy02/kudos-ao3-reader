# 3p — Home and Library first load

Measured on emulator-5554 only, debug build, demo library (15 active works). `visible=5` / `saved=5` is the existing mature-content filter, same counts before and after. Shelf rules were not changed.

`am start -W` TotalTime includes process start (ART, WebView, skipped frames) before `Activity.onCreate`. That stretch was 8–15s on this emulator with a second emulator and a phone also attached. It is not the library query.

## Before

Timing logs on the unfixed code.

Quietest non-demo cold start (`am start -W`, data already seeded, logcat cleared first):

| Point | Time |
|---|---|
| `am start -W` | COLD, TotalTime 12628 ms |
| `setContent` | +108 ms from `onCreate` |
| Displayed | +12628 ms from the start command, ~2.0 s after `onCreate` |
| Main-thread `decorate` of 15 works | 3547 ms (keep-state query 886 ms, per-work keeper queries 2661 ms), then a second pass 2646 ms (per-work 2635 ms) |
| Snapshot build on the main thread | 479 ms |
| "Loading your library…" | ~4.9 s |
| `setContent` → Home with data | ~9.6 s |
| Displayed → Home with data | ~7.7 s |

The same 15-work decorate on a background thread in that run was 64 ms. The main thread, not the SQL, was the cost. Home subscribed twice (`observeLibraryWorks` and `listSavedWorks` inside the update check).

Demo cold start after `pm clear` (`--ez kudosDemoLibrary true`):

| Point | Time |
|---|---|
| `am start -W` | TotalTime 25774 ms |
| `DemoLibrary.seed` on the main thread (`runBlocking`) | 2594 ms |
| `setContent` | +2915 ms from `onCreate` (blocked on the seed) |
| Two more main-thread decorate passes | ~1740 ms and ~1986 ms |
| Snapshot on the main thread | 388 ms |
| `setContent` → Home with data | ~12.7 s |

Library's first open matched Home: the same per-work queries ran again when the screen subscribed.

## After

Same device. Query numbers are from the instrumented build; the timing logs are removed in the tree this note describes.

Non-demo cold start (force-stop, library already seeded), 21:35:

| Point | Time |
|---|---|
| `am start -W` | COLD, TotalTime 11659 ms. ~10 s of that is before `onCreate` |
| Batched decorate, `DefaultDispatcher` | 30 ms, then 10 ms, both finished before `onCreate` |
| Snapshot of 15 works | 1 ms, before `onCreate` |
| `setContent` | +194 ms from `onCreate` |
| Displayed | +11659 ms, ~1.7 s after `setContent` |
| First Home composition | `loading=false`, visible=5, saved=5. No "Loading your library…" frame |
| That composition logged | 5.2 s after Displayed, 6.9 s after `setContent` |

Demo cold start after `pm clear`, 21:34:

| Point | Time |
|---|---|
| `am start -W` | TotalTime 17755 ms. `onCreate` ~13 s after the start command |
| `setContent` | +223 ms. The seed does not block it |
| `DemoLibrary.seed` off the main thread, one Room transaction | 2088 ms |
| Batched decorate + snapshot of 15 works | 26 ms + 1 ms, ~2.3 s after `setContent`, before Displayed |
| Displayed | ~3.7 s after `setContent` |
| Home | spinner at ~5.3 s after `setContent`, then visible=5 / saved=5 at 10.4 s after `setContent` (6.7 s after Displayed) |

Library tab, first open in the process: the first log was `loading=false`, items=5, saved=5. No second shelf query; the process already held the snapshot. Before that preload, the same tab reached data ~2.4 s after the tap, of which the query was ~0.45 s.

## What each change saved

- **Keep-state, one query.** `getKeptOfflineWorkIds` plus two keeper-name queries, first name per work wins, on `Dispatchers.IO`. Replaces a keeper query per work. Those per-work queries were 2.6–3.5 s on the main thread, and Home ran them twice. The batched pass is 7–30 ms off the main thread. About 5–7 s of main-thread work leaves a normal launch. A single work still uses `isKeptOffline`, with the same deleted-keeper rule as `getKeptOfflineWorkIds`.
- **Tags, collections, saved-for-later, one query each.** `observeLibraryIndex` loads tag links, active collections, membership links, and saved-for-later ids, then groups them in memory. Snapshot assembly went from 150–480 ms of N+1 on the main thread to 0–1 ms on `Dispatchers.Default`.
- **`conflate`, `distinctUntilChanged`, `flowOn`.** A burst of invalidations does not redo decorate on the collector. The demo seed is one `withTransaction`, so Room emits when it commits instead of once per insert. Seed duration stayed ~2.1–2.6 s (it was 2594 ms when it blocked the main thread).
- **Seed off the main thread.** `MainActivity` calls `KudosApplication.launchIo`. `setContent` went from +2915 ms to +223 ms.
- **Snapshot started in `Application.onCreate`.** `LibraryRepository` shares the flow on the application scope (`SharingStarted.Eagerly`). Home and Library use that snapshot as the `stateIn` initial value when it already contains works, so a normal launch composes Home with data and skips the spinner. An empty snapshot is not used as that initial value: during the seed it is the pre-commit database, and painting it composed an empty Home and then the real one.

## Targets

The library query is under 1 s. On a normal launch it finishes before `Activity.onCreate` (decorate 10–30 ms, snapshot 1 ms), and the first Home state is already loaded.

Two things that are still slower than the brief's wall-clock wording, and that this change does not claim to have fixed:

- `am start -W` TotalTime stays about 12–18 s. Almost all of it is process start before `onCreate`.
- The first Compose/draw of Home is a multi-second frame on this cold emulator (Davey frames of 4.5–8 s while the queries were already done). Displayed → painted Home with data was ~5 s on the normal launch and ~7 s on the demo launch. The shell and cover-card files named in the brief were not edited.

A demo launch shows the UI without waiting on the seed. The 15 works are in memory ~2.1 s after `setContent`. Painting them still waits on that cold Home frame, so the cards are not on screen within 2 s of the window.

`./gradlew :app:assembleDebug :app:testDebugUnitTest --offline --console=plain -q` exited 0 after the timing logs were removed. `DemoLibraryTest` reported 2 tests, 0 failures. Temporary `KudosLoad` logs are gone.
