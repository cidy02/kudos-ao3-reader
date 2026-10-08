# Audit A14 result: what the string checks were really missing

Read-only. Lines are the current source, not the line numbers in A9, A10 and A11 (those files have moved). iOS paths are under `/Users/cidy02/kudos-ios-polish/`. Android paths are under this worktree. Every not-found row is one class. Duplicate accessibility rows are counted separately. A9's triage note that no Search or Browse feature is missing is not followed: five of those rows are missing.

## 1. Counts

| Source | Rows | M | B | W | N |
|---|---:|---:|---:|---:|---:|
| A9 Search and Browse | 21 | 5 | 8 | 5 | 3 |
| A10 Account, Bookmarks, Authors, Comments | 88 | 15 | 39 | 28 | 6 |
| A11 Onboarding, Auth, Privacy, Support | 23 | 1 | 2 | 13 | 7 |

Sync-folder point 1 and What's New are W. `docs/android-port/DECISIONS.md:728-733` records them as reworded, not left out. The Privacy "Read Aloud downloads" sentences are not the Listening leave-out at `DECISIONS.md:514-518`.

Unsettled: none.

## 2. M — missing on Android

### A10. Account shortcut editor (3 rows)

`kudos-ao3-reader/Features/Account/AccountShortcuts.swift:127` "On the grid", `:130` "If you choose none, the grid is hidden. You can still find every destination in the sections below.", `:144` "Reset to Default".

A reader cannot choose which destinations sit on the Account grid, reorder them, reset them, or hide the grid by choosing none. Android's grid is a fixed list. The header that would open an editor is `android/app/src/main/java/io/github/cidy02/kudos/account/AccountScreen.kt:886` (`onSeeAll = { /* TODO implement shortcut editor */ }`).

AO3: none. The editor writes `AccountShortcutStore` on the device. Reorder is `onMove` at `AccountShortcuts.swift:121-124`.

### A10. Manage collection items (1 row)

`kudos-ao3-reader/Features/Account/AccountMoreOnAO3View.swift:170`, path suffix `collection_items` (`:60`, `:172`).

A reader cannot open their account-wide collection-items page. Android's matching card is "Manage collections" and opens `collections` (`account/AccountMoreOnAO3Screen.kt:82`). `AO3CollectionItems` on Android is one collection's moderator list, a different page. Belong beside `AccountMoreOnAO3Screen.kt:82`.

AO3: when the card is tapped, GET `https://archiveofourown.org/users/{username}/collection_items` (`AccountExternalNavCard.swift:120-125`). The card does not POST.

### A10. Open a chapter's comments from the inbox (2 rows)

`kudos-ao3-reader/Features/Account/AccountInboxViews.swift:246` accessibility action "Open Chapter Comments", and `:439` menu label "Chapter Comments". Both show only when `item.chapterPosition != nil`.

A reader cannot open that chapter's comments from an inbox row. Android's overflow has "Open Thread" only (`account/AccountInboxPane.kt:979`), and that opens the work's comments focused on the inbox comment. The chapter chip is display-only. Belong on that overflow.

AO3: the menu itself does not request. The destination (`AccountView.swift:1022-1043`, focus `.chapter`) then loads comments with GET `https://archiveofourown.org/works/{workID}/chapters/{chapterID}?show_comments=true&view_adult=true` (`Services/AO3Client+Comments.swift:19-37`; `page` when the page is past 1).

### A10. Share an author profile (1 row)

`kudos-ao3-reader/Features/Authors/AuthorProfileView.swift:878` "Share Profile", a `ShareLink` of `model.route.dashboardURL`.

A reader cannot share the profile URL from the author menu. Android's menu (`author/AuthorProfileScreen.kt:145-185`) has "Open on AO3" and no share. "Share Series" at `app/SeriesWorksScreen.kt:154` is the series screen. Belong in the author menu.

AO3: none. The share is local. The URL is `https://archiveofourown.org/users/{name}` or `.../pseuds/{pseud}` (`Models/AO3AuthorModels.swift:103-113`, `:155`).

### A10. Read Aloud downloads on Privacy (3 rows)

`kudos-ao3-reader/Features/Account/PrivacyDataView.swift:109` section "Read Aloud downloads", `:425` "Optional Voice Pack downloads stay separate from your reading data.", `:428` "Kudos never sends a work's text, spoken audio, your AO3 sign-in, saved works, reading history, usage information, or anything that identifies your account to the Voice Pack provider. …"

A reader cannot read that section. Android's Privacy intro (`settings/PrivacyDataScreen.kt:100-109`) is a different card, "No ads or tracking…", whose body mentions a Voice Pack connection and does not say these sentences. Not the Kokoro rows left out at `DECISIONS.md:514-518`. Belong in `settings/PrivacyDataScreen.kt`.

AO3: none.

### A10. "Showing cached AO3 data" (5 rows)

The banner is the same label on five rows. Android has no "Showing cached" / `isStale` line on these screens (the only stale UI found elsewhere is the fandom catalog cache).

