# Brief 3am result

**Landing note (Claude, 2026-10-05).** Landed with one change: the Works, Series and Authors
pills had been redrawn as stock Material filter chips in Material's default lavender; they are
the page's own pills again, as the row of filters under them. Gate green (1,446 tests). Seen on
the emulator: the Series tab's one series with its byline, the Authors tab's two authors, a tap
opening the series page and the author's page, Dark, and the largest text size. The two new
requests are the reader's own account pages, asked for only when a tab is opened, which the
networking policy allows. **Unsubscribe is not built for series and authors, and this brief
found that the Works tab's Unsubscribe never reaches AO3:** it hides the row on the device and
nothing else. That is brief 3an.

Implemented, uncommitted, Android only on `android/agent-gemini-3am`. No commits, pushes, branch switches, sign-ins, AO3 contact, Gradle or Xcode runs. `TASKS.md`, iOS, Room schemas and backup formats are unchanged.

## Request policy and reference

Allowed by `docs/AO3_NETWORKING_POLICY.md`, **What agents must NOT implement**, the paragraph beginning “No background or bulk scraping of logged-in pages”: authenticated reads are limited to “the user's own account lists” and explicitly opened pages. Named subscriptions are one foreground, signed-in account-page GET per activation/page/refresh through `AccountListRepository` and its existing paced `AO3Client`. No named-tab prefetch or enrichment.

Reference read-only: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Features/Bookmarks/AO3NamedSubscriptionsList.swift`, `Services/AO3Client+NamedSubscriptions.swift`, `Services/AO3Client.swift` (`subscriptionsURL`) and `Services/AO3WriteActions.swift` (`unsubscribe`). URLs use `type=series` / `type=users`, then `page=N` only after page one. Order: Works, Series, Authors. iOS refetches on scope changes rather than keeping a permanent first-visit cache; iOS wins if “first shown” in the brief implies caching subsequent visits. Authors have no byline; series show `by ` plus rel-author creator names. No invented unread fields.

## Unsubscribe fallback

Not built for named rows, as explicitly permitted by the brief. Android `SubscriptionsBrowser` confirms then calls `onUnsubscribeWork`, which only adds a work ID to an in-memory hidden set. It sends no request, has no AO3 failure flow, and cannot remove series/users. `AO3WriteRepository.toggleSubscribe(workId)` does have a delete POST, but prepares it by fetching a work page using a work ID; using it for series/users would require a new account-index write entry point.

Missing: iOS `unsubscribe(path:page:)` fetches the Works subscriptions index for a fresh CSRF token (even for a named row), then single-shot POSTs the parsed adjacent-dd form action with `_method=delete` and `authenticity_token`, with session-generation checks; it removes the row only on success, retreats from an emptied later page, and reports “Couldn't unsubscribe” on failure. A future authorized write implementation must wire that index-form flow to the existing authenticated write client. This brief does not add a misleading local-only named Unsubscribe control. Existing Works behavior is preserved.

## Implementation

- `AO3AccountUrls.namedSubscriptionsUrl` builds the two iOS addresses. `AO3AccountParser.parseNamedSubscriptions` reads `dl.subscription dt`, selects the kind from the first link's exact two-part path, keeps server order, deduplicates paths, collects only series rel-author bylines, and retains the existing pagination. `parseSubscriptionsPage` is unchanged (checked against HEAD).
- `AccountListRepository.loadNamedSubscriptions` uses the same injected client (`KudosAppContainer.accountListRepository` uses `ao3Client`) and authenticated cookies as Works. It rejects signed-out calls before GET, maps login/overload/transport failures, and rejects cancelled or superseded-session continuations. It does not put named counts into the Works cache.
- `NamedSubscriptionsLoader` has no constructor fetch. `SubscriptionsBrowser` starts it only for the rendered named tab, using a Compose-owned effect; retry and `KudosRefreshBox` pull-to-refresh reload that page. Scope/page/session changes replace the loader, cancel its visible waiter and refresh, and key its collected state so old rows cannot flash under a new tab. No timer, prefetch, later-page crawl, or named-row enrichment. Works' existing enrichment now stops when a named tab is selected.
- The screen keeps the subscriptions header and scope rail available even when Works is loading, empty or failed, so those states cannot prevent opening a named list. Named subtitles count only that page's named entries, with iOS singular/plural words and page suffix. Empty titles/messages and named error/retry copy are iOS's (`Couldn't load your list`, `Try Again`); loading and session-required presentations reuse Works' state cards.
- `NamedSubscriptionRow` uses Material Card, Works' Material shape/padding, account gutter/spacing and shared primary/secondary/theme-surface tokens. The text follows iOS: 15sp semibold name, optional 12.5sp `by …`, no metadata invented for author rows. `AppNavHost` supplies `Routes.seriesWorks` and `Routes.authorProfile` navigation. The scope rail uses Material FilterChip and the page's More control uses Material IconButton; no new glass or capsule controls.
- As in iOS `parseNamedSubscriptions`, a successful HTML response with no matching headings produces an empty page; this port does not add a stricter markup-recognition contract than the reference. Login, overload and failed requests never become an empty result.

