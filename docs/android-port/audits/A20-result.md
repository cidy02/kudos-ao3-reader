# Audit A20 result

Read-only. Lines are the current source under `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`. Tests cited below are under `/Users/cidy02/kudos-ios-polish/KudosTests/`. Findings already in `audits/A4-result.md`, `audits/A12-result.md`, and `audits/A19-result.md` were not re-filed. A19's ten fixes are reviewed under "A19's fixes". Android was not used as the reference.

One language rule this report rests on: in Swift, `return` leaves the enclosing function. A `do`/`catch` is a statement, not a function, so a `return` inside `do` does not resume after the `do`.

| id | severity | file:line | statement |
| --- | --- | --- | --- |
| A20-1 | P2 | `Features/Comments/CommentsModel.swift:246` | A comment typed while the signed-in name is still "AO3 Account" stays under `unknown-session:`. Verify Session never moves it. |
| A20-2 | P2 | `Features/Bookmarks/AO3AccountWorksList.swift:722` | Pull-to-refresh while a page load is in flight can leave Bookmarks, History, Subscriptions, or Marked for Later on the other page. |
| A20-3 | P2 | `Features/Browse/NativeBrowseView.swift:721` | Dismissing Filters keeps the edits, and the next tag or fandom page asks AO3 for that page of the new filters. |
| A20-4 | P2 | `Features/WorkDetail/WorkDetailOverviewSections.swift:156` | A series row shows a saved mature sibling's title and opens its detail with no reveal. |
| A20-5 | P2 | `Features/Comments/CommentsModel.swift:1191` | A reply or edit that AO3 accepted reloads the newest or first page, and an open thread says the comment is gone. |
| A20-6 | P2 | `Features/Home/HomeView.swift:580` | Verify Session during Home's first subscriptions load leaves the skeleton up. The list itself is not filled. |

## A20-1 Verify Session does not hand the unnamed draft to the account

`Features/Comments/CommentsModel.swift:21-37` and `:239-251`

```swift
let identity = knownUsername
    ?? (auth.isLoggedIn ? "\(unknownSessionPrefix)\(auth.sessionGeneration)" : "")
// ...
if authContext.identity.hasPrefix(AuthContext.unknownSessionPrefix),
   !current.identity.isEmpty,
   !current.identity.hasPrefix(AuthContext.unknownSessionPrefix),
   current.generation == authContext.generation + 1 {
    drafts.move(from: authContext.identity, to: current.identity)
}
```

`knownUsername` drops the placeholder `"AO3 Account"` (`:24-27`). Offline Keychain restore signs in with that name (`Services/AO3AuthService.swift:989-991`). The only production call of `drafts.move` is the condition above. Verify Session does not call it. It lives on the account menu (`Features/Account/AccountComponents.swift:248-249`).

`verifySession` bumps the generation, then awaits, and the real username is published only after that await (`Services/AO3AuthService.swift:667` and `:905-913`):

```swift
sessionGeneration += 1
let refreshedGeneration = sessionGeneration
// vault.save, then:
guard await finishAccepting(
    refreshed, expectedGeneration: refreshedGeneration
) else { return }
```

```swift
currentSession = session
sessionHintStore.saveUsername(session.username)
let cookieInstall = enqueueCookieInstall(session, expectedGeneration: expectedGeneration)
await cookieInstall.value
guard sessionGeneration == expectedGeneration else { return false }
status = .signedIn(username: session.username)
```

`CommentsView` owns its model as `@State` created in `init` (`Features/Comments/CommentsView.swift:89-98`). A model that is not in the hierarchy never runs `syncAuthenticationContext`. Opening comments afterwards builds a new model whose identity is the real username and reads `CommentDraftStore.draft` for that key only (`Services/CommentSubmission.swift:358-360`).

`KudosTests/CommentSubmissionTests.swift:552-571`, `anUnnamedSessionsDraftsMoveToTheAccountThatIsThenNamed`, calls `store.move` itself and then asserts the keys. It stays green if Verify Session never calls `move`.

**Failing case.** Airplane mode, launch, Keychain restore signs in as "AO3 Account". Open a work's comments, reply, type `typed offline`, and leave the screen (Cancel saves the draft; the composer also saves on disappear, `CommentsView.swift:1299` and `:1334-1336`). On Account, tap Verify Session once the network is back, and let it name the account. Open the same reply composer. The field is empty. The text is still stored under `unknown-session:<old generation>`. What should happen: that text is the draft for the account verification just named.

