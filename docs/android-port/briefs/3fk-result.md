# 3fk result

Dispatch: `96236916d1c341a569a99cf165d70c5498a52244`, branch
`android/agent-codex-3fk`, worktree `/Users/cidy02/kudos-agent-codex`.
Initial tree was clean. Changes are deliberately uncommitted for Claude.

Implemented priorities 1–2 and the identity allow-list part of 3. **Stopped at
3's explicit SameSite stop condition:** Android's stored cookie has no SameSite
field. Priorities 4–8 remain unmodified and need the next pass. No Room schema,
credential serialization fields, or backup format changed. No Gradle/build/test
execution, AO3 requests, sign-in, commit, push, or branch switch occurred.
`TASKS.md`, 3fj's fixes, and the document converters are untouched.

## 1. Initial client URL validation

Confirmed at dispatch: `OkHttpAO3Client.get`, `getBytes`, `postForm`, and
`postFormChecked` accepted arbitrary HTTP(S) destinations. `AO3CookieJar` scoped
the session header but did not prevent those requests.

`network/ao3/AO3Client.kt` now checks each public entry point before coalescing,
pacing, write callbacks, or constructing an OkHttp call. It reuses
`AO3RedirectCookieRelay.isTrustedUrl`: HTTPS with an exact AO3 host or AO3
subdomain. Invalid URLs and rejected destinations return `AO3Error.Validation`;
checked POSTs now return validation failures for malformed input too. Pacing,
GET retries, single-shot writes, and redirect cookie relay behavior are unchanged.
This ports the initial-destination checks in iOS `AO3ClientPolicyTests` and
`AO3RequestDefaults.isTrustedURL`; it does not change redirect-following policy.

The predicate is injectable as `isAllowedUrl`, defaulting to AO3 only. Existing
loopback integration tests explicitly pass `{ true }` in exactly these files:

- `AO3NetworkingCoreTest.kt`: `testClient`, the two single-shot POST regressions,
  cancellation/coalescing clients, and the bypass-cache read client.
- `AO3AuthenticatedPostTest.kt`: `postClient`.
- `AO3RedirectCookieRelayTest.kt`: the off-host redirect client and `relayClient`.

Other intercepted tests use HTTPS AO3 addresses and retain the production check.
No production caller passes an allow-all predicate.

Added `AO3ClientHostPolicyTest`: all four entry points reject lookalike, foreign,
cleartext, loopback and malformed input before an interceptor or write callback
can run. HTTPS AO3 and the download subdomain pass with interceptor-only fixture
responses. These port `lookalikeAndForeignHostsAreRejectedWithoutNetwork`,
`imageDataAndGetHTMLRefuseForeignHosts`, and the trusted URL positive assertion.

## 2. Parser drift is an error

Confirmed at dispatch: `AO3SearchParser.parseWorksListPage` silently discarded
every failing blurb. `AO3AccountParser` additionally swallowed author-bookmark
parser failures, so malformed bookmark metadata could appear successful.

`AO3SearchParser` now throws `MissingRequiredStructure` when work blurbs exist
but none parse, while preserving genuinely empty pages and partial success.
Bookmark lists retain the iOS exception for series/external/deleted-only pages.
Work ID fallback now uses the heading, matching iOS, so a link inside bookmark
notes cannot manufacture a work result.

`AO3AccountParser` propagates unrecognized bookmark-page failures and rejects a
page with a work heading when no work bookmark metadata parsed, including the
iOS `bookmark_nope` plus series fixture. Recognized empty indexes and non-work
pages still work; pagination survives.

Added assertions in `AO3SearchParserNoResultsTest` and `AO3BookmarksParserTest`
porting `blurbsPresentButNoneParseableThrowsInsteadOfLookingEmpty` and
`accountBookmarksPageStillThrowsWhenAWorkHeadingFailsToParse`, plus partial
success and non-work/pagination guards. Existing positive parser fixtures remain.
Inspected the repository/UI path: `AO3SearchRepository.parse` and
`AccountListRepository.parse` map these exceptions to `AO3Error.Parse`;
`SearchScreen` and `AccountWorksListScreen` already have error/Retry states.
No visual verification is claimed.

## 3. Identity cookies filtered; SameSite needs a follow-up decision

Confirmed at dispatch: domain checking allowed arbitrary AO3 cookie names through
capture, durable storage, installation, and validation-response merging. iOS's
`AO3RequestDefaults.persistedCookieNames` contains exactly
`_otwarchive_session` and `user_credentials`.

`auth/AO3Session.kt` now defines that allow-list and filters `validCookies` and
Set-Cookie conversion by name as well as domain/expiry. `identityOnly` preserves
the existing session timestamp and all existing retained-cookie attributes.
Filtering reaches:

- `AndroidAO3CookieStore.captureSession` and `install` (via `validCookies`).
- Both `AO3SessionStore` implementations' load/save paths and the encrypted
  store's plaintext migration write.
- `AO3AuthRepository` restore, accepted-login result, and validated-session
  save/install boundary, including injected stores/validators.
- `LiveAO3SessionValidator.mergingResponseCookies`, including the early return
  when the response contains no allowed cookie. Old disallowed cookies are
  pruned even when AO3 does not rotate the identity cookie.

The raw request-header parser remains general because sign-out also uses it to
expire cookies; it is not itself a persistence boundary. Sign-out behavior was
not changed as part of this filtering.

Added `AO3CookieAllowListTest` and Robolectric `AO3CookieBridgeAllowListTest`:
response filtering, actual file serialization, legacy load, validation merges
with/without identity refresh, auth save/install, WebView capture, and WebView
installation. They port `CookieAllowListTests`,
`captureAO3CookiesFiltersNonIdentity`, and `onlyAllowListedCookiesArePersisted`.
Updated `AO3AuthTest.kt`'s path-scope example to use allowed `user_credentials`
instead of `pref`; its expired-cookie example now uses the real session name so
expiry remains independently tested.

**SameSite remains unresolved.** `AO3StoredCookie` already serializes domain,
path, expiry, Secure and HttpOnly, but has no SameSite property. The iOS model has
an optional `sameSitePolicy`. Supporting parity would require an explicitly
approved nullable serialized cookie field with an absent-key default, capture
from full Set-Cookie attributes, and emission in
`toCookieManagerSetCookieHeader`, with legacy-decode and round-trip tests.
`CookieManager.getCookie` exposes only name/value pairs and cannot recover
SameSite; the existing `fromOkHttp` mapping also does not retain it. Do not invent
it from request headers. No such field was added under this brief's stop rule.

## Verification and pickup

`git diff --check` passes. Reviewed changed call sites and test constructor
arguments; builds and tests have **not** run, per dispatch. Claude should compile
and run the Android debug unit suite, including the new host/cookie suites and
the modified networking, parser, session-restore and persistence-default suites,
then build the debug app before committing. WebView tests use Robolectric with
`Application` and local cookie operations; host-policy tests use interceptors,
not AO3 sockets.

Next work: resolve the explicit SameSite-field constraint, then continue at
priority 4 (path/subdomain WebView sign-out), followed by 5 (hostile EPUB
preflight), 6 (blank usernames), 7 (availability), and 8 (displayed metadata).
These later findings were not assessed or fixed in this pass. For priority 5,
Android does not extract EPUB entries to disk: the requested preflight is a
reader/expanded-memory zip-bomb defense, not a disk path-traversal extraction fix.
