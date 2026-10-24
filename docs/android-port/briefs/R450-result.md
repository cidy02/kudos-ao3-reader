# R450 — adversarial review of Duo5b

What this change does: Duo5b records app navigation intent before dispatch, caches a content anchor before resize, and replaces resize `go(to:)` with a bounded JavaScript scroll. It adds a navigation test seam and tears down the navigator on reader disappearance.

**Result: five P1 findings and one P2 finding. Do not land this patch.** These are source-traced failure paths, not device reproductions.

## Scope and evidence

Reviewed `~/kudos-tools/out/backups/Duo5b.patch` against `97187d9ae8dd09835f6bbf81549c20422cf2ce88`. Reconstructed its five patched files in memory and confirmed they exactly match the live files in `~/kudos-agent-ios2`; app/test line references below refer to those patched files, not this review worktree's unrelated Duo6 edits.

Path abbreviations:

- **Book**: `kudos-ao3-reader/Features/ReaderReadium/ReadiumBook.swift`
- **Driver**: `kudos-ao3-reader/Features/ReaderReadium/ReadiumResizeNavigation.swift`
- **View**: `kudos-ao3-reader/Features/ReaderReadium/ReadiumReaderView.swift`
- **Tests**: `KudosTests/ReadiumResizeNavigationTests.swift`
- **SDK**: `/Users/cidy02/Library/Developer/Xcode/DerivedData/kudos-polish/SourcePackages/checkouts/swift-toolkit/Sources/`. The checkout is clean and at pinned Readium 3.9.0 revision `de07026e9f825a5791f27a7ac4cd6bb1a784ab8d`, matching `Package.resolved`.

Read R449's result, Duo5b's notes, the relevant project/persistence/reader guidance, and the local migration notes in `kudos-agent-ios2`. Inspected both supplied screenshot montages.

## Does it close R449's four findings?

| R449 finding | Assessment |
|---|---|
| **1. Explicit navigation loses to resize** | **Partly.** App bookmark/Contents/Find/annotation/seek/speech calls converge on `navigate`, which synchronously cancels the hold, increments its generation, and restarts measurement when needed (`Book:1369–1380`). The post-await/final generation fences prevent stale Swift publication (`Book:1523,1532`). Native scrolling and SDK internal links do not converge there: finding 2. |
| **2. Resize captures the previous chapter while a chosen chapter loads** | **The normal app Contents A→B case is closed.** Pending intent precedes dispatch, old-href callbacks cannot settle it, and geometry does not hold A while B is pending (`Book:664–672,1463–1464`). Both return/callback orders are handled. The pending-intent mechanism is not complete: same-page accepted navigation can remain pending indefinitely (finding 3), and native link navigation bypasses it (finding 2). |
| **3. Pixel fraction is not a passage** | **Not closed.** A cached anchor is used and saved during the hold, which is an improvement. But the pinned API identifies an entire block, not the visible text position inside it: finding 1. Even a good short-block anchor can lose to an SDK pending scroll or a late load: findings 4–5. The explicitly named progression fallback remains approximate. |
| **4. Failed reload leaves an uncancellable restore wait** | **Closed for the new resize adapter's own await, not for the whole lifecycle.** Its timeout/cancellation continuation is bounded and exactly-once (`Driver:76–100`), and the restore loop weakly references the book across waits. However, new anchor capture still enters an unbounded SDK wait, and serialized explicit commands still use the original SDK wait: finding 6. Ending the app hold also does not finish SDK rendering or make the saved position safe: finding 5. |

## Must fix

### 1. P1 — A paragraph spanning pages restores to its beginning

**Patched locations:** `Book:1438–1449,1465–1468`; `Driver:37–38`.

**Sequence:** In either mode, read partway through a long `<p>`—for example, page three of a paragraph at a large accessibility text size. Let the anchor cache finish, then rotate. The SDK's `findFirstVisibleLocator()` selects the first intersecting block and returns its CSS selector and **entire** `textContent` (`SDK Navigator/EPUB/Scripts/src/dom.js:53–94,97–103`). A paragraph intersecting the viewport qualifies even when its start is several screens behind it.

