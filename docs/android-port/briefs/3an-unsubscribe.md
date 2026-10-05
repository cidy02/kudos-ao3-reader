# Brief 3an: Unsubscribe on the Subscriptions page really unsubscribes

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; **don't edit `TASKS.md`**. Don't change the backup format or a Room schema. Your sandbox
can't run Gradle or Xcode. Claude builds, tests and commits afterwards, so make what you write
compile by reading the real symbols you use, and say which claims need a test run.

**Android only.** iOS is the reference: read it at `/Users/cidy02/kudos-ios-polish/`, change
nothing there. **When this brief and iOS's code disagree, iOS's code wins**; say so in the
result. Write `docs/android-port/briefs/3an-result.md` as you go.

## What is wrong

You found it in brief 3am (`briefs/3am-result.md`, "Unsubscribe fallback"): on the Subscriptions
page (`account/AccountWorksListScreen.kt`, `SubscriptionsBrowser`) the Works tab's Unsubscribe
confirms, then adds the work's id to a hidden set in memory. Nothing is sent to AO3. The reader
believes they unsubscribed; AO3 keeps the subscription and the row is back at the next visit.
The Series and Authors rows (3am) have no Unsubscribe at all.

iOS: `AO3WriteActions.unsubscribe(path:page:)` and its callers in
`Features/Bookmarks/AO3NamedSubscriptionsList.swift` and the works list. As you described it:
it fetches the subscriptions index for a fresh token, posts the form beside the row
(`_method=delete`, `authenticity_token`) once, checks the session has not changed, removes the
row only on success, steps back from a later page it has emptied, and says "Couldn't
unsubscribe" on failure.

## Build

Port that flow for all three tabs, through Android's existing authenticated write path (read
`AO3WriteRepository`, how `toggleSubscribe` prepares and sends its POST, and how other writes
report failure; reuse its client, its token handling and its pacing; do not write a second
HTTP path).

- **It is a write to AO3 that the reader starts with a tap and confirms.** One POST per
  confirmed tap. Never retried on its own, never batched, never run in the background, never
  started by anything but that tap. If the request fails or the answer is not the one AO3 gives
  on success, the row stays and the reader is told in iOS's words. Read
  `docs/AO3_NETWORKING_POLICY.md` and say which of its rules cover this; if any forbids it, stop
  and say so at the top of the result.
- **The form comes from the page AO3 served**, as on iOS: the action and token are read from the
  row's own form on a freshly fetched index page, not built by hand. If the row's form is not
  on that page (the subscription is already gone), treat it as iOS does and say what that is.
- **The row leaves the list only after AO3 confirms.** Delete the in-memory hidden set and
  everything that reads it. After a success the list shows what AO3 now has (iOS's way: read
  how it updates the list and the page it is on).
- **Works too**: the Works tab's Unsubscribe uses the same flow, and its new-chapter count for
  that work is forgotten the way iOS forgets it (read what iOS does with its watermark).
- **Series and Authors**: add Unsubscribe to the rows 3am built, where iOS puts it and in iOS's
  words, with the confirmation iOS shows.
- While a request is out, the row's control shows it and cannot be tapped twice; leaving the
  screen does not cancel a POST that has been sent (say what Android's write path does today
  and keep to it).
- Owner's rule since 2026-10-04: layout, content and behaviour follow iOS; navigation and
  chrome controls are Android's own (Material). Use the page's existing components (the pills
  are `SubjectChip`; a destructive confirmation is the page's existing dialog): no stock
  Material chips or default Material colours.

## Demo and tests

- The demo must answer the POST locally: add what `network/ao3/DemoNetwork.kt` needs so that
  Unsubscribe in the demo succeeds for one row and fails for another, with no network. Say how
  to reach each on the emulator.
- Tests, none of which may reach the network: the form is taken from the served page (action,
  method override, token) for a work, a series and a user; exactly one POST per confirmed tap;
  success removes the row and a later emptied page steps back; failure keeps the row and shows
  the message; a session that changed while the request was out does not touch the list; no
  request without a confirmed tap.
