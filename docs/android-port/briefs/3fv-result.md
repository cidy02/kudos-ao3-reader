# 3fv — request and screen-state rows

Working HEAD: `678efb6d`, branch `android/agent-codex-3fv`. Implemented locally,
**unbuilt and unrun**, for Claude to build, test, review and land. No Gradle, AO3
traffic, sign-in, commit, push, branch switch, Room/backup edit or `TASKS.md` edit.
`git diff --check` passes. No new regex or regex flags.

Paths below use **Android** = `android/app/src/main/java/io/github/cidy02/kudos/`,
**tests** = `android/app/src/test/java/io/github/cidy02/kudos/`, and **iOS** =
`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` (read-only).

## #90 — already fixed at this HEAD; regression test added

Android `network/ao3/AO3Client.kt:193` coordinates every explicit retry;
`performOnce` at line 218 makes one call and has no sleep/retry. The default
stack at line 94 disables transport retries and normalizes OkHttp's special
503/Retry-After:0 case. POST bodies are one-shot (`:482`); 307/308 are refused.
No production change needed for this row.

**iOS rule:** `Services/AO3Client.swift:347` retries transient reads through its
paced operation; writes remain single-shot.

**Test added:** `network/ao3/AO3NetworkingCoreTest.kt:308`,
`a503ReadRetryReentersCoordinatorSpacingForHtmlAndBytes`: localhost MockWebServer
returns 503/Retry-After:0 then 200; verifies exactly two requests and coordinator
starts at 0/600 ms for both HTML and bytes. Backoff's fake delay deliberately
does not advance the coordinator's clock, so a retry bypass cannot pass. Existing
POST 503/Retry-After:0 and POST 408 single-shot tests remain alongside it.

## #122 — confirmed; fixed

At the starting HEAD, `comments/CommentsScreen.kt` passed the chapter position
only for a focused Inbox comment and independently resolved the reader's chapter
in a later effect. `CommentsViewModel.open` therefore started All first.

**Changed:** Android `comments/CommentsScreen.kt:129` passes the position and
chapter repository into the model. `comments/CommentsViewModel.kt:233` resolves
`/navigate` before starting any comments request. The separate screen effect is
gone. A missing index falls back to one All load; focused Inbox thread/chapter
behavior remains on its existing path. The model's existing job cancellation and
session reset own this resolution too.

**iOS rule:** `Features/Comments/CommentsModel.swift:325` (`loadInitial`): resolve
the requested story chapter, then read that chapter; fall back to All if no index
is available. Existing newest-first pagination can still need the selected
scope's first and last pages; no preliminary All page is fetched.

**Tests added:** `comments/CommentsViewModelContextTest.kt:97` and `:125` gate
index resolution, assert zero comments reads before it resolves, then exactly
one chapter-comments read, and exactly one All read for index failure.

## #55 — confirmed; fixed, with related route sweep

At the starting HEAD, `account/AO3CollectionDetailScreen.kt:102` kept all pages,
segment and loaded flags in composition `remember` and started over on Back.

**Changed:** `account/AO3CollectionDetailScreen.kt:105` uses a navigation-entry,
session-keyed `AO3CollectionDetailViewModel`. Its `:45` appearance gate keeps
settled pages/failures, segment, pagination and the **same LazyListState** on
return. Pull refresh reads only the selected segment; confirmed collection
changes invalidate the segment gates. The already loaded header is retained,
matching iOS's request shape. No automatic read on a settled Back.

`account/AO3CollectionDetailRepository.kt:70` (the `collectionChanges` block)
records foreground confirmed changes only; it does not launch requests. Collection
form saves/deletion, maintainer invitation/leave, moderation, collection items,
challenge saves/sign-ups/withdrawal, assignment writes and prompt claim/release
mark the collection changed only in their success branches. Plain Back does not.
The existing collections-index navigation result remains in place.

**iOS rule:** `Features/Account/AO3CollectionDetailView.swift:36` keeps its state;
`:130` reuses loaded segments; `:146` refreshes the selected segment; `:159`
invalidates segment gates after `.ao3CollectionChanged`. Related screens retain
view state and gate activation (`Features/Challenges/ChallengeSettingsView.swift:87,521`,
`PromptMemeView.swift:114,526`).