**Result:** The cached locator identifies the paragraph's beginning. `scrollToLocator` resolves its whole text range, takes the range's bounding rectangle, and scrolls to that rectangle's beginning (`SDK Navigator/EPUB/Scripts/src/utils.js:209–228,295–313`). Scrolled mode jumps to the paragraph's top; paged mode snaps to an earlier page containing its beginning. Book also substitutes this anchor into `currentLocator` **before** restoration, so closing/backgrounding during the hold can save the wrong resume anchor even before any scroll succeeds. Blocks containing only inline content can make the anchor much larger than a paragraph. This is position loss, not page-number rounding.

**Smallest fix:** Capture a text range at the viewport's leading visible line, with a quote/selector and an intra-element offset, rather than treating the SDK's whole-block locator as the exact reading position. Preserve that range through persistence. Test a paragraph spanning at least three pages in both modes; a short paragraph immediately after an image alone does not catch this.

### 2. P1 — Native page/scroll and content-link navigation still lose to the hold

**Patched locations:** `Book:663,1369–1381`; `Driver:36`.

**Sequence:** While a resize hold is active, swipe/scroll to another passage, or follow an EPUB content link to chapter B. These operations do not call Book's `navigate`. The container preserves Readium's native gestures (`ReadiumNavigatorContainer.swift:20–22,128–169`); Readium enables native paging on the WebView's scroll view (`SDK Navigator/EPUB/EPUBReflowableSpreadView.swift:48–57`). Internal links call the SDK's own `go(to:)` after its delegate permission hook (`SDK Navigator/EPUB/EPUBNavigatorViewController.swift:1110–1144`). Book does not implement that hook to register intent.

**Result:** The unconditional hold gate discards their location callbacks. A same-resource restore scrolls back over the user's new passage. For a cross-resource link, the document-identity check rejects restoration of A into B, but all B callbacks during the hold were dropped; after retries expire, Book can still hold/save A while B is visible. Readium remembers the last callback it delivered and suppresses duplicates (`SDK Navigator/EPUB/EPUBNavigatorViewController.swift:703–725`), so simply clearing the hold does not replay B. The previous implementation at least released its hold on a different-href callback; this patch removes that escape.

**Smallest fix:** Register actual user navigation intent before native scroll/page gestures and SDK link dispatch, cancelling the hold there. Route `shouldNavigateToLink` through Book's command path (and return false to suppress duplicate SDK dispatch). Do not infer intent merely from any reflow location callback. Add native-input/link cases, including a different-href callback while held, rather than testing only Book's forward/backward wrappers.

### 3. P1 — A successful same-page seek can disable preservation indefinitely

**Patched locations:** `Book:1346–1353,1396–1402,1463–1464`.

**Sequence:** Release the seek slider on the current page, or let Read Aloud follow a sentence already on the visible page, then pause. The SDK can accept the command without changing the viewport. It emits no duplicate `locationDidChange` (`SDK Navigator/EPUB/EPUBNavigatorViewController.swift:718–724`). The `isAlreadyAt` check compares the **entire** target locator with Book's current locator. A progression seek clears `position` (`Book:407–413`), while normal viewport locators include it (`SDK Navigator/EPUB/EPUBViewportAndLocationCalculator.swift:94–102`); speech/bookmark text anchors also differ from normal viewport locators. Thus target equality is false despite a completed same-page navigation.

**Result:** `navigationTask` ends, but `pendingNavigation` stays set until some later location callback. Resize now skips acquiring any hold or anchor, even if the command finished long ago. Readium reflows/restores its old numeric progression, and the eventual same-href callback is accepted and saved. A mixed fixed-height/wrapping chapter reproduces R449.3's wrong-passage outcome. This is an unsettled-intent latch, rather than an endless `pageBoxRemeasureTask`.

