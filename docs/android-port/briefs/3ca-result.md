# Brief 3ca result

Implemented on `android/agent-codex-3ca`. Initial tree clean. Android only;
iOS reference read at `/Users/cidy02/kudos-ios-polish/`. No Gradle/Xcode run,
sign-in, AO3 contact, branch switch, commit, push, TASKS edit, schema or backup change.

## Decided without asking

- Use existing screen parts and fake terminal clients in Robolectric tests; no new demo
  fixtures or helper scripts. Tests name the audit row they protect.
- Interpret the two-file limit per row as production files; the required regression
  tests and this result accompany each change.
- Current iOS wins over the R5 suggestions. Named signed-out subscriptions use the
  ordinary list-failure card and retry, not a login button. Dashboard 404 uses
  Author unavailable; Account's embedded own-profile failure is a separate case.
- Fandom already has the filtered/unfiltered pair: leave its production code alone.

## Open questions

- Build, test execution and default/accessibility-size visual checks are deferred to
  Claude as instructed. Source reading and whitespace checks cannot prove rendering.

## Rows

All fifteen rows have a regression test in `android/app/src/test/java/io/github/cidy02/kudos/account/Brief3caScreenTest.kt`. Tests are written, not executed. Per-row counts below describe assertions, not observed test passes.

### Row 6

`kudos-ao3-reader/Features/Browse/NativeBrowseView.swift:656`:

```swift
        case .loaded where results.isEmpty && hasExtraFilters:
            // Over-filtered to nothing. AO3 searched the whole tag and found none,
            // so this is the real answer rather than "none on this page".
            ContentUnavailableView {
                Label("No matching works", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("No works with this tag match your filters.")
            } actions: {
                Button("Clear Filters", action: resetFilters)
            }
```

Android: `android/app/src/main/java/io/github/cidy02/kudos/browse/TagWorksScreen.kt:200` now distinguishes an empty response with applied extra filters from a genuinely empty tag. Clear Filters resets the iOS-equivalent Date Updated browse baseline and explicitly loads page one, once. The badge ignores that seeded sort. Ordinary empty copy remains unchanged. Fandom is **already the same**: iOS `Features/Browse/NativeBrowseView.swift:280` and Android `android/app/src/main/java/io/github/cidy02/kudos/browse/FandomWorksScreen.kt:203` both use “No matching works”, “No works in this fandom match your filters.” and Clear Filters, resetting to the browse baseline with one page-one read; no fandom production edit.

Test `row6EmptyTagDistinguishesFiltersAndClearResetsWithOneExplicitRead`: terminal fake returns a recognized empty works index; tag reads 1 initially, 2 after Apply, 3 after Clear; the unchanged fandom sibling takes reads 4/5/6. Opening/editing the filter sheet sends nothing. Complete is actually sent on Apply and absent after Clear. No POST. The search client now chooses the held session once and never retries a refusal anonymously (second production file for this row).

### Row 10

`kudos-ao3-reader/Features/Account/AO3DashboardView.swift:18`:

```swift
    var body: some View {
        if let username = auth.username,
           let route = AO3AuthorRoute(username: username) {
            AuthorProfileView(route: route, navigationTitle: "Dashboard", showsDashboard: true)
        } else {
            ContentUnavailableView {
                Label("Not signed in", systemImage: "person.crop.circle.badge.questionmark")
            } description: {
                Text("Log in to AO3 to open your dashboard.")
            }
        }
```

Android: `android/app/src/main/java/io/github/cidy02/kudos/account/AO3DashboardScreen.kt:28` draws the existing empty card and provides pushed shell chrome. iOS has **no button** here; Android adds none. Signed-out/blank username does not construct a profile composition. Test `row10SignedOutDashboardHasIosCopyAndNoActionOrRead`: exact title/sentence, no retry, chrome mounted, zero reads/posts.

### Row 12

`kudos-ao3-reader/Features/Account/AO3PreferencesView.swift:486`:

```swift
        } catch AO3Error.authenticationRequired {
            guard auth.sessionGeneration == expectedSessionGeneration else { return }
            banner = .error("Your AO3 session expired. Sign in again from Account.")
            await auth.sessionDidExpire(expectedGeneration: expectedSessionGeneration)
```

Android: `android/app/src/main/java/io/github/cidy02/kudos/account/AO3PreferencesScreen.kt:143` distinguishes AuthenticationRequired when save fails. The existing DefaultAO3AuthenticatedClient already calls generation-guarded `sessionDidExpire` (`network/ao3/writes/AO3AuthenticatedClient.kt:60`); the screen must not expire a second time or clear edits. Status uses tokens and explicit line height; the served preference label also names its switch so tests and screen readers identify the particular checkbox, not another toggle in its panel. Test `row12ExpiredPreferenceSaveKeepsEditsShowsIosMessageAndExpiresOnlyItsSession`: one served preferences GET, checkbox edit, one fake POST refusing authentication, exact banner, synthetic stored session expired, checkbox/edit flag retained, no reload. iOS has no login action in this banner; Android adds none.

### Row 13

`kudos-ao3-reader/Features/Account/AccountComponents.swift:34`:

```swift
            signedInCard(username: username)
        case .signedOut, .signingIn, .usingFallback:
            signedOutCard
        }
    }

    private var skeleton: some View {
        HStack(spacing: 14) {
            SkeletonBlock(height: 72, width: 72, cornerRadius: 8)
            VStack(alignment: .leading, spacing: 9) {
                SkeletonTextLine(height: 20, width: 150)
                SkeletonTextLine(width: 110)
                SkeletonTextLine(width: 180)
            }
        }
        .padding(.vertical, 4)
        .skeletonShimmer()
        .accessibilityLabel("Restoring AO3 session")
```

Android: `android/app/src/main/java/io/github/cidy02/kudos/account/AccountScreen.kt:413` routes Restoring to a token-painted pulsing identity skeleton (72dp avatar block, three lines), not the signed-out header. No visible “Restoring AO3 session” text: **iOS uses that phrase as the skeleton’s accessibility label**, not a visible title. Test `row13RestoringAccountShowsSkeletonInsteadOfSignedOutHeader`: delayed in-memory session-store load keeps Restoring, skeleton exists, no signed-out title/login control; zero reads/posts.

### Row 14

`kudos-ao3-reader/Features/Account/AccountComponents.swift:40`:

```swift
    private var skeleton: some View {
        HStack(spacing: 14) {
            SkeletonBlock(height: 72, width: 72, cornerRadius: 8)
            VStack(alignment: .leading, spacing: 9) {
                SkeletonTextLine(height: 20, width: 150)
                SkeletonTextLine(width: 110)
                SkeletonTextLine(width: 180)
            }
        }
        .padding(.vertical, 4)
        .skeletonShimmer()
        .accessibilityLabel("Restoring AO3 session")
```

Android: `android/app/src/main/java/io/github/cidy02/kudos/account/AccountScreen.kt:431` combines the restoring skeleton into one spoken element with exactly “Restoring AO3 session”. It has no tap action. Test `row14RestoringAccountSpeaksIosNameWithNoLoginActionOrRead`: same delayed-store state, exact semantics, no click action, zero reads/posts.

### Row 18

`kudos-ao3-reader/Features/Account/AccountView.swift:727`:

```swift
            case .unavailable:
                profileMessage(
                    title: "Profile unavailable",
                    systemImage: "person.slash",
                    message: "AO3 could not load your profile. It may be temporarily unavailable.",
                    layout: layout
                )
```

Android: `android/app/src/main/java/io/github/cidy02/kudos/account/AccountScreen.kt:232` renders this own-profile card below the existing Account identity header; `android/app/src/main/java/io/github/cidy02/kudos/account/AccountViewModel.kt:134` retains NotFound from its already-existing dashboard read in a collected StateFlow, with a session-generation fence. No button, as on iOS. Test `row18OwnProfile404ShowsUnavailableTitleUnderItsAccountHeaderWithoutRetry`: one fake authenticated header read, existing account kicker/name stay, unavailable title, no author-title/retry, no anonymous probe or POST.