The local-only LIVING-PROMPT is absent as dispatched, so an exact §10 name list
cannot be recovered here. I checked the actual route screens instead:

| Route screen, Android path:line | Finding/action |
| --- | --- |
| `account/AO3ChallengeSettingsScreen.kt:48` | Confirmed composition-owned model; retained VM + appearance gate; refresh after confirmed nested change. |
| `account/AO3CollectionMaintainersScreen.kt:44` | Confirmed; retained VM + gate, including invitation input. |
| `account/AO3CollectionModerationScreen.kt:57` | Confirmed; retained VM + gate, including current review page. |
| `account/AO3PromptMemeScreen.kt:63` | Confirmed; retained VM + gate, chosen filter saved. |
| `account/AO3TagSetScreen.kt:50` | Confirmed; retained VM + gate, typed fields kept. |
| `account/AO3ChallengeSignUpsScreen.kt:67` | Confirmed; retained VM + gate, filter saved; opening-generation admission kept across navigation. |
| `account/AO3ChallengeAssignmentsScreen.kt:60` | Confirmed; retained VM + gate, segment saved; opening-generation admission kept. |
| `account/AO3ChallengeSignUpScreen.kt:52` | Confirmed; retained VM + gate; draft form survives a pushed child. |
| `account/AO3CollectionFormScreen.kt:61` | Confirmed; retained VM + gate and its own probe scope; probes still cancel on departure. |
| `account/AO3CollectionItemsScreen.kt:95` | Already fixed by 3fo: entry VM + `loadOnAppear`; no activation change needed. |
| `account/AO3ChallengeSettingsEditScreen.kt:44` | Already retains entry VM and gates load. Added confirmed-change notification only. |
| `author/AuthorProfileScreen.kt:105` | Confirmed reset on every activation; retained per-route/session pages and selected tab, and removed unconditional reset. Cache TTL can no longer cause a Back read. |
| `app/SeriesWorksScreen.kt:85` | Confirmed unconditional repository call on Back; retains settled page/session state and gates initial load. Explicit saved-series refresh remains. |
| `author/AuthorWorksScreen.kt:65` | Confirmed; retains settled page and gates initial load. |
| `browse/FandomWorksScreen.kt:84` | Confirmed (also serves tag works); keeps page and applied filters and gates initial read. |
| `browse/FandomListScreen.kt:64` | Confirmed activation call (network depends on catalog cache); keeps page/query/options and gates it. |
| `browse/BrowseScreen.kt:66` | Confirmed category-index reread; keeps category page and asks only on initial load/explicit refresh. |

The last six routes share `ui/components/NavigationEntryState.kt:13` for small
in-memory values; the composition still owns every network coroutine. Session
keys remain on private profile/series state. No page read is moved into a
long-lived ViewModel scope. Collection-name probes now use the form model's scope
and are explicitly cancelled on every departure. Retained write models keep admission busy until the
original in-flight operation finishes, including when a reader returns meanwhile;
returning never resumes/repeats a write.

**Tests added:**

- `account/AO3CollectionReturnStateTest.kt:40`: fake-client counts across initial
  profile + selected page, segment/page changes, repeated return, confirmed-change
  revision and pull. Checks same entry/model, same scroll object and kept page.
- `account/AO3CollectionReturnStateTest.kt` also checks that session expiry during
  the header read installs nothing and starts no segment read, that a successfully
  loaded settings hub reloads only after a confirmed nested change, and that
  settled failures in all nine migrated account/challenge models do not reread
  on return.
- `author/AuthorProfileSortScreenTest.kt:79`: removes/recreates the actual profile
  composition, with cache TTL and stale fallback both zero; chosen Series remains
  and the fake client's count does not increase.
- `account/AO3CollectionMaintainersTest.kt:247`: returning during a gated invitation
  keeps admission busy and cannot send another POST. The existing disposed-screen
  assertion now permits release of admission after that original operation ends;
  private result data still does not install while hidden.

