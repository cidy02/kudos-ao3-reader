# Brief 3am: Subscriptions › Series and Authors, as iOS's

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; **don't edit `TASKS.md`**. Don't change the backup format or a Room schema. Your sandbox
can't run Gradle or Xcode. Claude builds, tests and commits afterwards, so make what you write
compile by reading the real symbols you use, and say which claims need a test run.

**Android only.** iOS is the reference: read it at `/Users/cidy02/kudos-ios-polish/`, change
nothing there. **When this brief and iOS's code disagree, iOS's code wins**; say so in the
result. Write `docs/android-port/briefs/3am-result.md` as you go.

## What is wrong

On the Subscriptions page (`account/AccountWorksListScreen.kt`, `SubscriptionsBrowser`) the
Series and Authors pills show a fixed empty state ("No series subscriptions…") and ask AO3 for
nothing. A reader who subscribes to series or authors is told they have none. You found this in
brief 3al (`briefs/3al-result.md`, section 4): `AO3AccountUrls` builds only the `type=works`
address and `AO3AccountParser.parseSubscriptionsPage` keeps only `/works/` links.

iOS lists them: `AO3NamedSubscriptionsList.swift` (and whatever it calls in `AO3Client`) asks for
the `type=series` and `type=users` pages and shows each entry's name and byline, with paging,
a tap that opens the series or the author, and Unsubscribe.

## Build

Port iOS's two lists, in iOS's order and words:

- **Requests.** One GET per tab, made when the tab is first shown and on pull-to-refresh or a
  page change, through the same paced client and repository the Works tab uses
  (`AccountListRepository`), signed in only. Nothing is fetched for a tab the reader never
  opens, and nothing in the background. Check iOS's addresses and parameters exactly and use
  the same ones. This is the kind of request `docs/AO3_NETWORKING_POLICY.md` already allows for
  an account page the reader opened; say which paragraph covers it, and if none does, stop and
  say so at the top of the result.
- **Parsing.** Read the entries from the same subscriptions page markup the Works tab reads
  (the bundled `ao3_subscriptions.html` has a series and a user entry beside its works). Keep
  the Works parser's behaviour unchanged.
- **Rows.** Name and byline as iOS draws them, on the tokens and components the Works tab's
  rows use: read how the screen draws a row and its Unsubscribe today and reuse it. A tap opens
  the series page (`Routes.seriesWorks`) or the author's page (`Routes.authorProfile`), as iOS
  does. Paging uses the page's existing pager.
- **Unsubscribe.** iOS's flow, through whatever the Works tab's Unsubscribe uses today (read it:
  the form it posts, its confirmation, how the row leaves the list, what happens on failure).
  It is a write to AO3 that the reader starts with a tap; it must never run on its own. If the
  existing code cannot unsubscribe from a series or a user without a new kind of request, build
  the lists without it and say exactly what is missing.
- **States.** Loading, a true empty state (iOS's words) only after AO3 answered with none, an
  error with a retry, and signed-out, each as the Works tab shows them.
- **The header's count** ("3 works · page 1 of 3") follows the tab, as on iOS.
- Owner's rule since 2026-10-04: layout, content and behaviour follow iOS; navigation and chrome
  controls are Android's own (Material). No glass or capsule controls.

## Demo and tests

- The demo answers `…/subscriptions?type=works` today. Add routes in `network/ao3/DemoNetwork.kt`
  for the two new addresses, answered by fixtures that hold one series (My Series, `/series/999`,
  which the demo can open since 3al) and two authors. Original filler only.
- Tests: the parser on the bundled page (works, series and users each found, none mixed up);
  the two new addresses as iOS builds them; the tab asks only when shown; an AO3 "none" page
  gives the empty state and a failed request does not; Unsubscribe, if built, posts what the
  Works tab's does for its kind. No test may reach the network.
