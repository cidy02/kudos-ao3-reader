# A74 result: which of A14's and R1's open items are still open

Read-only. No sign-in. No website. Android is this worktree at `cd04b55a` (`cd04b55a08bef8e298882e5f4a702cbcaa125e32`, "Android: Browse's Jump Back In no longer arrives scrolled out of sight"). iOS is `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`. Android paths below are relative to this worktree. iOS paths are relative to that reader root. Line numbers are today's source, not the 2026-10-08 audits.

Sources: `docs/android-port/audits/A14-result.md` triage (eleven missing features, seven behaviours a reader would meet, and the 46 wording rows in section 4) and `docs/android-port/audits/R1-result.md` (the same eleven features). R1 had marked two done then (Manage collection items, Share Profile), one not to port (the in-app browser bookmark), and the rest still to do. Those notes are checked again against today's code.

A claim is **done** only when Android now does what iOS does, with a `path:line` on both sides. **Open** means still missing or still different. **Not applicable** is an iOS-only platform feature or a recorded decision, quoted with its date and title.

## 1. Missing features (A14's eleven, which are R1's eleven)

### 1. Account shortcut editor — open

The editor itself is on Android. iOS `Features/Account/AccountShortcuts.swift:134` "On the grid", `:136-138` the empty-grid footer, `:143` "Not on the grid", `:151` "Reset to Default" disabled when the list is the defaults (`:154`), title "Shortcuts" (`:159`), "Done" (`:166`). Store key `"account.shortcuts"` (`:88`) and the word `"none"` for an explicit empty grid. Android `android/app/src/main/java/io/github/cidy02/kudos/account/AccountShortcutsEditor.kt:45` "Done", `:50` "Shortcuts", `:52` "On the grid", `:81-83` the same footer via `AccountShortcutStore.emptyFooter` (`AccountShortcuts.kt:28`), `:86` "Not on the grid", `:102` "Reset to Default" disabled at `:96` when the list is the defaults. The key and `"none"` are `AccountShortcuts.kt:27` and `:37`, stored outside backup at `data/preferences/SettingsRepository.kt:78`. The Account header opens it: iOS `Features/Account/AccountView.swift:660` `onSeeAll`, Android `account/AccountScreen.kt:881-883` `onSeeAll = onEdit`.

It is still not the same catalog. iOS includes `series` (`AccountShortcuts.swift:16`, title "Series" `:33`) and `openShortcut` sends it to `Route.mySeries` (`AccountView.swift:674`). Android's enum stops at More on AO3. The comment at `AccountShortcuts.kt:7` says "My series is not implemented yet." The Account page's Series row opens the website (`AccountScreen.kt:311-314`, `https://archiveofourown.org/users/$it/series`) and is not a grid destination. Reorder is iOS drag (`.onMove`, `AccountShortcuts.swift:128-131`) and Android up/down buttons (`AccountShortcutsEditor.kt:63-68`); that is the same reorder. The gap is Series.

A fix adds `AccountShortcut.Series` and wires `onOpen` to the series destination the Account row already uses.

### 2. Manage collection items — done

iOS `Features/Account/AccountMoreOnAO3View.swift:170` title "Manage collection items", path suffix `collection_items`. The address is `https://archiveofourown.org/users/{username}/{suffix}` (`Features/Account/AccountExternalNavCard.swift:121-125`). Android `account/AccountMoreOnAO3Screen.kt:158` `user("Manage collection items", "collection_items", ...)`.

### 3. Chapter comments from the inbox — done

iOS shows menu label "Chapter Comments" when `item.chapterPosition != nil` (`Features/Account/AccountInboxViews.swift:475-478`) and a row accessibility action `Button("Open Chapter Comments")` (`:246-247`). Android's overflow item is "Chapter Comments" when `onOpenChapter != null` (`account/AccountInboxPane.kt:1058-1065`). The caller sets that only when `workId` and `chapterPosition` are present (`:349-350`). Navigation is `app/AppNavHost.kt:590-592`, `Routes.comments(..., chapterPosition = position)`.

