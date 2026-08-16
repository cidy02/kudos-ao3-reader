# Grok iOS revert-loophole fixes (`rc-fix/iostests`)

Local only. No push, no PR, no remote branch. Worktree:
`/Users/cidy02/kudos-rcfix-iostests`. Branch: `rc-fix/iostests` off
`security-fixes/rc`.

Implementer: Grok 4.6. Findings from Gemini (WPA-1/WPA-2) and Claude
(WPB-1/WPB-2/WPB-5/WPB-6). Production code on the RC was already
correct; this unit is about making the tests able to fail.

File scope observed. Did **not** touch `AppRouter.swift`,
`AO3SessionVault.swift`, `Storage.swift`, or `ReaderWebIsolation.swift`.

---

## What changed

| ID | Status | What |
|---|---|---|
| **WPB-1** | **CLOSED** | Two `openAO3Link` tests now assert WP-A's stricter contract |
| **WPA-1** | **CLOSED in-test** | `unguardedURLSinkIsClosed` spies `UIApplication.open` |
| **WPA-2** | **CLOSED** | `CookieAllowListTests` pins `responseCookies` + `merging` |
| **WPB-6** | **CLOSED** | Same file pins `install` + `capture` + `merging` (WP-A breadth) |
| **WPB-2** | **CLOSED** | Relay test has origin/attacker hit counters; no `try?` |
| **WPB-5** | **CLOSED** | `validationURL` init is `#if DEBUG` |

### WPB-1 — tests asserted the looser pre-merge contract

**On the RC, before this change, both tests FAILED.** Confirmed by
running them, not by reading the source.

`/tmp/rb-iostests-baseline.xcresult`:

```
result: Failed
passedTests: 16
failedTests: 2
totalTestCount: 18
```

Quoted failures (non-zero duration):

- `lookalikeHostIsNotRoutedAsANativeTagPage` **0.13s**:
  `Expectation failed: (router.pendingURL → nil) == (bait → https://archiveofourown.org.evil.com/tags/Fluff/works)`
  and `isPresentingWebBrowser → false`
- `httpAO3TagLinkIsNotTreatedAsTrusted` **0.29s**:
  `Expectation failed: (router.pendingURL → nil) == (url → http://archiveofourown.org/tags/Fluff/works)`

Updated both to the RC contract: a non-AO3 host / `http` AO3 URL must
**not** reach the cookie-bearing in-app sheet (`pendingURL == nil`,
`isPresentingWebBrowser == false`). Production `AppRouter.open` was not
changed.

### WPA-1 — M19 test now watches the system opener

`AppRouter.swift` is out of scope, so there is no injectable
`systemOpen` on the type. The test spies the production call:

- swizzle `UIApplication.openURL:options:completionHandler:`
- assert `javascript:` / `data:` / `file:` are **not** recorded
- positive control: `https://evil.com` and `http://example.org`
  **are** recorded (otherwise a dead spy would bless a hostile
  hand-off)
- AO3 `https` is **not** recorded (in-app sheet instead)

The existing `pendingURL` / `isPresentingWebBrowser` assertions stay.

**Production mutation of `AppRouter.open` was not performed** — that
file is out of scope (four sibling agents). The exact patch that would
make this test go RED is at the bottom of this report.

### WPA-2 / WPB-6 — allow-list at the real functions

New `KudosTests/CookieAllowListTests.swift`:

| Test | Entry |
|---|---|
| `responseCookiesDropsOffDomainAndNonAllowListed` | `LiveAO3SessionValidator.responseCookies` (what `validate()` calls) |
| `mergingDropsNonAllowListedAndOffDomainStoredCookies` | `LiveAO3SessionValidator.merging` |
| `installDoesNotReinjectNonAllowListedCookiesIntoWebKit` | `AO3CookieBridge.install` (WK store, not the helper) |
| `captureDropsNonAllowListedCookiesFromWebKitStore` | `AO3CookieBridge.captureAO3Cookies` |

Allow-list pinned: `{ _otwarchive_session, user_credentials }`.
Off-domain and `_ga` / `viewed_adult` must drop. Fixtures have
positive controls so an empty parse cannot pass.

