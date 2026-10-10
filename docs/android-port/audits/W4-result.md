# W4 Audit: Words on Three Android Screens Beside iOS's

Android strings found: 137
DIFFERS: 2
NO IOS STRING: 13
(SAME: 122)

- **Android path**: `/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/`
- **iOS path**: `kudos-ao3-reader/`

---

## Table 1: Differing and Missing Strings (DIFFERS & NO IOS STRING)

### Pair 1: Own Works Controls and Profile
- **Android**: `author/OwnWorksControls.kt`, and the own-works parts of `author/AuthorProfileScreen.kt`
- **iOS**: `Features/Authors/OwnWorksBulkBar.swift`, `Features/Authors/AuthorProfileView.swift`, `Features/Authors/WorksScopeAndSort.swift`

| Android String (`path:line`) | iOS String (`path:line`) | Status | Notes / Words Searched |
|---|---|---|---|
| `"Actions for ${work.title}"` (`author/OwnWorksControls.kt:89`) | *None* | **NO IOS STRING** | Searched `OwnWorksBulkBar.swift`, `AuthorProfileView.swift`, `WorksScopeAndSort.swift` for `"Actions"`, `"for"`, `"title"`. iOS uses `.swipeActions` on the work row and does not draw an overflow actions menu button. |
| `"Deselect ${work.title}"` (`author/AuthorProfileScreen.kt:645`) | `"Double-tap to deselect this work."` (`Features/Authors/AuthorProfileContentSections.swift:440`) | **DIFFERS** | Android TalkBack contentDescription on selection checkbox: `"Deselect ${work.title}"`. iOS VoiceOver accessibility label is `.accessibilityLabel(work.title)` with accessibilityHint `"Double-tap to deselect this work."`. |
| `"Select ${work.title}"` (`author/AuthorProfileScreen.kt:645`) | `"Double-tap to select this work."` (`Features/Authors/AuthorProfileContentSections.swift:440`) | **DIFFERS** | Android TalkBack contentDescription on selection checkbox: `"Select ${work.title}"`. iOS VoiceOver accessibility label is `.accessibilityLabel(work.title)` with accessibilityHint `"Double-tap to select this work."`. |

---

### Pair 2: Writing Bulk Edit
- **Android**: `writing/WritingBulkEditScreen.kt`
- **iOS**: `Features/Writing/EditMultipleWorksView.swift`

| Android String (`path:line`) | iOS String (`path:line`) | Status | Notes / Words Searched |
|---|---|---|---|
| `"Try Again"` (`writing/WritingBulkEditScreen.kt:92`) | *None* | **NO IOS STRING** | Searched `EditMultipleWorksView.swift` for `"Try"`, `"Again"`, `"retry"`. Not present in `EditMultipleWorksView.swift` (retry button is rendered by caller `WritingBulkEditDestination` in `WritingDraftsView.swift:446`). |
| `"Loading ${model.ids.size} works…"` (`writing/WritingBulkEditScreen.kt:95`) | *None* | **NO IOS STRING** | Searched `EditMultipleWorksView.swift` for `"Loading"`, `"works"`, `"works…"`. Not present in `EditMultipleWorksView.swift` (loading progress indicator is rendered by caller `WritingBulkEditDestination` in `WritingDraftsView.swift:449`). |
| `"Selected"` (`writing/WritingBulkEditScreen.kt:189`) | *None* | **NO IOS STRING** | Searched `EditMultipleWorksView.swift` for `"Selected"`, `"scalars"`, `"option"`. iOS uses native SwiftUI inline `Picker` menus with system checkmarks for scalar options rather than rendering `"Selected"` text. |

---

### Pair 3: Challenge Assignments
- **Android**: `account/AO3ChallengeAssignmentsScreen.kt` (and `account/AO3ChallengeAssignmentsState.kt`)
- **iOS**: `Features/Challenges/ChallengeAssignmentsView.swift` and the files it uses in `Features/Challenges/`