## Demo

Launch a debug build with `--ez kudosDemoLibrary true --ez kudosDemoSignedIn true` (existing fixture session; no real login), then Account → Subscriptions → Series / Authors.

| Address | Fixture | Rows |
| --- | --- | --- |
| `/users/AO3_Reader/subscriptions?type=works` | existing `ao3_subscriptions.html` | Existing three works, untouched mixed index |
| `/users/AO3_Reader/subscriptions?type=series` | `ao3_demo_subscriptions_series.html` | My Series, `/series/999`, by seriesauthor |
| `/users/AO3_Reader/subscriptions?type=users` | `ao3_demo_subscriptions_users.html` | someuser, seriesauthor (no bylines) |

Both new demo pages have one page. The names/paths retain the bundled iOS sample identities; no copied creative prose or new unread values. Existing `/series/999` and author dashboard/works/profile fixtures answer row navigation. `DemoNetworkRoutes.fixtureName(HttpUrl)` selects subscriptions by the `type` query, including reordered parameters, later pages and optional trailing slash. Works and other route precedence remain intact. The active demo interceptor still refuses missing fixtures locally.

The obsolete 3al section 4 now links here as superseded rather than continuing to present its placeholder finding as current behavior.

## Tests and verification

Written, **not run**:

- `AO3AccountUrlsTest`: exact series/users type parameters, whitespace/path encoding, omission of page one and later-page parameters.
- `AO3SubscriptionsParserTest`: the real bundled mixed index yields three works, one series and one user without mixing; first-link selection, duplicate suppression, deeper-user-link rejection, server pagination, bylines, iOS empty/count copy. Existing sparse-Works test retained.
- `NamedSubscriptionsLoaderTest`: construction has no GET, signed-out has no GET, authenticated cookies and later-page URL, failed request versus answered-none, retry recovery, and a logout during a held GET rejects private rows.
- `NamedSubscriptionsBrowserTest`: real composable scope taps fetch only that scope; names/byline/header counts, row navigation callbacks, named pagination/current-page refresh; loading before a held response, signed-out without a request, failure never showing empty, retry producing a true answered-none state. Uses plain Application and a terminal in-memory client, avoiding app-container/network startup.
- `DemoNetworkBlockTest.namedSubscriptionsRoutesServeTheirOwnFixturesAndKeepWorkAndDetailRoutes`: new addresses serve the actual bundled assets, one series/two users, no works mixed in, preserved Works and destination routes, and local destination responses. Its final interceptor throws if a request tries to fall through to the network.

Passed here: `git diff --check`; inline Python HTML checks of mixed-index preservation, one series/two users, correct name/path/byline and existing destination assets; comparison of the Works parser against HEAD; Kotlin lexical delimiter sanity (not a compiler/type check); checks that `TASKS.md` and the branch remain unchanged. Read the real repository/client/auth/model/pager/component/navigation symbols used, and inspected the locally cached Compose test API signatures with `javap`. No helper files or `.orig` files were created.

**Claude must establish compilation and every Kotlin/Jsoup/JUnit/Robolectric behavior claim above.** From `android/`, run:

```sh
./gradlew :app:assembleDebug
./gradlew :app:testDebugUnitTest \
  --tests 'io.github.cidy02.kudos.network.ao3.account.*' \
  --tests 'io.github.cidy02.kudos.account.NamedSubscriptions*Test' \
  --tests 'io.github.cidy02.kudos.network.ao3.DemoNetworkBlockTest'
./gradlew :app:testDebugUnitTest
```

Manual, fixture-only emulator review remains: Works → Series → Authors; named rows, header counts, correct destinations/back navigation, switching while loading/failing, retry, signed-out state, empty response, page changes and pull-to-refresh. The one-page demo does not demonstrate multi-page paging; the composable test supplies a three-page response. Check theme/large-text density and confirm existing Works Updated/Mark All as Seen still work. No visual correctness is claimed. Named Unsubscribe remains the explicit fallback described above; no live write verification is requested for this implementation.
