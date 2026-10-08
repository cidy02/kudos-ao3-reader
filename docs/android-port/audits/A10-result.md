# Audit A10: a string check, Account, Bookmarks and Authors

## 1. Counts

- iOS files read: 34
- Strings checked: 480
- Found: 392
- Not found: 88

## 2. Not found on Android

### `kudos-ao3-reader/Features/Account/AO3CollectionDetailView.swift`
| String | iOS path:line | Kind | Exact Search Ran | Nearest Android File |
|---|---|---|---|---|
| ` work\(count == 1 ? ` | `kudos-ao3-reader/Features/Account/AO3CollectionDetailView.swift:643` | Text | `" work\(count == 1 ? "` | `android/app/src/main/java/io/github/cidy02/kudos/account/AO3CollectionDetailScreen.kt` |


### `kudos-ao3-reader/Features/Account/AO3CollectionsList.swift`
| String | iOS path:line | Kind | Exact Search Ran | Nearest Android File |
|---|---|---|---|---|
| `These are your AO3 collections. Collections you make in Kudos are in Library.` | `kudos-ao3-reader/Features/Account/AO3CollectionsList.swift:382` | Text | `"These are your AO3 collections. Collections you make in Kudos are in Library."` | `android/app/src/main/java/io/github/cidy02/kudos/account/AO3CollectionsScreen.kt` |


### `kudos-ao3-reader/Features/Account/AO3DashboardView.swift`
| String | iOS path:line | Kind | Exact Search Ran | Nearest Android File |
|---|---|---|---|---|
| `Log in to AO3 to open your dashboard.` | `kudos-ao3-reader/Features/Account/AO3DashboardView.swift:26` | Text | `"Log in to AO3 to open your dashboard."` | `android/app/src/main/java/io/github/cidy02/kudos/account/AO3DashboardScreen.kt` |


### `kudos-ao3-reader/Features/Account/AO3PreferencesView.swift`
| String | iOS path:line | Kind | Exact Search Ran | Nearest Android File |
|---|---|---|---|---|
| `Couldn't load preferences` | `kudos-ao3-reader/Features/Account/AO3PreferencesView.swift:59` | Label | `"Couldn't load preferences"` | `android/app/src/main/java/io/github/cidy02/kudos/account/AO3PreferencesScreen.kt` |
| `My Preferences` | `kudos-ao3-reader/Features/Account/AO3PreferencesView.swift:77` | navigationTitle | `"My Preferences"` | `android/app/src/main/java/io/github/cidy02/kudos/account/AO3PreferencesScreen.kt` |
| `Couldn't load help` | `kudos-ao3-reader/Features/Account/AO3PreferencesView.swift:265` | Label | `"Couldn't load help"` | `android/app/src/main/java/io/github/cidy02/kudos/account/AO3PreferencesScreen.kt` |
| `Your AO3 session expired. Sign in again from Account.` | `kudos-ao3-reader/Features/Account/AO3PreferencesView.swift:485` | Error banner | `"Your AO3 session expired. Sign in again from Account."` | `android/app/src/main/java/io/github/cidy02/kudos/account/AO3PreferencesScreen.kt` |


### `kudos-ao3-reader/Features/Account/AccountComponents.swift`
| String | iOS path:line | Kind | Exact Search Ran | Nearest Android File |
|---|---|---|---|---|
| `Restoring AO3 session` | `kudos-ao3-reader/Features/Account/AccountComponents.swift:49` | Label | `"Restoring AO3 session"` | `none` |
| `Restoring AO3 session` | `kudos-ao3-reader/Features/Account/AccountComponents.swift:49` | accessibilityLabel | `"Restoring AO3 session"` | `none` |
| `View Profile` | `kudos-ao3-reader/Features/Account/AccountComponents.swift:70` | Label | `"View Profile"` | `none` |
| `View Profile` | `kudos-ao3-reader/Features/Account/AccountComponents.swift:70` | accessibilityLabel | `"View Profile"` | `none` |
| `Posting as \(postingPseudName ?? ` | `kudos-ao3-reader/Features/Account/AccountComponents.swift:133` | Text | `"Posting as \(postingPseudName ?? "` | `none` |
| `Account actions` | `kudos-ao3-reader/Features/Account/AccountComponents.swift:282` | Label | `"Account actions"` | `none` |
| `Account actions` | `kudos-ao3-reader/Features/Account/AccountComponents.swift:282` | accessibilityLabel | `"Account actions"` | `none` |