| Android String (`path:line`) | iOS String (`path:line`) | Status | Notes / Words Searched |
|---|---|---|---|
| `"Refresh assignments"` (`account/AO3ChallengeAssignmentsScreen.kt:67`) | *None* | **NO IOS STRING** | Searched `ChallengeAssignmentsView.swift` for `"Refresh"`, `"assignments"`, `"toolbar"`. iOS uses pull-to-refresh (`.refreshable`) and draws no toolbar refresh button. |
| `"AO3 shows assignments to collection owners and moderators after sign-ups close."` (`account/AO3ChallengeAssignmentsState.kt:108`) | *None* | **NO IOS STRING** | Searched `ChallengeAssignmentsView.swift` and `Features/Challenges/` for `"moderators"`, `"assignments"`, `"sign-ups"`. Not present in iOS challenges views. |
| `"AO3 shows assignments to maintainers after sign-ups close."` (`account/AO3ChallengeAssignmentsState.kt:116`) | *None* | **NO IOS STRING** | Searched `ChallengeAssignmentsView.swift` and `Features/Challenges/` for `"maintainers"`, `"assignments"`, `"sign-ups"`. Not present in iOS challenges views. |
| `"Kudos can't confirm that sign-ups are closed."` (`account/AO3ChallengeAssignmentsState.kt:126`) | *None* | **NO IOS STRING** | Searched `ChallengeAssignmentsView.swift` and `Features/Challenges/` for `"confirm"`, `"sign-ups"`, `"closed"`. Not present in iOS challenges views. |
| `"Dismiss error"` (`account/AO3ChallengeAssignmentsScreen.kt:120`) | *None* | **NO IOS STRING** | Searched `ChallengeAssignmentsView.swift` for `"Dismiss"`, `"error"`, `"xmark"`. iOS xmark button has no text label or accessibility label (`ChallengeAssignmentsView.swift:600-602`). |
| `"Load more complete assignments"` (`account/AO3ChallengeAssignmentsScreen.kt:268`) | *None* | **NO IOS STRING** | Searched `ChallengeAssignmentsView.swift` for `"Load"`, `"complete"`, `"assignments"`. iOS fetches all pages at once via `allPages(of:)` and does not provide pagination buttons. |
| `"Load more open assignments"` (`account/AO3ChallengeAssignmentsScreen.kt:269`) | *None* | **NO IOS STRING** | Searched `ChallengeAssignmentsView.swift` for `"Load"`, `"open"`, `"assignments"`. iOS fetches all pages at once via `allPages(of:)`. |
| `"Load more defaulted assignments"` (`account/AO3ChallengeAssignmentsScreen.kt:270`) | *None* | **NO IOS STRING** | Searched `ChallengeAssignmentsView.swift` for `"Load"`, `"defaulted"`, `"assignments"`. iOS fetches all pages at once via `allPages(of:)`. |
| `"Load more pinch hits"` (`account/AO3ChallengeAssignmentsScreen.kt:271`) | *None* | **NO IOS STRING** | Searched `ChallengeAssignmentsView.swift` for `"Load"`, `"pinch"`, `"hits"`. iOS fetches all pages at once via `allPages(of:)`. |

---

## Table 2: Identical Strings (SAME)

### Pair 1: Own Works Controls and Profile
- **Android**: `author/OwnWorksControls.kt`, and the own-works parts of `author/AuthorProfileScreen.kt`
- **iOS**: `Features/Authors/OwnWorksBulkBar.swift`, `Features/Authors/AuthorProfileView.swift`, `Features/Authors/WorksScopeAndSort.swift`