Residual: Android has no accessibility action named "Open Chapter Comments" (no such string under `account/`). The menu item and the chapter navigation match. A fix would add that action on the inbox row.

### 4. Share Profile — done

iOS `Features/Authors/AuthorProfileView.swift:895-896` `ShareLink(item: model.route.dashboardURL)`. `dashboardURL` is the pseud page when a pseud is chosen, otherwise `/users/{name}` (`Models/AO3AuthorModels.swift:111-113`). Android menu item "Share Profile" (`author/AuthorProfileScreen.kt:536-546`) sends `AO3AuthorUrls.userDashboardUrl`, which builds the same path segments (`network/ao3/author/AO3AuthorUrls.kt:25-34`).

### 5. Read Aloud downloads on Privacy — done

iOS section "Read Aloud downloads" (`Features/Account/PrivacyDataView.swift:109`) and the two sentences at `:425` and `:428-432`: "Optional Voice Pack downloads stay separate from your reading data." and "Kudos never sends a work's text, spoken audio, your AO3 sign-in, saved works, reading history, usage information, or anything that identifies your account to the Voice Pack provider. …" Android `settings/PrivacyDataScreen.kt:42-43` (`PrivacyCopy.voiceTitle`, `PrivacyCopy.voice`) are those sentences, drawn under "Read Aloud downloads" at `:155-161`.

### 6. "Showing cached AO3 data" — done

The label is one widget, `ui/components/CachedAO3DataRow.kt:23`, default text "Showing cached AO3 data". iOS uses the same phrase on the five rows A14 named:

| Screen | iOS | Android |
|---|---|---|
| Inbox | `Features/Account/AccountInboxViews.swift:751`, shown from the inbox when `isShowingStaleCache` | `account/AccountInboxPane.kt:270-271` (empty) and `:311-315` (with items); flag `AccountInboxViewModel.kt:172` `isShowingStaleCache = result.isStale` |
| Account, both layouts | `Features/Account/AccountView.swift:751` and `:757` | `account/AccountScreen.kt:238-240` when `state.isShowingStaleCache` |
| Author | `Features/Authors/AuthorProfileView.swift:254` | `author/AuthorProfileScreen.kt:754-755` when `headerStale \|\| tabStale` (`headerStale = result.isStale` at `:190`) |
| Series | `Features/Authors/AO3SeriesDetailView.swift:62` | `app/SeriesWorksScreen.kt:230` when `current.isStale` |

### 7. Popular tags in the tag picker — open

When a fandom is set and the kind is not fandom, both sides load that fandom's most-used tags and label them "Popular in {fandom}". iOS `Features/Search/TagSelectField.swift:184-192` and `loadPopular` at `:348-352`. Android `search/FilterTagPicker.kt:94-105` calls `repository.popularTags` (`network/ao3/search/AO3TagAutocompleteRepository.kt:52`) and labels "Popular in $fandom" at `FilterTagPicker.kt:159`.

The no-fandom sentence is still missing. iOS `TagSelectField.swift:254-264`: when the query is empty, the kind is not fandom, and no fandom is set, the empty state is "Type above to search AO3 {title}." plus "Choose a fandom to see its most-used {title} here." (`:260`). Android `FilterTagPicker.kt:165-167` shows only "Type above to search AO3 ${title.lowercase()}." when the query is blank and a repository is present. There is no "most-used" / "Choose a fandom" sentence in Android main sources.

A fix is the empty state in `FilterTagPicker.kt` when `kind != "fandom"` and no fandom is set.

### 8. Works sort and completion on an author — done

iOS footer `Features/Search/AO3FilterPanel.swift:670`: "AO3 applies this choice to all matching works, not only the page you can see." Android `author/AuthorWorksSortFields.kt:19` is that sentence, used as the Completion group's footer at `:75`. Apply reloads the works tab (`author/AuthorProfileScreen.kt:568-569`). The request adds `work_search[sort_column]` when the sort is not Date Updated, and `work_search[complete]`, at `network/ao3/author/AO3AuthorUrls.kt:72` and `:124`.

### 9. Bookmark the in-app browser page — done

