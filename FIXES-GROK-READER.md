# Grok reader fix — WPB-3 Readium navigation guard hole

Local only. No push, no PR, no remote branch. Worktree: `/Users/cidy02/kudos-rcfix-reader` (`rc-fix/reader` off `security-fixes/rc`).

Implementer: **Grok 4.6**. Finding: **F3 / WPB-3** in `/Users/cidy02/kudos-fix-wp-b/REVIEW-CLAUDE-WPB.md`. Re-scoped **G1** (hostile-EPUB device probe) is this same hole.

Commit: `f10f032` — `Guard Readium spread web views at navigationDelegate assignment`

---

## What changed

### The hole

The guard that cancels off-publication navigation (`javascript:`, `data:`, `blob:`, `vbscript:`, `http(s)`, off-root `file:`) was installed **opportunistically** by walking WKWebViews already in the view tree:

| Site | When |
|---|---|
| `ReadiumBook.swift` after `EPUBNavigatorViewController` init | Spreads may not be in the tree yet; `loadSpread()` has already been called inside `EPUBSpreadView.init` |
| `ReadiumBook.navigator(_:locationDidChange:)` | After a page **settles** |
| `ReadiumNavigatorContainer.Coordinator.install` | On the next SwiftUI re-render |

Readium 3.9.0 (`EPUBSpreadView.swift`) does this in one initializer, in this order:

1. `config.setURLSchemeHandler(..., forURLScheme: viewModel.server.scheme)` — our store hook swaps in `isolatedDataStore`
2. `WebView(..., configuration: config)`
3. `setupWebView()` → `webView.navigationDelegate = self`
4. `loadSpread()`

Readium also **preloads adjacent spreads**. A freshly created preload therefore exists, has a delegate, and is loading **before** any of the three sweeps fire. Readium's own `decidePolicyFor` allows everything that is not `.linkActivated`, so a script-driven `window.location` on that spread had no Kudos policy.

The credential boundary (isolated non-persistent store ≠ default) was already real. The residual exposure is an unguarded spread becoming a full-page attacker document — phishing, not cookie theft.

### The fix

Reuse the existing `ReadiumStoreHook` (already installed first thing in `ReadiumBook.open`) and also swizzle `WKWebView.navigationDelegate`.

- Isolated-store web views (`configuration.websiteDataStore === isolatedDataStore`) are wrapped the moment a non-guard delegate is assigned — **before** `loadSpread()`.
- Browse / login web views use the default store and are not wrapped.
- `NavigationGuardStore.forceInstall` does **not** trust a stale map entry. If Readium later reassigns `navigationDelegate`, the new original is re-wrapped. The old `install` early-return on "already recorded" was the second half of F3.
- The three view-tree sweeps stay as belt-and-braces (they now also key off the **live** delegate, not the map) and refresh `onOpenExternalURL`.

Forbidden-scheme deny-list (`javascript` / `data` / `blob` / `vbscript`, evaluated before the origin switch) was not touched. WP-B's 11 existing tests were not weakened; 5 cases were added.

### Tests added (production entry = the setter)

Readium's real entry is `webView.navigationDelegate = self` in `EPUBSpreadView.setupWebView()`, not `installNavigationGuards(in:)`.

| Test | What it proves |
|---|---|
| `assigningNavigationDelegateOnAnIsolatedStoreWebViewInstallsTheGuard` | Isolated store + assign a plain delegate → live delegate **is** `ReaderWebNavigationGuard`, `original ===` the dummy |
| `readiumSchemeWebViewIsGuardedWhenItsDelegateIsAssigned` | Same construction order as `EPUBSpreadView.init`: scheme handler → `WKWebView(configuration:)` → assign delegate |
| `defaultStoreWebViewsAreNotWrappedByTheDelegateHook` | Negative control — Browse is not hijacked |
| `reassignedDelegateOnAnIsolatedStoreWebViewIsRewrapped` | Second assignment is re-wrapped (stale map entry cannot skip it) |
| `setterInstalledGuardCancelsScriptDrivenOffPublicationNavigation` | The **installed** guard cancels `javascript:` / `data:` / `https://evil.example` (`.other`) and does not fire Browse; `readium://` is allowed |

The dummy delegate implements `decidePolicyFor` → `.allow`, matching Readium's "allow everything that is not `.linkActivated`".

---

## Mutation evidence

Revert: `kudos_setNavigationDelegate` assigned the original and **did not** call `forceInstall` (creation-time wrap removed; opportunistic sweeps still present). The new tests never call the sweep — they only assign `navigationDelegate`, which is the preloaded-spread case.

A 0.000s failure would be a setup throw and does not count. These are assertion failures with non-zero duration. Quoted from `/tmp/reader-mut2.log` (Swift Testing on iPhone 17 `77492544-056E-4D4A-ABB6-7E38CC042A4D`).

### `assigningNavigationDelegateOnAnIsolatedStoreWebViewInstallsTheGuard` — **RED 0.041s**