| # | Android String (`path:line`) | iOS String (`path:line`) | Status |
|---|---|---|---|
| 1 | `"Delete “${works.first().title}”?"` (`author/OwnWorksControls.kt:24`) | `"Delete “\(works[0].title)”?"` (`Features/Authors/OwnWorksBulkBar.swift:28`) | **SAME** |
| 2 | `"Delete ${works.size} works?"` (`author/OwnWorksControls.kt:24`) | `"Delete \(works.count) works?"` (`Features/Authors/OwnWorksBulkBar.swift:28`) | **SAME** |
| 3 | `"This permanently removes the work and its chapters, kudos, comments and bookmarks from AO3 for everyone."` (`author/OwnWorksControls.kt:26`) | `"This permanently removes the work and its chapters, kudos, comments and bookmarks from AO3 for everyone."` (`Features/Authors/OwnWorksBulkBar.swift:35-36`, `AuthorProfileView.swift:99-100`) | **SAME** |
| 4 | `"This permanently removes $titles and their chapters, kudos, comments and bookmarks from AO3 for everyone."` (`author/OwnWorksControls.kt:28`) | `"This permanently removes \(titles) and their chapters, kudos, comments and bookmarks from AO3 for everyone."` (`Features/Authors/OwnWorksBulkBar.swift:39-40`) | **SAME** |
| 5 | `"Your AO3 session changed, so nothing was deleted."` (`author/OwnWorksControls.kt:54`) | `"Your AO3 session changed, so nothing was deleted."` (`Features/Authors/OwnWorksBulkBar.swift:77`) | **SAME** |
| 6 | `"Edit $count"` (`author/OwnWorksControls.kt:68`) | `"Edit \(selectedCount)"` (`Features/Authors/OwnWorksBulkBar.swift:14`) | **SAME** |
| 7 | `"Edit"` (`author/OwnWorksControls.kt:68`) | `"Edit"` (`Features/Authors/OwnWorksBulkBar.swift:14`) | **SAME** |
| 8 | `"Collections"` (`author/OwnWorksControls.kt:69`) | `"Collections"` (`Features/Authors/OwnWorksBulkBar.swift:16`) | **SAME** |
| 9 | `"Visibility"` (`author/OwnWorksControls.kt:69`) | `"Visibility"` (`Features/Authors/OwnWorksBulkBar.swift:18`) | **SAME** |
| 10 | `"Delete"` (`author/OwnWorksControls.kt:69`) | `"Delete"` (`Features/Authors/OwnWorksBulkBar.swift:20`) | **SAME** |
| 11 | `"Delete"` (`author/OwnWorksControls.kt:91`) | `"Delete"` (`Features/Authors/AuthorProfileContentSections.swift:394`) | **SAME** |
| 12 | `"Chapter"` (`author/OwnWorksControls.kt:91`) | `"Chapter"` (`Features/Authors/AuthorProfileContentSections.swift:401`) | **SAME** |
| 13 | `"Tags"` (`author/OwnWorksControls.kt:91`) | `"Tags"` (`Features/Authors/AuthorProfileContentSections.swift:409`) | **SAME** |
| 14 | `"Edit"` (`author/OwnWorksControls.kt:91`) | `"Edit"` (`Features/Authors/AuthorProfileContentSections.swift:416`) | **SAME** |
| 15 | `"Delete on AO3"` (`author/AuthorProfileScreen.kt:279`) | `"Delete on AO3"` (`Features/Authors/OwnWorksBulkBar.swift:59`, `AuthorProfileView.swift:96`) | **SAME** |
| 16 | `"Cancel"` (`author/AuthorProfileScreen.kt:280`) | `"Cancel"` (`Features/Authors/OwnWorksBulkBar.swift:60`, `AuthorProfileView.swift:97`) | **SAME** |
| 17 | `"Couldn’t delete"` (`author/AuthorProfileScreen.kt:284`) | `"Couldn’t delete"` (`Features/Authors/AuthorProfileView.swift:108`) | **SAME** |
| 18 | `"OK"` (`author/AuthorProfileScreen.kt:286`) | `"OK"` (`Features/Authors/AuthorProfileView.swift:109`) | **SAME** |
| 19 | `"${selection.selectedIn(works?.works.orEmpty()).size} selected"` (`author/AuthorProfileScreen.kt:290`) | `"\(bulkSelection.selected(in: model.works).count) selected"` (`Features/Authors/AuthorProfileView.swift:833`) | **SAME** |
| 20 | `"Deselect All"` (`author/AuthorProfileScreen.kt:295`) | `"Deselect All"` (`Features/Authors/AuthorProfileView.swift:767`) | **SAME** |
| 21 | `"Select All"` (`author/AuthorProfileScreen.kt:295`) | `"Select All"` (`Features/Authors/AuthorProfileView.swift:767`) | **SAME** |
| 22 | `"Done"` (`author/AuthorProfileScreen.kt:298`) | `"Done"` (`Features/Authors/OwnWorksBulkBar.swift:95`) | **SAME** |
| 23 | `"Sort and filter"` (`author/AuthorProfileScreen.kt:301`) | `"Sort and filter"` (`Features/Authors/WorksScopeAndSort.swift:131`) | **SAME** |
| 24 | `"Select Works"` (`author/AuthorProfileScreen.kt:308`) | `"Select Works"` (`Features/Authors/AuthorProfileView.swift:844`) | **SAME** |
| 25 | `"Works"` (`author/AuthorProfileScreen.kt:622`, `AO3AuthorModels.kt:81`) | `"Works"` (`Features/Authors/WorksScopeAndSort.swift:13`) | **SAME** |
| 26 | `"In collections"` (`author/AuthorProfileScreen.kt:622`, `AO3AuthorModels.kt:82`) | `"In collections"` (`Features/Authors/WorksScopeAndSort.swift:14`) | **SAME** |
| 27 | `"Gifts"` (`author/AuthorProfileScreen.kt:622`, `AO3AuthorModels.kt:83`) | `"Gifts"` (`Features/Authors/WorksScopeAndSort.swift:15`) | **SAME** |
| 28 | `"Your works"` (`author/AuthorProfileScreen.kt:635`) | `"Your works"` (`Features/Authors/AuthorProfileContentSections.swift:349`) | **SAME** |
| 29 | `"${selection.selectedIn(pageData?.works.orEmpty()).size} / ${pageData?.works.orEmpty().size}"` (`author/AuthorProfileScreen.kt:635`) | `"\(selection.count) / \(works.count)"` (`Features/Authors/AuthorProfileContentSections.swift:351, 362`) | **SAME** |

---

### Pair 2: Writing Bulk Edit
- **Android**: `writing/WritingBulkEditScreen.kt`
- **iOS**: `Features/Writing/EditMultipleWorksView.swift`