`responseCookies` and `merging` were `private`; they are now
package-visible so the tests call the same functions `validate()` uses.
`validate()` itself cannot be driven at a loopback URL: session cookies
are AO3-domain + `Secure`, so `cookieHeader(for:)` returns nil and
`validate` returns `.expired` before it ever parses `Set-Cookie`.

`AO3SessionVault.swift` is out of scope, so `install` / `capture` were
tested at the production entry but **not** mutated (that would require
editing `persistableStoredCookies` / `install` in that file).

### WPB-2 — relay test no longer passes if the 302 never happens

- `try await` instead of `try?`
- `LoopbackCounter` (NSLock) for origin hits, attacker hits, Cookie
- `#expect(originHits.value == 1)`
- `#expect(attackerHits.value == 1, "the redirect never reached the attacker — test proved nothing")`

ATS did **not** block loopback on this simulator. The GREEN run after
the positive control is 0.029s–0.308s and both hit counters are 1.

### WPB-5 — `validationURL` is DEBUG-only

An init parameter *can* be gated the same way as
`Storage.fontsDirectoryOverride`. Production keeps `init()` →
`https://archiveofourown.org`. `init(validationURL:)` exists only
under `#if DEBUG`. `AO3AuthService` still constructs
`LiveAO3SessionValidator()`. The RC note in that file is gone.

There is no runtime assertion that goes RED if someone deletes the
`#if DEBUG` — that is a compile-time seam, not a behavioural filter.

---

## Mutation evidence

A 0.000s failure would be a setup throw and does not count. These are
assertion failures with the quoted message and a non-zero duration.
Mutations were applied, the suite run, then the production code
restored. Result bundles for the mutation runs were not always
finalised (xcodebuild hung on teardown after the test process had
already printed the failures); counts below are from the Swift Testing
console, which is what recorded the assertion text and duration.

### WPA-2 — drop the `responseCookies` filter

Temporary change: return every `HTTPCookie` parsed from `Set-Cookie`,
no domain / name filter.

`responseCookiesDropsOffDomainAndNonAllowListed` **RED 0.016s**:

> `non-allow-listed _ga was kept from Set-Cookie`
> `Expectation failed: !((names → ["_otwarchive_session", "viewed_adult", "user_credentials", "_ga"]).contains("_ga") → true)`

Also RED on the same run: `viewed_adult` kept; `off-domain Set-Cookie
was kept` (evil.example `_otwarchive_session=stolen`). Filter restored
→ GREEN.

### WPB-6 — `merging` uses `session.cookies` unfiltered

Temporary change: seed from `session.cookies` instead of
`persistableStoredCookies(session.validCookies)`.

`mergingDropsNonAllowListedAndOffDomainStoredCookies` **RED 0.039s**:

> `non-allow-listed _ga survived merging`
> `Expectation failed: !((names → ["viewed_adult", "_otwarchive_session", "user_credentials", "_ga"]).contains("_ga") → true)`

Also RED: `viewed_adult survived merging`; `off-domain session cookie
survived merging`. Restore → GREEN.

`install` / `capture` were **not** mutated (`AO3SessionVault.swift` is
out of scope). Those two tests are in place to catch a future revert
of WP-A's broader filter.

### WPB-2 — detach `AO3RedirectCookieRelay`

Temporary change: `session.data(for: request)` with no delegate.

`validatorRedirectDoesNotForwardTheSessionCookie` **RED 0.111s**:

> `Expectation failed: (attackerCookie == nil → false) || (attackerCookie?.isEmpty == true → false)`
> `Expectation failed: (attackerCookie?.contains("SECRET-SESSION") → true) != true`

The hit-count expects stayed GREEN (origin 1, attacker 1), so this is
not a vacuous miss — the 302 reached the attacker **with** the session
cookie. Restore the delegate → GREEN (0.029s).

### WPB-1 — already RED on the RC (quoted above)

Updating the two expects to the stricter contract is the fix. The
baseline run *is* the mutation evidence: the old asserts fail against
current `AppRouter.open`. After the update they pass.

### WPA-1 — production revert not run

Would require editing `AppRouter.swift`. Not done. See "Not closed".

---

## Gate results (real counts)

Never trusted exit 0 alone. Counts from
`xcrun xcresulttool get test-results summary`.

Simulator: iPhone 17e `47998C20-9ADE-4415-A0BB-A0226779E6DF`.
No `-sdk iphonesimulator` with the UDID.