**Smallest fix:** Acknowledge completed, loaded same-resource no-ops using the actual viewport/target containment, rather than full Locator equality. Preserve the pending state for genuinely loading targets; clearing it on every accepted SDK return would reintroduce R449.2. Add a driver case returning true with no callback and an equivalent viewport locator whose metadata differs, then resize and require a restore. Repeat with a text-anchored speech locator on the same page.

### 4. P1 — “Idle” does not mean the SDK's pending initial scroll has finished

**Patched locations:** `Driver:21–22,53–64`; `Book:1528,1533–1539`.

**Sequence:** Resize at passage A. The replacement HTML reaches `readyState == complete` and `web.isLoading == false`, while Readium's spread-load task is still in its 200 ms delay before applying `pendingLocation`. The adapter sees enabled ancestors and accepts an anchor restore during that interval.

**Evidence:** `_reloadSpreads()` calls `paginationView.reloadAtIndex(...)` and then **synchronously** raises `.loaded` (`SDK Navigator/EPUB/EPUBNavigatorViewController.swift:600–637`). `.loaded` changes state to idle and re-enables interaction (`:184–185,245–250`). The actual document task separately sets `isSpreadLoaded`, applies settings, delays, then scrolls to its pending location (`SDK Navigator/EPUB/EPUBSpreadView.swift:398–406`; `EPUBReflowableSpreadView.swift:147–165`). Ancestor interaction flags do not cover that delay. The adapter's comment claiming otherwise is false for this pinned source.

**Result:** The app restores the correct anchor, calls it successful, and releases its hold. The SDK's later initial scroll overwrites it with the old progression in the new layout; subsequent callbacks/persistence save the wrong passage. The 220 ms quiet delay is not a readiness guarantee: document loading can finish at any point relative to it. The same guard also ignores `web.scrollView.alpha == 0`, which Readium uses until `showSpread` (`SDK Navigator/EPUB/EPUBSpreadView.swift:124–125,436–441`). A successful script need not imply readable text is showing.

**Smallest fix:** Wait on actual completion of the SDK spread's pending-location scroll before accepting the app restore. Expose a loaded-and-presented signal, or gate this adapter on the SDK's completed presentation state with resource/generation identity. Keep that wait cancellable and bounded; neither an interaction flag nor a longer fixed delay proves it. Add the real ordering: idle/enabled + complete HTML, app restore, SDK pending scroll. The existing UIView test cannot represent it.

### 5. P1 — Retry exhaustion protects the locator only until the late load reports

**Patched locations:** `Book:1520–1529,1538–1542,663,698–705`.

**Sequence:** Hold a valid content anchor during resize. Let the replacement document take longer than the retry budget, then load successfully. Immediate rejection while `web.isLoading` is true exhausts twelve attempts in about **2.86 seconds**, including the initial quiet period and final retry sleep—not nine seconds. About 8.86 seconds applies only if every attempt spends its full 500 ms in the script bridge. There is no post-budget restore-on-load recovery.

**Result:** On exhaustion the code retains `currentLocator` momentarily, but clears the hold. The late SDK load restores its own old, unanchored progression; its next location callback now passes the gate, replaces the anchor with that wrong passage, and schedules persistence. Close/reopen and background flush preserve the newly wrong locator. A bounded hold is useful, but the bound currently abandons the position guarantee precisely on slow loads.

**Smallest fix:** Separate ending an active retry task from abandoning the saved resize target. On exhaustion, preserve the last good durable anchor and arrange a generation-scoped restore/reconciliation when that resource actually becomes ready; an explicit user navigation can supersede it. If recovery fails, expose a recoverable failure without publishing unverified reflow locators. Add a callback **after** exhaustion with a different progression and require it not to replace the saved passage. The current test instead sends the unchanged original locator.

### 6. P2 — Anchor capture still has an uncancellable SDK wait; explicit commands can stall the shared queue

**Patched locations:** `Book:1437–1440,1480–1481,1381–1389,1417–1424,1550–1551`.