| Row | iOS | Where it would belong | AO3 read that sets the flag (the banner adds none) |
|---|---|---|---|
| Inbox | `Features/Account/AccountInboxViews.swift:713` | `account/AccountInboxPane.kt` | GET `https://archiveofourown.org/users/{name}/inbox` (`Services/AO3Client+Inbox.swift:16-22`), flagged at `AO3InboxModel.swift:557` |
| Account profile, list layout | `Features/Account/AccountView.swift:747` | `account/AccountScreen.kt` | GET `route.dashboardURL`, `https://archiveofourown.org/users/{name}` or `.../pseuds/{pseud}` (`AO3AuthorProfileService.swift:591`, `:618`; `AO3AuthorModels.swift:111-113`) |
| Account profile, other layout | `Features/Account/AccountView.swift:753` | same | same fetch |
| Author profile | `Features/Authors/AuthorProfileView.swift:251` | `author/AuthorProfileScreen.kt` | same fetch |
| Series | `Features/Authors/AO3SeriesDetailView.swift:60` | `app/SeriesWorksScreen.kt` | GET `AO3Client.seriesPageURL(series.url, page:)` (`AO3SeriesDetailView.swift:239`, builder `Services/AO3Client.swift:1284-1289`): the series page, with `page` only when the page is past 1. Flag set at `:268-270` |

### A9. Popular tags in the tag picker (1 row)

`kudos-ao3-reader/Features/Search/TagSelectField.swift:247` "Choose a fandom to see its most-used {kind} here." Shown when the kind is not fandom and no fandom is set (`:242-247`). That sentence does not fetch.

A reader cannot browse a fandom's most-used tags before typing. Android's empty picker says "Type above to search AO3 …" and searches only once the token is at least two characters (`search/FilterTagPicker.kt:145-154`). Belong in `search/FilterTagPicker.kt`.

AO3: when a fandom is set and the popular list is empty, the picker task (`TagSelectField.swift:218`, `loadPopular` `:335-338`) GETs `https://archiveofourown.org/tags/{tagPathSegment}/works` and reads the sidebar checkboxes `include_work_search[character_ids|relationship_ids|freeform_ids][]` (`Services/AO3Client.swift:1597-1627`). `tagPathSegment` (`:628`) escapes `&` `*` `/` `.` `?` `#` as `*a*` `*s*` `*d*` `*q*` `*h*`, then percent-encodes.

### A9. Works sort and completion on an author (1 row)

`kudos-ao3-reader/Features/Search/AO3FilterPanel.swift:667` "AO3 applies this choice to all matching works, not only the page you can see." Footer of the works sort sheet. The footer does not fetch.

A reader cannot sort an author's works, or limit them to complete or incomplete works, on AO3's index. Android's works tab has scope chips only (`author/AuthorProfileScreen.kt:366-378`). `AO3AuthorUrls.userWorksUrl` can add the query (`network/ao3/author/AO3AuthorUrls.kt:70-79`) and nothing in the works tab passes a non-default sort. Belong beside those chips.

AO3: Apply calls `applyWorksSort` (`Services/AO3AuthorProfileService.swift:298`), which reloads `contentURL` (`Models/AO3AuthorModels.swift:126-145`): GET `https://archiveofourown.org/users/{name}[/pseuds/{pseud}]/{scope}`. `AO3WorksSort.queryItems` (`Models/AO3WorksSort.swift:135-146`, sent via `indexQueryItems` `:160-162`) adds `work_search[sort_column]`, `work_search[sort_direction]`, and `work_search[complete]` only when the choice is not AO3's default.

### A9. Bookmark the in-app browser page (2 rows)

