# How the app handles the Duo fold today (survey of claude/iphone-duo @ 1e5d3d44)

App today on `claude/iphone-duo` (tip `1e5d3d44`, T-455). Everything below was read from the code with grep, sed and cat. Paths are relative to `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader`.

**How layout is chosen**
- `UIComponents/WideLayout.swift` `WideLayout.isAvailable` is true only for regular width and regular height. Since T-448, the spread toggle, Readium's column count and the filter inspector all use this check.
- `UIComponents/AdaptiveContentRegions.swift` `init(viewport:)` reads `proxy.reservedRegions(kind: .division/.occlusion)` (iOS 27.1). These are the only two calls to that API in the app; the other is in `LocalNavigationHost.swift` `navigationRegions(in:)`. `subtract` turns a vertical fold into a left pane and a right pane, each the full height.
- `DashboardRegionRow` places each child at its pane's x position. `dashboardLeadingRegion` puts a view in the leading pane only.
- `readableNavigationPage()` (`LocalNavigationHost.swift`) caps a page at 760pt and puts it in the leading pane when there are several panes.
- `LocalNavigationHost.body` is a `NavigationSplitView(.balanced)` with a sidebar column of min 240 / ideal 260. It only shows the split when `fitsLocalNavigation` passes: regular/regular, not an accessibility text size, and either one pane ≥600pt or two panes of ≥240 and ≥360. Otherwise it shows `.detailOnly`.
- `localNavigationDetailNeedsWidth(true)` collapses that sidebar while a filter inspector is open.
- Root tabs: `App/ContentView.swift` `tabs` is `TabView` with `.sidebarAdaptable`, the four tabs plus `Tab(..., role: .search)`, and `.tabBarMinimizeBehavior(.onScrollDown)`. The app never sets tab bar, sidebar or rail placement itself. The system decides.

**Cover display (466×678)**
- **Home:**
  - The tab rail on the right edge comes from the 27.1 SDK, not app code (TASKS T-447).
  - Every horizontal row (18 of them) goes through `horizontalScrollViewport` (`HorizontalScrollViewport.swift`). It masks cards so they stop at the rail. Cards clamp to the measured container width (`CarouselCardGrid`, `ScaledCarouselCardSize`).
  - The layout stays compact. `HomeResumeComposition.compactContent` shows the hero at full width with the next 4 works in a horizontal scroll, because `heroFits` needs about 696pt (300+24+2×164+12+32).
  - Section order (`Features/Home/HomeView.swift` body): Continue Reading, Reading Queues, collection shelves, Recently Updated, Subscriptions.
- **Reader:**
  - The tab bar is hidden and the status bar follows the reader chrome (`ReadiumReaderView` `.toolbar(.hidden, for: .tabBar)`, `.statusBarHidden(!chromeVisible)`).
  - The page box follows the host size and the side safe areas (`ReaderPageBoxGeometry.updating`, T-449).
  - Width is compact, so there is one column (`ReadiumReaderStyleMapper`: paged gives `.one`, scroll gives nil).

**Open flat (951×669)**
- **Home:**
  - One `DashboardRegionHost { ScrollView {...} }`.
  - When `resumePanes` fits, the hero sits on the left (width 520–48% of the viewport) and the next works sit on the right as a paged grid (`HomeResumeComposition`, `DashboardCardShelf(groupsInSinglePane:)`).
  - Shelves become two-row pages that snap sideways when the height is at least 502 and there are 3 or more columns (`AdaptiveContentRegions.usesGroupedShelves`, `shelfPages`, `DashboardCardShelf.paneShelf`).
- **Library:**
  - `Features/Library/LibraryNavigation.swift` `LibraryView.body` uses `LocalNavigationHost`. Its sidebar is `LibraryLocationsList`: Library; then Locations (Reading Now, Saved for Later, Finished, Downloaded, History, Favorites, Collections, Reading Queues); then Reading Insights and Recently Deleted.
  - The detail column is the dashboard, as shelves or a ledger. The ledger is a leading-region list.
  - Collections swaps the sidebar for `LibraryCollectionsList`. Queues swaps it for the organizer and opens the first queue (`ReadingQueueOrganizer.openWideDefault`).
  - The code still names the local list "Saved for Later" (`LibrarySectionKind.savedForLater`).
