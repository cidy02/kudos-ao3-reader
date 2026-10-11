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

## Second step, landed 2026-10-11: Mute and Block

- `AO3WriteFormParser.parseAuthorModerationForm` (iOS `parseAuthorModerationForm`): the form
  on AO3's confirm page, its heading, its notice with the lists kept as lists, and the words
  on its two buttons; an undo (Unblock, Unmute) is known by `_method=delete` or the label.
- `AO3WriteRepository.loadAuthorModerationForm`: one authenticated read of the confirm page
  on the tap; AO3's refusal on that page is reported and nothing is sent.
  `submitAuthorModeration`: that page's own form, once, with the token the page carried (no
  second read; `postOnce`, the POST half of `indexWrite`). Success says "Blocked.",
  "Unblocked.", "Muted." or "Unmuted."; the failure "AO3 didn't accept the block action."
- `author/AuthorProfileScreen.kt`: the two buttons open a dialog in AO3's words (the Yes
  button in the error colour unless it undoes), are off while a step is out, and after a
  success the account's kept dashboards are dropped and the header read again.
- The demo serves both confirm pages (a mute fixture was added) and accepts the post.

Tests: `AuthorModerationTest` (7): the page as AO3 wrote it; an undo; a page without the form;
one read on the tap and nothing sent; AO3's refusal reported; another session, a signed-out
reader, another site and another kind of link ask nothing; the confirm sends the page's own
form once without reading again; an unconfirmed reply is a failure. One mutation caught (the
refusal). The other (no session check in the submit) is not, because the client refuses a
post from another session by itself: the check is there twice. Gate 2,588.

Seen on the emulator (demo): Mute opens AO3's notice with "Cancel" and "Yes, Mute User";
Cancel leaves the page; Block, then "Yes, Block User", then "AO3 Profile / Blocked."

## Not done, and not checked

- The demo is not stateful for a mute or a block: the buttons read the same afterwards, and
  the undo pages (Unblock, Unmute) were parsed in tests, not seen on screen.
- A real AO3 confirm page was not read (no request is made to AO3, by rule): the parser
  follows iOS's, on the fixtures iOS's own tests use.
- **Signed out**, AO3 serves no subscription form, so Android shows no button; iOS shows one
  and asks the reader to log in. Left as it is.
- No screen-level test: the confirmation and the reload are by the emulator only.
- Never run against AO3 (no write is, by rule).
