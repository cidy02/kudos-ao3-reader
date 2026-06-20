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
- `KeychainAO3SessionVault` stores the session as a device-only Keychain item
  using `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- `AO3CookieBridge` keeps the saved session, WebKit cookie store, and shared HTTP
  cookie store in agreement.
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

If the form cannot be recognized, submitted, inspected, or completed before the
timeout, the login view automatically displays the same WebView with an
"alternative login method" notice. Manual login is monitored for the same
logged-in signal and then follows the normal cookie capture path. A known
username/password rejection remains in the native form so the user can correct
it without being sent to the fallback.

## Session lifecycle

- App launch restores the Keychain session, installs its cookies, and validates
  it against AO3.
- A confirmed logged-out response clears the stored session and asks the user to
  log in again.
- A connectivity failure preserves a plausible session for offline use rather
  than treating it as expired.
- Future feature clients should call `sessionDidExpire()` when AO3 redirects an
  authenticated operation to login.
- Logout clears the Keychain item and all AO3 cookies known to WebKit and
  `HTTPCookieStorage`.

## Authenticated feature requests

`authenticatedRequest(for:method:)` creates a request only for secure AO3 hosts
and attaches the cookies that apply to that URL. This is the starting point for
bookmarks, history, Marked for Later, subscriptions, kudos, and comments.

State-changing AO3 actions will still need to fetch the relevant AO3 page,
extract its current authenticity token, submit the expected form fields, and
detect a redirect to login. Those feature-specific details should live in their
own clients while authentication and session invalidation remain centralized in
`AO3AuthService`.

## Security boundaries

- Passwords exist only in the native field and the short-lived WebKit form-fill
  operation. They are not logged, persisted, or included in app diagnostics.
- Cookie values are never logged.
- Authenticated requests are rejected for non-HTTPS or non-AO3 URLs.
- Login success is checked only on a secure AO3 page.
- The session is device-only and does not migrate through Keychain backups.