The same condition fails if a comments screen is still mounted and it observes the generation bump before the username write. Those two writes sit on opposite sides of `await cookieInstall`. The move runs only when one `syncAuthenticationContext` sees both a real name and a generation that is exactly one higher. This pass did not prove SwiftUI always delivers those as two updates. The Account path above does not need that.

**Smallest fix.** When `finishAccepting` replaces an `"AO3 Account"` session with a real username, move drafts off every `unknown-session:` identity onto that username there, not only from a live comments screen, and not only when the generation grew by exactly one. `CommentDraftStore.move` (`Services/CommentSubmission.swift:364-374`) still deletes the source when the destination key already exists, so a just-typed offline reply is dropped if that account already had a draft for the same parent. Keep the newer text.

## A20-2 Account lists apply whichever page finishes last

`Features/Bookmarks/AO3AccountWorksList.swift:722` and `:922-977`

```swift
.refreshable { await load(page: currentPage) }
```

```swift
private func load(page: Int) async {
    let expectedSessionGeneration = auth.sessionGeneration
    // ...
    phase = .loading
    do {
        // await accountBookmarksPage / subscriptionsIndex / kind.fetch
        guard auth.sessionGeneration == expectedSessionGeneration else { return }
        works = result.works
        // ...
        currentPage = result.currentPage
        totalPages = result.totalPages
        phase = .loaded
```

The pager disables its arrows while `phase == .loading` (`:882-890`). Nothing cancels an in-flight `load`, and there is no load token. `currentPage` stays on the old page until the response is assigned, and the loading overlay does not block the list. Pull-to-refresh, and a second `load` from Try Again (`:483`) after a failure that overlapped a late response, both call `load` again. Bookmarks, History, Marked for Later, and the subscriptions list all use this function.

**Failing case.** Signed in, Bookmarks, more than one page. Tap Next. While the spinner is up, pull to refresh. Next started `load(page: 2)` while `currentPage` was still 1, so refresh starts `load(page: 1)`. Both pass the session-generation check. Whichever response is assigned last writes `works` and `currentPage`. The screen can show page 1 after Next, or page 2 after a refresh that asked for page 1. What should happen: one load owns the screen, and a refresh waits for or replaces the in-flight page instead of racing it.

**Smallest fix.** The collections list already does this. Bump a load generation at the start of `load` (as `AO3CollectionsList.load` does at `Features/Account/AO3CollectionsList.swift:454-465`) and write `works` only when that generation is still current. Refresh should request the page the user is looking at, captured when the gesture starts, or cancel the previous load first.

A page from a session that has ended is not applied. The guard at `:967` returns before the assignment, and `AO3CollectionsList.load` (`:460-465`) plus `loadWholeIndexIfNeeded` (`:586-590`) require both the load generation and the session generation via `AO3CollectionSessionReload.shouldApplyLoad`. Inbox's `load` checks cancellation and `isCurrent` before it writes (`Features/Account/AO3InboxModel.swift:533-550`). That half of A19's suspicion is closed below.

## A20-3 A dismissed filter is what the next page requests

`Features/Search/AO3FilterPanel.swift:46-60` binds the host's filters directly. Reset and Apply are the only actions (`:186-218`). There is no Cancel, and `FilterPanelPresentation` (`UIComponents/FilterPanelPresentation.swift:35-48`) has no dismiss handler that puts the old filters back. The works-index sort is a real draft and is reseeded on appear (`AO3FilterPanel.swift:12-28` and `:144`); refine mode is documented as applying facets live because they do not fetch (`:83-86`). This finding is the search-mode panel on a tag or fandom works page.

`Features/Browse/NativeBrowseView.swift:696-702` and `:721-733` (`TagWorksView`; `FandomWorksView.load` at `:344-365` is the same shape):

```swift
/// Apply the chosen filters and close the panel. Back to page 1: page 7 of the
/// old result set is not page 7 of the new one, and AO3 would answer a page
/// number past the filtered end with nothing at all.
private func applyFilters() {
    showingFilters = false
    reload()
}
```

```swift
private func load(page: Int) async {
    phase = .loading
    loadToken += 1
    let token = loadToken
    do {
        let result = try await AO3Client.shared.worksPage(
            at: request.url, filters: filters, page: page, request: auth.authenticatedRequest()
        )
```