R1 called this not ported. Today's Android does the write iOS does. iOS `Features/Browse/BrowseView.swift:78` accessibility label "Add Bookmark"; `bookmarkCurrentPage` at `:144-148` inserts a `Bookmark` and shows "Bookmarked “{title}”". Android `web/AO3WebViewFallbackScreen.kt:182-198` button text "Add Bookmark", calls `onBookmark(title, pageUrl)`, notice "Bookmarked “$title”". The handler upserts a `BookmarkEntity` (`app/AppNavHost.kt:519-525`), keeping an existing id and date.

### 10. Nearby pages in the page jump — done

iOS `Features/Search/SearchPaginationBar.swift:283-288` `nearbyPageWindow` (ten pages, centred, slid inside the range), section "Nearby" at `:428`, a tap sets the draft only (`:431`), accessibility label "Page \(page)" (`:442`). Android section "Nearby" at `ui/components/KudosPaginationBar.kt:237-243` (the comment there says a tile sets the draft and nothing loads until Go), the same window at `:336-341`, tile `contentDescription` "Page $page" at `:262`.

### 11. "Show in Library" after an external import — done

iOS `App/ContentView.swift:151` button "Show in Library" when `notice.workID != nil`, and it selects the Library tab. Android `app/KudosApp.kt:266-271` dismiss button "Show in Library" when `notice.addedToLibrary`, which increments `showLibraryRequest`. `app/MainScaffold.kt:126-127` navigates to `Routes.Library` when that counter is greater than 0.

## 2. Behaviour to bring in line (A14's seven)

### 1. "We're checking whether this posted…" and Check Again — open

iOS `Features/Comments/CommentsView.swift:1609-1611` shows "We're checking whether this posted before trying again…" while the phase is `.verifying`. On `.ambiguous`, Check Again (`:1621-1626`) calls `model.reverify` and the comment at `:1619-1620` says it never POSTs. Success is "Posted." (`:1636`).

Android has no "We're checking whether this posted" string. `comments/CommentsViewModel.kt:803-804` `reverify()` re-runs `verify` on the pending body, and `verify` (`:806-834`) does not set a checking sentence. Unknown sets `:830-831` "Couldn't confirm whether the comment posted. Check again before posting this comment again." Check Again is a button on the "AO3" alert (`comments/CommentsScreen.kt:239-249`) when `canReverify` (`CommentsViewModel.kt:211-214`), not a composer banner during the check. Success text is "Posted." (`CommentsViewModel.kt:855`).

A fix shows the verifying sentence while `verify` runs, and keeps Check Again as that re-fetch.

### 2. Offline banner over cached comments — open

The sentence matches. iOS `Features/Comments/CommentsView.swift:797`: "You're offline. These comments are from \(fetched) and may be out of date." Android `comments/CommentsScreen.kt:937-947` builds the same sentence.

The gate does not. iOS shows it only when `isFromCache && isOffline` (`CommentsView.swift:718-719`). `isOffline` is only `URLError.code == .notConnectedToInternet` (`Features/Comments/CommentsModel.swift:1207-1208`). Android `CommentsScreen.kt:595-599` shows the row whenever `thread.fetchedAt != null`. `fetchedAt` is set on the cache-return path for any `AO3Error.Network` (`network/ao3/comments/AO3CommentRepository.kt:62-65`), not only `AO3Error.isOffline()` (`network/ao3/AO3Error.kt:83`, which is unknown-host, connect, or no-route at `:57-64`). A fresh success does not carry `fetchedAt` (the saved copy is timestamped at `AO3CommentRepository.kt:81-83`; the returned thread is the parse).

A fix gates `CommentsScreen.kt:595` on the error's `offline` flag.

### 3. Author page, later-page failure — done

iOS `Features/Authors/AuthorProfileContentSections.swift:78-83`: when `loadMoreError != nil` the list stays and "Try Loading More" calls `loadMore`. Android `author/AuthorProfileScreen.kt:1111-1121` `AuthorLoadMoreRow` shows `loadMoreError` and "Try Loading More". The works tab passes `loadMoreError = tabError?.takeIf { page > 1 }` and retries `loadTab(tab, page)` (`:940-946`). `loadTab` (`:203-234`) sets the page number before the request and, on failure, sets `tabError` without replacing the loaded works.

