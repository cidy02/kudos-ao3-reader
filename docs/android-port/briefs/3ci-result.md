# 3ci result: Subscribe and Unsubscribe on an author's page are native (Android)

Landed 2026-10-11 by Claude, alone (Codex and Gemini were out). Gate 2,572.

## What was built

- `AO3WriteRepository.submitAuthorSubscription(form, expectedGeneration)`: the session the form
  was read in is checked first (another session's form is never sent, and nothing is asked of
  AO3); then `indexWrite`: a fresh token from the page the form was on, one POST of the served
  fields with that token, the usual verdict. A reply that does not confirm is a failure and is
  not sent again.
- `author/AuthorProfileScreen.kt`: Subscribe writes at once; Unsubscribe asks first, in iOS's
  words ("Unsubscribe from <username>?", "Unsubscribing here applies to the whole AO3 account,
  not only this pseud."); the button is off while the write is out; the result is shown in a
  dialog titled "AO3 Profile"; on success the account's kept dashboards are dropped
  (`AO3PageCache.removeAuthorDashboards`) and the header is read again past the cache.
  Without a write repository (a test host) the button does what it did.
- The demo answers both posts and then serves the form that ends the subscription
  (`DemoNetwork.kt`, `followedAuthors`), for this run only.

## Tests

`network/ao3/writes/AuthorSubscriptionWriteTest.kt` (5): the fields sent and the fresh token;
the unsubscribe form; another session's form, a signed-out reader and an address off AO3 send
nothing and ask nothing; a session that changes while the token is read sends nothing; an
unconfirmed reply is a failure and one POST. Two mutations caught (no session check; the old
token kept).

## Seen on the emulator (demo)

Subscribe → "AO3 Profile / Subscribed." → the button reads Unsubscribe → the confirmation →
Cancel leaves it → Unsubscribe → "Unsubscribed." → the button reads Subscribe again.

## Not done, and not checked

- **Mute and Block** still open AO3's confirm page in the web view (the brief's second step).
- **Signed out**, AO3 serves no subscription form, so Android shows no button; iOS shows one
  and asks the reader to log in. Left as it is.
- No screen-level test: the confirmation and the reload are by the emulator only.
- Never run against AO3 (no write is, by rule).