Pagination and pull-to-refresh call `load(page:)` with the page on screen (`:253-262`, `:219-221`, and the tag copies at `:566-568`). They do not compare the filters to the ones that loaded that page. The load token drops a stale response. It does not revert an edit the sheet was dismissed without applying.

Search's copy does notice the difference, and then runs the dismissed edits (`Features/Search/SearchView.swift:850-856`):

```swift
if page != 1, filters != loadedFilters {
    runSearch()
    return
}
```

**Failing case.** Open a tag or fandom with several pages and go to page 7. Open Filters, set Rating to Explicit, and swipe the sheet away (or close the iPad inspector) without Apply. The results on screen are still the unfiltered page 7. Tap Next, or pull to refresh. The request uses Explicit and page 7 or 8. Apply's own comment says that page of a new filter set is the wrong page and can come back empty. What should happen: a dismiss leaves the loaded query alone, and Apply is what starts page 1 of the new filters.

On Search the same swipe does not change the results until the next page tap, refresh, or Try Again. That tap calls `runSearch()` and replaces the loaded query with the edits the sheet was dismissed without applying. What should happen: those edits are discarded, and Next stays on the query that is already on screen.

**Smallest fix.** Keep the panel's search-mode edits in a draft, the way `WorksSortPresentation` already keeps the works-index sort, and write them to the host binding only from `confirm()`. Reset edits the draft. Browse's `load` then keeps requesting the filters the current page was loaded with.

## A20-4 Series rows leak a mature work and open it

`Features/WorkDetail/WorkDetailView.swift:57` and `:633-637`, drawn from `WorkDetailOverviewSections.swift:156-168` (the section is included at `WorkDetailView.swift:317`):

```swift
@Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion }) private var allWorks: [SavedWork]
```

```swift
var seriesWorks: [SavedWork] {
    guard let work = localWork, !work.seriesTitle.isEmpty else { return [] }
    return allWorks
        .filter { $0.seriesTitle == work.seriesTitle && $0.id != work.id }
        .sorted { $0.seriesPosition < $1.seriesPosition }
}
```

```swift
ForEach(seriesWorks) { other in
    NavigationLink {
        WorkDetailView(work: other)
    } label: {
        HStack {
            if other.seriesPosition > 0 {
                Text("\(other.seriesPosition).")
            }
            Text(other.title).lineLimit(1)
        }
    }
}
```

Nothing under `Features/WorkDetail/` consults `PrivacyGate`. The destination's title and summary are the saved record's own text (`WorkDetailView.swift:471-472` and `:495-497`).

**Failing case.** Settings, Hide Mature Content, mode Hide or Blur. Two saved works share a series title. The one on screen is General. The other is Explicit and not revealed. Open the General work's detail. The Series section shows the Explicit work's title. Tap it. That work's detail opens, title and summary included, and no Face ID prompt runs. What should happen: that row is omitted in Hide, and in Blur it is the same unnamed reveal row used on Home until `PrivacyGate.reveal` succeeds.

**Smallest fix.** Drop `gate.isHidden` works from `seriesWorks`. For a blurred sibling, show the "Hidden mature work" row and call `gate.reveal` instead of pushing `WorkDetailView`.

## A20-5 A posted reply reloads a different page

`Features/Comments/CommentsModel.swift:149` (`newestFirst` defaults to `true`), `:632-655`, and `:1181-1191`:

```swift
private func load(
    auth: AO3AuthService, forceRefresh: Bool = false,
    expected: AuthContext
) async {
    guard isCurrent(expected, auth) else { return }
    var target = 1
    if newestFirst {
        if let known = knownTotalPages() {
            target = known
        } else if let first = await fetchPage(
            1, auth: auth, forceRefresh: forceRefresh, expected: expected
        ) {
            // ...
            target = first.totalPages
        } else {
            return
        }
    }
    await loadPage(target, auth: auth, forceRefresh: forceRefresh, expected: expected)
}
```

```swift
closeComposer()
composerText = ""
// One refresh so the new/updated comment is visible (bypasses cache).
await load(auth: auth, forceRefresh: true, expected: expected)
```

`finishIfSucceeded` runs only after the submit phase is `.succeeded`. It does not pass the page the reader was on. `CommentThreadScreen` is a live read of that same model (`Features/Comments/CommentThreadScreen.swift:12-13` and `:36`). When the root is no longer in `displayThreads` it shows "Thread Unavailable" / "This comment is no longer on this page" (`:76-83`). The thread screen is pushed from `CommentsView` (`:180-188`), which stays alive underneath and owns the composer.