**Still manual:** actual navigation-entry scroll offset after returning from each
Manage destination, theme/density/screenshots and process recreation. The unit
check proves the same LazyListState is retained; it is not visual proof.

## #56 — confirmed for empty pages; nonempty failure handling already fixed

`account/AccountInboxViewModel.kt:186` formerly tested `items.isNotEmpty()`, so an
empty successfully shown page was still replaced by the full-screen failure.
Nonempty pages already survived the first and every later failed pull at this HEAD.

**Changed:** the kept-page test now uses the loaded `pageUrl`, including while
loading. A failed pull retains empty or populated rows/forms and shows the existing
failure card; the card lives outside the rows-only branch
(`account/AccountInboxPane.kt`, after its content-state switch). Same-page failures
say "Couldn't refresh your inbox". A stale cache fallback after a pull also keeps
the shown page and reports refresh failure (`AccountInboxViewModel.kt:150`).
Authentication-required failures continue clearing the private page.

**iOS rule / P3 handoff:** iOS `Features/Account/AO3InboxModel.swift:540,592` also
uses `items.isEmpty`, and `Features/Account/AccountInboxViews.swift:566` renders
`.failed` as "Couldn't load your inbox". Match Android's existing later-failure
behavior here; **iOS still needs the empty-shown-page correction**, and its stale
refresh fallback has no explicit refresh-failure message. No iOS files changed.

**Tests added:** `account/InboxFailedPageTest.kt:102` tests first and second failed
pulls for populated and empty successfully loaded pages, exactly one Inbox GET
per pull, and preserved rows/page URL/form. `:130` checks a stale fallback also
keeps the rows and reports the failed first refresh. Existing session-expiry test
still requires private data to clear.

## #41 — not real as an Android/iOS parity gap; shared P3 remains

The reference moved: iOS's file is
`Features/Bookmarks/AO3BookmarksWorksBrowser.swift`, not `Features/Account/…`.
Its `bookmark(for:)` at line 324 reads the parent's dictionary; the parent
`Features/Bookmarks/AO3AccountWorksList.swift:355` loads only while idle or after
a session change and has no bookmark-save observer. Android
`account/AccountWorksListScreen.kt:188` / `account/AccountViewModel.kt:250` likewise
keep the page on same-session return. I found no iOS row-update propagation to copy.

**Changed/test:** no Android row mutation, extra AO3 read or test encoding a
new behavior. Bookmark edits from Work Detail remain a shared owner/iOS follow-up;
an Android-only refresh here would exceed iOS's reads.

## #98 — confirmed; fixed

At the starting HEAD `web/AO3WebViewFallbackScreen.kt` classified all navigations
without checking the frame, and `openExternal` had no demo guard.

**Changed:** `web/AO3WebUrlPolicy.kt:26` adds a frame/demo-aware verdict, used by
the address bar and navigation delegate (`AO3WebViewFallbackScreen.kt:167,259`).
Web subframes stay embedded instead of launching an external browser; non-web
schemes remain blocked and `about:` frames are allowed. Every OS-browser entry
point goes through the demo guard at `:324`, including Browser buttons and the
initial URL fallback.

**iOS rule:** `Features/Browse/WebBrowser.swift:49`
(`BrowserThemeStyle.navigationVerdict`): only main-frame external web navigation
leaves the app; demo never launches the system browser. Android deliberately
continues allowing AO3 fixture URLs in demo because its `shouldInterceptRequest`
serves those and all subresources locally; external demo navigations are blocked.
The existing main-frame GET requirement for importing EPUB links is preserved.

**Test added:** `web/AO3WebUrlPolicyTest.kt:13` covers main vs subframe external
web links, about:blank, non-web schemes, local demo AO3 fixture navigation and
refusal of all demo external-launch entry points. No requests are made by it.

## Verification handoff

No Kotlin compilation, Gradle or test execution performed, per dispatch. Run the
new/changed test classes above plus the existing collection/challenge, profile,
series/browse, comments, Inbox, network retry/redirect and WebView policy suites.
`RegexPortabilityTest` remains appropriate even though this patch adds no regex.
Manually verify actual Back navigation, pull failures and iframe/demo browser
behavior before landing. No visual correctness or test-pass claim is made here.