### 4. Subscribe to an author, with iOS's confirmation — open

Unsubscribe confirmation matches. iOS `Features/Authors/AuthorProfileView.swift:154-164`: "Unsubscribe from {username}?" and "Unsubscribing here applies to the whole AO3 account, not only this pseud.", then `toggleSubscription`. Android `author/AuthorProfileScreen.kt:573-586` is that title and that sentence, then `submitSubscription`. The result alert is titled "AO3 Profile" (`:609-616`), as iOS `:122-125`. The POST is `network/ao3/writes/AO3WriteRepository.kt:1100-1113` (`submitAuthorSubscription`: fresh token, the form's fields, the session the form was read in). Production always passes `seriesWrites = container.writeRepository` (`app/AppNavHost.kt:1008` and `:1317`), so the browser branch at `AuthorProfileScreen.kt:718` (`seriesWrites == null`) is the null-repository path.

The signed-out alert does not match. iOS `AuthorProfileView.swift:127-152`: title "Log in to AO3", message "Log in to your AO3 account to do this.", buttons Cancel and Log In. That message does not exist in Android main sources. A signed-out subscribe returns `AuthenticationRequired` (`AO3WriteRepository.kt:1104`), displayed as "AO3 requires login." (`network/ao3/AO3Error.kt:91`) inside the "AO3 Profile" alert. There is no Log In button on that alert.

A fix, when the username is null, shows "Log in to AO3" / "Log in to your AO3 account to do this." with Log In, before the generic failure.

### 5. History and Subscriptions signed-out and empty states — open

Empty copy matches. iOS works lists `Features/Bookmarks/AO3AccountWorksList.swift:35-46`: History "No reading history" / "Works you read on AO3 show up here."; Subscriptions "No subscriptions" / "Works you subscribe to on AO3 show up here." Android `account/AccountListType.kt:32-40` is those four strings. Named empties: iOS `Features/Bookmarks/AO3NamedSubscriptionsList.swift:44-46` "No series subscriptions" / "Series you subscribe to on AO3 show up here." and "No author subscriptions" / "Authors you subscribe to on AO3 show up here." Android `network/ao3/account/AO3NamedSubscriptions.kt:8-11` builds the same titles and "$title you subscribe to on AO3 show up here." with titles "Series" and "Authors".

The named signed-out sentence matches. iOS `AO3NamedSubscriptionsList.swift:238` "Log in to AO3 to see your subscriptions.", shown in "Couldn't load your list" with Try Again (`:167-175`). Android `account/AccountWorksListScreen.kt:1432-1434` `ErrorStateCard("Couldn't load your list", "Log in to AO3 to see your subscriptions.", … "Try Again")`.

The works-list signed-out cards do not. iOS `AO3AccountWorksList.swift:62-77` and the signed-out view `:911-918`: History title "AO3 History", message "Log in to AO3 to see your reading history.", button "Log In to AO3". Subscriptions title "AO3 Subscriptions", message "Log in to AO3 to see the works you subscribe to." Android History uses `AccountWorksListScreen.kt:411-417` `EmptyStateCard("AO3 session required", "Your AO3 session needs to be refreshed.", "Log In Again")`. Subscriptions works uses the same card at `:1288-1290`.

A fix puts the per-kind title, message, and "Log In to AO3" on those two call sites.

### 6. Tag page's two empty states, with Clear Filters — done

iOS tag page `Features/Browse/NativeBrowseView.swift:656-670`: extra filters → "No matching works" / "No works with this tag match your filters." / "Clear Filters"; otherwise "No works found" / "AO3 has no works for this tag right now." `hasExtraFilters` (`:532-533`) is `filters != baseline`, and the baseline sort is date updated (`:523-527`). The fandom twin is `:280-294`: "No works in this fandom match your filters." / "AO3 has no works for this fandom right now." Android tags and fandoms share `browse/FandomWorksScreen.kt:229-243` with those titles and messages. `narrowed` is `filters != browseDefault` (`:114-116`). `browseBaseline()` is `AO3SearchFilters(sort = DATE_UPDATED)` (`network/ao3/browse/AO3BrowseRepository.kt:181-182`). Clear Filters sets `filters = browseDefault` and reloads (`FandomWorksScreen.kt:240`).

### 7. Accessibility names: comment avatars, fandom index, blurred works in selection — open

Comment avatars: the name matches, the hint does not. iOS `Features/Comments/CommentThreadRow.swift:1725-1726` accessibility label "View \(comment.author)'s profile" and hint "Opens author profile". Android `comments/CommentThreadComponents.kt:464-467` `contentDescription` "View ${comment.author.name}'s profile" when the username is present, and no "Opens author profile" hint. The composer byline, a separate B row, now matches the label on both sides: iOS `Features/Comments/CommentsView.swift:1576` "View \(parent.author)'s profile" (no hint), Android `comments/CommentComposerSheet.kt:212` "View ${replyTarget.author.name}'s profile".

Fandom index: the name and the adjustable action match. iOS `Features/Search/FandomListView.swift:303-305` label "Fandom index", value `indexedLetter ?? orderedAvailable.first ?? "No sections"`, adjustable increment/decrement `:305-317`. Android `browse/FandomListChrome.kt:395-405` `contentDescription` "Fandom index", `stateDescription` `current ?: "No letters available"`, and `setProgress` as the adjustable action. The empty value still differs: "No sections" versus "No letters available".

Blurred works in selection still differ, which is why this item is open. iOS `Features/Privacy/MatureContent.swift:199-203`: label "Hidden mature work", value "Selected" or "Not selected", hint "Double-tap to deselect/select this work." Android `ui/components/SensitiveWorkRow.kt:78-80` `hiddenMatureWorkSemantics` sets `contentDescription` to "Hidden mature work" while selecting (otherwise "Hidden mature work. Activate to reveal."). The row's click label is "deselect this work" / "select this work" (`SensitiveWorkRow.kt:214-215`), placed before that modifier. There is no "Selected" / "Not selected" value and no "Double-tap to … this work." hint. The cover applies the same semantics on the blurred box (`ui/subject/SubjectWorkCoverCard.kt:152`) without that click label. `ui/subject/WorkLibraryComponents.kt:170` does the same.

A fix adds the selected value and the double-tap hint on the selecting blurred surface, and the avatar hint "Opens author profile".

## 3. Wording rows (A14's 46)

Compared today's strings. Of the 46 rows in A14 section 4: **38 done**, **6 still differ**, **2 not applicable**. A second row that shared an iOS line in that table is the accessibility row. Where the visible words now match and the spoken words do not, the visible row is counted done and the accessibility row is listed here.

### Still differ (6)

1. **Cycle tag.** iOS `Features/Search/TagSelectField.swift:418` accessibility action named "Cycle tag". The chip's label (`:416`) is "Excluded/Included: {tag}" and its hint (`:417`) is "Tap to {next} this tag". Android `search/FilterTagPicker.kt:218-219` `contentDescription` "Excluded/Included: $tag" and `stateDescription` "Tap to ${state.next.status.lowercase()} this tag". The hint matches. There is no action named "Cycle tag".

2. **"{remainder} more fandoms" (accessibility row).** Visible chips match: iOS `Features/Search/MediaBrowserView.swift:941` `"+{compact remainder} more"`, Android `browse/BrowseCategoryPanels.kt:300` `"+${remainder.compactCount()} more"`. The spoken label does not. iOS `:942` `"\(remainder.formatted()) more fandoms"` (a grouped integer, then "more fandoms"). Android sets no `contentDescription`, so the chip speaks "+N more".

3. **Couldn't load your profile.** iOS `Features/Account/AccountView.swift:740` title "Couldn't load your profile" on header phase `.failed`. Android has no that string. A failed account load clears the header and sets the unavailable flag only for `NotFound` (`account/AccountViewModel.kt:154-157`). The card that flag draws is "Profile unavailable" / "AO3 could not load your profile. It may be temporarily unavailable." (`account/AccountScreen.kt:243-245`), which is iOS's `.unavailable` copy (`AccountView.swift:732-735`), a different case. The author error card is still "Couldn't load author" (`author/AuthorProfileScreen.kt:676`).

4. **Works Filters.** iOS `Features/Account/AccountInboxViews.swift:108` toolbar title "Works Filters" when `isWorksVisible`. Android has no "Works Filters". The account works list uses `FilterButton` (`account/AccountWorksListScreen.kt:260`), whose label is "Filter" or "Filter, $badgeCount active" (`ui/subject/SubjectComponents.kt:1004`). (The inbox control is a different row and now matches: iOS `AccountInboxViews.swift:100` "Inbox Filters", Android `account/AccountInboxPane.kt:648` "Inbox Filters".)

5. **Continue thread, {n} (label row).** iOS `Features/Comments/CommentThreadRow.swift:876` accessibility label "Continue thread, \(countText)", where `countText` is "1 deeper reply" or "N deeper replies" (`:856`) and the drawn words are "Continue thread" (`:859`) plus that count. Android draws "Continue thread" (`comments/CommentThreadComponents.kt:393`), a separator, and the same count text (`:382` and `:400`). The click label is "open the rest of this thread" (`:388`). Android does not speak "Continue thread, 1 deeper reply" or "Continue thread, N deeper replies".

6. **Continue thread, {n} (accessibility row).** Same pair of strings as row 5. iOS `CommentThreadRow.swift:876` "Continue thread, \(countText)". Android `CommentThreadComponents.kt:388` "open the rest of this thread".

### Not applicable (2)

Decision **2026-10-05 · "First run, What's New and the login screen say what iOS's say."** (`docs/android-port/DECISIONS.md:729-735`): "Welcome and the sync-folder setup now carry iOS's text word for word, except where iOS names an Apple-only thing: "iCloud Drive" became "a cloud storage app"… its first entry says "native Android reader" where iOS says "native SwiftUI reader"."

- Sync folder. iOS `Features/Onboarding/SyncFolderOnboardingView.swift:62-63`: "Choose where Kudos keeps another copy of your library. If the folder is in iCloud Drive, Apple can keep it up to date on your devices." Android `onboarding/SyncFolderOnboardingScreen.kt:220-222`: "Choose where Kudos keeps another copy of your library. Use the system folder picker. If the folder belongs to a cloud storage app, that app can keep it up to date on your devices."
- What's New. iOS `Features/Support/WhatsNew.swift:21`: "Welcome to Kudos — a native SwiftUI reader for Archive of Our Own." Android `support/WhatsNew.kt:40`: "Welcome to Kudos — a native Android reader for Archive of Our Own."

### Done (38)

The other rows. Both sides, today's lines:

| Row | iOS | Android |
|---|---|---|
| First page | `Features/Search/SearchPaginationBar.swift:466` "First page" | `ui/components/KudosPaginationBar.kt:286` "First page" |
| Last ({n}) | `SearchPaginationBar.swift:468` "Last (\(totalPages.formatted()))" | `KudosPaginationBar.kt:292` "Last (${"%,d".format(totalPages)})" |
| +{n} more (visible chip; the pair's other row is listed above) | `Features/Search/MediaBrowserView.swift:941` | `browse/BrowseCategoryPanels.kt:300` |
| {count} work/works | `Features/Account/AO3CollectionDetailView.swift:652` | `account/AO3CollectionDetailScreen.kt:492` |
| Couldn't load preferences | `Features/Account/AO3PreferencesView.swift:63` | `account/AO3PreferencesScreen.kt:209` |
| View Profile (label and accessibility) | `Features/Account/AccountComponents.swift:72` | `account/AccountScreen.kt:753` "View Profile" when the avatar is tappable |
| Posting as {pseud or Account Default} | `AccountComponents.swift:138` | `AccountScreen.kt:521` |
| Account actions (label and accessibility) | `AccountComponents.swift:290` | `AccountScreen.kt:569` |
| Select Inbox Items | `Features/Account/AccountInboxViews.swift:116` | `account/AccountInboxPane.kt:523` |
| Inbox empty sentence | `AccountInboxViews.swift:575-576` | `AccountInboxPane.kt:303-304` |
| Related works | `Features/Account/AccountMoreOnAO3View.swift:177` | `account/AccountMoreOnAO3Screen.kt:159` |
| Skins and site styles | `AccountMoreOnAO3View.swift:219` | `AccountMoreOnAO3Screen.kt:179` |
| Gifts given and received | `AccountMoreOnAO3View.swift:280` | `AccountMoreOnAO3Screen.kt:171` |
| {n} imported work/works came from other sites… | `Features/Account/AvailabilitySweepView.swift:118-120` | `settings/AvailabilitySweepScreen.kt:124-126` |
| Kudos marked them as no longer on AO3… | `AvailabilitySweepView.swift:158-159` | `AvailabilitySweepScreen.kt:172-174` |
| Free {n} File/Files | `Features/Account/PrivacyDataView.swift:141`, plural helper `:481-482` | `settings/PrivacyDataScreen.kt:176`, `countLabel` `:241` |
| Removes saved fandom and category lists… | `PrivacyDataView.swift:175-176` | `PrivacyDataScreen.kt:171` |
| {n} words (grouped, not compact) | `Features/Authors/AuthorProfileComponents.swift:354` and `AuthorProfileView.swift:354` | `author/AuthorProfileComponents.kt:346`, `AuthorProfileScreen.kt:1140-1142` and `:1166` |
| Loading author profile (label and accessibility) | `AuthorProfileComponents.swift:644` | `ui/subject/SubjectSkeletons.kt:128`, spoken at `:38-39`, drawn from `AuthorProfileScreen.kt:650` |
| New series on AO3 | `Features/Authors/AuthorProfileContentSections.swift:508` | `author/AuthorProfileScreen.kt:957` |
| This opens AO3 in Browse, where you can create the series. | `AuthorProfileContentSections.swift:516` | `AuthorProfileScreen.kt:959` |
| REPLYING TO YOU | `Features/Comments/CommentThreadRow.swift:1214` `Text("Replying to you".uppercased())` | `comments/CommentThreadComponents.kt:587` "REPLYING TO YOU" |
| Browse comments by chapter, and the sheet title Browse Comments by Chapter | `Features/Comments/CommentsView.swift:626` and `:1076` | `comments/CommentsScreen.kt:502` and `:777` |
| {n} left | `CommentsView.swift:1490` | `comments/CommentComposerSheet.kt:293` |
| Welcome: unofficial reader; no ads; made by fans; shake to report | `Features/Onboarding/WelcomeView.swift:48-49`, `:53-54`, `:58-59`, `:63-64` | `onboarding/WelcomeScreen.kt:138-139`, `:144-145`, `:150-151`, `:156-157` |
| Sync: offline; same kind of file; deletion signing | `Features/Onboarding/SyncFolderOnboardingView.swift:67-68`, `:72-73`, `:77-78` | `onboarding/SyncFolderOnboardingScreen.kt:227-228`, `:233-234`, `:239-240` |
| Login credentials sentence | `Features/Auth/AO3LoginView.swift:129-130` | `auth/AO3NativeLoginScreen.kt:191-192` |
| Login handoff the reader sees | `Services/AO3WebLoginCoordinator.swift:83` "Let's finish logging in on AO3's page below.", assigned at `Services/AO3AuthService.swift:852` | `auth/AO3NativeLoginScreen.kt:382`, drawn at `:120` |
| Bug report: describe; only these details | `Features/Support/BugReportView.swift:27-29` and `:48-49` | `account/BugReportScreen.kt:100-101` and `:188-189` |

The login view's nil default is still "Complete login on AO3 below." (`Features/Auth/AO3LoginView.swift:188`). Every fallback path sets `fallbackMessage` to the shared prompt before that view is shown, so the sentence a reader gets matches Android.

## 4. Summary

| Item | Verdict | One line |
|---|---|---|
| Account shortcut editor | open | Editor, reset, and "none" match; Series is not a destination (`AccountShortcuts.kt:7`, iOS `AccountShortcuts.swift:16`). |
| Manage collection items | done | Same title and `collection_items` path (`AccountMoreOnAO3Screen.kt:158`, iOS `AccountMoreOnAO3View.swift:170`). |
| Chapter comments from the inbox | done | Menu and chapter navigation match; no "Open Chapter Comments" accessibility action. |
| Share Profile | done | Shares the pseud or user dashboard URL (`AuthorProfileScreen.kt:536`, iOS `AuthorProfileView.swift:895`). |
| Read Aloud downloads on Privacy | done | Section and both sentences match (`PrivacyDataScreen.kt:42-43`, iOS `PrivacyDataView.swift:425`). |
| Showing cached AO3 data | done | Same label on inbox, account, author, and series (`CachedAO3DataRow.kt:23`). |
| Popular tags | open | "Popular in {fandom}" and the GET exist; the no-fandom sentence does not (`FilterTagPicker.kt:165`). |
| Works sort and completion | done | Same footer, and Apply reloads with `work_search[sort_column]` (`AuthorWorksSortFields.kt:19`). |
| Bookmark the in-app browser page | done | "Add Bookmark" writes a local bookmark (`AO3WebViewFallbackScreen.kt:198`, iOS `BrowseView.swift:144`). |
| Nearby pages | done | Ten tiles, draft only, "Page N" (`KudosPaginationBar.kt:237`, iOS `SearchPaginationBar.swift:428`). |
| Show in Library | done | The import notice switches to the Library tab (`KudosApp.kt:271`, `MainScaffold.kt:127`). |
| Checking whether this posted | open | No verifying sentence; Check Again is on the "AO3" alert (`CommentsScreen.kt:249`, iOS `CommentsView.swift:1610`). |
| Offline cached-comments banner | open | Sentence matches; Android shows it for every network failure, not only offline (`CommentsScreen.kt:595`). |
| Author later-page failure | done | List stays, "Try Loading More" retries that page (`AuthorProfileScreen.kt:1121`). |
| Subscribe with confirmation | open | Unsubscribe confirm and the POST match; no "Log in to AO3" alert (`AuthorProfileView.swift:152`). |
| History and Subscriptions signed-out and empty | open | Empty copy matches; works lists still say "AO3 session required" (`AccountWorksListScreen.kt:414`). |
| Tag empty states | done | Both empties and Clear Filters, against a date-updated baseline (`FandomWorksScreen.kt:231`). |
| Accessibility names | open | Avatar name and fandom index match; blurred selection has no Selected value or double-tap hint (`MatureContent.swift:201-203`). |
| Wording, 38 rows | done | Strings cited in section 3 match, including both casings of Browse comments. |
| Wording, Cycle tag | open | No action named "Cycle tag" (`TagSelectField.swift:418`). |
| Wording, more fandoms (spoken) | open | iOS speaks "N more fandoms"; Android speaks "+N more" (`MediaBrowserView.swift:942`). |
| Wording, Couldn't load your profile | open | Android account failure is "Profile unavailable" or nothing (`AccountView.swift:740`). |
| Wording, Works Filters | open | Android's works control says "Filter" (`SubjectComponents.kt:1004`). |
| Wording, Continue thread ×2 | open | Visible count matches; spoken string is "open the rest of this thread" (`CommentThreadComponents.kt:388`). |
| Wording, sync-folder cloud sentence | not applicable | 2026-10-05 "First run, What's New and the login screen say what iOS's say." |
| Wording, What's New platform word | not applicable | Same decision: "native Android reader" for "native SwiftUI reader". |

### Counts

| Group | Done | Open | Not applicable |
|---|---|---|---|
| Missing features (11) | 9 | 2 | 0 |
| Behaviours (7) | 2 | 5 | 0 |
| Wording rows (46) | 38 | 6 | 2 |
| **All 64** | **49** | **13** | **2** |

The two open features are the shortcut editor (no Series) and popular tags (no "Choose a fandom…" sentence). The five open behaviours are the comment verifying sentence, the offline-banner gate, the subscribe login alert, the History and Subscriptions works signed-out cards, and the accessibility names (avatars and the fandom index match apart from a hint and an empty value; blurred selection does not). R1's "not ported" browser bookmark and its "still to do" cached banner are done in this tree.
