# AO3 Authentication Architecture

Kudos authenticates against AO3's real website because AO3 does not provide a
public API. The app keeps account entry native, uses WebKit only to establish the
website session, and never stores the user's password.

## Components

- `AO3AuthService` is the app-facing authentication API and owns observable
  login state. Views and future sync clients use this service instead of talking
  to WebKit or Keychain directly.
- `AO3WebLoginCoordinator` loads AO3's official login page in an off-screen
  `WKWebView`, fills the live form after AO3 supplies its CSRF token, and submits
  it. It exposes that same WebView only when the automatic mechanism cannot
  complete.
- `AO3Session` and `AO3StoredCookie` are serializable session values. Cookies are
  scoped by AO3 domain, path, expiry, and secure transport when requests are
  built.
- `CascadingAO3SessionVault` (default) stores the session in **Keychain first**
  (`KeychainAO3SessionVault`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
  On success it does **not** dual-write cookies elsewhere. Only when Keychain
  returns `errSecMissingEntitlement` (typical Simulator / unsigned builds) does
  it fall back to an app-container file
  (`Application Support/KudosAuth/ao3-session.json` via `FileAO3SessionVault`).
  That file is cleared on logout and with the app container on uninstall.
- `AO3CookieBridge` keeps the saved session, WebKit cookie store, and shared HTTP
  cookie store in agreement.
- Preferences still hold only a non-secret username hint.
- If Keychain and the file are both empty, restore falls back to capturing
  cookies from WebKit's persistent store (dev safety net).
  - **Verify Keychain persistence on a signed device build** — the file + WebKit
    paths are backstops, not the long-term product store.
- `LiveAO3SessionValidator` checks a restored session against AO3 without logging
  the user out merely because the network is unavailable.

## Login flow

1. `AO3LoginView` collects a username or email and password in native SwiftUI.
2. `AO3AuthService` clears stale AO3 cookies and asks
   `AO3WebLoginCoordinator` to load `https://archiveofourown.org/users/login`.
3. The coordinator waits for AO3's live form and CSRF field, fills
   `user[login]`, `user[password]`, and the remember-me control, then submits.
4. Login is considered successful only when AO3's returned page identifies
   itself as logged in. The mere presence of `_otwarchive_session` is not enough,
   because AO3 also gives anonymous visitors a session cookie.
5. AO3 cookies are captured, serialized, saved to Keychain, and installed for
   authenticated WebKit and URL requests. The password is discarded.

The automatic-login WebView stays mounted (but invisible, at 1×1) behind the
native form so it always has a window: an off-screen `WKWebView` can have its
web-content process throttled, which would otherwise make the hidden login stall
and fall back for no real reason. A single transient navigation failure silently
restarts the hidden flow once before any fallback is shown.

If the form cannot be recognized, submitted, inspected, or completed before the
timeout, the login view automatically displays the same WebView with an
"alternative login method" notice. The user-facing fallback copy is deliberately
calm and action-oriented ("Let's finish logging in on AO3's page below") rather
than worded like a security warning. Manual login is monitored for the same
logged-in signal and then follows the normal cookie capture path. A known
username/password rejection remains in the native form so the user can correct
it without being sent to the fallback. The native form also links to AO3's
sign-up and password-reset pages, opened in the in-app Browse tab.

## Session lifecycle

- App launch restores the Keychain session, installs its cookies, and validates
  it against AO3. Builds without Keychain entitlement recover and validate the
  persistent WebKit session instead.
- A confirmed logged-out response clears the stored session and asks the user to
  log in again.
- A connectivity failure preserves a plausible session for offline use rather
  than treating it as expired.
- Login, restore, logout, session expiry, and an accepted session verification
  advance `sessionGeneration`. WebKit-cookie installs and clears are serialized
  and each verifies that generation immediately before mutating the shared store,
  so an older account transition cannot alter a newer account's cookies.
- Feature clients must capture `sessionGeneration` before beginning an
  authenticated operation. If AO3 redirects that operation to login, they call
  `sessionDidExpire(expectedGeneration:)` with that captured value, so an old
  response cannot clear a newer account session.
- Logout clears the Keychain item, username hint, and all AO3 cookies known to
  WebKit and `HTTPCookieStorage`.

## Authenticated feature requests

`authenticatedRequest(for:method:)` creates a request only for secure AO3 hosts
and attaches the cookies that apply to that URL. This is the starting point for
bookmarks, history, Marked for Later, subscriptions, kudos, and comments.

State-changing AO3 actions fetch the relevant AO3 page, extract its current
authenticity token, submit the expected form fields, and detect a redirect to
login. Bookmarks, Marked for Later, kudos, comments, preferences, and Inbox
actions all ship today (`AO3WriteActions`, `AO3CommentActions`,
`AO3PreferencesActions`, `AO3InboxActions`); each feature-specific client owns
its own form/token details while authentication and session invalidation
remain centralized in `AO3AuthService`.

## AO3 markup assumptions

Authentication depends on a small set of AO3 selectors. They live in **two** places
that must stay in sync — the in-page JavaScript in `AO3WebLoginCoordinator`
(`inspectPage` / `submit`) and the Swift/SwiftSoup parser in
`LiveAO3SessionValidator` (`isLoggedIn` / `username`). When AO3 changes its markup,
update both and refresh the `KudosTests/Fixtures/ao3_logged_*.html` fixtures.

- **Logged-in signal:** `body.logged-in`, or a logout control
  (`a[href="/users/logout"]` / `form[action="/users/logout"]`).
- **Username:** the first `#greeting a[href^="/users/<name>"]` that is not
  `/users/login` or `/users/logout` (percent-decoded).
- **Login form:** `form#new_user` with `#user_login`, `#user_password`, and the
  optional `#user_remember_me`; AO3 injects the `authenticity_token` (CSRF) field.
- **Errors:** `#main .flash.error, #main .error, .flash.error, .flash.alert`.

## Security boundaries

- Passwords exist only in the native field and the short-lived WebKit form-fill
  operation. They are not logged, persisted, or included in app diagnostics.
- Cookie values are never logged.
- Authenticated requests are rejected for non-HTTPS or non-AO3 URLs.
- Login success is checked only on a secure AO3 page.
- The session is device-only and does not migrate through Keychain backups.
- On signed builds, session cookies live in Keychain (and WebKit after install),
  not in UserDefaults. The Application Support session file exists **only** as
  the `errSecMissingEntitlement` fallback (see `CascadingAO3SessionVault` above).
