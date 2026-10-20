# Brief 3fu Result: Own Works & Series, Card Unfold Control, Lists Default to Compact

Owner Q24/Q25 (2026-10-20). Implemented by Agent Flash. Build, tests and landing by Claude.

## What changed

### 1. Own Works and Own Series (Q24)
- **`android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:77, 102-105, 122, 692-727, 778`**:
  - `initialTab` parameter changed to `AuthorTab? = AuthorTab.Works`.
  - Added `ownAccount = isOwnWorks(signedInUsername, username)`.
  - Added `isContentDestination = initialTab != null`.
  - Added `usesAccountHeader = isDashboard || (ownAccount && isContentDestination)`.
  - Added `showsTabs = !isDashboard && (!ownAccount || !isContentDestination)`.
  - When `usesAccountHeader` is true, the header renders `SubjectHeaderBlock` with kicker `"AO3 Account"`, title `if (isDashboard) route.displayName else tab.label` ("Works" or "Series"), and subtitle (`ownWorksLine(...)` for Works, series tally / "No series yet" for Series).
  - Multiple pseuds are rendered as a `LazyRow` of pseud pills within the account header block.
  - The 4 profile tabs (`Works`, `Series`, `Bookmarks`, `About`) segmented control is gated behind `if (showsTabs)`, hiding them on the signed-in writer's own Works and own Series pages.
  - Kept writer totals line ("12 works · 248,400 words · 3,812 kudos") via `ownWorksLine`.
  - All existing actions are preserved: Select mode, Edit multiple works bulk bar, per-row menus (Edit, Add Chapter, Edit Tags, Delete), "+" (New work), and Load More.
  - Fandom filter chips row (`LazyRow` of author fandoms) is rendered on Works as before.
  - Follows iOS:
    - `Features/Authors/AuthorProfileView.swift:44, 49-61` (`initialTab`, `isContentDestination`)
    - `Features/Authors/AuthorProfileView.swift:238` (`if !showsDashboard, !isContentDestination` omits segmented control)
    - `Features/Authors/AuthorProfileView.swift:291` (`usesAccountHeader: Bool { showsDashboard || (isOwnProfile && isContentDestination) }`)
    - `Features/Authors/AuthorProfileView.swift:293-308` (`accountHeader` with kicker "AO3 Account", title, subtitle, pseud selector)
    - `Features/Authors/AuthorProfileView.swift:310-333` (`accountSubtitle`: `ownWorksLine` for works, series tally for series)
- **`android/app/src/main/java/io/github/cidy02/kudos/app/AppNavHost.kt:1003, 1310`**:
  - `AccountListType.MyWorks` navigation sets `initialTab = io.github.cidy02.kudos.author.AuthorTab.Works`.
  - `Routes.AuthorProfile` shared composable passes `initialTab = null` so standard author profile navigation keeps the 4 tabs.
  - Follows iOS:
    - `Features/Account/AccountView.swift:494-503, 766-778` (`ownProfile(title:tab:)` passing `initialTab: .works` or `.series`)

### 2. Card Unfold Control (Q25a)
- **`android/app/src/main/java/io/github/cidy02/kudos/ui/components/SensitiveWorkRow.kt:417-445, 629-679`**:
  - **Detailed Card (`ledger = false`)**: Removed the `IconButton` from before the title. Placed it at the foot of the card beside `CardMetaLine(dateText)` in a `SpaceBetween` row.
  - **Ledger Card (`ledger = true`)**: Removed the unfold `Icon` from the top kicker row (`identity`). Placed it at the foot of the card beside `date()` aligned with trailing figures.
  - Exact display rule preserved: `expandable = summary.length > 120 || tags.isNotEmpty() || (ledger && bookmark == null && fandoms.size > 1)`.
  - Follows iOS:
    - `Features/Library/WorkRow.swift:303-351` (`expandButton` placed at the foot of the card)
    - `Features/Library/AO3WorkRow.swift:212-226` (`expandButton` in footer HStack beside `TagChip(date)`)

### 3. Lists Open on Compact (Q25b)
- **`android/app/src/main/java/io/github/cidy02/kudos/library/QueuePageScreen.kt:125`**:
  - Changed `displayMode` from transient `rememberSaveable { mutableStateOf(QueueDisplayMode.Detailed) }` to `rememberStoredChoice("library.readingQueueBrowser.displayMode.$queueId", QueueDisplayMode.Compact)`.
  - Follows iOS:
    - `Features/Library/ReadingQueueBrowser.swift:287, 319` (`"library.readingQueueBrowser.displayMode.\(id)"`, default `.compact`)
- **`android/app/src/main/java/io/github/cidy02/kudos/account/AccountWorksListScreen.kt:168`**:
  - Confirmed `displayMode` defaults to `AccountDisplayMode.Compact` under key `"account.displayMode"`, matching iOS.
  - Covers Bookmarks, History, Marked for Later, Subscriptions, and Collections.
  - Follows iOS:
    - `Features/Account/AccountView.swift:46` (`@AppStorage("account.displayMode") ... = .compact`)
    - `Features/Bookmarks/AO3AccountWorksList.swift:162` (`@AppStorage("account.displayMode") ... = .compact`)

## Tests added

1. **`android/app/src/test/java/io/github/cidy02/kudos/author/OwnWorksScreenTest.kt:235-269`**:
   - `ownWorksShapeShowsTotalsLineAndHidesFourProfileTabs()`: Asserts kicker "AO3 Account", title "Works", totals line containing works and words count, and that "Bookmarks" and "About" tab nodes do not exist.
   - `ownWorksTotalsLineMatchesExpectedFormatting()`: Asserts `ownWorksLine` format matching "12 works · 248,400 words · 3,812 kudos", as well as single-work and count-less fallbacks.
   - `ownSeriesTallyPartsSumsExpectedTotals()`: Asserts `seriesTallyParts` summation.
2. **`android/app/src/test/java/io/github/cidy02/kudos/ui/components/SensitiveWorkRowLedgerTest.kt:109-138`**:
   - `unfoldControlSitsAtTheFootOfLedgerCard()`: Asserts via `boundsInRoot` that the unfold control ("Show more") top is below title bottom on a ledger card.
   - `unfoldControlSitsAtTheFootOfDetailedCard()`: Asserts via `boundsInRoot` that the unfold control ("Show more") top is below title bottom on a detailed card.
3. **`android/app/src/test/java/io/github/cidy02/kudos/ui/components/StoredChoiceLayoutTest.kt:1-55`**:
   - `freshLaunchDefaultsToCompactForAccountAndQueueLists()`: Asserts that fresh launches default to `Compact` for `"account.displayMode"` and `"library.readingQueueBrowser.displayMode.$queueId"`.
   - `storedChoiceKeepsReaderSelectionBetweenLaunches()`: Asserts that user-selected display mode persists to `layout-choices` preferences and is preserved across reads.

## What could not be done

- Per agent contract and task instructions: did not commit, push, switch branches, sign in, run Gradle (`./gradlew`), or contact archiveofourown.org. Claude builds, tests, and lands the branch.