### `kudos-ao3-reader/Features/Account/AccountInboxViews.swift`
| String | iOS path:line | Kind | Exact Search Ran | Nearest Android File |
|---|---|---|---|---|
| `Works Filters` | `kudos-ao3-reader/Features/Account/AccountInboxViews.swift:108` | title | `"Works Filters"` | `none` |
| `Select Inbox Items` | `kudos-ao3-reader/Features/Account/AccountInboxViews.swift:116` | title | `"Select Inbox Items"` | `none` |
| `Open Chapter Comments` | `kudos-ao3-reader/Features/Account/AccountInboxViews.swift:246` | Button | `"Open Chapter Comments"` | `none` |
| `Chapter Comments` | `kudos-ao3-reader/Features/Account/AccountInboxViews.swift:439` | Label | `"Chapter Comments"` | `none` |
| `Comments on your works and replies to your comments appear here ` | `kudos-ao3-reader/Features/Account/AccountInboxViews.swift:537` | message | `"Comments on your works and replies to your comments appear here "` | `none` |
| `Couldn't load page ` | `kudos-ao3-reader/Features/Account/AccountInboxViews.swift:545` | title | `"Couldn't load page "` | `none` |
| `Showing cached AO3 data` | `kudos-ao3-reader/Features/Account/AccountInboxViews.swift:713` | Label | `"Showing cached AO3 data"` | `none` |
| `See All Comments` | `kudos-ao3-reader/Features/Account/AccountInboxViews.swift:730` | Text | `"See All Comments"` | `none` |


### `kudos-ao3-reader/Features/Account/AccountMoreOnAO3View.swift`
| String | iOS path:line | Kind | Exact Search Ran | Nearest Android File |
|---|---|---|---|---|
| `Manage collection items` | `kudos-ao3-reader/Features/Account/AccountMoreOnAO3View.swift:169` | title | `"Manage collection items"` | `android/app/src/main/java/io/github/cidy02/kudos/account/AccountMoreOnAO3Screen.kt` |
| `Related works` | `kudos-ao3-reader/Features/Account/AccountMoreOnAO3View.swift:176` | title | `"Related works"` | `android/app/src/main/java/io/github/cidy02/kudos/account/AccountMoreOnAO3Screen.kt` |
| `Skins and site styles` | `kudos-ao3-reader/Features/Account/AccountMoreOnAO3View.swift:218` | title | `"Skins and site styles"` | `android/app/src/main/java/io/github/cidy02/kudos/account/AccountMoreOnAO3Screen.kt` |
| `Gifts given and received` | `kudos-ao3-reader/Features/Account/AccountMoreOnAO3View.swift:279` | title | `"Gifts given and received"` | `android/app/src/main/java/io/github/cidy02/kudos/account/AccountMoreOnAO3Screen.kt` |


### `kudos-ao3-reader/Features/Account/AccountShortcuts.swift`
| String | iOS path:line | Kind | Exact Search Ran | Nearest Android File |
|---|---|---|---|---|
| `On the grid` | `kudos-ao3-reader/Features/Account/AccountShortcuts.swift:127` | Text | `"On the grid"` | `none` |
| `If you choose none, the grid is hidden. You can still find every ` | `kudos-ao3-reader/Features/Account/AccountShortcuts.swift:130` | Text | `"If you choose none, the grid is hidden. You can still find every "` | `none` |
| `Reset to Default` | `kudos-ao3-reader/Features/Account/AccountShortcuts.swift:144` | Button | `"Reset to Default"` | `none` |


### `kudos-ao3-reader/Features/Account/AccountView.swift`
| String | iOS path:line | Kind | Exact Search Ran | Nearest Android File |
|---|---|---|---|---|
| `Account Content` | `kudos-ao3-reader/Features/Account/AccountView.swift:326` | Label | `"Account Content"` | `android/app/src/main/java/io/github/cidy02/kudos/account/AccountScreen.kt` |
| `Account Content` | `kudos-ao3-reader/Features/Account/AccountView.swift:326` | accessibilityLabel | `"Account Content"` | `android/app/src/main/java/io/github/cidy02/kudos/account/AccountScreen.kt` |
| `Profile unavailable` | `kudos-ao3-reader/Features/Account/AccountView.swift:718` | title | `"Profile unavailable"` | `android/app/src/main/java/io/github/cidy02/kudos/account/AccountScreen.kt` |
| `AO3 could not load your profile. It may be temporarily unavailable.` | `kudos-ao3-reader/Features/Account/AccountView.swift:720` | message | `"AO3 could not load your profile. It may be temporarily unavailable."` | `android/app/src/main/java/io/github/cidy02/kudos/account/AccountScreen.kt` |
| `Couldn't load your profile` | `kudos-ao3-reader/Features/Account/AccountView.swift:725` | title | `"Couldn't load your profile"` | `android/app/src/main/java/io/github/cidy02/kudos/account/AccountScreen.kt` |
| `Showing cached AO3 data` | `kudos-ao3-reader/Features/Account/AccountView.swift:736` | Label | `"Showing cached AO3 data"` | `android/app/src/main/java/io/github/cidy02/kudos/account/AccountScreen.kt` |
| `Showing cached AO3 data` | `kudos-ao3-reader/Features/Account/AccountView.swift:742` | Label | `"Showing cached AO3 data"` | `android/app/src/main/java/io/github/cidy02/kudos/account/AccountScreen.kt` |