**Baseline (before any edit)** `/tmp/rb-iostests-baseline.xcresult`:

```
result: Failed
passedTests: 16
failedTests: 2
totalTestCount: 18
```

The two failures are exactly WPB-1. `KudosTests/AppRouterM19Tests`
matched the suite even though its `@Suite` display name is
`"AppRouter M19 Tests"` (identifier stays `AppRouterM19Tests`).

**GREEN last, scoped suites** `/tmp/rb-iostests.xcresult`:

```
result: Passed
passedTests: 22
failedTests: 0
totalTestCount: 22
```

Filters that actually ran (4 suites, 22 cases):

- `KudosTests/AppRouterM19Tests` (1)
- `KudosTests/AppRouterTests` (16; the two WPB-1 tests now pass)
- `KudosTests/CookieAllowListTests` (4)
- `KudosTests/LiveAO3SessionValidatorRelayTests` (1)

A single-test filter
`KudosTests/CookieAllowListTests/responseCookiesDropsOffDomainAndNonAllowListed`
matched **0** cases and still exited 0 (`totalTestCount: 0`). The suite
path is the one that runs. Same trap class as `KudosBackupTests`.

**KudosBackupTests (prove we broke nothing)**
`/tmp/rb-iostests-backup.xcresult`:

```
result: Passed
passedTests: 44
failedTests: 0
totalTestCount: 44
```

Filter: `KudosTests/PersistenceGateSuites/KudosBackupTests`. Not 0.

Android was not in this unit's scope and was not re-run.

---

## Not closed

1. **WPA-1 production mutation.** `AppRouter.swift` is out of scope.
   The test-side spy is live (positive control: non-AO3 `https` *does*
   invoke `UIApplication.open`). I did not temporarily change
   `AppRouter.open` to hand `javascript:` / `data:` to the system
   opener. The patch that should turn
   `unguardedURLSinkIsClosed` RED is:

   ```swift
   // kudos-ao3-reader/App/AppRouter.swift — DO NOT APPLY HERE
   func open(_ url: URL) {
       // broken: no scheme gate; every URL including javascript:/data:
       // goes to the system opener. pendingURL stays nil.
       #if os(macOS)
       NSWorkspace.shared.open(url)
       #else
       UIApplication.shared.open(url)
       #endif
   }
   ```

   Expected RED (non-zero duration):
   `"javascript: was handed to the system opener"`.

   The injectable seam I would add *inside* `AppRouter` if that file
   were in scope (preferred over swizzling):

   ```swift
   #if os(iOS)
   var systemOpen: (URL) -> Void = { UIApplication.shared.open($0) }
   #else
   var systemOpen: (URL) -> Void = { _ = NSWorkspace.shared.open($0) }
   #endif

   func open(_ url: URL) {
       guard let scheme = url.scheme?.lowercased(),
             scheme == "http" || scheme == "https"
       else { return }
       if !AO3AuthorRoute.isAO3URL(url) {
           systemOpen(url)
           return
       }
       pendingURL = url
       isPresentingWebBrowser = true
   }
   ```

   Then the test would assign `router.systemOpen = { opened.append($0) }`
   and would not need a process-wide swizzle.

2. **`AO3CookieBridge.install` / `capture` mutation.** Tests hit the
   production entries and would go RED if those filters were deleted.
   Reverting them requires `AO3SessionVault.swift`, which is out of
   scope. Only `merging` / `responseCookies` (this file) were mutated.

3. **WPB-5 has no RED test.** Gating an init is compile-time. Removing
   `#if DEBUG` would put `init(validationURL:)` back in Release; nothing
   in the suite fails. I gated it; I did not invent a Release-config
   compile check.

4. **`performRequest` remains internal.** WPB-5 asked about
   `validationURL`. `performRequest` is the real credential-bearing
   call and must stay callable in production (`validate` uses it).
   Gating *that* would break the app. Not gated.

5. **Mutation result bundles** for the three in-scope reverts were not
   always flushed (`xcodebuild` hung on teardown after Swift Testing
   had already printed the failures). Assertion text and durations
   above are from that console, not from a surviving `.xcresult`.
   Baseline, GREEN-last, and backup counts *are* from xcresulttool.

6. **No Android run.** Not in this unit.
