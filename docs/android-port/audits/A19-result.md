# Audit A19 result

Read-only. Lines are the current source under `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`. Tests cited below are under `/Users/cidy02/kudos-ios-polish/KudosTests/`. Findings already in `audits/A4-result.md` (AO3 writes) and `audits/A12-result.md` (reader, Library, backup), including the triage note that Subscribe and Bookmark still treat one 2xx as success, were not re-filed. Android `audits/A18-result.md` was used only as a checklist: the iOS edit composer does not write the draft store, and the inbox open path passes `initialCommentID`.

Two framework rules checked before use:

- `Task.cancel()` is cooperative. A function that does not check cancellation runs to completion, including the lines after an `await` that has already returned. Apple, [Task.cancel()](https://developer.apple.com/documentation/swift/task/cancel()).
- `WKWebView` networking runs out of process and does not see an app `URLProtocol`. Apple DTS, [developer.apple.com/forums/thread/69854](https://developer.apple.com/forums/thread/69854). `WKURLSchemeHandler` cannot replace `http` or `https`.

| id | severity | file:line | statement |
| --- | --- | --- | --- |
| A19-1 | P2 | `Features/Browse/WebBrowser.swift:279` | The in-app browser loads non-AO3 and non-https addresses in the web view that keeps the AO3 cookie store, and imports any EPUB response. |
| A19-2 | P2 | `App/DemoLibrary.swift:425` | With the demo library on, opening AO3 Website still requests archiveofourown.org. The URLProtocol test stays green. |
| A19-3 | P2 | `Features/Search/SearchView.swift:484` | Hide Mature leaves a matching saved work's title and summary in "In Your Library", and can list a fandom that exists only on that work. |
| A19-4 | P2 | `Features/Browse/NativeBrowseView.swift:380` | A fandom or tag page applies whichever load finishes last, so a sort change or pull-to-refresh can show another query's works. |
| A19-5 | P2 | `Features/Home/HomeView.swift:567` | A subscriptions response that returns after Sign Out is written back onto Home and into the signed-out list-count cache. |
| A19-6 | P2 | `Features/Library/WorkCardActions.swift:340` | Long-press Read and Work Details open a blurred mature work without revealing it. |
| A19-7 | P2 | `Features/Comments/CommentsModel.swift:30` | A comment typed while the signed-in name is still "AO3 Account" is stored under a key the real username never loads. |
| A19-8 | P3 | `Features/Privacy/MatureContent.swift:187` | VoiceOver on a blurred row or cover in Select mode reads the work's title. |
| A19-9 | P3 | `Features/Account/AvailabilitySweepView.swift:69` | "No longer on AO3" lists titles and authors with Hide or Blur on. |
| A19-10 | P3 | `Services/ExternalFileImport.swift:60` | A failed Open With logs the file name with `privacy: .public`. |

## A19-1 In-app browser skips the cookie-store gate

`Features/Browse/WebBrowser.swift:233-246` and `:272-284`

```swift
override init() {
    let configuration = WKWebViewConfiguration()
    // Default data store persists cookies, so the user's AO3 login sticks.
    configuration.websiteDataStore = .default()
    webView = WKWebView(frame: .zero, configuration: configuration)
    ...
    load(BrowserModel.home)
}

func load(_ url: URL) {
    webView.load(URLRequest(url: url))
}

func loadFromAddressBar() {
    let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    if let url = URL(string: trimmed), url.scheme != nil {
        load(url)
    } else if let encoded = ...
```

`App/AppRouter.swift:186-206` is the gate this web view does not use. `AO3AuthorRoute.isAO3URL` (`Models/AO3AuthorModels.swift:147-152`) is https, apex or subdomain, only.

```swift
/// Scheme + host gates live at this sink, not at the call sites.
/// `javascript:` / `data:` / `file:` are refused (not handed to the
/// system opener). Non-AO3 `http(s)` is routed to the system browser so
/// it never shares the AO3 cookie store. Only `https` AO3 hosts present
/// the in-app sheet
func open(_ url: URL) {
    guard let scheme = url.scheme?.lowercased(),
          scheme == "http" || scheme == "https"
    else { return }
    if !AO3AuthorRoute.isAO3URL(url) {
        UIApplication.shared.open(url) // macOS: NSWorkspace
        return
    }
    pendingURL = url
    isPresentingWebBrowser = true
}
```

`BrowserModel` implements `decidePolicyFor navigationResponse` and does not implement `decidePolicyFor navigationAction`. The response policy (`WebBrowser.swift:337-346`) downloads when the MIME type is `application/epub+zip` or the path extension is `epub`. It does not look at `isForMainFrame` or the host. `downloadDidFinish` (`:398-400`) calls `onImport`, and `AO3WebBrowserView.configureImport` (`Features/Browse/BrowseView.swift:129-140`) imports that file into the library. The address field submits straight to `loadFromAddressBar` (`BrowseView.swift:95`).

The visible login web view is the same hole: `AO3WebLoginCoordinator` uses `WKWebsiteDataStore.default()` (`Services/AO3WebLoginCoordinator.swift:99-104`) and its delegate (`:410-431`) handles finish and failure only.

**Failing case.** Signed in, Browse, Open AO3 Website. The address placeholder is "Search AO3 or enter a URL". Type `https://example.com` and submit. `URL(string:)` has a scheme, so `load` puts that page in the web view whose data store holds the AO3 session. A link on an AO3 page to a non-AO3 host does the same, because nothing cancels the navigation. `router.open` would have sent that http(s) URL to the system browser. From the loaded page, a main-frame or subframe response with an EPUB MIME type or a `.epub` path is saved into the library with no Download tap. What should happen: only `https` archiveofourown.org (apex or subdomain) stays in this web view; other http(s) URLs open outside it; `javascript:`, `data:`, and `file:` are cancelled; an EPUB import runs only for a main-frame AO3 download the reader started.

**Smallest fix.** In `load` and in `decidePolicyFor navigationAction`, allow only `BrowserThemeStyle.isAO3URL` (already https-only). Cancel every other scheme inside the web view. For a non-AO3 `http` or `https` navigation, cancel and call the same external open `AppRouter.open` uses. Download only when `navigationResponse.isForMainFrame` and the response URL is https AO3.

## A19-2 Demo mode still loads AO3 in the web view

`App/DemoLibrary.swift:406-428`

```swift
/// With the demo library on, every request to AO3 fails at once, on every
/// session — the design-review simulator must never touch the real site, even
/// when a screen it opens would normally fetch (owner rule: never contact
/// archiveofourown.org). Off, this is inert.
final class DemoNetworkBlock: URLProtocol {
    override static func canInit(with request: URLRequest) -> Bool {
        guard isActive, let host = request.url?.host?.lowercased() else { return false }
        return host == "archiveofourown.org" || host.hasSuffix(".archiveofourown.org")
    }
}
```

`App/MyApp.swift:30-34` calls `DemoNetworkBlock.installGlobally()` only inside `#if DEBUG`, and only when `KudosDemoLibrary` is true. `install(into:)` covers the AO3 `URLSession`. `BrowserModel.init` then calls `load(BrowserModel.home)`, which is `https://archiveofourown.org` (`WebBrowser.swift:224` and `:246`). That load is a `WKWebView` request. Per the DTS note above, it never enters `canInit`.

`KudosTests/DemoNetworkBlockTests.swift:7-22`, `blocksOnlyAO3AndOnlyInDemoRuns`, expects `canInit` true for archiveofourown.org and download.archiveofourown.org in demo, and false for `https://example.com`. A web view load of AO3 leaves that test green. The test does prove the `canInit` host check.

**Failing case.** Launch a debug build with `-KudosDemoLibrary YES`. Open AO3 Website (or the login web view, which uses the same default data store and the same unguarded `WKWebView.load`). The web view performs a real request to archiveofourown.org. URLSession fetches from the app are failed or served from fixtures. What should happen: that web view never contacts archiveofourown.org while the demo library is on (local fixture, or an immediate failure), matching the comment at `DemoLibrary.swift:406-409`.

**Smallest fix.** While `DemoNetworkBlock.isActive`, do not call `WKWebView.load` with a remote AO3 URL in `BrowserModel` or `AO3WebLoginCoordinator`. Load a fixture page or fail in-process. `WKURLSchemeHandler` cannot intercept `https`.

## A19-3 Search Hide mode still shows the saved work

`Features/Search/SearchView.swift:484-496`

```swift
matches.works = Array(
    savedWorks.lazy.filter { WorkSearchIndex.matches($0, terms: terms) }.prefix(20)
)

var seenFandoms = Set<String>()
outer: for work in savedWorks {
    for fandom in work.workFandoms {
        let key = WorkSearchIndex.normalize(fandom)
        guard key.contains(normalizedQuery), seenFandoms.insert(key).inserted else { continue }
        matches.libraryFandoms.append(fandom)
```

`SearchLocalResultsList` draws those works with `SensitiveWorkRow` (`Features/Search/SearchLocalResultsList.swift:38-50`). `SensitiveWorkRow.blurred` is true only when the mode is `.obscure` (`Features/Privacy/MatureContent.swift:121-123`). The comment on that view (`:87-89`) says Hide mode filters the work out before the row. `PrivacyGate.isHidden` (`:63-65`) is that filter: Hide, adult, and not revealed. Search never calls it. The visible branch is `WorkRow`, which prints the summary (`Features/Library/WorkRow.swift:256-258`). Home does filter, in `HomeView.passesPrivacy` (`Features/Home/HomeView.swift:100-102`).

**Failing case.** Settings, Hide Mature Content, mode Hide. A saved work is Mature or Explicit and its title contains "lantern". On Search, before submitting an AO3 search, type `lantern`. "In Your Library" shows that title, author, and summary. If the only saved work carrying a fandom named in the query is that adult work, "Fandoms in Your Library" shows the fandom name too. Show mature (`PrivacyGate.toggleRevealAll`) is what should bring the row back. Blur mode does blur the row.

**Smallest fix.** When building `matches.works` and the library-fandom loop, skip `gate.isHidden(work, enabled: hideMature, mode: mode)`, the same predicate as `passesPrivacy`. Select-all already uses `localWorks`, so it follows the filtered list.

## A19-4 Fandom and tag pagers keep the late page

`Features/Browse/NativeBrowseView.swift:339-384` (`FandomWorksView.load`) assigns with no token and no cancellation check:

```swift
private func load(page: Int) async {
    phase = .loading
    do {
        ...
        result = try await AO3Client.shared.fandomWorksPage(...)
        // or search(...)
        results = result.works
        currentPage = result.currentPage
        totalPages = result.totalPages
        resultSummary = result.summary
        phase = .loaded
```

`TagWorksView.load` (`:706-721`) is the same assignment after `worksPage`. Callers start a new unstructured task and leave the previous one running: pagination `Task { await load(page: page) }` (`:257` and `:615`), `reload()` (`:408-414` and `:696-703`), pull-to-refresh (`:214-217` and `:551-554`). The hero sort menu calls `reload()` immediately (`:310-319` and `:668-677`). `SearchPaginationBar` disables the arrows while `phase == .loading` (`Features/Search/SearchPaginationBar.swift:62` and `:174`), so a second tap on Next is not the trigger. The hero stays up during a page load because `load` does not clear `resultSummary` (`NativeBrowseView.swift:178` and `:515`).

Search already drops a stale page. `Features/Search/SearchView.swift:857-870` bumps `loadToken`, cancels `loadTask`, and returns before assigning when the token changed. The comment at `:849-852` says that guard is what Browse's pager was missing.

**Failing case.** Open a fandom with more than one page. Tap Next. While that request is in flight the arrows are disabled and the previous page stays on screen, sort menu included. Change the sort. `reload()` starts page 1 of the new sort and does not cancel the page-2 request. Whichever request finishes last writes `results` and `currentPage`. The screen can show page 2 of the old sort under the new sort, or page 1 of the new sort with `currentPage` taken from the old response. Pull to refresh while a page request is in flight is the same pair of writes. The tag works page behaves the same way.

**Smallest fix.** Copy Search's `loadToken`: bump it synchronously, cancel the previous task, and `guard token == loadToken` before every assignment to `results`, `currentPage`, `totalPages`, `resultSummary`, and `phase`.

## A19-5 Subscriptions return after Sign Out

`Features/Home/HomeView.swift:231-234` and `:555-571`

```swift
.task(id: auth.isLoggedIn) {
    await Task.yield()
    await loadSubscriptions()
}

private func loadSubscriptions() async {
    guard auth.isLoggedIn else {
        subscriptions = []
        ...
        return
    }
    isLoadingSubscriptions = true
    do {
        subscriptions = try await auth.accountSubscriptions()
        subscriptionsListCount = AO3AccountListCountsCache.shared.count(...)
```

`subscriptionsSection` (`:513-528`) renders `subscriptions` whenever `merged` is non-empty. It does not require `auth.isLoggedIn`. `accountSubscriptions` (`Services/AO3AuthService.swift:804-814`) checks `isLoggedIn` only before the fetch, then records the page and returns the works:

```swift
let result = try await AO3Client.shared.subscriptionsPage(for: request, page: page)
AO3AccountListCountsCache.shared.record(
    page: result,
    kind: .subscriptions,
    authenticationScope: AO3AuthorProfileFetcher.sessionScopedCacheScope(for: self)
)
return result.works
```

`logout()` (`AO3AuthService.swift:588-600`) bumps `sessionGeneration`, clears the session, and sets `status = .signedOut` before any later await. SwiftUI then cancels the Home task whose id is `auth.isLoggedIn` and starts the signed-out task, which clears `subscriptions`. Cancellation does not rewind an `await` that has already produced a value, and nothing after that `await` reads `Task.isCancelled` or the generation. The catch path (`:573-578`) does avoid treating `CancellationError` as a failure, and it does not assign `subscriptions`.

**Failing case.** Signed in on Home, subscriptions request in flight, and the response has already come back when Sign Out runs. The signed-out task clears the shelf. The cancelled task then assigns `subscriptions` to that private list, and the carousel shows those titles while signed out. On the same return, `accountSubscriptions` records the count under `sessionScopedCacheScope`, which is now `anonymous#session-<logout generation>` (`Services/AO3AuthorProfileService.swift:10-24`). What should happen: the shelf stays empty, and the count is not recorded for the signed-out scope. A request that is still outstanding and throws `CancellationError` does not hit the assignment; the missing check is what leaves the completed-response window open.

**Smallest fix.** Capture `sessionGeneration` before the await. After it, assign and record only when `!Task.isCancelled`, `auth.isLoggedIn`, and the generation is unchanged. Put the same guard inside `accountSubscriptions` before `record`.

## A19-6 Blurred cover opens from the context menu

`Features/Home/HomeView.swift:485-506` wraps every non-selecting local cover in a reader link and attaches the menu. The selecting branch attaches the menu too:

```swift
NavigationLink(value: LocalWorkDestination.reader(work)) {
    SensitiveWorkCoverCard(work: work, footer: footer(kind, work), progress: progress(kind, work))
}
.buttonStyle(.plain)
.localWorkContextMenu(work: work, onSelect: selectAction(for: work))
```

`CanonicalWorkCoverCard` does the same for a local subscription match (`Features/Home/CanonicalWorkCoverCard.swift:13-20`). `HomeResumeHero` attaches the menu on both blurred branches (`Features/Home/HomeResumeHero.swift:52` and `:58`) and does not wrap the blurred hero in a `NavigationLink`.

The menu has no privacy check (`Features/Library/WorkCardActions.swift:337-341` and `:415-417`):

```swift
content
    .contextMenu {
        NavigationLink(value: LocalWorkDestination.reader(work)) {
            Label("Read", systemImage: "book")
        }
        ...
        NavigationLink(value: LocalWorkDestination.detail(work)) {
            Label("Work Details", systemImage: "info.circle")
        }
```

`SensitiveWorkCoverCard` reveals on its own tap only (`Features/Privacy/MatureContent.swift:312-316`), and only when Blur is on and the work is not yet revealed (`:267-268`). Hide mode is filtered earlier by `passesPrivacy`. Blur mode still puts the card on the carousel.

**Failing case.** Hide Mature Content is on, mode Blur, and the work is not revealed. On Home, long-press a blurred card in Continue Reading, a local carousel, or the resume hero. Tap Read. The reader opens. Tap Work Details. The title, summary, and tags open. Neither action calls `PrivacyGate.reveal`, so a required Face ID check (`MatureContent.swift:67-77`) is skipped. What should happen: those actions stay unavailable until the work has been revealed the same way a tap on the blurred card reveals it.

**Smallest fix.** Attach `localWorkContextMenu` only when the work is not currently blurred, and do not wrap a blurred card in `NavigationLink` to the reader. `HomeResumeHero`'s tap path already reveals instead of navigating; the menu on that hero needs the same gate.

## A19-7 Placeholder account name strands the comment draft

`Features/Comments/CommentsModel.swift:19-35`

```swift
let knownUsername = username.flatMap {
    !$0.isEmpty && $0.caseInsensitiveCompare("AO3 Account") != .orderedSame
        ? $0 : nil
}
let identity = knownUsername
    ?? (auth.isLoggedIn ? "unknown-session:\(auth.sessionGeneration)" : "")
```

The draft key is `"\(identity)|w\(workID)-c\(chapterID ?? 0)-p\(parentID ?? 0)"` (`Services/CommentSubmission.swift:354-356`). An offline Keychain restore whose saved username is empty signs in as `"AO3 Account"` (`Services/AO3AuthService.swift:982-987`). A later Verify Session bumps `sessionGeneration` (`:664-667`) and `finishAccepting` sets `status = .signedIn(username: session.username)` (`:909`). `CommentsView` watches `"\(sessionGeneration)|\(isLoggedIn)|\(username)"` (`Features/Comments/CommentsView.swift:101-103` and `:203-211`) and calls `syncAuthenticationContext`, which saves under the old identity and then clears the composer (`CommentsModel.swift:232-259`). The next `startComposer` loads `drafts.draft(for:identity:)` for the new identity (`:978`). Nothing else in the app reads an `unknown-session:` key.

**Failing case.** Launch offline with a Keychain session whose username is empty. Status is signed in as AO3 Account. Open a work's comments and type a reply. The draft is stored under `unknown-session:<generation>|w…`. Come online and tap Verify Session. The generation increments and the real username arrives. Reopen the composer. It is empty. The typed text is still in UserDefaults under the old key. What should happen: that draft opens under the username Verify Session just confirmed.

**Smallest fix.** In `syncAuthenticationContext`, when the old identity has the prefix `unknown-session:` and the new identity is a real username, rewrite those draft entries to the new identity before swapping `authContext`.

## A19-8 Select mode reads the blurred title to VoiceOver

`Features/Privacy/MatureContent.swift:176-189` (`SensitiveWorkRow`) and `:307-311` (`SensitiveWorkCoverCard`):

```swift
if isSelecting {
    Button { onToggleSelection?() } label: { content }
    .buttonStyle(.plain)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(work.title)
```

The non-select branch of the same row uses `"Hidden mature work. Activate to reveal."` (`:198`). `HomeResumeHero` uses `"Hidden mature work"` while selecting (`Features/Home/HomeResumeHero.swift:48-49`). Search passes `isSelecting` into `SensitiveWorkRow` (`SearchLocalResultsList.swift:44-49`). Home's select mode uses `SensitiveWorkCoverCard` (`HomeView.swift:487-494`).

**Failing case.** Blur mode, mature work not revealed, Select turned on. VoiceOver focuses the blurred Search row or Home cover and speaks `work.title`. The row is still visually blurred. What should happen: the same "Hidden mature work" label the non-select branch and the resume hero already use.

**Smallest fix.** Replace both `.accessibilityLabel(work.title)` calls on the blurred selecting branches with that hidden label. Keep the selected / not-selected value.

## A19-9 Availability list shows mature titles

`Features/Account/AvailabilitySweepView.swift:64-77` and `:191-193`

```swift
ForEach(unavailableWorks) { work in
    NavigationLink(value: work) {
        VStack(alignment: .leading, spacing: 2) {
            Text(work.title)
            Text(work.author)
        }
    }
}
...
unavailableWorks = works
    .filter { $0.ao3Unavailable && !$0.isPendingDeletion }
    .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
```

No `PrivacyGate` check. The sweep log line is counts only (`Services/WorkAvailabilitySweep.swift:139`).

**Failing case.** Hide or Blur is on, and a Mature saved work has `ao3Unavailable`. Account, Check Availability. "No longer on AO3" shows that title and author, and the link opens Work Detail. What should happen: the row is omitted in Hide, and blurred in Blur, until Show mature.

**Smallest fix.** Filter with `isHidden` in Hide, and draw the row through `SensitiveWorkRow` in Blur.

## A19-10 Import failure logs the file name in the clear

`Utilities/Logging.swift:8-10` says interpolated user content, work titles included, stays at the default redaction, and that `privacy: .public` is for technical values. `Services/ExternalFileImport.swift:58-60` and `:89-91` mark the file name public:

```swift
let fileName = url.lastPathComponent
let reason = error.localizedDescription
Log.library.error("Opening \(fileName, privacy: .public) failed: \(reason, privacy: .public)")
```

**Failing case.** Open With a file whose name is the work's title. Detection or import throws. Console shows that file name. Work-title interpolations in `WorkImporter` leave the default redaction (`Services/WorkImporter.swift:64`, `:66`, `:114`, `:298`). What should happen: the file name stays redacted the same way.

**Smallest fix.** Drop `privacy: .public` on `fileName` at both call sites.

## Unconfirmed

- `javascript:` and custom-scheme addresses in the address bar. `loadFromAddressBar` will call `WKWebView.load` for any URL that has a scheme (`WebBrowser.swift:279-280`). This audit did not confirm that `load` runs a `javascript:` URL, or that an unknown scheme is handed to another app. There is no navigation-action delegate that calls `UIApplication.shared.open`. Confirm on a debug build: submit `javascript:document.title='owned'` and a custom scheme, and see whether the script runs or another app opens. A19-1's fix still cancels those schemes.
- Whether a tap on the Home carousel follows the outer `NavigationLink` (`HomeView.swift:497`) past `SensitiveWorkCoverCard`'s reveal gesture (`MatureContent.swift:314`). The context-menu path in A19-6 does not depend on which gesture wins.
- `WorkAvailabilitySweep.run`'s default `verify` force-unwraps `$0.modelContext` (`Services/WorkAvailabilitySweep.swift:90`). A fetched, inserted work has a context. Confirm by deleting that work on another screen during the 1.5s gap and seeing whether the unwrap or a later SwiftData access traps.
- `AO3AccountWorksList.load` (`Features/Bookmarks/AO3AccountWorksList.swift:922-1033`) checks `sessionGeneration` after the await and its pager disables arrows while loading. This pass did not find a sort or refresh overlap that still applies a stale page, so nothing is filed there. `AO3CollectionsList.load` bumps `loadGeneration` before the fetch (`Features/Account/AO3CollectionsList.swift:450-458`); the lines after the fetch were not read far enough to claim the generation is ignored.
- Reopening a browser `Bookmark`. `BrowseView.bookmarkCurrentPage` inserts whatever URL is loaded (`BrowseView.swift:143-147`). The view that later opens that SwiftData row was not found. If it calls `AppRouter.open`, the host gate applies. If it calls `BrowserModel.load`, A19-1 covers it only while that load exists.

## What was not read

End to end: `docs/REDESIGN_DECISIONS.md`, `docs/AO3_NETWORKING_POLICY.md`, and most of `TASKS.md` (the demo, browser-gate, and bookmark-blur notes that a search hit were used). Most of `Features/WorkDetail/` past the refresh and bookmark entry points, the author moderation screens past `AO3AuthorProfileService.submitScrapedHTMLForm`, Onboarding, Support, and the Settings forms. Comment thread layout, the filter panel's draft fields, saved-search persistence, tag pickers, and the native fandom index. Login UI past the coordinator's navigation delegate. The rest of `AO3CollectionsList.load` after the fetch starts. Reader web policy was seen only as the contrast for the missing browser action policy (`Features/Reader/ReaderController.swift:188`); the reader itself is A12's scope. Test bodies other than `DemoNetworkBlockTests`. Android sources were not re-audited.