### `kudos-ao3-reader/Features/Account/AvailabilitySweepView.swift`
| String | iOS path:line | Kind | Exact Search Ran | Nearest Android File |
|---|---|---|---|---|
| `) imported ` | `kudos-ao3-reader/Features/Account/AvailabilitySweepView.swift:98` | Text | `") imported "` | `none` |
| `Kudos marked them as no longer on AO3. Any downloaded copies are now ` | `kudos-ao3-reader/Features/Account/AvailabilitySweepView.swift:138` | Text | `"Kudos marked them as no longer on AO3. Any downloaded copies are now "` | `none` |


### `kudos-ao3-reader/Features/Account/PrivacyDataView.swift`
| String | iOS path:line | Kind | Exact Search Ran | Nearest Android File |
|---|---|---|---|---|
| `Read Aloud downloads` | `kudos-ao3-reader/Features/Account/PrivacyDataView.swift:107` | title | `"Read Aloud downloads"` | `none` |
| `Clear \(countLabel(freedHistory.count, ` | `kudos-ao3-reader/Features/Account/PrivacyDataView.swift:123` | Button | `"Clear \(countLabel(freedHistory.count, "` | `none` |
| `Moves works that only remain in your reading history to Recently Deleted for ` | `kudos-ao3-reader/Features/Account/PrivacyDataView.swift:130` | Text | `"Moves works that only remain in your reading history to Recently Deleted for "` | `none` |
| `Free \(countLabel(freeableDownloads.count, ` | `kudos-ao3-reader/Features/Account/PrivacyDataView.swift:139` | Button | `"Free \(countLabel(freeableDownloads.count, "` | `none` |
| `Clear \(countLabel(positionedWorks.count, ` | `kudos-ao3-reader/Features/Account/PrivacyDataView.swift:153` | Button | `"Clear \(countLabel(positionedWorks.count, "` | `none` |
| `Clears your place in every work. Your works and their order in Continue Reading ` | `kudos-ao3-reader/Features/Account/PrivacyDataView.swift:158` | Text | `"Clears your place in every work. Your works and their order in Continue Reading "` | `none` |
| `Removes saved fandom and category lists. Your reading, saved works, and ` | `kudos-ao3-reader/Features/Account/PrivacyDataView.swift:173` | Text | `"Removes saved fandom and category lists. Your reading, saved works, and "` | `none` |
| `Optional Voice Pack downloads stay separate from your reading data.` | `kudos-ao3-reader/Features/Account/PrivacyDataView.swift:423` | Text | `"Optional Voice Pack downloads stay separate from your reading data."` | `none` |
| `Kudos never sends a work's text, spoken audio, your AO3 sign-in, saved works, ` | `kudos-ao3-reader/Features/Account/PrivacyDataView.swift:426` | Text | `"Kudos never sends a work's text, spoken audio, your AO3 sign-in, saved works, "` | `none` |


### `kudos-ao3-reader/Features/Authors/AO3SeriesDetailView.swift`
| String | iOS path:line | Kind | Exact Search Ran | Nearest Android File |
|---|---|---|---|---|
| `Showing cached AO3 data` | `kudos-ao3-reader/Features/Authors/AO3SeriesDetailView.swift:60` | Label | `"Showing cached AO3 data"` | `none` |
| `Edit series` | `kudos-ao3-reader/Features/Authors/AO3SeriesDetailView.swift:111` | Label | `"Edit series"` | `none` |


### `kudos-ao3-reader/Features/Authors/AuthorProfileComponents.swift`
| String | iOS path:line | Kind | Exact Search Ran | Nearest Android File |
|---|---|---|---|---|
| `) words` | `kudos-ao3-reader/Features/Authors/AuthorProfileComponents.swift:242` | Text | `") words"` | `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileComponents.kt` |
| `Loading author profile` | `kudos-ao3-reader/Features/Authors/AuthorProfileComponents.swift:544` | Label | `"Loading author profile"` | `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileComponents.kt` |
| `Loading author profile` | `kudos-ao3-reader/Features/Authors/AuthorProfileComponents.swift:544` | accessibilityLabel | `"Loading author profile"` | `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileComponents.kt` |