| # | Android String (`path:line`) | iOS String (`path:line`) | Status |
|---|---|---|---|
| 30 | `"Save"` (`writing/WritingBulkEditScreen.kt:74`) | `"Save"` (`Features/Writing/EditMultipleWorksView.swift:137`) | **SAME** |
| 31 | `"Cancel"` (`writing/WritingBulkEditScreen.kt:76`) | `"Cancel"` (`Features/Writing/EditMultipleWorksView.swift:143`) | **SAME** |
| 32 | `"AO3 could not save the change"` (`writing/WritingBulkEditScreen.kt:81`) | `"AO3 could not save the change"` (`Features/Writing/EditMultipleWorksView.swift:130`) | **SAME** |
| 33 | `"OK"` (`writing/WritingBulkEditScreen.kt:83`) | `"OK"` (`Features/Writing/EditMultipleWorksView.swift:133`) | **SAME** |
| 34 | `"Edit 1 work"` (`writing/WritingBulkEditScreen.kt:87`) | `"Edit 1 work"` (`Features/Writing/EditMultipleWorksView.swift:38`) | **SAME** |
| 35 | `"Edit ${model.ids.size} works"` (`writing/WritingBulkEditScreen.kt:87`) | `"Edit \(form.workIDs.count) works"` (`Features/Writing/EditMultipleWorksView.swift:38`) | **SAME** |
| 36 | `"Your changes apply to every selected work. Use the separate Add and Remove groups for tags. Anything you leave alone stays unchanged."` (`writing/WritingBulkEditScreen.kt:99-100`) | `"Your changes apply to every selected work. Use the separate Add and Remove groups for tags. Anything you leave alone stays unchanged."` (`Features/Writing/EditMultipleWorksView.swift:65-66`) | **SAME** |
| 37 | `"Tags to add"` (`writing/WritingBulkEditScreen.kt:102`) | `"Tags to add"` (`Features/Writing/EditMultipleWorksView.swift:82`) | **SAME** |
| 38 | `"Tags to remove"` (`writing/WritingBulkEditScreen.kt:102`) | `"Tags to remove"` (`Features/Writing/EditMultipleWorksView.swift:85`) | **SAME** |
| 39 | `"Fandoms"` (`writing/WritingBulkEditScreen.kt:155`) | `"Fandoms"` (`Features/Writing/EditMultipleWorksView.swift:187`) | **SAME** |
| 40 | `"Relationships"` (`writing/WritingBulkEditScreen.kt:155`) | `"Relationships"` (`Features/Writing/EditMultipleWorksView.swift:189`) | **SAME** |
| 41 | `"Characters"` (`writing/WritingBulkEditScreen.kt:156`) | `"Characters"` (`Features/Writing/EditMultipleWorksView.swift:196`) | **SAME** |
| 42 | `"Additional tags"` (`writing/WritingBulkEditScreen.kt:156`) | `"Additional tags"` (`Features/Writing/EditMultipleWorksView.swift:202`) | **SAME** |
| 43 | `"Change on all"` (`writing/WritingBulkEditScreen.kt:109`) | `"Change on all"` (`Features/Writing/EditMultipleWorksView.swift:88`) | **SAME** |
| 44 | `"Rating"` (`writing/WritingBulkEditScreen.kt:110`) | `"Rating"` (`Features/Writing/EditMultipleWorksView.swift:212`) | **SAME** |
| 45 | `"Archive warnings"` (`writing/WritingBulkEditScreen.kt:110`) | `"Archive warnings"` (`Features/Writing/EditMultipleWorksView.swift:218`) | **SAME** |
| 46 | `"Categories"` (`writing/WritingBulkEditScreen.kt:111`) | `"Categories"` (`Features/Writing/EditMultipleWorksView.swift:225`) | **SAME** |
| 47 | `"Language"` (`writing/WritingBulkEditScreen.kt:111`) | `"Language"` (`Features/Writing/EditMultipleWorksView.swift:232`) | **SAME** |
| 48 | `"Leave as is"` (`writing/WritingBulkEditScreen.kt:115`) | `"Leave as is"` (`Features/Writing/EditMultipleWorksView.swift:159, 359`) | **SAME** |
| 49 | `"+$adds, -$removes"` (`writing/WritingBulkEditScreen.kt:115`) | `"+\(added), -\(removed)"` (`Features/Writing/EditMultipleWorksView.swift:360`) | **SAME** |
| 50 | `"Changing the rating or language replaces that value on every selected work. Warnings and categories are added or removed instead."` (`writing/WritingBulkEditScreen.kt:121`) | `"Changing the rating or language replaces that value on every selected work. Warnings and categories are added or removed instead."` (`Features/Writing/EditMultipleWorksView.swift:91-92`) | **SAME** |
| 51 | `"Collections and gifts"` (`writing/WritingBulkEditScreen.kt:122`) | `"Collections and gifts"` (`Features/Writing/EditMultipleWorksView.swift:102`) | **SAME** |
| 52 | `"Add to collections"` (`writing/WritingBulkEditScreen.kt:123`) | `"Add to collections"` (`Features/Writing/EditMultipleWorksView.swift:242`) | **SAME** |
| 53 | `"Remove from collections"` (`writing/WritingBulkEditScreen.kt:126`) | `"Remove from collections"` (`Features/Writing/EditMultipleWorksView.swift:251, 259`) | **SAME** |
| 54 | `"Gift recipients"` (`writing/WritingBulkEditScreen.kt:130`) | `"Gift recipients"` (`Features/Writing/EditMultipleWorksView.swift:270`) | **SAME** |
| 55 | `"Per work"` (`writing/WritingBulkEditScreen.kt:130`) | `"Per work"` (`Features/Writing/EditMultipleWorksView.swift:271`) | **SAME** |
| 56 | `"Comments and visibility"` (`writing/WritingBulkEditScreen.kt:131`) | `"Comments and visibility"` (`Features/Writing/EditMultipleWorksView.swift:105`) | **SAME** |
| 57 | `"Only show to registered users"` (`writing/WritingBulkEditScreen.kt:132`) | `"Only show to registered users"` (`Features/Writing/EditMultipleWorksView.swift:287`) | **SAME** |
| 58 | `"Enable comment moderation"` (`writing/WritingBulkEditScreen.kt:133`) | `"Enable comment moderation"` (`Features/Writing/EditMultipleWorksView.swift:293`) | **SAME** |
| 59 | `"Who can comment"` (`writing/WritingBulkEditScreen.kt:133`) | `"Who can comment"` (`Features/Writing/EditMultipleWorksView.swift:299`) | **SAME** |
| 60 | `"Creators"` (`writing/WritingBulkEditScreen.kt:137`) | `"Creators"` (`Features/Writing/EditMultipleWorksView.swift:108`) | **SAME** |
| 61 | `"Add co-creators"` (`writing/WritingBulkEditScreen.kt:140`) | `"Add co-creators"` (`Features/Writing/EditMultipleWorksView.swift:313`) | **SAME** |
| 62 | `"Pseud"` (`writing/WritingBulkEditScreen.kt:140`) | `"Pseud"` (`Features/Writing/EditMultipleWorksView.swift:314`) | **SAME** |
| 63 | `"Remove me as a co-creator"` (`writing/WritingBulkEditScreen.kt:147`) | `"Remove me as a co-creator"` (`Features/Writing/EditMultipleWorksView.swift:327, 328`) | **SAME** |
| 64 | `"AO3 sends each co-creator an invitation. Their work doesn't change until they accept it."` (`writing/WritingBulkEditScreen.kt:150`) | `"AO3 sends each co-creator an invitation. Their work doesn't change until they accept it."` (`Features/Writing/EditMultipleWorksView.swift:111`) | **SAME** |
| 65 | `"AO3 Account"` (`writing/WritingBulkEditScreen.kt:161`) | `"AO3 Account"` (`Features/Writing/EditMultipleWorksView.swift:57`) | **SAME** |
| 66 | `"Leave as is"` (`writing/WritingBulkEditScreen.kt:184`) | `"Leave as is"` (`Features/Writing/EditMultipleWorksView.swift:159`) | **SAME** |
| 67 | `"Add"` (`writing/WritingBulkEditScreen.kt:188`) | `"Add"` (`Features/Writing/BulkTagStatePicker.swift:103`) | **SAME** |
| 68 | `"Remove"` (`writing/WritingBulkEditScreen.kt:188`) | `"Remove"` (`Features/Writing/BulkTagStatePicker.swift:104`) | **SAME** |
| 69 | `"Unchanged"` (`writing/WritingBulkEditScreen.kt:188`) | `"Unchanged"` (`Features/Writing/BulkTagStatePicker.swift:64`) | **SAME** |
| 70 | `"Collection name"` (`writing/WritingBulkEditScreen.kt:210`) | `"Collection name"` (`Features/Writing/EditMultipleWorksView.swift:243`, `BulkTagStatePicker.swift:158`) | **SAME** |
| 71 | `"Add"` (`writing/WritingBulkEditScreen.kt:213`) | `"Add"` (`Features/Writing/BulkTagStatePicker.swift:165`) | **SAME** |
| 72 | `"Enter the collection name exactly as it appears on AO3. If AO3 doesn't recognize it, you will see that when you save."` (`writing/WritingBulkEditScreen.kt:216`) | `"Enter the collection name exactly as it appears on AO3. If AO3 doesn't recognize it, you will see that when you save."` (`Features/Writing/BulkTagStatePicker.swift:168-169`) | **SAME** |
| 73 | `"Tap an option once to add it to every selected work, twice to remove it, or three times to leave it unchanged."` (`writing/WritingBulkEditScreen.kt:218`) | `"Tap an option once to add it to every selected work, twice to remove it, or three times to leave it unchanged."` (`Features/Writing/BulkTagStatePicker.swift:30-31`) | **SAME** |
| 74 | `"On"` (`writing/WritingBulkEditScreen.kt:225`) | `"On"` (`Features/Writing/EditMultipleWorksView.swift:307`) | **SAME** |
| 75 | `"Off"` (`writing/WritingBulkEditScreen.kt:225`) | `"Off"` (`Features/Writing/EditMultipleWorksView.swift:308`) | **SAME** |

