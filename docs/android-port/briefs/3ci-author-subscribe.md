# Brief 3ci: Subscribe, Unsubscribe, Mute and Block on an author's page are not native (Android)

Found 2026-10-11 by listing every iOS confirmation and checking Android for it ("Unsubscribe
from <name>?" had no counterpart). **Android only. P2 for Subscribe; P3 for Mute and Block.**

## What is wrong

`author/AuthorProfileScreen.kt:520` passes `onSubscription = onOpenWeb` and
`onModeration = { onOpenWeb(it.url) }`. The Subscribe button (`AuthorProfileComponents.kt:125`)
calls `onSubscription(form.actionUrl)`: it opens **the form's submit address** in the web
view. That address answers a POST; opened with a GET it is the reader's own subscriptions list
(or nothing, for Unsubscribe). So tapping Subscribe does not subscribe.

The parser already reads everything a native write needs
(`AO3AuthorSubscriptionForm`: label, actionUrl, fields, csrfToken, referer;
`network/ao3/author/AO3AuthorParser.kt:272`).

## What iOS does

- `AuthorProfileView.subscriptionTapped` (`:648`): signed out → "Log in to AO3" alert;
  subscribed → a confirmation "Unsubscribe from <username>?" with the message
  "Unsubscribing here applies to the whole AO3 account, not only this pseud." and the buttons
  "Unsubscribe" (destructive) and "Cancel"; not subscribed → the write at once.
- `AO3AuthorProfileModel.toggleSubscription` (`Services/AO3AuthorProfileService.swift:419`):
  one write (`submitAuthorSubscription`, `:912`: the captured form's fields, its token added if
  absent, any query items of the action address added as fields, the form's referer), fenced
  by route and session; then the kept dashboards for that author are dropped and the header is
  read again; the result ("Subscribed." / "Unsubscribed.", or the failure) is shown in an alert
  titled "AO3 Profile".
- Mute and Block: `beginModeration` (`:440`) fetches AO3's confirm page, parses its form
  (`parseAuthorModerationForm`), shows a native confirmation, and `submitAuthorModeration`
  posts it. Never the in-app browser.

## What to build (Subscribe and Unsubscribe first)

1. `network/ao3/writes/AO3WriteRepository.kt`: `submitAuthorSubscription(form, expectedGeneration)`
   in this file's own pattern (the session check, a fresh token from the form's referer, one
   POST in `NonCancellable`, the verdict order). `indexWrite` (used by `unsubscribe(path, page)`,
   `:1076`) is the nearest helper; the fields are the served form's, with the fresh token.
2. `author/AuthorProfileScreen.kt`: the button calls the write; Unsubscribe asks first, in
   iOS's words; a busy state; the result in a dialog titled "AO3 Profile"; on success drop the
   author's kept dashboard page (`AO3PageCache.removePages`) and read the header again past
   the cache. Signed out: iOS's login alert.
3. The demo: answer the POST (`network/ao3/DemoNetwork.kt`; `removedSubscriptions` there is
   for the Subscriptions list) so it can be seen on the emulator.
4. Tests: the fields sent (served fields kept, fresh token); a session change before the POST
   sends nothing; Unsubscribe sends nothing until confirmed; the header is read again after.
5. `docs/AO3_NETWORKING_POLICY.md`: a user-triggered, single-shot write, never retried.

Mute and Block are a second step (a confirm page to fetch and parse first): their own brief
when this has landed. Until then they still open AO3's page in the web view, which for them is
AO3's own confirm page and does work.