> Expectation failed: (webView.navigationDelegate → DummyNavigationDelegate) is (ReaderWebNavigationGuard)
> ↳ **must wrap at navigationDelegate assignment, not a later view-tree sweep**

### `readiumSchemeWebViewIsGuardedWhenItsDelegateIsAssigned` — **RED 0.006s**

> Expectation failed: (webView.navigationDelegate → DummyNavigationDelegate) is (ReaderWebNavigationGuard)
> ↳ **a Readium-built spread must be guarded before loadSpread**

### `reassignedDelegateOnAnIsolatedStoreWebViewIsRewrapped` — **RED 0.313s**

> Expectation failed: (webView.navigationDelegate → DummyNavigationDelegate) is (ReaderWebNavigationGuard)
> ↳ **reassigning navigationDelegate must re-wrap, not skip on a stale map entry**

### `setterInstalledGuardCancelsScriptDrivenOffPublicationNavigation` — **RED 0.190s**

> Expectation failed: (webView.navigationDelegate → DummyNavigationDelegate) is (ReaderWebNavigationGuard)
> ↳ **must wrap at navigationDelegate assignment, not a later view-tree sweep**

The original 11 cases plus `defaultStoreWebViewsAreNotWrappedByTheDelegateHook` stayed GREEN under the mutation (12 passed / 4 failed / 16 total in the Swift Testing run). That is the point: the old sweep test cannot catch this hole.

Wrap restored → GREEN last (bundle below).

**Honesty on the mutation bundle:** `/tmp/rb-reader-mut.xcresult` never grew an `Info.plist`. `xcodebuild` printed the Swift Testing results and then hung in post-test result-bundle finalization (same machine has several sibling `xcodebuild` runs). The process was killed after the 16-test RED transcript was complete. Counts and quotes above are from that transcript, not from `xcresulttool`. GREEN last **does** have a complete bundle.

---

## Gate results

Filter used (as specified): `-only-testing:KudosTests/ReaderWebIsolationTests`

This suite is **not** nested. The filter matches the Swift Testing struct. XCTest still prints `Executed 0 tests` for "Selected tests" because these cases are Swift Testing, not XCTest — do not treat that 0 as `totalTestCount`. The Swift Testing runner is what ran.

Simulator: iPhone 17 `77492544-056E-4D4A-ABB6-7E38CC042A4D`. No `-sdk iphonesimulator` with the UDID.

**GREEN last** (`/tmp/rb-reader.xcresult`, `xcrun xcresulttool get test-results summary`):

```
result: Passed
passedTests: 16
failedTests: 0
skippedTests: 0
totalTestCount: 16
```

`totalTestCount` is not 0. 11 original + 5 new.

Android `:app:testDebugUnitTest` was **not** run. This unit is iOS Readium-only.

---

## G1 — is it closeable?

**Yes, for the re-scoped item.** The review signed G1 off as "not a BLOCK" on the condition that the leftover manual work be *exactly* "hostile EPUB whose script fires on a **preloaded, not-yet-visited** spread" — i.e. F3 / WPB-3. That timing hole is now closed at the production setter, and a revert turns the new tests RED.

A physical-device probe would still add things unit tests structurally cannot:

1. Confirmation that Readium's `WebView` subclass actually hits the swizzled `WKWebView.navigationDelegate` setter on a real `EPUBSpreadView` (our tests construct a `WKWebView` the same *way*, they do not instantiate Readium's type).
2. Confirmation that a preloaded *adjacent* spread's first script runs under the wrap — we prove wrap-at-assignment; we do not run a live Readium navigator with three spreads.
3. A live `window.location = "https://…"` / `javascript:` / `document.cookie` probe inside a hostile EPUB. Cookie non-crossing is already asserted at `WKHTTPCookieStore`; the device probe would show the JS-visible `document.cookie` is empty in the `readium:` origin.

None of those reopen the hole this patch closes. I would treat G1 as **signed off** for merge, with the device probe remaining a useful but optional acceptance check.

---

## What I could not close / out of scope

- **`docs/REGRESSION_TEST_MATRIX.md`** still describes M8 as the 11-case suite and does not mention wrap-at-assignment. Updating it would be the right doc fix; it is outside this unit's file scope.
- **`TASKS.md` T-195** still says `ReaderWebIsolationTests` **11/11** and "manual remaining: hostile-EPUB JS on a real device". Same — out of scope. After this commit the count is **16/16** and the remaining manual item is the optional device probe above.
- **`ReaderController.swift`** (legacy macOS reader) was not touched, per the brief. Its RC hybrid stands. macOS production never calls `installReadiumStoreIsolation()`; the new setter hook is therefore iOS-Readium-only in practice.
- No live Readium navigator / hostile EPUB was executed on a simulator or device.
- Full `Scripts/verify.sh` / macOS build / Android gate were not this unit.

No existing assertion was weakened. No file outside the four-file scope was modified. Nothing was pushed.