---

### Pair 3: Challenge Assignments
- **Android**: `account/AO3ChallengeAssignmentsScreen.kt` (and `account/AO3ChallengeAssignmentsState.kt`)
- **iOS**: `Features/Challenges/ChallengeAssignmentsView.swift` and the files it uses in `Features/Challenges/`

| # | Android String (`path:line`) | iOS String (`path:line`) | Status |
|---|---|---|---|
| 76 | `"${row.giverDisplay} → ${row.recipientDisplay}"` (`account/AO3ChallengeAssignmentsScreen.kt:75`) | `"\(giverDisplay(for: assignment)) → \(displayName(assignment.requestPseud))"` (`Features/Challenges/ChallengeAssignmentsView.swift:746`) | **SAME** |
| 77 | `"Cancel"` (`account/AO3ChallengeAssignmentsScreen.kt:78`) | `"Cancel"` (`Features/Challenges/ChallengeAssignmentsView.swift:135`) | **SAME** |
| 78 | `"Report a default"` (`account/AO3ChallengeAssignmentsState.kt:23`) | `"Report a default"` (`Features/Challenges/ChallengeAssignmentsView.swift:687, 767`) | **SAME** |
| 79 | `"Report this default?"` (`account/AO3ChallengeAssignmentsState.kt:23`) | `"Report this default?"` (`Features/Challenges/ChallengeAssignmentsView.swift:768`) | **SAME** |
| 80 | `"Report default"` (`account/AO3ChallengeAssignmentsState.kt:23`) | `"Report default"` (`Features/Challenges/ChallengeAssignmentsView.swift:769`) | **SAME** |
| 81 | `"Claim a pinch hit"` (`account/AO3ChallengeAssignmentsState.kt:24`) | `"Claim a pinch hit"` (`Features/Challenges/ChallengeAssignmentsView.swift:708, 767`) | **SAME** |
| 82 | `"Claim this pinch hit?"` (`account/AO3ChallengeAssignmentsState.kt:24`) | `"Claim this pinch hit?"` (`Features/Challenges/ChallengeAssignmentsView.swift:768`) | **SAME** |
| 83 | `"Claim"` (`account/AO3ChallengeAssignmentsState.kt:24`) | `"Claim"` (`Features/Challenges/ChallengeAssignmentsView.swift:769`) | **SAME** |
| 84 | `"This marks ${write.assignment.giverDisplay}'s assignment for ${write.assignment.recipientDisplay} as defaulted on AO3 and adds it to the pinch hits waiting for cover."` (`account/AO3ChallengeAssignmentsState.kt:54-55`) | `"This marks \(giverDisplay(for: write.assignment))'s assignment for \(recipient) as defaulted on AO3 and adds it to the pinch hits waiting for cover."` (`Features/Challenges/ChallengeAssignmentsView.swift:753-754`) | **SAME** |
| 85 | `"You'll be the pinch hitter for ${write.assignment.recipientDisplay}'s gift${dueText?.let { ", due $it" }.orEmpty()}."` (`account/AO3ChallengeAssignmentsState.kt:56`) | `"You'll be the pinch hitter for \(recipient)'s gift\(due)."` (`Features/Challenges/ChallengeAssignmentsView.swift:757`) | **SAME** |
| 86 | `"Cancel"` (`account/AO3ChallengeAssignmentsScreen.kt:91`) | `"Cancel"` (`Features/Challenges/ChallengeAssignmentsView.swift:145`) | **SAME** |
| 87 | `"Assignments"` (`account/AO3ChallengeAssignmentsScreen.kt:99`) | `"Assignments"` (`Features/Challenges/ChallengeAssignmentsView.swift:113, 157`) | **SAME** |
| 88 | `"${matched.size} matched"` (`account/AO3ChallengeAssignmentsState.kt:51`) | `"\(matched.count) matched"` (`Features/Challenges/ChallengeAssignmentsView.swift:167`) | **SAME** |
| 89 | `"${unmatched.size} unmatched"` (`account/AO3ChallengeAssignmentsState.kt:52`) | `"\(unmatched.count) unmatched"` (`Features/Challenges/ChallengeAssignmentsView.swift:168`) | **SAME** |
| 90 | `"works due $it"` (`account/AO3ChallengeAssignmentsState.kt:53`) | `"works due \(due)"` (`Features/Challenges/ChallengeAssignmentsView.swift:171`) | **SAME** |
| 91 | `"Matched"` (`account/AO3ChallengeAssignmentsState.kt:21`) | `"Matched"` (`Features/Challenges/ChallengeAssignmentsView.swift:69`) | **SAME** |
| 92 | `"Unmatched"` (`account/AO3ChallengeAssignmentsState.kt:21`) | `"Unmatched"` (`Features/Challenges/ChallengeAssignmentsView.swift:70`) | **SAME** |
| 93 | `"Pinch hits"` (`account/AO3ChallengeAssignmentsState.kt:21`) | `"Pinch hits"` (`Features/Challenges/ChallengeAssignmentsView.swift:71`) | **SAME** |
| 94 | `"Loading assignments…"` (`account/AO3ChallengeAssignmentsScreen.kt:242`) | `"Loading assignments…"` (`Features/Challenges/ChallengeAssignmentsView.swift:546`) | **SAME** |
| 95 | `"Couldn't load assignments"` (`account/AO3ChallengeAssignmentsScreen.kt:110, 246`) | `"Couldn't load assignments"` (`Features/Challenges/ChallengeAssignmentsView.swift:566`) | **SAME** |
| 96 | `"Sign in to AO3 to view assignments."` (`account/AO3ChallengeAssignmentsState.kt:107`) | `"Sign in to AO3 to view assignments."` (`Features/Challenges/ChallengeAssignmentsView.swift:462`) | **SAME** |
| 97 | `"Unmatched sign-ups"` (`account/AO3ChallengeAssignmentsScreen.kt:134`) | `"Unmatched sign-ups"` (`Features/Challenges/ChallengeAssignmentsView.swift:242`) | **SAME** |
| 98 | `"Couldn't load matched assignments"` (`account/AO3ChallengeAssignmentsScreen.kt:137`) | `"Couldn't load matched assignments"` (`Features/Challenges/ChallengeAssignmentsView.swift:206`) | **SAME** |
| 99 | `"Couldn't load defaults"` (`account/AO3ChallengeAssignmentsScreen.kt:138`) | `"Couldn't load defaults"` (`Features/Challenges/ChallengeAssignmentsView.swift:245`) | **SAME** |
| 100 | `"Couldn't load pinch hits"` (`account/AO3ChallengeAssignmentsScreen.kt:139`) | `"Couldn't load pinch hits"` (`Features/Challenges/ChallengeAssignmentsView.swift:224`) | **SAME** |
| 101 | `"No matched assignments yet."` (`account/AO3ChallengeAssignmentsScreen.kt:143`) | `"No matched assignments yet."` (`Features/Challenges/ChallengeAssignmentsView.swift:208`) | **SAME** |
| 102 | `"No defaulted assignments are waiting for a pinch hitter."` (`account/AO3ChallengeAssignmentsScreen.kt:144`) | `"No defaulted assignments are waiting for a pinch hitter."` (`Features/Challenges/ChallengeAssignmentsView.swift:247`) | **SAME** |
| 103 | `"No pinch hits open right now."` (`account/AO3ChallengeAssignmentsScreen.kt:145`) | `"No pinch hits open right now."` (`Features/Challenges/ChallengeAssignmentsView.swift:226`) | **SAME** |
| 104 | `"${row.recipientDisplay} → ${row.giverDisplay}"` (`account/AO3ChallengeAssignmentsScreen.kt:151`) | `"\(displayName(assignment.requestPseud)) → \(giverDisplay(for: assignment))"` (`Features/Challenges/ChallengeAssignmentsView.swift:270`) | **SAME** |
| 105 | `"due $it"` (`account/AO3ChallengeAssignmentsScreen.kt:152`) | `"due \(due)"` (`Features/Challenges/ChallengeAssignmentsView.swift:340`) | **SAME** |
| 106 | `"DELIVERED"` (`account/AO3ChallengeAssignmentsScreen.kt:157`, `AO3ChallengeSignUps.kt:25`) | `"DELIVERED"` (`Features/Challenges/ChallengeAssignmentsView.swift:307, 315`) | **SAME** |
| 107 | `"DEFAULTED"` (`account/AO3ChallengeAssignmentsScreen.kt:158`, `AO3ChallengeSignUps.kt:26`) | `"DEFAULTED"` (`Features/Challenges/ChallengeAssignmentsView.swift:309, 315`) | **SAME** |
| 108 | `"LATE"` (`account/AO3ChallengeAssignmentsScreen.kt:155`, `AO3ChallengeSignUps.kt:27`) | `"LATE"` (`Features/Challenges/ChallengeAssignmentsView.swift:308, 315`) | **SAME** |
| 109 | `"Two sign-ups lost their giver"` (`account/AO3ChallengeAssignmentsScreen.kt:168`) | `"Two sign-ups lost their giver"` (`Features/Challenges/ChallengeAssignmentsView.swift:395`) | **SAME** |
| 110 | `"One sign-up lost its giver"` (`account/AO3ChallengeAssignmentsScreen.kt:168`) | `"One sign-up lost its giver"` (`Features/Challenges/ChallengeAssignmentsView.swift:395`) | **SAME** |
| 111 | `"The givers for ${names[0]} and ${names[1]} defaulted, and no pinch hitter has covered them yet. Only AO3 can match participants, so cover this with a pinch hit or assign someone on AO3."` (`account/AO3ChallengeAssignmentsScreen.kt:169-171`) | `"The givers for \(pair[0]) and \(pair[1]) defaulted, and no pinch hitter has covered them yet. Only AO3 can match participants, so cover this with a pinch hit or assign someone on AO3."` (`Features/Challenges/ChallengeAssignmentsView.swift:415, 417`) | **SAME** |
| 112 | `"The giver for ${names[0]} defaulted, and no pinch hitter has covered it yet. Only AO3 can match participants, so cover this with a pinch hit or assign someone on AO3."` (`account/AO3ChallengeAssignmentsScreen.kt:170-171`) | `"The giver for \(pair[0]) defaulted, and no pinch hitter has covered it yet. Only AO3 can match participants, so cover this with a pinch hit or assign someone on AO3."` (`Features/Challenges/ChallengeAssignmentsView.swift:416, 417`) | **SAME** |
| 113 | `"Open on AO3"` (`account/AO3ChallengeAssignmentsScreen.kt:173`) | `"Open on AO3"` (`Features/Challenges/ChallengeAssignmentsView.swift:407`) | **SAME** |
| 114 | `"Pinch hit #${index + 1}"` (`account/AO3ChallengeAssignmentsScreen.kt:181`) | `"Pinch hit #\(row.number)"` (`Features/Challenges/ChallengeAssignmentsView.swift:616`) | **SAME** |
| 115 | `"OPEN"` (`account/AO3ChallengeAssignmentsScreen.kt:182`) | `"OPEN"` (`Features/Challenges/ChallengeAssignmentsView.swift:620`) | **SAME** |
| 116 | `"CLAIMED"` (`account/AO3ChallengeAssignmentsScreen.kt:182`) | `"CLAIMED"` (`Features/Challenges/ChallengeAssignmentsView.swift:620`) | **SAME** |
| 117 | `"an anonymous sign-up"` (`account/AO3ChallengeAssignmentsScreen.kt:183`) | `"an anonymous sign-up"` (`Models/AO3ChallengeScreenModels.swift:94`) | **SAME** |
| 118 | `"Requested by $recipient"` (`account/AO3ChallengeAssignmentsScreen.kt:184`) | `"Requested by \(recipient)"` (`Models/AO3ChallengeScreenModels.swift:95`) | **SAME** |
| 119 | `"Claimed by ${row.pinchHitter.ifEmpty { row.giver }} for $recipient"` (`account/AO3ChallengeAssignmentsScreen.kt:184-185`) | `"Claimed by \(hitter) for \(recipient)"` (`Models/AO3ChallengeScreenModels.swift:97`) | **SAME** |
| 120 | `"Claim"` (`account/AO3ChallengeAssignmentsScreen.kt:187`) | `"Claim"` (`Features/Challenges/ChallengeAssignmentsView.swift:354`) | **SAME** |
| 121 | `"You can view assignments and pinch hits here one page at a time. You can report a default or claim a pinch hit here, but asking for a pinch hitter and running the match open on AO3."` (`account/AO3ChallengeAssignmentsScreen.kt:204-205`) | `"You can view assignments and pinch hits here one page at a time. You can report a default or claim a pinch hit here, but asking for a pinch hitter and running the match open on AO3."` (`Features/Challenges/ChallengeAssignmentsView.swift:437-438`) | **SAME** |
| 122 | `"Try Again"` (`account/AO3ChallengeAssignmentsScreen.kt:252`) | `"Try Again"` (`Features/Challenges/ChallengeAssignmentsView.swift:576`) | **SAME** |

## Triage (Claude, 2026-10-10)

137 strings, 122 the same. The 2 that differ are the selection checkbox's spoken label
("Select <title>" on Android; iOS speaks a hint, "Double-tap to select this work."): Android's
is right for TalkBack, which adds its own hint. The 13 with no iOS string are Android's own
controls where iOS has a gesture or does the thing unasked (a row's overflow menu for swipe
actions, a refresh button for pull to refresh, "Load more ..." where iOS reads every page, the
three sentences 3cc added for a refused assignments page). **Nothing to change.** Three rows
were checked against the files; the rest are taken as leads.