**Failing case.** Open comments on a work with more than one page. Newest First is the default, so the screen is on the last page. Tap Previous until an older page is showing, open Thread on a comment there, reply, and post. AO3 accepts it. `finishIfSucceeded` then loads the last page again. The open thread's root is not on that page, so the screen says the comment is gone. Back lands on the last page, not the page the reply was posted under. The new reply is under its parent, on the page the reader just left. A successful edit takes the same path: `submit` calls `finishIfSucceeded` at `:1112` after `submissionGuard.succeed()`, and Check Again does it again at `:1123`. What should happen: the refresh keeps the page that contains the thread, and the open thread still shows the comment that was just replied to or edited.

**Smallest fix.** Pass the current page into that reload, and use the parent's thread page for a reply, instead of `load`'s first-or-last target. Leave the default Newest First behaviour for a fresh open of the comments screen.

## A20-6 The subscriptions skeleton survives the generation check

`Features/Home/HomeView.swift:573-597`

```swift
isLoadingSubscriptions = true
let generation = auth.sessionGeneration
do {
    let loaded = try await auth.accountSubscriptions()
    guard !Task.isCancelled, auth.isLoggedIn, auth.sessionGeneration == generation else { return }
    subscriptions = loaded
    // ...
} catch {
    if subscriptions.isEmpty, !Task.isCancelled { subscriptionsLoadFailed = true }
    // ...
}
isLoadingSubscriptions = false
```

The `return` is inside `do`, so it leaves `loadSubscriptions` and skips `isLoadingSubscriptions = false`. The skeleton is `isLoadingSubscriptions && subscriptions.isEmpty` (`:524` and `:545-546`). The assignment itself is fenced, and `accountSubscriptions` returns without recording when the generation changed (`Services/AO3AuthService.swift:808-812`). Sign-out still clears the flag, because the signed-out task takes the branch at `:566-570`. Verify Session does not: it stays logged in, so `.task(id: auth.isLoggedIn)` (`:231-234`) does not start a new load.

**Failing case.** Signed in, Home, first visit, subscriptions request still in flight and the shelf is the skeleton. On Account, tap Verify Session and let it succeed. Home never assigns that response, and it never clears the loading flag. The shelf stays six cover skeletons until a later pull-to-refresh runs `loadSubscriptions` again. What should happen: the flag drops, and the next load (or this one, if the generation is accepted) shows the list or the empty state.

**Smallest fix.** Clear `isLoadingSubscriptions` in a `defer`, or `return` only from a nested scope that still reaches the line that clears the flag.

## A19's fixes

Commit `86389972` on `claude/polish-loop`. The uncommitted text-size edits in that working copy were ignored.

**A19-1.** Closed for the failing case. `BrowserThemeStyle.navigationVerdict` (`Features/Browse/WebBrowser.swift:47-59`) cancels a missing URL, allows `about`, cancels every scheme other than `http` and `https`, cancels all remote URLs while the demo flag is on, allows a non-main-frame `http(s)` embed, allows a main-frame `https` AO3 host, and sends every other main-frame `http(s)` outside. `load` (`:332-346`) uses that verdict before `WKWebView.load`. The navigation delegate (`:425-430`) returns `decide`, which calls `openOutside` only for `.openOutside` (`:64-75`). `mayImportDownload` (`:97-99`) requires a main frame and an AO3 URL, and the response policy uses it (`:419-422`). `javascript:`, `data:`, `file:`, and a custom scheme are `.cancel` in the address bar and in the delegate, and `decide` does not hand them to `UIApplication.shared.open`. This was not executed on a device. `BrowserNavigationVerdictTests` asserts the verdict and `mayImportDownload` only. It would stay green if `load` or the delegate stopped calling them. The subframe `http(s)` allow is the comment at `:57-58` (AO3 embeds). A cookie is not sent to a different host. Not re-filed.

**A19-2.** Closed. With the demo flag on, `load` uses `loadHTMLString` and returns (`:333-339`). The verdict cancels remote navigations, including a subframe. The login web view's navigation delegate calls the same `decide` (`Services/AO3WebLoginCoordinator.swift:417`).

**A19-3.** Closed for the failing case. The library-match builder skips `gate.isHidden` (`Features/Search/SearchView.swift:492`), and `localMatchKey` includes the privacy inputs (`:90-100`) so the task reruns when Hide, Blur, or reveal changes.