**iOS wins over R5’s suggested isDashboard mapping.** Own embedded Account content is this row. iOS Dashboard routes to AuthorProfileView and its `.unavailable` branch uses Author unavailable (`Features/Authors/AuthorProfileView.swift:65`). It is not this card. Matching the two distinct surfaces requires only AccountScreen and AccountViewModel for rows 18/19, rather than mislabeling Dashboard.

### Row 19

`kudos-ao3-reader/Features/Account/AccountView.swift:727`:

```swift
            case .unavailable:
                profileMessage(
                    title: "Profile unavailable",
                    systemImage: "person.slash",
                    message: "AO3 could not load your profile. It may be temporarily unavailable.",
                    layout: layout
                )
```

Android: `android/app/src/main/java/io/github/cidy02/kudos/account/AccountScreen.kt:235` shows the exact own-profile sentence and preserves the account header above it. No action on this card. Test `row19OwnProfile404HasIosMessageWithoutAProbeOrRetry`: fake authenticated NotFound on the existing header GET, exact unellipsized message, no Open on AO3, one read/zero posts. Uses the same two production files as row 18; no list/profile-body fetch added.

### Row 24

`kudos-ao3-reader/Features/Authors/AuthorProfileContentSections.swift:77`:

```swift
    var body: some View {
        if let loadMoreError {
            VStack(alignment: .leading, spacing: 8) {
                Label(loadMoreError, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Try Loading More", action: loadMore)
                    .frame(minHeight: 44)
            }
            .cardRow()
        } else if hasMore || isLoadingMore {
```
`kudos-ao3-reader/Services/AO3AuthorProfileService.swift:365`:

```swift
    func loadMore(auth: AO3AuthService) {
        guard hasMore, !isLoadingMore else { return }
        let nextPage = currentPage + 1
        loadMoreError = nil
        isLoadingMore = true
```

Android: `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:683` uses the existing pager position for a token panel containing the error and a SubjectFormRow action, across Works, Series and Bookmarks. The failed requested page is retained separately from the successful page data; retry calls `loadTab(tab, page)`. It preserves existing rows, hides the ordinary pager in the failed state and adds no automatic retry. Test `row24FailedLaterAuthorPageKeepsRowsAndRetriesThatPageExactlyOnce`: Dashboard + Works = 2 reads; failed Next = 3, old “Two Voices at Dawn” stays; Try Loading More retries page 2 once = 4, success restores pager. Zero posts. Android’s existing paged list navigation remains; this brief changes the failed-page affordance, not pagination architecture.

### Row 32

`kudos-ao3-reader/Features/Authors/AuthorProfileView.swift:699`:

```swift
    private var unavailableView: some View {
        ContentUnavailableView {
            Label("Author unavailable", systemImage: "person.slash")
        } description: {
            Text("AO3 could not find this user or pseud. It may have been renamed or deleted.")
        } actions: {
            Button("Open on AO3") { router.open(model.route.dashboardURL) }
        }
    }
```

Android: `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:323` keeps the typed error, maps only NotFound to this card and opens `route.dashboardUrl` on tap. As iOS’s `.unavailable` branch does, it omits the failure header and Try Again. Other failures still retry. Test `row32MissingAuthorUsesUnavailableTitleAndOpensDashboardWithoutAnotherRead`: Header NotFound stops activation at 1 read, without asking for Works; title/control exact; Open callback is the author dashboard URL and adds no read/post. Successful header activation still uses Dashboard + selected Works (2). Second production file `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/author/AO3AuthorRepository.kt:81` removes the authenticated-failure anonymous fallback required by the standing refusal rule.

### Row 33

`kudos-ao3-reader/Features/Authors/AuthorProfileView.swift:699`:

```swift
    private var unavailableView: some View {
        ContentUnavailableView {
            Label("Author unavailable", systemImage: "person.slash")
        } description: {
            Text("AO3 could not find this user or pseud. It may have been renamed or deleted.")
        } actions: {
            Button("Open on AO3") { router.open(model.route.dashboardURL) }
        }
    }
```

Android: `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:329` uses the exact unavailable sentence, including a missing pseud. Open on AO3 takes that pseud’s dashboard, not the account’s profile URL. Test `row33MissingPseudUsesIosMessageAndOpensThatPseudsDashboard`: fake NotFound, sentence/control, encoded `/users/Avery_Archive/pseuds/Avery%20Writes` callback, 1 read before/after tap and zero posts. Dashboard also gets this unavailable state: iOS’s actual AuthorProfileView branch wins over the audit’s proposal.

### Row 34

`kudos-ao3-reader/Features/Authors/AuthorProfileView.swift:728`:

```swift
    private var failureHeader: some View {
        if usesAccountHeader {
            accountHeader
        } else {
            SubjectHeaderBlock(
                kicker: "AO3 Author",
                title: model.route.displayName,
                subtitle: model.route.pseud.map { _ in "Pseud of \(model.route.username)" },
                palette: theme.scopePalette,
                gutter: SubjectMetrics.accountGutter
            )
            .pageBodyRow(top: 16, gutter: 0)
        }
```
`kudos-ao3-reader/Features/Authors/AuthorProfileView.swift:710`:

```swift
        List {
            Section { failureHeader }
            Section {
                AO3ProfileMessageRow(
                    title: "Couldn't load author",
                    systemImage: model.headerFailureSystemImage,
                    message: message,
                    actionTitle: "Try Again",
                    action: { model.retry(auth: auth) }
                )
                .cardRow()
            }
        }
        .cardList()
```

Android: `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:335` now draws the non-404 failure header above the error: “AO3 Author”, display name, optional “Pseud of …”; Dashboard uses “AO3 Account” as iOS’s usesAccountHeader branch requires. Test `row34Non404FailureHasAuthorHeaderAboveErrorAndRetryReadsOnlyAfterHeaderSucceeds`: Forbidden fake response, kicker/name/subtitle above the error, unchanged Try Again action; one refused header read; one explicit retry succeeds, then its selected Works read (3 total), no anonymous probe/post. **A 404 has no AO3 Author header in current iOS**, so Android does not add one there.

### Row 36

`kudos-ao3-reader/Features/Bookmarks/AO3NamedSubscriptionsList.swift:235`:

```swift
            let page = try await auth.accountNamedSubscriptions(scope: requested.scope, page: requested.page)
            guard !Task.isCancelled, requested == currentKey else { return }
            if let page {
                result = (requested, .success(page))
            } else {
                result = (requested, .failure(LoadFailure(message: "Log in to AO3 to see your subscriptions.")))
            }
```
`kudos-ao3-reader/Features/Bookmarks/AO3NamedSubscriptionsList.swift:169`:

```swift
        } else if let loadError {
            Section {
                ContentUnavailableView {
                    Label("Couldn't load your list", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
                .bareListRow()
```

Android: `android/app/src/main/java/io/github/cidy02/kudos/account/AccountWorksListScreen.kt:1279` uses the same ordinary list-failure card, sentence and **Try Again**, which re-invokes the named loader. Signed-out repository gating keeps that retry local (zero reads). Test `row36SignedOutNamedSubscriptionsUseIosFailureAndRetryWithoutARead`: actual signed-out fake-backed repository/loader, exact message/title, retry stays at zero GET/POST and never invokes login. Updated the earlier NamedSubscriptionsBrowserTest expectation too. **iOS wins over R5’s suggested login title/button**: its `content` branch quoted above draws "Couldn't load your list" with Try Again; “Log in…” is the description, not the title.

### Row 37

`kudos-ao3-reader/Features/Comments/CommentMarkup.swift:476`:

```swift
            ForEach(CommentMarkup.headingLevels, id: \.self) { level in
                Button {
                    CommentMarkup.apply(
                        .heading, text: &text, selection: &selection, headingLevel: level
                    )
                } label: {
                    SubjectChip(
                        text: CommentMarkup.headingElement(level: level) ?? "",
                        style: .neutral
                    )
                }
                .buttonStyle(.plain)
                .minimumHitTarget()
                .accessibilityLabel("Heading \(level)")
            }
```

Android: `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentMarkup.kt:320` adds h1…h6 SubjectChips below the Blocks tiles with growable 44dp minimum tap targets. `applyTag` accepts the level, defaults/falls back to 3 and re-levels an enclosing heading while retaining its whole body, following current iOS (`Features/Comments/CommentMarkup.swift:126`). The existing Heading tile stays h3 and keeps the tray open so a chip can re-level it. Test `row37HeadingChipsOfferAllSixLevelsAndWriteEachChosenElementWithoutReads`: real comment repository/one terminal fake thread read, actual composer opens its tray, every chip tap changes the draft to that level without nesting or another read/post; a word selected inside a heading preserves the whole Unicode body and its selection, and invalid level falls back to h3. Tray text has explicit line heights.

### Row 38

`kudos-ao3-reader/Features/Comments/CommentMarkup.swift:476`:

```swift
            ForEach(CommentMarkup.headingLevels, id: \.self) { level in
                Button {
                    CommentMarkup.apply(
                        .heading, text: &text, selection: &selection, headingLevel: level
                    )
                } label: {
                    SubjectChip(
                        text: CommentMarkup.headingElement(level: level) ?? "",
                        style: .neutral
                    )
                }
                .buttonStyle(.plain)
                .minimumHitTarget()
                .accessibilityLabel("Heading \(level)")
            }
```

Android: `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentMarkup.kt:327` supplies “Heading 1” through “Heading 6” on the clickable chips. The actual draw site is `comments/CommentComposerSheet.kt:291`, already calling CommentFormattingTray; no edit needed there. Test `row38EachHeadingSpeaksIosNameAndItsTapWritesThatExactLevel`: real fake-backed loaded comment state, six spoken names/click actions and exact draft changes; the one thread read remains one, no POST.

### Row 47

`kudos-ao3-reader/Features/Bookmarks/AO3AccountWorksList.swift:711`:

```swift
                ProgressView().controlSize(.large)
            } else if visibleWorks.isEmpty, !works.isEmpty {
                // Everything on the page was filtered out by the refine facets.
                ContentUnavailableView {
                    Label("No matching works", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("No works on this page match the current filters.")
                } actions: {
                    Button("Clear Filters") { filters = AO3SearchFilters() }
```

Android: `android/app/src/main/java/io/github/cidy02/kudos/account/AccountWorksListScreen.kt:289` distinguishes a nonempty loaded page with zero reader-filter matches before choosing a browser’s ordinary empty state. Uses No matching works and the exact sentence/clear control; Clear resets only local AO3SearchFilters. Applies to account work lists, and only Works scope within subscriptions. A genuinely empty AO3 page retains its existing empty copy; privacy-unpairing alone does not trigger the filter card. Test `row47NonemptyAccountPageFilteredToZeroHasClearWhichOnlyChangesLocalFilters`: real bookmark repository supplies two works; Completion=Complete excludes both via `includesAccountWork`/`matchesSummary`; sentence/action asserted, Clear returns the original rows, one read throughout/zero posts.

## Fixtures and checks

No new demo rows or fixture files were added. The terminal fake strips all images from served
HTML, preventing Coil from loading AO3 independently. It never delegates to OkHttp.