- **Search + filters:**
  - Search is a focused full-screen mode. It hides the tab bar, has its own Back button, and puts the search field in the `.principal` toolbar slot rather than using `.searchable` (`Features/Search/SearchView.swift`).
  - Filters use `filterPanelPresentation`. On regular/regular they open as an `.inspector` 280–380pt wide (`inspectorColumnWidth`), with a header row of glass Reset, title and confirm (`FilterPanelChrome`). Otherwise they open as a sheet with a grabber and `[.medium, .large]` detents.
  - The results have no layout split into panes.
- **Work Detail:**
  - `Features/WorkDetail/WorkDetailLayout.swift` `adaptiveDetailContent` / `contentPanes`: two Lists that scroll separately when the view is at least 2×340+24pt wide and 480pt tall (480pt per side at accessibility sizes). Each side is capped at 720pt and centred.
  - Leading: identity, status, AO3 actions, archive stats, page actions. Trailing: summary, tags, facts, comments, series, My copy.
  - Anything narrower, including a narrow split detail, gets one column with every block.
- **Account:**
  - `AccountView.body` uses `LocalNavigationHost`. The sidebar is `AccountDestinationsList`: Account; Reading; Writing; Activity; Account; then a Settings button.
  - Detail pages use `readableNavigationPage()`. The root hides the navigation bar unless the split fits or the inbox is in selection mode (`localNavigationRootBar`).
  - A floating chrome row with the gear sits top-trailing and fades on scroll.
- **Settings:**
  - Pushing Settings swaps the sidebar for `SettingsCategoriesList` (`localNavigationSidebar`).
  - When the split fits, `SettingsHubView` calls `onDefaultPage` so a page fills the detail.
  - The "Two-page spread" toggle only shows on regular/regular. It is disabled unless the layout is Paged (`Settings/SettingsView.swift` `twoPageSpreadAvailable`).
- **Reader:**
  - With spread on, Paged mode and regular/regular, `columnCount` is `.auto`, so Readium picks 1 or 2 columns. Scroll mode sets no column count.
  - The reader opens these as sheets: the reader panel, Work Detail (inside a `NavigationStack`), the note editor (medium/large), speech settings, and Comments.

**Book pose (455 | fold 40 | 456)**
- **Home:**
  - Still one vertical ScrollView covering both panes. The two sides do not scroll separately.
  - Headers sit in the leading pane. Each shelf pages inside each pane.
  - In the right pane the next-works shelf falls back to a sideways scroll, so both next works stay in view (T-454).
  - TASKS T-452 records that nothing crossed the fold on the simulator.
- **Library and Account:** the comment in `fitsLocalNavigation` says the system split allocates space around the fold. Pages use `readableNavigationPage`, which puts them in the leading pane.
- **Work Detail:** each side sits wholly in its own pane. At AX5 everything is in the leading pane (T-455).
- **Reader:** nothing handles the fold. The reader never calls `reservedRegions`, and the spread is just Readium's `.auto`. TASKS T-449 says the Duo unfolding was never seen on a device.
- **Comments:** `CommentsView.swift` `CommentsSheetModifier` opens a sheet that can expand to a `fullScreenCover`. There is no fold or wide-layout code in Comments. Its "fold" matches are about collapsing threads.

**Open portrait (669×951) — Browse**
- `NativeBrowseView` has no wide or region code.
- Its filters use `filterPanelPresentation(detents: [.medium, .large])`: an inspector only if regular/regular, otherwise a sheet.
- The code doesn't say which size class the Duo's portrait screen reports.
- TASKS T-452 and T-455 say portrait keeps the compact Home, Library and Work Detail layouts.

**Gaps where the app has nothing specific (the design must decide)**
1. Reader in Book pose: one page per pane versus a spread, and keeping text clear of the fold.
2. Comments on the wide screen and in Book pose. Today it is only a sheet or a full-screen cover.
3. Search results and Browse: no pane split on the wide screen, only the choice between inspector and sheet.
4. Home in Book pose: each pane scrolling on its own. Today it is one shared scroll.
5. The app tab sidebar or rail on the open screen: the code only says `.sidebarAdaptable`, and TASKS doesn't record what the inner screen showed.
6. Library and Account show two sidebars at once on the open screen: the app tab sidebar plus the local `NavigationSplitView` sidebar. How they relate isn't defined.
7. The Home stats strip linking to Insights and a "New Chapters" section don't exist. Home's order is as listed under Cover display above.
8. "Want to Read" is still `savedForLater` / "Saved for Later" in the code.
9. Reader panels on the wide screen are all sheets. There is no inspector or side panel.
10. Not verified anywhere: iPad, the Duo actually unfolding with the reader open, and the open portrait size classes.