### `kudos-ao3-reader/Features/Authors/AuthorProfileContentSections.swift`
| String | iOS path:line | Kind | Exact Search Ran | Nearest Android File |
|---|---|---|---|---|
| `Try Loading More` | `kudos-ao3-reader/Features/Authors/AuthorProfileContentSections.swift:83` | Button | `"Try Loading More"` | `none` |
| `You have not made a series.` | `kudos-ao3-reader/Features/Authors/AuthorProfileContentSections.swift:482` | Text | `"You have not made a series."` | `none` |
| `A series groups your works in reading order. Create one on AO3, ` | `kudos-ao3-reader/Features/Authors/AuthorProfileContentSections.swift:484` | Text | `"A series groups your works in reading order. Create one on AO3, "` | `none` |
| `New series on AO3` | `kudos-ao3-reader/Features/Authors/AuthorProfileContentSections.swift:498` | title | `"New series on AO3"` | `none` |
| `This opens AO3 in Browse, where you can create the series.` | `kudos-ao3-reader/Features/Authors/AuthorProfileContentSections.swift:506` | Text | `"This opens AO3 in Browse, where you can create the series."` | `none` |


### `kudos-ao3-reader/Features/Authors/AuthorProfileView.swift`
| String | iOS path:line | Kind | Exact Search Ran | Nearest Android File |
|---|---|---|---|---|
| `This permanently removes the work and its chapters, kudos, comments and bookmarks ` | `kudos-ao3-reader/Features/Authors/AuthorProfileView.swift:99` | Text | `"This permanently removes the work and its chapters, kudos, comments and bookmarks "` | `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt` |
| `Couldn’t delete` | `kudos-ao3-reader/Features/Authors/AuthorProfileView.swift:108` | alert | `"Couldn’t delete"` | `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt` |
| `AO3 Profile` | `kudos-ao3-reader/Features/Authors/AuthorProfileView.swift:119` | alert | `"AO3 Profile"` | `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt` |
| `Log in to your AO3 account to do this.` | `kudos-ao3-reader/Features/Authors/AuthorProfileView.swift:149` | Text | `"Log in to your AO3 account to do this."` | `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt` |
| `Unsubscribing here applies to the whole AO3 account, not only this pseud.` | `kudos-ao3-reader/Features/Authors/AuthorProfileView.swift:161` | Text | `"Unsubscribing here applies to the whole AO3 account, not only this pseud."` | `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt` |
| `Showing cached AO3 data` | `kudos-ao3-reader/Features/Authors/AuthorProfileView.swift:251` | Label | `"Showing cached AO3 data"` | `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt` |
| `Author scope` | `kudos-ao3-reader/Features/Authors/AuthorProfileView.swift:419` | Label | `"Author scope"` | `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt` |
| `Author scope` | `kudos-ao3-reader/Features/Authors/AuthorProfileView.swift:419` | accessibilityLabel | `"Author scope"` | `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt` |
| `Choose the works to edit, then try again.` | `kudos-ao3-reader/Features/Authors/AuthorProfileView.swift:623` | Text | `"Choose the works to edit, then try again."` | `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt` |
| `Author unavailable` | `kudos-ao3-reader/Features/Authors/AuthorProfileView.swift:701` | Label | `"Author unavailable"` | `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt` |
| `AO3 could not find this user or pseud. It may have been renamed or deleted.` | `kudos-ao3-reader/Features/Authors/AuthorProfileView.swift:703` | Text | `"AO3 could not find this user or pseud. It may have been renamed or deleted."` | `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt` |
| `AO3 Author` | `kudos-ao3-reader/Features/Authors/AuthorProfileView.swift:733` | kicker | `"AO3 Author"` | `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt` |
| `Share Profile` | `kudos-ao3-reader/Features/Authors/AuthorProfileView.swift:878` | Label | `"Share Profile"` | `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt` |


### `kudos-ao3-reader/Features/Bookmarks/AO3AccountWorksList.swift`
| String | iOS path:line | Kind | Exact Search Ran | Nearest Android File |
|---|---|---|---|---|
| `No works on this page match the current filters.` | `kudos-ao3-reader/Features/Bookmarks/AO3AccountWorksList.swift:713` | Text | `"No works on this page match the current filters."` | `none` |