**A19-4.** Closed for both pages. `FandomWorksView.load` (`Features/Browse/NativeBrowseView.swift:344-412`) and `TagWorksView.load` (`:721-746`) bump `loadToken` and return before assigning when it has changed. The new failure is A20-3: the token does not undo a filter edit that was dismissed without Apply.

**A19-5.** Closed for the failing case. `loadSubscriptions` assigns only when the task is not cancelled, the user is still signed in, and the generation matches (`Features/Home/HomeView.swift:580`). `accountSubscriptions` returns before `record` on a generation change (`Services/AO3AuthService.swift:812`). What the fix leaves open is A20-6, the stuck skeleton.

**A19-6.** Closed. Read and Work Details are inside `if !isBlurred` (`Features/Library/WorkCardActions.swift:344-347`). A blurred Home cover is not wrapped in a `NavigationLink` (`Features/Home/HomeView.swift:496-503`). Its tap calls `gate.reveal` (`Features/Privacy/MatureContent.swift:322`). The resume hero's blurred branch does the same (`Features/Home/HomeResumeHero.swift:53-58`). The context menu is still attached there, and its actions are the empty branch above, so the long-press does not open the work.

**A19-7.** Not closed. The move was added at `CommentsModel.swift:246-250` and still does not run for the failing case. Filed as A20-1.

**A19-8.** Closed. Select-mode blurred covers and rows use "Hidden mature work" (`Features/Privacy/MatureContent.swift:316-318` and `:323-324`, and `HomeResumeHero.swift:49-50`).

**A19-9.** Closed for the title leak. A hidden or blurred row is a reveal button labelled "Hidden mature work" (`Features/Account/AvailabilitySweepView.swift:70-84`). The section count still includes those works. It does not print their titles.

**A19-10.** Closed. Both failure logs use `privacy: .private` for the file name and the reason (`Services/ExternalFileImport.swift:61` and `:93`).

## A19's unconfirmed suspicions

**`javascript:` and custom schemes.** Closed by reading. `navigationVerdict` returns `.cancel` for any scheme other than `http`, `https`, and `about` (`WebBrowser.swift:50-53`). `load` does not call `WKWebView.load` in that case (`:341-344`). `decide` returns `.cancel` and does not call `openOutside` (`:73-74`). `BrowserNavigationVerdictTests.otherSchemesGoNowhere` locks the verdict for `javascript:`, `data:`, `file:`, and `kudos:`. Not run on a device.

**Home carousel tap versus the reveal gesture.** Closed. The blurred branch has no `NavigationLink` (`HomeView.swift:496-503`). The non-selecting tap is only `gate.reveal(work)` (`MatureContent.swift:320-322`).

**Availability sweep force-unwrap.** Not closed. Still under Unconfirmed.

**A page from an ended session.** Closed. See A20-2. Collections, collection detail (`Features/Account/AO3CollectionDetailView.swift:551-559`), collection items, the account works list, and the inbox all refuse the write when the session generation has moved on. The account works list can still apply the wrong page of the same session. That is A20-2.

**Reopening a browser `Bookmark`.** Closed. The only insert of the SwiftData `Bookmark` is `BrowseView.bookmarkCurrentPage` (`Features/Browse/BrowseView.swift:143-147`). Nothing in the app reads `Bookmark.url` or `urlString` into `BrowserModel.load` or `AppRouter.open`. Backup restores the row (`Services/KudosBackup.swift:3138`). The model comment says the link can be reopened in Browse (`Models/Models.swift:694-698`); no such screen exists, and the port notes treat that list as not built. There is no gate to bypass. Not filed as a missing screen.

## Unconfirmed

`WorkAvailabilitySweep.run`'s default verifier force-unwraps the context (`Services/WorkAvailabilitySweep.swift:90`):

```swift
verify: (SavedWork) async -> Void = { await WorkAvailability.verify($0, in: $0.modelContext!) }
```

`WorkAvailability.verify` returns immediately when `modelContext` is nil (`Services/WorkAvailability.swift:39-42`), and its comment says the caller can delete the work before `verify` runs. The unwrap happens before that guard. The batch is held across `requestSpacing`, 1500ms (`WorkAvailabilitySweep.swift:40` and `:111-114`). SwiftData's `modelContext` is nil once the model is no longer in a context, which includes after deletion. If a not-yet-checked work in `batch` is deleted while this task is still running, the next default `verify(work)` traps.

