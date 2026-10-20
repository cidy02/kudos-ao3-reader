# Brief 3fv: A65's request and screen-state rows (Android)

**Write code; do not commit, push, switch branches, sign in, run Gradle or contact
archiveofourown.org.** Claude builds, tests and lands it. Do not edit `TASKS.md`. Leave a result
file `docs/android-port/briefs/3fv-result.md`, written as you go: per row, **confirmed / already
fixed / not real** at this HEAD with `path:line`, what changed, the iOS rule followed
(`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`, read-only) and the test added.

Hard rules: `docs/AO3_NETWORKING_POLICY.md` is binding (reads only of the reader's own lists or a
page they opened; no background or bulk reading; a write only when asked, sent once, never
retried; pacing never weakened). iOS is the source of truth. Nothing Android shows today may be
lost. No Room or backup change. Android's ICU regex rejects some JVM-accepted flags
(`RegexPortabilityTest`).

The rows are from `docs/android-port/audits/A65-result.md` §1 (Gemini's index: it has been wrong
before, so **confirm each in the code first**). In this order:

1. **#90** A 503 retry inside `AO3Client.performOnce` (`network/ao3/AO3Client.kt:129`) sleeps and
   requests again without going back through `AO3RequestCoordinator`'s spacing and width. Make
   any repeat go through the coordinator, or follow iOS (`Services/AO3Client.swift`) if it does
   not repeat at all. A write must never be repeated (3fn: 307/308 rule).
2. **#122** Opening a chapter's comments starts an All-comments read, then switches to the
   chapter (`comments/CommentsScreen.kt:153`). iOS reads only the chapter
   (`Features/Comments/CommentsView.swift:92`). One read.
3. **#55** An AO3 collection's page forgets its segment and scroll place and reads its page again
   every time the reader comes back from one of its Manage screens (state in route `remember`,
   `account/AO3CollectionDetailScreen.kt:85`). Keep both across the return (a navigation-entry
   `ViewModel`, as 3fo #4 did for `AO3CollectionItemsScreen`), reading again only on a pull or
   after a Manage screen saved a change. Check the other route screens LIVING-PROMPT §10 names
   with the same `remember` pattern and list them; fix those that reread AO3 on return.
4. **#56** The Inbox's first failing pull after opening shows "Couldn't load your inbox" instead
   of keeping the page shown (`account/AccountInboxPane.kt:290`). Keep the shown page and say the
   refresh failed, as a later failing pull already does. iOS has the same P3: match Android's
   later-pull behaviour and note it for iOS in the result file.
5. **#41** A bookmark saved on a work opened from the AO3 Bookmarks list: is the row updated on
   the way back (`account/AccountWorksListScreen.kt:140`; iOS
   `Features/Account/AO3BookmarksWorksBrowser.swift:28`)? If iOS updates it, do the same with no
   extra AO3 read beyond what iOS makes.
6. **#98** The in-app web view treats sub-frame navigations as top-level ones (no
   `isForMainFrame` check) and, in the demo, has no counterpart of iOS's
   `BrowserThemeStyle.navigationVerdict` for external links (`web/AO3WebViewFallbackScreen.kt:160`;
   iOS `Features/Browse/WebBrowser.swift:18`). Only main-frame navigations leave the app; the demo
   never opens the phone's browser.

Tests for each confirmed row (a fake client counting requests where it is about reads).