**Sequence:** A location callback schedules anchor capture. Before that Task executes, geometry reloads the spreads and cancels the capture. The Task has no cancellation check before calling `navigation.firstVisibleElementLocator()`, so it can still enter the replacement spread's `spreadLoaded()` wait. Alternatively, cancellation happens after entry. Let that spread fail to send `spreadLoaded`. An explicit same-resource command issued while that replacement loads can likewise enter SDK `waitGoToCompletion`; newer commands then remain queued behind it.

**Evidence:** `firstVisibleElementLocator` calls `findFirstVisibleElementLocator`, which uses `evaluateScript`, which awaits `spreadLoaded()` with an unchecked-for-cancellation continuation (`SDK Navigator/EPUB/EPUBNavigatorViewController.swift:696–700`; `EPUBSpreadView.swift:175–186,416–425,505–506`). Explicit same-index navigation awaits `view.go` (`SDK Navigator/Toolkit/PaginationView.swift:334–335,405–409`), reaching the original continuation (`SDK Navigator/EPUB/EPUBReflowableSpreadView.swift:229–263`). Neither wait has a cancellation handler. Removing a spread does resume its go continuations (`:36–43`), but cancelling the app Task or nil-ing Book's navigator does not itself remove that retained spread. Resource-load errors use `didFailToLoadResourceAt`, whose default implementation does nothing; `presentError` is a different callback (`SDK Navigator/EPUB/EPUBNavigatorViewController.swift:1007–1014`; `Navigator.swift:123–124` and its default implementation).

**Result:** Cancellation does not bound these actual waits. The outstanding tasks retain their navigation boundary/spread even after Book drops its handles; while open, an unfinished explicit await blocks the shared command queue. The new weak-book restore loop improves Book ownership, but its test does not establish release of the production SDK graph. This is a stuck/retained-reader-resource defect; I am not claiming the weakly captured Book itself must be retained by this particular task.

**Smallest fix:** Use a bounded, cancellation-aware document callback for anchor capture too, with a pre-dispatch cancellation check and no SDK pending-load await. Make SDK explicit-navigation completion failure/teardown-aware before relying on one serialized queue. Handle the actual resource-error callback. A timeout wrapping the same uncancellable SDK await in another Task does not release it. Test stalled anchor acquisition and stalled explicit command completion separately from stalled restore scripts.

## Spinner / skeleton observation

The supplied `r5b-paged.png` contains a blank portrait viewport with a centered spinner at `paged-3-back-plain`, followed by text after interaction. `r5b-notap.png` also shows delayed text without taps. Those images establish delayed presentation, not its cause or exact callback sequence.

**No touch-required location-callback wait exists in the new restore loop.** It finishes on a JavaScript Bool or timeout and clears its own task/hold (`Book:1521–1542`). It does not await `locationDidChange`. Resize does not reset `hasPresentedFirstPage`; the SwiftUI opening skeleton is lifted by the initial callback or the independent three-second opening timeout (`Book:563–575`; `View:507–509`). Thus a normally opened reader's resize cannot newly latch that opening skeleton through this loop.

**The SDK spinner/hidden content can outlive the app restore.** Readium initially hides `web.scrollView` and only shows it after the separate spread-load/decorations chain (`SDK Navigator/EPUB/EPUBSpreadView.swift:124–125,398–406,436–441`; `EPUBNavigatorViewController.swift:1047–1084`). The adapter can call restoration successful before that chain finishes (finding 4), and exhausting app retries does not complete it (finding 5). WebKit `didFail` only logs; the SDK's two-second spinner-stop fallback is scheduled from `didFinish`, so a stalled load that never finishes has no such escape (`EPUBSpreadView.swift:643–649,718–748`). Book's new `presentError` handling is not a WebKit load-failure handler.

The exact 13-second observation remains **unproven** without event traces. A touch may coincide with delayed WebKit presentation or trigger further layout; source review does not establish that only a touch can unblock it. Before landing, trace geometry generation, resource, spread load/pending-scroll/show completion, script dispatch/result, and locator callbacks on a local fixture, and require bounded readable presentation or a recovery UI without input. Clearing the app hold alone is not that guarantee.