`AvailabilitySweepView` cancels that task on disappear (`Features/Account/AvailabilitySweepView.swift:59`), and pushing a work from this list leaves the screen. This pass did not find a same-window delete that keeps the sweep task alive. Confirm on a Mac or iPad with the library in another window: start Check Now, and during a gap delete a work that is still queued and not yet the one in `verify`. A trap confirms it. Passing `context` (the argument `run` already has) into `verify`, and deleting the `!`, removes the unwrap either way.

## What was not read

Not walked line by line: `Settings/` form bodies, `Features/Onboarding/`, `Features/Support/`, and the login screens in `Features/Auth/` past the coordinator's `decide` call and the two constant `archiveofourown.org` URLs in `AO3LoginView.swift:19-20`. A search of those trees found no `try!`, `fatalError`, or `privacy: .public`. `Features/Search/TagSelectField.swift` and the fandom index views were not re-read in this pass; a search there found no `try!` or `fatalError`.

Work Detail sheets other than the series list and the bookmark composer were sampled, not exhausted. The bookmark composer keeps a failed save's text and treats Cancel as dismiss (`Features/WorkDetail/AO3WorkActionsModel.swift:125-140`). `downloadItem` can pass id `0` when a saved work has no AO3 id (`WorkDetailView.swift:1100-1101`), and `DownloadQueue.run` then requests `/downloads/0/work.epub` (`Services/DownloadQueue.swift:168-169`). No user path that reaches id 0 was established. `read()` restores a pending-deletion work and downloads when the file is missing (`WorkDetailView.swift:1046-1056`); that path was not followed into the importer.

Comment thread geometry, collapse, and "load more" (`expandReplies`) were not walked for an index. The comments pager cancels `contextLoadTask` (`CommentsView.swift:805-807`) and `fetchPage` drops `CancellationError` (`CommentsModel.swift:856-859`). A fast Next then Previous can still assign whichever request already resumed past that `await`. Not filed. Inbox focus uses the immediate Parent Thread id (`CommentsModel.swift:570-577`, `AO3CommentModels.swift:236-243`). The fixture and `standaloneThreadResolvesInboxParentOrSelfAndExactChapter` treat that as the parent-or-self view `TASKS.md` describes. Not filed.

Author block, mute, and subscribe still report success from `submitScrapedHTMLForm`'s any-2xx path. That is the P3 leftover A4 already recorded for Subscribe and Bookmark. Not re-filed. `docs/REDESIGN_DECISIONS.md` and `docs/AO3_NETWORKING_POLICY.md` were not read end to end. `docs/TASKS.md` is not in this worktree; the iOS repo's `TASKS.md` was used only for the inbox Parent Thread note.

## Triage (Claude, 2026-10-08)

All six read against the code; all real. Fixed on iOS in **T-370** (`af328f7c` on
`claude/polish-loop`, `54b3cbbd` on integrate; full suite 2,320 with the one known failure;
macOS builds). Nothing was seen on a device.

| id | iOS | Android |
| --- | --- | --- |
| A20-1 | Fixed. My A19-7 fix only ran while a comments screen was open. `verifySession` now moves the drafts of the session it has just named; an open screen follows the session through both of its steps; a conflict keeps both drafts, the one just typed first. | No unnamed-session state. |
| A20-2 | Fixed: a load token (the function moved into an extension to stay within the linter's length). | Already cancels the previous load and checks the request. |
| A20-3 | Fixed by dropping the edits when the panel closes without Apply (fandom page, tag page; on Search only while results are on screen, and the typed text stays). A draft inside the panel would be the fuller fix. | The same fault on all three screens; fixed the same way. No test. |
| A20-4 | Fixed: hidden siblings left out, blurred ones an unnamed reveal row. | Work Detail has no sibling list. |
| A20-5 | Fixed: a reply or an edit reloads the page on screen. | The same fault (a reply, an edit, a delete and the "couldn't confirm" check all reloaded page 1); fixed, and the focused comment is kept. No test. |
| A20-6 | Fixed: Home asks again when the session moved on while it was loading. A regression from T-367. | Not present: the load is not abandoned there. |

Grok's review of T-367: nine of ten fixes close their cases (A19-7 did not: A20-1).
Open, not filed as findings: `WorkAvailabilitySweep.swift:90` force-unwraps a work's context;
a fast Next then Previous in the comments pager can apply whichever answer resumed; inbox
focus uses the immediate parent thread id; `downloadItem` with no AO3 id asks for
`/downloads/0/`. Not read: Settings forms, Onboarding, Support, the login screens.