`kudos-ao3-reader/Features/Browse/BrowseView.swift:78` image button, accessibility label "Add Bookmark" (the audit's Label row and its accessibility row are this one control).

A reader cannot save the page open in the in-app browser. `web/AO3WebViewFallbackScreen.kt` is a read-only WebView with no bookmark control. Belong on that screen.

AO3: none. `bookmarkCurrentPage` (`BrowseView.swift:143-147`) inserts a local `Bookmark`.

### A9. Nearby pages in the page jump (1 row)

`kudos-ao3-reader/Features/Search/SearchPaginationBar.swift:411` section "Nearby": ten page tiles that only set the draft (`:414`).

A reader cannot jump to a neighbouring page from a tile. Android's sheet (`ui/components/KudosPaginationBar.kt:146-201`) is a slider, "First", "Last" and "Go". Belong in that sheet.

AO3: none from the tiles. Confirming a page uses the list's existing page load.

### A11. "Show in Library" after an external import (1 row)

`kudos-ao3-reader/App/ContentView.swift:142`. Shown on the import-notice alert only when `notice.workID != nil`. It selects the Library tab (`:144`).

A reader cannot go to Library from the import result. Android's dialog is title "Import", body "Added N to your Library: …", confirm "OK" (`app/KudosApp.kt:87`, `:213-223`). Belong on that dialog.

AO3: none. The import is a local file.

## 3. B — both have it, and they differ

### A9

**Go to page** (1 row). iOS sheet title `kudos-ao3-reader/Features/Search/SearchPaginationBar.swift:343`: "Go to page", a number field, then confirm. Android `ui/components/KudosPaginationBar.kt:146-200` has no title: the draft page as a large number, "of $totalPages" (`:152`), a slider that does not fetch while dragging, and "Go" (`:200`). First and Last are the W rows below.

**Opens filters** (2 rows, the card's text and its `accessibilityHint`, both `kudos-ao3-reader/Features/Search/SearchResultsHero.swift:168`). iOS: the summary card is a button whose spoken hint is "Opens filters". Android `search/SearchResultsHero.kt:114-122`: the card is clickable when `onEditFilters != null`, and `contentDescription` is only the spoken summary. No "Opens filters".

**Fandom index** (2 rows, Label and `accessibilityLabel`, both `kudos-ao3-reader/Features/Search/FandomListView.swift:293`). iOS: "Fandom index", value the current letter (`:294`), and an adjustable increment/decrement (`:295-308`). Android `browse/FandomListChrome.kt:351-388`: the same letter strip, pointer-only, no `contentDescription` and no adjustable action.

**No works with this tag match your filters.** iOS `kudos-ao3-reader/Features/Browse/NativeBrowseView.swift:629`, only when the tag page is empty and `hasExtraFilters` (`:623`), with "Clear Filters" (`:631`). Android `browse/TagWorksScreen.kt:193-196`: any empty AO3 page, including one emptied by AO3 filters, is "AO3 returned no works for this tag." with no Clear Filters. The local-refine sentence at `:189` ("No works on this page match your refinement.") is a different state.

**AO3 has no works for this tag right now.** (2 rows; the audit listed a Text and a description. The sentence is now the description once, `kudos-ao3-reader/Features/Browse/NativeBrowseView.swift:637`.) iOS shows it when the tag page is empty and there are no extra filters (`:633-637`), title "No works found". Android uses the same "AO3 returned no works for this tag." (`TagWorksScreen.kt:196`) for every empty AO3 page.

### A10

**Collections footer.** iOS `kudos-ao3-reader/Features/Account/AO3CollectionsList.swift:382`: "These are your AO3 collections. Collections you make in Kudos are in Library." Android `account/AO3CollectionsScreen.kt:270`: "These are your AO3 collections..." The second sentence is absent.

**Dashboard signed out.** iOS `kudos-ao3-reader/Features/Account/AO3DashboardView.swift:26`: "Log in to AO3 to open your dashboard." under "Not signed in" (`:24`). Android `account/AO3DashboardScreen.kt:21-25` returns without drawing when `username` is blank.

**Couldn't load help.** iOS `kudos-ao3-reader/Features/Account/AO3PreferencesView.swift:268`, after `loadPreferenceHelp` fails (`Services/AO3PreferencesActions.swift:18-20`, GET of the preference's public help URL), with Try Again and Open on AO3 (`:272-273`). Android `account/AO3PreferencesScreen.kt:248-250`: the help icon (`contentDescription` "Help") calls `onOpenHelp(helpUrl)` and opens that URL in the web fallback. No in-app help sheet and no "Couldn't load help".

**Session expired while saving preferences.** iOS `kudos-ao3-reader/Features/Account/AO3PreferencesView.swift:488`: "Your AO3 session expired. Sign in again from Account." then `sessionDidExpire`. The save itself is one POST of the scraped form (`AO3PreferencesActions.swift:26-44`: `snapshot.actionURL`, `authenticity_token`, `_method`, preference fields). Android `account/AO3PreferencesScreen.kt:139`: "Save failed: ${result.error.displayMessage()}". `AuthenticationRequired` displays "AO3 requires login." (`network/ao3/AO3Error.kt:86`).

**Restoring AO3 session** (2 rows, Label and `accessibilityLabel`, both `kudos-ao3-reader/Features/Account/AccountComponents.swift:51`). Shown on the restoring skeleton. Android has `AO3AuthState.Restoring`, and `AccountProfileHeader` (`account/AccountScreen.kt:380-392`) draws `AccountSignedOutHeader` for every state that is not `SignedIn`. That header's else title is "Not signed in" (`:580-584`).

**Inbox page failed.** iOS `kudos-ao3-reader/Features/Account/AccountInboxViews.swift:545`: "Couldn't load page {n}", the previous page stays (`:541-543`). Android `goToPage` calls `load` (`account/AccountInboxViewModel.kt:175-176`). A non-auth failure with items still on screen sets `actionError` and stays `Loaded` (`:150-159`), shown as AlertDialog "Couldn't update Inbox" (`AccountInboxPane.kt:171`). An auth failure clears the items (`:142-148`).

**Account Content** (2 rows, Label and `accessibilityLabel`, both `kudos-ao3-reader/Features/Account/AccountView.swift:337`). A segmented control that shows one of Reading, Writing, Activity. Android `account/AccountScreen.kt:236`, `:269`, `:290` draws "Reading", "Writing" and "Activity" as groups that are all on the page. No "Account Content" string.

**Profile unavailable** (2 rows). iOS `kudos-ao3-reader/Features/Account/AccountView.swift:729` "Profile unavailable" and `:731` "AO3 could not load your profile. It may be temporarily unavailable." Shown when `headerPhase` is `.unavailable`, which is `AO3Error.notFound` (`AO3AuthorProfileService.swift:628-633`). Android's author and dashboard card (`author/AuthorProfileScreen.kt:201-208`) is "Couldn't load author" plus `displayMessage()`. `NotFound` is "AO3 could not find that page." (`AO3Error.kt:88`), with Try Again. `AccountScreen` has no profile phase of its own.

**Clear Reading History button.** iOS `kudos-ao3-reader/Features/Account/PrivacyDataView.swift:125`: "Clear {n} Work(s)". It soft-deletes `freedHistory` (`:64-66`): works with no EPUB and not protected. Local, no AO3 write. Android `settings/PrivacyDataScreen.kt:184` "Clear {n} Work(s)" calls `softDeleteAllFinished()` (`:188`, `works/WorkRepository.kt:137-141`), which soft-deletes every finished work.

**Clear Reading History message.** iOS `PrivacyDataView.swift:132`: "Moves works that only remain in your reading history to Recently Deleted for {window}. Your saved and downloaded works stay where they are, and you can download these works from AO3 again." Android `PrivacyDataScreen.kt:183`: "Moves your local reading-history records to Recently Deleted for 90 days. The works themselves can also be re-downloaded from AO3 anytime. Your saved and downloaded works aren't affected." The set cleared is the button row above.

**Clear reading positions button.** iOS `PrivacyDataView.swift:155`: "Clear {n} Position(s)", then `LocalDataClearing.clearReadingPositions`. Local, no AO3 write. Android `PrivacyDataScreen.kt:148`: `SubjectFormRow("Clear reading positions", …, onClick = {})`. No dialog and no clear.

**Clear reading positions message.** iOS `PrivacyDataView.swift:160`: "Clears your place in every work. Your works and their order in Continue Reading stay the same." Android has no message, because the row's click is empty (`:148`).

**Try Loading More.** iOS `kudos-ao3-reader/Features/Authors/AuthorProfileContentSections.swift:83`, when `loadMoreError != nil` (`:78`): the list stays and the button retries the next page. Android `author/AuthorProfileScreen.kt:95-119` sets `page = pageNum` before the request and `tabError` on failure. The error card is drawn only when `tabError != null && page == 1` (`:354-361`). A later page keeps the old list and `PagerRow`, with no error and no retry. The retry GETs that tab's next page (`contentURL`, `AO3AuthorModels.swift:126-145`).

**You have not made a series.** iOS `kudos-ao3-reader/Features/Authors/AuthorProfileContentSections.swift:486`, only when the signed-in author has no series and the load did not fail (`:480`). Android `author/AuthorProfileScreen.kt:406-407`: `EmptyStateCard("No series", "No series by this author are visible to you on AO3.")` for every empty series tab, including the signed-in author.

**A series groups your works…** iOS `AuthorProfileContentSections.swift:488`: "A series groups your works in reading order. Create one on AO3, then refresh this page to see it here." Same own-profile empty state. Android uses the "No series by this author…" sentence above.

**AO3 Profile alert.** iOS `kudos-ao3-reader/Features/Authors/AuthorProfileView.swift:119` shows `model.actionMessage` after subscribe, unsubscribe, block, mute, and moderation confirm. Subscribe posts the scraped form: `submitAuthorSubscription` (`AO3AuthorProfileService.swift:909-917`) POSTs `form.actionURL` with the form's own fields and CSRF. Android `author/AuthorProfileScreen.kt:239` sets `onSubscription = onOpenWeb`, and moderation opens `it.url` (`:240`). No alert titled "AO3 Profile".

**Log in to your AO3 account to do this.** iOS `AuthorProfileView.swift:149`, alert "Log in to AO3" with Log In, before an auth-gated profile action. Android opens the subscription form URL in the browser (`:239`) with no login alert.

**Unsubscribing here applies to the whole AO3 account, not only this pseud.** iOS `AuthorProfileView.swift:161`, confirmation, then `toggleSubscription`, which is the POST in `submitAuthorSubscription` (`:909-917`, `form.actionURL` from the profile page). Android opens that URL in the browser and does not confirm.

**Author scope** (2 rows, Label and `accessibilityLabel`, both `kudos-ao3-reader/Features/Authors/AuthorProfileView.swift:419`). The visible title is the current pseud (`:411`). Android is a chip row "All Pseuds" / pseud names (`author/AuthorProfileScreen.kt:246-260`; dashboard `:222-230`) with no group name "Author scope". Both switch the pseud and reload.

**Author unavailable** (2 rows). iOS `AuthorProfileView.swift:701` "Author unavailable" and `:703` "AO3 could not find this user or pseud. It may have been renamed or deleted." plus "Open on AO3" (`:705`). Same `.unavailable` / `AO3Error.notFound` path as the account row (`AO3AuthorProfileService.swift:628-633`). Android collapses it into "Couldn't load author" / "AO3 could not find that page." / Try Again (`AuthorProfileScreen.kt:204`, `AO3Error.kt:88`).

**AO3 Author.** iOS `AuthorProfileView.swift:733`, the kicker on the failed-profile header (not the 404 view). Android's error card (`AuthorProfileScreen.kt:201-208`) has no kicker. The success hero subtitle "AO3 user" / "Pseud of {name}" (`author/AuthorProfileComponents.kt:111`) is the loaded header, not this failure.

**Delete from history.** iOS `kudos-ao3-reader/Features/Bookmarks/AO3HistoryWorksBrowser.swift:145`, the swipe label. Confirming calls `deleteReading` (`Services/AO3WriteActions.swift:243-268`): GET `https://archiveofourown.org/users/{name}/readings` for the CSRF token (`Services/AO3Client.swift:661-667`), then POST `https://archiveofourown.org/users/{name}/readings/{readingID}` (`AO3Client+Readings.swift:154-162`; `page` when past 1) with `_method=delete`, `authenticity_token`, `reading={id}`, referer the history page. Android's chip is "Delete" (`account/AccountWorksListScreen.kt:920-925`). The confirm title is "Delete from History?" and the button "Delete from History" (`:805-811`), and the confirm only adds the id to local `deletedIds` (`:816`). It does not call AO3.

**Log in to AO3 to see your subscriptions.** iOS `kudos-ao3-reader/Features/Bookmarks/AO3NamedSubscriptionsList.swift:240`, when `accountNamedSubscriptions` returns nil. Android `account/AccountWorksListScreen.kt:1242-1244`: `EmptyStateCard("AO3 session required", "Your AO3 session needs to be refreshed.")` with "Log In Again". `AccountListRepository.kt` returns `AuthenticationRequired` for that load.

**Heading** (2 rows, Label and `accessibilityLabel`, both `kudos-ao3-reader/Features/Comments/CommentMarkup.swift:489`). "Heading {level}" for levels 1…6; the visible chip is the element (`h1`…). Android `comments/CommentMarkup.kt:83` is one tag, `Heading`, which always wraps `<h3>`.

**You're offline. These comments are from {when}…** iOS `kudos-ao3-reader/Features/Comments/CommentsView.swift:760`, shown when `isFromCache && isOffline` (`:681`). The banner does not fetch. The failed read is `commentsPageURL` (`AO3Client+Comments.swift:19-37`). Android `network/ao3/comments/AO3CommentRepository.kt:48-50` returns a cached thread as `Success` on a public-get failure. `comments/CommentsScreen.kt` has no banner. (`CommentsViewModel` has a different offline string, "You're offline. Comments will load when you're back online.", which is not this banner.)

**View {author}'s profile, comment avatar** (2 rows, Label and `accessibilityLabel`, both `kudos-ao3-reader/Features/Comments/CommentThreadRow.swift:1680`). Hint "Opens author profile" (`:1681`). Android `comments/CommentThreadComponents.kt:427-434`: the avatar box is clickable and has no `contentDescription`.

**View {author}'s profile, composer byline** (2 rows, Label and `accessibilityLabel`, both `kudos-ao3-reader/Features/Comments/CommentsView.swift:1465`). Android `comments/CommentComposerSheet.kt:178-185`: the name is clickable and has no `contentDescription`.

**We're checking whether this posted before trying again…** iOS `CommentsView.swift:1499`, phase `.verifying`. Android `comments/CommentsViewModel.kt:355-407` has no verifying label. A duplicate hash sets "You just posted this. Reload to see if it appeared." (`:365`). A non-offline network failure sets "Couldn't confirm this posted — reloading to check." and calls `load()` (`:397-400`).

**Check Again.** iOS `CommentsView.swift:1513`. The comment at `:1508-1509` says this re-runs the verification fetch and never the POST. Android has no Check Again button.

**Posted.** iOS `CommentsView.swift:1523`, phase `.succeeded`. Android's success text is "Reply posted." or "Comment posted." (`AO3CommentRepository.kt:152`).

**No works on this page match the current filters.** iOS `kudos-ao3-reader/Features/Bookmarks/AO3AccountWorksList.swift:716`, only when `visibleWorks` is empty and `works` is not (`:711`), with "Clear Filters" on the card (`:718`). Android's bookmark list, chip All, says "No works on this page." whenever `displayedWorks` is empty (`account/AccountWorksListScreen.kt:717-725`), including a page AO3 returned empty. Clearing filters is a long-press on the toolbar Filter button (`ui/subject/SubjectComponents.kt:930-936`), not a button on the empty card.

### A11

**Double-tap to select this work. / Double-tap to deselect this work.** (2 rows, the two branches of one hint, `kudos-ao3-reader/Features/Privacy/MatureContent.swift:189`). Spoken while a blurred mature work is in selection, together with value "Selected" or "Not selected" (`:188`). Android `ui/subject/SubjectWorkCoverCard.kt:547` speaks "Selected" only while the check is showing, and speaks nothing on an unselected card in selection.

## 4. W — same thing, different words

No commentary. A second row with the same iOS line is the audit's separate accessibility row.

### A9

| iOS string | Android string | iOS path:line | Android path:line |
|---|---|---|---|
| First page | First | `kudos-ao3-reader/Features/Search/SearchPaginationBar.swift:449` | `android/app/src/main/java/io/github/cidy02/kudos/ui/components/KudosPaginationBar.kt:175` |
| Last ({totalPages}) | Last | `kudos-ao3-reader/Features/Search/SearchPaginationBar.swift:451` | `android/app/src/main/java/io/github/cidy02/kudos/ui/components/KudosPaginationBar.kt:181` |
| Cycle tag | Tap to {next status} this tag | `kudos-ao3-reader/Features/Search/TagSelectField.swift:405` | `android/app/src/main/java/io/github/cidy02/kudos/search/FilterTagPicker.kt:202` |
| {remainder} more fandoms | +{remainder} more | `kudos-ao3-reader/Features/Search/MediaBrowserView.swift:930` | `android/app/src/main/java/io/github/cidy02/kudos/browse/BrowseCategoryPanels.kt:293` |
| {remainder} more fandoms | +{remainder} more | `kudos-ao3-reader/Features/Search/MediaBrowserView.swift:930` | `android/app/src/main/java/io/github/cidy02/kudos/browse/BrowseCategoryPanels.kt:293` |

### A10

| iOS string | Android string | iOS path:line | Android path:line |
|---|---|---|---|
| {count} work / {count} works | {count} work / {count} works | `kudos-ao3-reader/Features/Account/AO3CollectionDetailView.swift:646` | `android/app/src/main/java/io/github/cidy02/kudos/account/AO3CollectionDetailScreen.kt:537` |
| Couldn't load preferences | Preferences failed | `kudos-ao3-reader/Features/Account/AO3PreferencesView.swift:62` | `android/app/src/main/java/io/github/cidy02/kudos/account/AO3PreferencesScreen.kt:162` |
| Couldn't load your profile | Couldn't load author | `kudos-ao3-reader/Features/Account/AccountView.swift:736` | `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:204` |
| View Profile | Avatar | `kudos-ao3-reader/Features/Account/AccountComponents.swift:72` | `android/app/src/main/java/io/github/cidy02/kudos/account/AccountScreen.kt:733` |
| View Profile | Avatar | `kudos-ao3-reader/Features/Account/AccountComponents.swift:72` | `android/app/src/main/java/io/github/cidy02/kudos/account/AccountScreen.kt:733` |
| Posting as {pseud or Account Default} | Posting as {pseud or Account Default} | `kudos-ao3-reader/Features/Account/AccountComponents.swift:135` | `android/app/src/main/java/io/github/cidy02/kudos/account/AccountScreen.kt:491` |
| Account actions | Account menu | `kudos-ao3-reader/Features/Account/AccountComponents.swift:284` | `android/app/src/main/java/io/github/cidy02/kudos/account/AccountScreen.kt:539` |
| Account actions | Account menu | `kudos-ao3-reader/Features/Account/AccountComponents.swift:284` | `android/app/src/main/java/io/github/cidy02/kudos/account/AccountScreen.kt:539` |
| Works Filters | Filter / Filter, {n} active | `kudos-ao3-reader/Features/Account/AccountInboxViews.swift:108` | `android/app/src/main/java/io/github/cidy02/kudos/ui/subject/SubjectComponents.kt:918` |
| Select Inbox Items | Select inbox items | `kudos-ao3-reader/Features/Account/AccountInboxViews.swift:116` | `android/app/src/main/java/io/github/cidy02/kudos/account/AccountInboxPane.kt:469` |
| Comments on your works and replies to your comments appear here from your AO3 inbox. | Comments on your works and replies to your comments appear here from your AO3 inbox. | `kudos-ao3-reader/Features/Account/AccountInboxViews.swift:537` | `android/app/src/main/java/io/github/cidy02/kudos/account/AccountInboxPane.kt:282` |
| Related works | Related Works | `kudos-ao3-reader/Features/Account/AccountMoreOnAO3View.swift:177` | `android/app/src/main/java/io/github/cidy02/kudos/account/AccountScreen.kt:338` |
| Skins and site styles | Skins | `kudos-ao3-reader/Features/Account/AccountMoreOnAO3View.swift:219` | `android/app/src/main/java/io/github/cidy02/kudos/account/AccountScreen.kt:332` |
| Gifts given and received | Gifts | `kudos-ao3-reader/Features/Account/AccountMoreOnAO3View.swift:280` | `android/app/src/main/java/io/github/cidy02/kudos/account/AccountScreen.kt:339` |
| {n} imported work came / works came from other sites, so Kudos can't check them on AO3. | {n} imported work came / works came from other sites, so Kudos can't check them on AO3. | `kudos-ao3-reader/Features/Account/AvailabilitySweepView.swift:98` | `android/app/src/main/java/io/github/cidy02/kudos/settings/AvailabilitySweepScreen.kt:110` |
| Kudos marked them as no longer on AO3. Any downloaded copies are now treated as the last copies you have and will be kept permanently. | Kudos marked them as no longer on AO3. Any downloaded copies are now treated as the last copies you have and will be kept permanently. | `kudos-ao3-reader/Features/Account/AvailabilitySweepView.swift:138` | `android/app/src/main/java/io/github/cidy02/kudos/settings/AvailabilitySweepScreen.kt:158` |
| Free {n} File / Files | Free {n} File / Files | `kudos-ao3-reader/Features/Account/PrivacyDataView.swift:141` | `android/app/src/main/java/io/github/cidy02/kudos/settings/PrivacyDataScreen.kt:171` |
| Removes saved fandom and category lists. Your reading, saved works, and downloads stay untouched; Browse rebuilds the lists next time you open it. | Cached AO3 fandom and category data used to show Browse instantly. Safe to clear — it rebuilds the next time you open Browse. | `kudos-ao3-reader/Features/Account/PrivacyDataView.swift:175` | `android/app/src/main/java/io/github/cidy02/kudos/settings/PrivacyDataScreen.kt:196` |
| `\(words.formatted()) words` | `${it.compactCount()} words` | `kudos-ao3-reader/Features/Authors/AuthorProfileComponents.swift:246` | `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileComponents.kt:283` |
| Loading author profile | Loading… | `kudos-ao3-reader/Features/Authors/AuthorProfileComponents.swift:550` | `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:200` |
| Loading author profile | Loading… | `kudos-ao3-reader/Features/Authors/AuthorProfileComponents.swift:550` | `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:200` |
| New series on AO3 | New series | `kudos-ao3-reader/Features/Authors/AuthorProfileContentSections.swift:502` | `android/app/src/main/java/io/github/cidy02/kudos/account/AccountMoreOnAO3Screen.kt:80` |
| This opens AO3 in Browse, where you can create the series. | These open your AO3 pages in Browse. You can find works, series, bookmarks, history and inbox in the Reading, Writing and Activity sections of Account. | `kudos-ao3-reader/Features/Authors/AuthorProfileContentSections.swift:510` | `android/app/src/main/java/io/github/cidy02/kudos/account/AccountMoreOnAO3Screen.kt:85` |
| Continue thread, {n deeper reply / replies} | Continue thread | `kudos-ao3-reader/Features/Comments/CommentThreadRow.swift:876` | `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentThreadComponents.kt:361` |
| Continue thread, {n deeper reply / replies} | Continue thread | `kudos-ao3-reader/Features/Comments/CommentThreadRow.swift:876` | `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentThreadComponents.kt:361` |
| REPLYING TO YOU | REPLYING TO YOU | `kudos-ao3-reader/Features/Comments/CommentThreadRow.swift:1213` | `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentThreadComponents.kt:527` |
| Browse Comments by Chapter | Browse comments by chapter | `kudos-ao3-reader/Features/Comments/CommentsView.swift:978` | `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsScreen.kt:729` |
| {n} left | {n} left | `kudos-ao3-reader/Features/Comments/CommentsView.swift:1395` | `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentComposerSheet.kt:264` |

### A11

| iOS string | Android string | iOS path:line | Android path:line |
|---|---|---|---|
| An unofficial reader for Archive of Our Own. Kudos is free and open source, has no ads, and isn't affiliated with AO3 or the OTW. | An unofficial reader for Archive of Our Own. Kudos is free and open source, has no ads, and isn't affiliated with AO3 or the OTW. | `kudos-ao3-reader/Features/Onboarding/WelcomeView.swift:46` | `android/app/src/main/java/io/github/cidy02/kudos/onboarding/WelcomeScreen.kt:136` |
| Kudos has no ads, analytics, tracking, or hidden data collection. Your AO3 sign-in and the information Kudos needs stay on your device. | Kudos has no ads, analytics, tracking, or hidden data collection. Your AO3 sign-in and the information Kudos needs stay on your device. | `kudos-ao3-reader/Features/Onboarding/WelcomeView.swift:51` | `android/app/src/main/java/io/github/cidy02/kudos/onboarding/WelcomeScreen.kt:142` |
| Kudos is made by fans. It doesn't accept donations, but you can contribute to the project. | Kudos is made by fans. It doesn't accept donations, but you can contribute to the project. | `kudos-ao3-reader/Features/Onboarding/WelcomeView.swift:56` | `android/app/src/main/java/io/github/cidy02/kudos/onboarding/WelcomeScreen.kt:148` |
| Found a bug? Shake your device to send a report, or open an issue on GitHub. The AO3 team can't help with Kudos, so please don't contact them about it. | Found a bug? Shake your device to send a report, or open an issue on GitHub. The AO3 team can't help with Kudos, so please don't contact them about it. | `kudos-ao3-reader/Features/Onboarding/WelcomeView.swift:61` | `android/app/src/main/java/io/github/cidy02/kudos/onboarding/WelcomeScreen.kt:154` |
| Choose where Kudos keeps another copy of your library. If the folder is in iCloud Drive, Apple can keep it up to date on your devices. | Choose where Kudos keeps another copy of your library. Use the system folder picker. If the folder belongs to a cloud storage app, that app can keep it up to date on your devices. | `kudos-ao3-reader/Features/Onboarding/SyncFolderOnboardingView.swift:61` | `android/app/src/main/java/io/github/cidy02/kudos/onboarding/SyncFolderOnboardingScreen.kt:219` |
| You can use Kudos without an internet connection. If you skip this, you can choose a folder later in Settings. | You can use Kudos without an internet connection. If you skip this, you can choose a folder later in Settings. | `kudos-ao3-reader/Features/Onboarding/SyncFolderOnboardingView.swift:66` | `android/app/src/main/java/io/github/cidy02/kudos/onboarding/SyncFolderOnboardingScreen.kt:226` |
| Kudos saves the same kind of file as a backup in your folder. Updates aren't instant. | Kudos saves the same kind of file as a backup in your folder. Updates aren't instant. | `kudos-ao3-reader/Features/Onboarding/SyncFolderOnboardingView.swift:71` | `android/app/src/main/java/io/github/cidy02/kudos/onboarding/SyncFolderOnboardingScreen.kt:232` |
| To let another device remove items from your library, pair it in Settings → Sync Folder → Deletion signing. Pairing takes a few seconds. | To let another device remove items from your library, pair it in Settings → Sync Folder → Deletion signing. Pairing takes a few seconds. | `kudos-ao3-reader/Features/Onboarding/SyncFolderOnboardingView.swift:76` | `android/app/src/main/java/io/github/cidy02/kudos/onboarding/SyncFolderOnboardingScreen.kt:238` |
| Kudos submits these credentials only to AO3's official login page. Your password is never saved. | Kudos submits these credentials only to AO3's official login page. Your password is never saved. | `kudos-ao3-reader/Features/Auth/AO3LoginView.swift:129` | `android/app/src/main/java/io/github/cidy02/kudos/auth/AO3NativeLoginScreen.kt:172` |
| Complete login on AO3 below. | Let's finish logging in on AO3's page below. | `kudos-ao3-reader/Features/Auth/AO3LoginView.swift:187` | `android/app/src/main/java/io/github/cidy02/kudos/auth/AO3NativeLoginScreen.kt:412` |
| Welcome to Kudos — a native SwiftUI reader for Archive of Our Own. | Welcome to Kudos — a native Android reader for Archive of Our Own. | `kudos-ao3-reader/Features/Support/WhatsNew.swift:21` | `android/app/src/main/java/io/github/cidy02/kudos/support/WhatsNew.kt:36` |
| Found a bug? Describe what happened and Kudos will open a prefilled GitHub issue you can review and post. Nothing is sent automatically. | Found a bug? Describe what happened and Kudos will open a prefilled GitHub issue you can review and post. Nothing is sent automatically. | `kudos-ao3-reader/Features/Support/BugReportView.swift:27` | `android/app/src/main/java/io/github/cidy02/kudos/account/BugReportScreen.kt:74` |
| Only these app and system details are sent with your report. Nothing personal is included, and never your AO3 account. | Only these app and system details are sent with your report. Nothing personal is included, and never your AO3 account. | `kudos-ao3-reader/Features/Support/BugReportView.swift:48` | `android/app/src/main/java/io/github/cidy02/kudos/account/BugReportScreen.kt:119` |

## 5. N — not applicable

- `kudos-ao3-reader/Features/Search/MediaBrowserView.swift:359` "Browse by fandom". macOS category list, inside the `#else` of `#if os(iOS)` (`:334`).
- `kudos-ao3-reader/Features/Search/MediaBrowserView.swift:388` "Popular fandoms from AO3. Tap one to search its works." The `#else` of `instructions` (`:385-388`). The iOS sentence is different and was not a not-found row.
- `kudos-ao3-reader/Features/Search/FandomListView.swift:632` "classmates - RPF". A doc comment on a `CharacterSet`, not shown.
- `kudos-ao3-reader/Features/Account/AO3PreferencesView.swift:80` "My Preferences". `navigationTitle` inside `#if os(macOS)` (`:79-81`).
- `kudos-ao3-reader/Features/Account/AccountInboxViews.swift:730` "See All Comments". Drawn only when `onSeeAll` is set (`AccountInboxScreen.swift:77`). The inbox construction (`AccountInboxScreen.swift:187-195`) leaves `onSeeAll` nil (`AccountInboxViews.swift:515`). Not shown.
- `kudos-ao3-reader/Features/Authors/AO3SeriesDetailView.swift:111` "Edit series". Known. This brief, lines 34–37. `docs/android-port/briefs/3bw-series-edit.md:42-48` (there is no `3bw-result.md`): a writer cannot change a series on Android.
- `kudos-ao3-reader/Features/Authors/AuthorProfileView.swift:99` "This permanently removes the work…". Known, Delete of a work. This brief, lines 34–37. `docs/android-port/briefs/3bd-result.md:108`: Delete on AO3 / Cancel, not built in that brief.
- `kudos-ao3-reader/Features/Authors/AuthorProfileView.swift:108` "Couldn't delete". Same known delete. The failure alert of that confirmation.
- `kudos-ao3-reader/Features/Authors/AuthorProfileView.swift:623` "Choose the works to edit, then try again." Known, edit multiple works. This brief, lines 34–37. Empty bulk-edit destination.
- `kudos-ao3-reader/Features/Support/BugReportView.swift:104` "Include a screenshot". Known. `docs/android-port/briefs/6a-result.md:49`: the screenshot section is left out.
- `BugReportView.swift:117` "Attached screenshot preview". Same known section.
- `BugReportView.swift:120` "Kudos screenshot". Same.
- `BugReportView.swift:122` "Save or Share Screenshot". Same.
- `BugReportView.swift:126` "Screenshot". Same.
- `BugReportView.swift:128` "GitHub can't add the screenshot for you. …". Same.
- `BugReportView.swift:161` "Screenshot: attached below (added separately)". Same.

## 6. What was not read

- Strings inside `#Preview`, `#if DEBUG`, and comments, except the three N rows that are themselves a macOS branch or the "classmates - RPF" comment.
- Android test sources.
- Briefs other than the lines cited above (`3ak`, `3ax`, `3l`, `3ba`, `3bb`, `3bp`, `3bq`, `3bt`, `3bu` were not re-read past the known-missing names in this brief).
- Live AO3. No sign-in. Neither app was run.
- The per-work HTTP call inside the availability sweep. The two not-found sentences match, and `docs/android-port/briefs/6a-result.md:55-68` already records that screen.
- The body of the work-delete request. Those two rows are N.
- The subscription POST is the scraped `form.actionURL` (`AO3AuthorProfileService.swift:909-917`). No path was synthesized for it.
- Comment-cache storage past `AO3CommentRepository.kt:48-50`.
- How `series.url` is first built. The series stale row cites `seriesPageURL(series.url, page:)` only.

## Triage (Claude, 2026-10-08, first pass)

Grok classed all 132 rows: 21 missing, 49 behaving differently, 46 worded differently, 16 not
applicable. It also corrects the triage of A9: five Search and Browse rows are missing
features, not wording. The three gravest were read against both codebases and fixed at once:

- **Clear Reading History took every finished work**, saved and downloaded ones included,
  under a message promising otherwise. **P1, fixed** (`903ec596`): only works left in the
  history alone, as iOS, and none still in a queue.
- **Clear reading positions did nothing.** **P2, fixed** (`903ec596`).
- **"Delete from History" hid the row and told AO3 nothing.** **P2, fixed**: iOS's write
  (`deleteReading`: a fresh token from the history page, one POST with the reading's id),
  the row removed only on AO3's confirmation, seen in the demo. The screen's "Clear your
  entire history" confirmation has no control that opens it; iOS's write for it
  (`clearReadingHistory`) is not built.

**Missing features to brief** (none reads or writes AO3 unless said):
the Account shortcut editor (choose, reorder, reset the grid: local); the account-wide
"Manage collection items" card (one GET on tap); a chapter's comments from an inbox row;
Share Profile on an author page; the Privacy page's Read Aloud section; "Showing cached AO3
data" on five screens; a fandom's most-used tags in the tag picker (one GET per fandom);
sort and completion on an author's works (a reload with a query); a bookmark button in the
in-app browser (local); "Nearby" pages in the page jump; "Show in Library" after an import.

**Behaviour to bring in line** (the ones a reader would meet): the comment composer's
"checking whether this posted" state with Check Again; the offline banner over cached
comments; an author page's later-page failure (no error, no retry today); subscribing to an
author from the app with iOS's confirmation (Android opens the browser); the History and
Subscriptions signed-out and empty states; the tag page's two empty states with Clear
Filters; accessibility names on comment avatars, the fandom index strip and blurred works in
selection.

The 46 wording rows are a table in the file: one mechanical batch.