## Tests: real loop, incomplete boundary coverage

The new fixture **does** install `navigationOverride` (`Tests:300–315`), so geometry executes the production restore loop. It also reuses the real `ReadiumResizeScript` cancellation/timeout bridge (`Tests:358–367`). This fixes R449's objection that the fake was only passed as a delegate argument. There are 14 test functions, expanding to 32 cases.

- `explicitNavigationWinsDuringResize` and the pending-Contents test exercise synchronous cancellation, stale publication, and the two app-command/callback orders. Removing cancellation/pending-intent protection should violate their assertions. However, the fake injects the chosen target for every command (`Tests:26–28,378–382`); it does not model native gestures, internal links, deduplicated no-op callbacks, or physical scrolling by an already-issued script.
- The anchor test verifies use of a cached **supplied** locator. The fake returns that anchor immediately (`Tests:353–355`); it never runs the SDK's block selection or `scrollToLocator`. It would catch reverting cache selection, but passes with findings 1 and 4 intact.
- `restoreWaitsForTheSDKToFinishItsPendingScroll` only toggles a plain UIView's interaction flag (`Tests:137–150`). It proves the helper reads that flag, not that the SDK keeps it disabled during pending scroll. The actual pinned source contradicts that assumption.
- Rejection/stall, late completion, cancellation, and close tests meaningfully exercise the app bridge and retry bound. They do not exercise late **location** delivery after exhaustion: `Tests:113–115` sends the original locator, hiding finding 5. The fake's anchor never stalls, and even its explicit command await uses the cancellation-aware app bridge (`Tests:382`), unlike the production SDK in finding 6.
- `cancellationImmediatelyAfterRestoreReturnsFencesSideEffects` checks the publication outcome. Removing only the immediate post-await guard need not turn it red because the final cancellation/generation guard at `Book:1532` also blocks publication; the notes overstate that particular mutation's discriminatory power.
- `ordinaryForwardPublishesWithoutClearingMeasuredPages` checks Book's wrapper with an injected immediate callback. Actual ordinary swipe turns use native scrolling. In an unchanged-size phone session, the geometry equality guard schedules no restore, the callback path remains immediate, and measured digits are retained. I found no separate steady-size page-turn regression in that path; the test does not prove native rendering or input behavior.
- The seek-after-anchor test correctly checks removal of text/selector/fragments/position. The production scrub/release and speech calls do converge on the new queue (`Book:404–419`; `View:338–342,1888–1901`), but same-page speech/seek remains exposed to finding 3 and pending-load commands to finding 6.

No tests were run or mutated in this review. None of the new tests runs the actual document restore adapter in a WKWebView, checks SDK spinner presentation, or verifies persisted close/reopen behavior through the production View callbacks.

## Lifecycle and limits

Close and background flush use Book's held `currentLocator` (`View:914–934`), which is correct only if that anchor is correct; findings 1–5 can poison it. Explicit Close latches ingestion before disappearance, and disappearance performs the final flush/speech teardown before navigation teardown (`View:894–908,423–448`). Background does not tear down navigation or suspend restoration (`View:405–421`); slow background WebKit completion therefore still reaches findings 4–6. Reappearance of a retained SwiftUI reader has an opening `.task(id: bookLoadToken)`; no separate proven permanent nil-navigator skeleton was found from teardown alone (`View:376–382,1514–1516`). Reappearance/background timing was not exercised.

No builds, test execution, simulator interaction, sign-in, AO3/network access, source/task-board edits, branch changes, commits, or pushes. Only this result file was written. The patched Swift additions are iOS-guarded; no macOS/signing/project-file change is in this patch.

**Verdict: don't land. Fix findings 1–6, add tests for the actual document/readiness behavior, and rerun the local no-touch paged/scrolled presentation and close/reopen checks.**
