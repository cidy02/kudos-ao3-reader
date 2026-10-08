# 3br result: real reader end and chapter scrub

## iOS rules read from code

Reference root: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`; read only.

- `Features/ReaderReadium/ReadiumReaderCompletion.swift:21–33`: require a viewport and a final reading-order link; normalize that link's URL; find that visible resource; require its progression **upper bound exactly 1.0**. Both paginated and scrolled reading use this rule: the last page can have a leading edge below 1 while its trailing edge is at 1; scrolling finishes when the viewport reaches the resource's bottom. No whole-work percentage participates.
- Its comment at lines 9–18 explains the exact boundary and rejects a tolerance: “any tolerance would re-admit the \"99% ≈ done\" defect this replaces.” The locator's total progression is the leading edge and interpolated, not an end signal.
- `ReadiumBook.swift:1010–1021`: a viewport change updates `isAtPublicationEnd`; only its rising edge calls `onReachedPublicationEnd`. Dismissal blocks ingestion.
- `ReadiumReaderView.swift:1385–1402`: reaching the end writes the current locator, marks that position persisted and sync dirty; only a complete, unfinished work gets `isFinished = true` and a full progress stamp. WIPs remain manual. This does **not** invoke explicit Mark as Finished or hold/free the copy. The reader stays open on the end page, with the normal floating chrome; no new completion dialog or forced navigation is presented by this callback.
- `ReadiumReaderView.swift:428` calls `WorkLifecycle.freeEPUBIfFinished` on disappearance: an eligible un-kept copy starts its 60-day hold when leaving. Explicit Mark as Finished retains its separate lifecycle behavior.
- `ReadiumBook.swift:233–306`: whole-work percent is the rounded locator total progression × 100; chapter place comes from the current reading-order resource. Page and count are measured **visual swipe pages in that resource**, never the ~1 KB position list. While measurement is unavailable the page line waits.
- `ReaderTimeEstimate.swift:98–146`: bottom line is `Chapter N of M · P% of work · D left`. Posted chapter total wins, floored at N; Preface/Summary/Afterword are named, Other omits the place. Unknown remaining positions omit time. Duration is rounded from positions × 55 / 60 minutes, formatted `12 min`, `1 hr`, or `1 hr 5 min`.
- `ReadiumReaderView.swift:1136–1209`, `ReaderPositionCard.swift`: top line is `Page N of M`, with `D left in chapter`; while measuring, `Page …`, no chapter time, disabled slider, accessibility value `Measuring pages`. Bottom time is the work's remainder; top time is the chapter's. Chapter remainder scales `(pageCount − page) / pageCount` by chapter position count and rounds; work remainder is total positions minus global position (`ReadiumBook.swift:469–493`, `ReaderPageMetrics.swift`).
- `ReadiumReaderView.swift:1776–1870`: slider range 0…1, thumb `(page − 1)/(pageCount − 1)`; a one-page chapter reads full (1) and is disabled. Drag freezes the origin tick, rounds to a preview page, snaps back when preview matches the origin page, and emphasizes changed page/time numbers. Each changed page live-seeks within the current resource; release commits that page even if the last live seek was missed. `ReadiumBook.swift:404–448` copies the locator, changes resource progression, clears discrete position, and coalesces live seeks to latest-wins. Transient drag locations aren't debounced saves; current locator still advances for a leave-mid-drag flush. `ReaderPositionCard.swift` labels the slider `Seek within chapter`, with value `Page N of M`.

## Kotlin capability and implementation

A5-2/A5-3 and the audit's final triage read; 3j/3q/3ao including landing notes read. Initial worktree clean on `android/agent-gemini-3br`.

Version: `android/gradle/libs.versions.toml` pins Readium **3.3.0**. The cache contains AARs, not Kotlin source JARs. Read the cached navigator's bundled `assets/readium/scripts/readium-reflowable.js` directly without extracting files; inspected cached navigator/shared class signatures and relevant bytecode with `javap`; read the matching upstream 3.3.0 Kotlin source at the links below. No toolkit sources or build outputs were added to this worktree.

- [EpubNavigatorFragment](https://raw.githubusercontent.com/readium/kotlin-toolkit/3.3.0/readium/navigator/src/main/java/org/readium/r2/navigator/epub/EpubNavigatorFragment.kt), lines 252–255, 277–285, 972–1022: no Swift-style public viewport range. `PaginationListener.onPageChanged(pageIndex, totalPages, locator)` reports the settled reflowable WebView's **zero-based physical page index and count**, after load/ready gating and a 100 ms quiet period. The current locator flow and the pagination callback describe the same resource. `evaluateJavascript` awaits the loaded current reflowable resource; it is the public route to its scroll extent. The factory's actual `paginationListener` argument was checked in both source and cached bytecode.
- [R2WebView](https://raw.githubusercontent.com/readium/kotlin-toolkit/3.3.0/readium/navigator/src/main/java/org/readium/r2/navigator/R2WebView.kt), lines 294–299, 1005–1009: page index comes from native horizontal scroll/viewport width; count rounds horizontal range/viewport width. The horizontal count is **not** a scrolled page count. The adapter reverses physical pages in RTL before using the final page as the navigator's paginated end.
- [R2BasicWebView](https://raw.githubusercontent.com/readium/kotlin-toolkit/3.3.0/readium/navigator/src/main/java/org/readium/r2/navigator/R2BasicWebView.kt), lines 121–166: locator resource progression divides leading offset by full content size; even the scrolled bottom usually stays below 1. Vertical text uses the horizontal axis. Internal end/scroll methods are not public viewport observations; `goForward` can attempt a resource jump and is not a safe end probe.
- Cached `readium-reflowable.js`: Readium's own `scrollToPosition` uses `document.scrollingElement`, full resource extent, and resource-local progression, with horizontal/vertical and RTL handling. Android now calls that existing function for live and release scrubs, through `evaluateJavascript`, with latest-wins coalescing and a frozen resource href. It does not create a second navigation engine or cross-resource jump.

`ReadiumNavigatorHost` uses the native pagination callback in paginated mode. In scrolled mode, it reads only `{offset, extent, range}` from that loaded resource's scrolling element (including vertical text), discards a result if locator/settings changed during the read, and calculates the resource's actual bottom from **offset + visible extent >= full extent**, with no tolerance. Scrolled display pages round extent ratios like iOS; those rounded page labels never trigger scrolled completion. Missing/invalid metrics or an unknown href do not finish anything. All measurements are local; no requests are added.

`ReaderViewport` is transient UI state, separate from `ReaderProgress`. `EndOfWorkActions.isAtEndOfPublication` requires an exact final reading-order index and either the navigator's last paginated page or the measured scrolled resource bottom. It no longer accepts total progression or a chapter-progression threshold. A one-page final resource and a one-resource work follow the same rule.

`ReaderViewModel.onViewport` finishes complete works even on the initial end-page landing (independent of the persistence gate), flushes existing pending progress before writing the current location, then calls `ReaderRepository.finishAtPublicationEnd`. That method stamps finished/progress/shelf dates without touching `freedAt`. `pauseReadingSession` does not hold; `close` still ends the session and calls `ReaderRepository.close` → `WorkRepository.holdFinishedCopy`. The explicit `markFinished` → `setFinished` path remains unchanged and still holds immediately. No new completion screen was added.

`ReaderScreen` draws from its collected `ReaderUiState.Reading`, including `viewport` and `liveProgress`. Position lists are obtained from the existing publication positions service, not another download. `ReaderProgressDisplay` now supplies the iOS words, rounded percent, chapter-local thumb/page arithmetic, scaled chapter remaining positions, and 55-second position duration formatting. Work time uses total position count minus the live global position. The card retains its tokens, dimensions, glass and layout. Its slider has separate `Seek within chapter` description and `Page N of M` state value, page-based origin snapping, live preview, and a release callback. The chapter href/page count are frozen while dragging. Transient drag reports update live state without debounced saves; release resumes the existing save path, and background/close flush the latest settled drag location.

No persistence DTO, locator envelope, mapper, Room entity/schema, backup format, WorkRepository finish/hold policy, demo or iOS file changed.

## Where iOS code won

- iOS uses rounded percent and defaults a missing navigator total to zero; removed Android's floor and spine-count percent guess from the card formatter.
- iOS's scrolled **page labels round** both ratios; used that rather than a ceiling page count or floor page digit. The exact scroll extent still decides completion.
- iOS live-seeks during dragging and commits again on release; retained both, rather than interpreting the audit's older release-only description literally.
- A one-page chapter is full and disabled. Time uses Readium positions, not work word count; durations of an hour or more use hours. The chapter denominator uses the known AO3 total as the reference does.

## Tests written, not run

| Suite | Claims requiring Claude's test run |
|---|---|
| `EndOfWorkActionsTest` | 98.5% long work remains unfinished in either mode; old 97% last-chapter rule rejected; exact last page/bottom; one-page final chapter; one-chapter work; earlier-resource end, unknown href and missing/invalid metrics fail closed. |
| `ReaderProgressDisplayTest` | Rounded/missing-total percent and exact chapter/matter words; chapter-page thumb/preview; full one-page bar; minutes scale visual pages to positions; duration/hour words; AO3 total and stale-total floor. |
| `ReadiumProgressAdapterTest` | First/middle/last chapter drag targets preserve href at 0/0.5/1, change resource progression and clear discrete position. Existing fallback/save mapping tests retained. |
| `ReaderPositionCardTest` | Real card semantics/value, separate chapter/work time words, live drag callback and single release callback, one-page disabled/full, measuring label with no fabricated chapter time. Tall window, native graphics. |
| `ReaderRepositoryTest` | Auto finish preserves location and EPUB without a hold; leaving starts/keeps the first hold date; WIP remains manual; explicit finish still holds immediately. |
| `ReaderCompletionTest` | Actual ViewModel → repository → Room path: threshold landing doesn't finish, last page does, background doesn't hold, close holds and retains the file. No Readium rendering or transport is involved. |

Static verification: `sh android/Scripts/check-invariants.sh` and `git diff --check` passed. This is **not** compilation or test success. Gradle/Xcode were not run. Claude should run Android assembly, the six suites above plus the existing reader/session/progress regressions, and the Android verify gate.

## Decided without asking

- Use existing reader/unit-test files where possible; no demo changes, network fixtures, new EPUBs, scripts, schema or backup changes.
- Put the transient resource metrics in `reader/ReaderViewport.kt`; put actual card and completion integration coverage in `ReaderPositionCardTest.kt` and `ReaderCompletionTest.kt`. Reuse the existing repository test's temporary local file-presence setup, not a new EPUB fixture. AO3-looking fixture URLs are identity strings only; no transport is created or called.
- Use Kotlin's public pagination callback for paginated pages and its public loaded-resource JavaScript evaluator for scrolled extent. Use Readium's already-shipped `scrollToPosition` for scrub backpressure instead of queuing synchronous `go` calls whose `true` return does not mean navigation completed.
- Follow the brief's prohibition on TASKS edits and git operations over the general AGENTS workflow.

## Open questions

- Build/test and emulator verification belong to Claude; Gradle and Xcode will not be run here.
- Kotlin 3.3.0 has no public native viewport equivalent. The paginated rule uses its own final page; scrolled completion uses the actual loaded resource's strict scroll end, obtained through its public evaluator. **Manual gap:** verify that the DOM extent and native viewport agree at the bottom on horizontal/vertical text, RTL, short resources, after settings/rotation and with delayed font/image layout. No percentage fallback is used if measurement fails.
- Fixed-layout publications do not supply this reflowable pagination/scroll measurement. They remain manual-finish; adding a separate fixed-layout viewport adapter would cost more reads and behavior than this AO3 reader brief requires.
- The iOS custom page-measurement stabilization pipeline was not copied: paginated metrics use Kotlin's own loaded/settled callback; scrolled labels use the loaded DOM sample. Emulator verification must check for transient page counts on layout changes. No visual correctness claim is made.
- A5's triage already leaves reader-dispose versus ViewModel cancellation ordering open. This brief preserves that lifecycle ownership; verify close/background and leave-mid-drag on a device, including the hold timestamp and final resume point. The tests cover completion/close with a live ViewModel, not OS reclamation during disposal.

Manual handoff: offline imported/local EPUB, both reading modes, long last chapter before the actual end, true end and one-page last resource; open the card in first/middle/last chapters, scrub and release/reopen; check chapter time versus work time, TalkBack, origin cancel, a rapid drag and leave-mid-drag. Confirm no hold while still reading/backgrounded and a hold only after leaving; also check an explicit finish and a WIP. No sign-in or AO3 contact is needed.

## Landing note (Claude, 2026-10-08)

Applied cleanly; gate green at the first run (2,096 tests, 2,097 with the test added here).

**Found while testing, and older than this brief: a saved position from another file killed
the reader's position tracking.** The stored locator was handed to Readium without checking
that the book has the resource it names. When it does not (the work was rebuilt, replaced or
re-downloaded with different parts), Readium opens at the start and never reports a location
again: the position card stayed on "Page …", and **nothing was saved for that work from then
on**, so it reopened at chapter 1 every time. `ReadiumProgressAdapter.initialLocator` now
drops such a locator and the book opens at the beginning. Test
`aPositionFromAnotherFileOpensTheBookAtTheBeginning`. iOS not checked for the same fault.

Seen on `emulator-5556` in airplane mode, scrolled reading, with a six-chapter test book
(about two hours long) put in place of two demo works' files:

- The card: "Page 1 of 16", "18 min left in chapter", "Chapter 2 of 6 · 15% of work · 1 hr
  45 min left". Dragging the thumb went to page 11 and then 16 of 16, the work's percent to
  25 and 29, and the chapter stayed chapter 2 (before this brief a drag jumped to the start
  of some chapter).
- A one-page work opens on its only page, which is its end: finished on leaving, as iOS.
- The finish rule, on a complete work in its last chapter: left at 96% of the work (page 21
  of 24) and again at 98% (page 22): **not finished**, and reopened where it was left. At the
  last page scrolled to its bottom: finished after leaving. The old rule finished at 98.5%.

Not seen: paginated reading (the brief uses the navigator's own page count there); the
60-day hold's stamp on leaving; right-to-left and vertical text; a drag abandoned half-way.
Still open from audit A5: whether leaving the reader can lose the session's end when the
view model is cleared first.