### `kudos-ao3-reader/Features/Bookmarks/AO3HistoryWorksBrowser.swift`
| String | iOS path:line | Kind | Exact Search Ran | Nearest Android File |
|---|---|---|---|---|
| `Delete from history` | `kudos-ao3-reader/Features/Bookmarks/AO3HistoryWorksBrowser.swift:145` | Label | `"Delete from history"` | `none` |


### `kudos-ao3-reader/Features/Bookmarks/AO3NamedSubscriptionsList.swift`
| String | iOS path:line | Kind | Exact Search Ran | Nearest Android File |
|---|---|---|---|---|
| `Log in to AO3 to see your subscriptions.` | `kudos-ao3-reader/Features/Bookmarks/AO3NamedSubscriptionsList.swift:238` | message | `"Log in to AO3 to see your subscriptions."` | `none` |


### `kudos-ao3-reader/Features/Comments/CommentMarkup.swift`
| String | iOS path:line | Kind | Exact Search Ran | Nearest Android File |
|---|---|---|---|---|
| `Heading ` | `kudos-ao3-reader/Features/Comments/CommentMarkup.swift:487` | Label | `"Heading "` | `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentMarkup.kt` |
| `Heading ` | `kudos-ao3-reader/Features/Comments/CommentMarkup.swift:487` | accessibilityLabel | `"Heading "` | `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentMarkup.kt` |


### `kudos-ao3-reader/Features/Comments/CommentThreadRow.swift`
| String | iOS path:line | Kind | Exact Search Ran | Nearest Android File |
|---|---|---|---|---|
| `Continue thread, ` | `kudos-ao3-reader/Features/Comments/CommentThreadRow.swift:876` | Label | `"Continue thread, "` | `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentThreadScreen.kt` |
| `Continue thread, ` | `kudos-ao3-reader/Features/Comments/CommentThreadRow.swift:876` | accessibilityLabel | `"Continue thread, "` | `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentThreadScreen.kt` |
| `Replying to you` | `kudos-ao3-reader/Features/Comments/CommentThreadRow.swift:1213` | Text | `"Replying to you"` | `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentThreadScreen.kt` |
| `'s profile` | `kudos-ao3-reader/Features/Comments/CommentThreadRow.swift:1680` | Label | `"'s profile"` | `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentThreadScreen.kt` |
| `'s profile` | `kudos-ao3-reader/Features/Comments/CommentThreadRow.swift:1680` | accessibilityLabel | `"'s profile"` | `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentThreadScreen.kt` |


### `kudos-ao3-reader/Features/Comments/CommentsView.swift`
| String | iOS path:line | Kind | Exact Search Ran | Nearest Android File |
|---|---|---|---|---|
| `You're offline. These comments are from ` | `kudos-ao3-reader/Features/Comments/CommentsView.swift:758` | Text | `"You're offline. These comments are from "` | `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsScreen.kt` |
| `Browse Comments by Chapter` | `kudos-ao3-reader/Features/Comments/CommentsView.swift:976` | navigationTitle | `"Browse Comments by Chapter"` | `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsScreen.kt` |
| `) left` | `kudos-ao3-reader/Features/Comments/CommentsView.swift:1389` | Text | `") left"` | `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsScreen.kt` |
| `'s profile` | `kudos-ao3-reader/Features/Comments/CommentsView.swift:1459` | Label | `"'s profile"` | `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsScreen.kt` |
| `'s profile` | `kudos-ao3-reader/Features/Comments/CommentsView.swift:1459` | accessibilityLabel | `"'s profile"` | `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsScreen.kt` |
| `We're checking whether this posted before trying again…` | `kudos-ao3-reader/Features/Comments/CommentsView.swift:1493` | Label | `"We're checking whether this posted before trying again…"` | `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsScreen.kt` |
| `Check Again` | `kudos-ao3-reader/Features/Comments/CommentsView.swift:1507` | Label | `"Check Again"` | `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsScreen.kt` |
| `Posted.` | `kudos-ao3-reader/Features/Comments/CommentsView.swift:1517` | Label | `"Posted."` | `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsScreen.kt` |


## 3. Found, but worded differently on Android

| iOS String | Android String | iOS path:line | Android path:line |
|---|---|---|---|
| (None observed during mechanical check) | | | |

## 4. What was not read

- Strings that are only in comments
- Strings in `#Preview` blocks
- Strings in debug-only code (`#if DEBUG`)
- Log messages
- Excluded files outside the specified directories
- Strings mapped from single-character symbols (e.g. "B", "I" for bold/italics in CommentMarkup)
- Strings existing only in Android test directory (`android/app/src/test/`)