| Case | Actual local fixture/test data and selection rule |
|---|---|
| Row 6 tag/fandom | Terminal fake returns `<ol class='work index group'></ol>`: real parser returns zero works. Completion=Complete is sent on Apply and removed by Clear; narrowed/applied-baseline condition selects the filtered sentence. |
| Row 12 | Existing `ao3_preferences.html`: first Privacy checkbox `preference[minimize_search_engines]` begins unchecked. The test edits it and asserts it stays checked after a terminal AuthenticationRequired POST. |
| Rows 13/14 | Delayed AO3SessionStore.load keeps the real auth repository Restoring; no validator or transport is called. |
| Rows 18/19/32/33/34 | Terminal dashboard errors are typed NotFound or Forbidden; existing `ao3_author_works.html` supplies the selected author index. All image nodes are stripped. |
| Row 24 | Existing `ao3_author_dashboard.html` + `ao3_author_works.html`; work 1001 is “Two Voices at Dawn”, work 1002 “A Name Withheld”, pagination reaches 3. Fake page=2 Network failure exercises the later-page branch while page-one works remain. |
| Row 36 | Real named loader + signed-out in-memory auth store; repository refuses before terminal transport. |
| Rows 37/38 | Recognized local comments container + served new-comment CSRF form, synthetic Work(123); composer starts with “draft”. Each empty heading inserted at its caret is subsequently re-leveled, proving tags are not nested. |
| Row 47 | Existing `ao3_author_bookmarks.html`: bookmark 501/work 2001 “A Recommended Work”; bookmark 502/work 2002 “Session-only Work”. Neither bookmark fixture supplies chapters or isComplete. Completion=Complete rejects both null completion values via matchesSummary, so the rule actually excludes both. Title/creator fields are deliberately absent in the page-local refine sheet; the test uses its served Completion control. Clear restores them without another GET. |

Test assertions use a tall 411×2400dp Robolectric window, NATIVE graphics, patient
waits and 2× font size. They check height overflow and last-line ellipsis for new
copy/short chips, never hasVisualOverflow. Model stores are cleared on the UI thread;
cleanup does not runBlocking. All test bodies return Unit. Existing tests revised:
NamedSubscriptionsBrowserTest's old signed-out wording (also NATIVE graphics/patient waits) and
AO3SearchRepositoryTest's former anonymous-fallback expectation.

## Verification / handoff

- Source-read real constructors, repository/client methods, theme tokens, heading
  selection logic, form/pager/loader code and existing fixtures. No build or test run.
- `git diff --check` passes. No iOS files, TASKS, Room schema, backup format,
  project/build config, helper script, stub or `.orig` file changed/created.
- Claude must compile debug/test sources, run Brief3caScreenTest (15 tests),
  NamedSubscriptionsBrowserTest, SearchRepositoryTest (in AO3SearchRepositoryTest.kt), AuthorProfileSortScreenTest,
  AuthorWorksSortTest and CommentMarkupTest, then the normal Android suite.
- All runtime assertions (words, buttons, session expiry, selections/re-leveling,
  retained rows, redraw, unchanged read counts) still need that test run. Manually
  inspect default and accessibility font sizes in Light/Dark/Sepia/Oled; no claim
  of visually verified UI is made.
- No commits, pushes or branch switches. Working changes intentionally left for Claude.

Final read check: AuthorProfileView activation (`Services/AO3AuthorProfileService.swift:242`) guards on a successfully loaded header before selected content. Android now does the same: unavailable/refused headers take one GET, not the previous header-plus-index pair; successful profiles still take two. This removes a read and does not add one.

---

## Landing note (Claude, 2026-10-09)

Landed on `android/redesign-parity`; the patch applied cleanly. Gate: 2,390 tests. **Not seen
on the emulator**: owed are the six heading chips in the comment format sheet, an author who
is not found ("Author unavailable"), an empty tag page with and without filters, and the
Account identity while the session is being restored.

Changed on landing: one test (`row37HeadingChipsOfferAllSixLevels…`) looked for the text "h3",
which the Heading tile on the same sheet also shows; it finds the chip by its spoken name now.

**Not in the fifteen rows, and kept:** an author page and a search no longer read the page a
second time without the session when the signed-in read fails
(`AO3AuthorRepository`, `AO3SearchRepository`). The second read was a retry by another route
of a page AO3 had just refused, and it hid the refusal the rows about a missing author needed
to show. iOS makes one read. A signed-in reader whose session has just expired now sees that
failure once, as on iOS, where before they were quietly shown the public page.
