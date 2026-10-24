# Duo7 — native layouts for iPhone Duo

Implementation plan, 2026-10-24. Codex → Claude-CLI. This file is the only output of this task. Recommendations below are decisions for Claude-CLI to assess on usability and readability; none is parked as an owner question.

## Scope and evidence

Read-only review of `/Users/cidy02/kudos-ios-polish`, HEAD `64979c71`, following `97187d9a` (T-449), `de1a36ae` (T-448) and `e8036a77` (T-447). T-450's staged `ReadiumBook.swift`, `ReadiumReaderView.swift`, `ReadiumResizeNavigation.swift` and tests were read as work in progress. Preserve that work; do not reopen its navigation/restore fixes as Duo7 tasks. Recheck the lane tip before implementing.

Snapshot qualification: at the final 12:44 EDT check, HEAD and branch were unchanged but those staged WIP files were no longer present in this shared source worktree; T-450 still says IN PROGRESS. This plan records the initial WIP inspection, not a claim that T-450 has landed. Its new navigation seam/test names below apply after integration; use the lane's final equivalent if they change. No source mutation was performed by this task.

Read AGENTS, task-board context, README, onboarding, architecture, networking policy and regression matrix. The local `READIUM_MIGRATION_NOTES.md` is absent in the polish worktree; this review instead inspected the live reader and the exact dependency checkout. No source changes, build, test execution, AO3 access, sign-in, task-board edits, branch switches, commits or pushes were performed. Existing unrelated untracked files in this output worktree were left alone.

Evidence labels used below:

- **SDK checked:** declaration inspected in the installed iOS Simulator 27.1 SDK, not a runtime guarantee. `xcrun --show-sdk-path` returns the macOS SDK here; `xcrun --sdk iphonesimulator --show-sdk-path` returns `/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator27.1.sdk`.
- **Apple guidance:** primary pages fetched during this review, linked beside the relevant decisions. Apple-app patterns describe the visible interaction model; their private implementation is unknown. The SwiftUI/UIKit components named here are Kudos implementation equivalents, not claims about Apple's source code.
- **Observed:** supplied PNGs opened during this review, not a fresh simulator run. Read `Duo2-result.md`'s **Checked by** header first: its secondary reporting does not establish Apple policy. Duo3 is a prior static audit, not proof that every failure still exists after T-447–450.
- **Recommendation:** design or implementation judgment to verify in Claude-CLI's simulator rounds.

Viewed `cover-sheet-1.png`, `cover2-1.png`, `inner-land-{1,2,3}.png`, `inner-port.png`, `inner-book.png`, `inner-slow.png`, and `duo6/ipad-{reader-settings,searchfilters,libraryfilters}.png` under `/Users/cidy02/kudos-tools/out/duo/`. The shots show stretched Home/Settings/detail content and Book-pose fold crossings. Some debug routes still show Home or skeletons; those tiles do **not** prove the destination's final layout. The slow shots are the reader/detail/comments evidence. The iPad Library-filter shot shows the dashboard, not an open inspector; only the Search shot visually establishes an inspector.

## API evidence and limits

The SDK paths below are relative to `System/Library/Frameworks/` in that simulator SDK. Line numbers are inspection anchors for this installed SDK, not portable API identifiers.

| API / claim | Evidence and use |
|---|---|
| `ReservedRegion` | **SDK checked:** `SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64-apple-ios-simulator.swiftinterface:4842`; `id`, `kind`, `frame`, `margins`, `isActive`; `.division` and `.occlusion` at 4875–4878. `GeometryProxy.reservedRegions(kind:options:layoutDirectionBehavior:)` at 10289; `.includeInactive` at 4890. Available 27.1. Query in the consuming view's coordinate space. Do not assume safe-area insets describe an internal division. |
| `ArrangementView` | **SDK checked:** same interface:16652, `init(primary:secondary:)`; `.arrangementViewStyle` at 16678 and `.split.axes(...)` at 4595–4605. Available 27.1. Candidate for two content regions, not two independently running readers. Its exact sizing/scroll behavior in Kudos remains runtime-unverified. |
| UIKit equivalent | **SDK checked:** `UIKit.framework/Headers/UIArrangementViewController.h`: primary/secondary placements, `setViewController:forPlacement:` and `updateArrangement:`. `UIView.h:760–763` exposes reserved-region queries. Swift's refined spelling of these Objective-C methods is **not confirmed** here; implementation must use the imported SDK signature, not guess it. |
| Hinge observation | **SDK checked:** SwiftUICore interface:24267, `onHingeChange(isEnabled:_:)` receives old/new `DeviceHingeContext`; context/hinge/status/angle at 16740–16772. UIKit `UIHinge.h`, `UIHingeInteraction.h` also checked. Use only if geometry observation misses a pose change; angle is not a pane width or a reason to select a layout. |
| Vertical bars | **SDK checked:** SwiftUICore interface:2548, optional `EnvironmentValues.toolbarVerticalEdge`; SwiftUI interface:25398, `.toolbarVerticalCompressionBehavior`, with `.prefersTabBar` / `.prefersToolbarItems` (iOS 27.1). `ToolbarOverflowMenu { ... }` at 31134 (iOS 27.0). These are real APIs. The particular compression/overflow result must be seen on Duo. |
| Existing adaptive navigation | **SDK checked:** `TabView`, `Tab`, `.sidebarAdaptable` (SwiftUI interface:9260), `NavigationSplitView` including two-/three-column and preferred compact-column overloads (27048 onward), column widths (336), balanced split style, `NavigationStack`, `List`, `Form`, `inspector` / inspector widths (14520). Split views' automatic fold accommodation is **Apple guidance**, not something an interface declaration proves. |
| Reflow primitives | **SDK checked:** `GeometryReader`, `onGeometryChange`, `ViewThatFits`, `LazyVGrid`, `LazyHGrid`, `GridItem`, `Label`, `safeAreaInset`, and the UIKit representable protocols are present. Width caps/column minima suggested below are Kudos tuning values, not Apple-required dimensions. |

New APIs need `#if os(iOS)` and availability branches; keep the app's existing deployment target. No project/signing change is part of this plan. No other unconfirmed Apple API is required. An SDK declaration establishes availability, not that an arbitrary custom grid, WebKit document, or overlay becomes fold-aware automatically.

Primary guidance: [Prepare for iPhone Duo](https://developer.apple.com/iphone-duo/prepare/) supports container sizing and extending the iPad layout rather than choosing by idiom. [Duo HIG](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo), fetched through its [documentation JSON](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/designing-for-iphone-duo.json), establishes automatic system-bar relocation, fold-adapting split views, and explicit handling for custom content. These support the recommendations; they do not prescribe a two-page book reader. Duo2 correctly marks Books-on-Duo two-page reporting as secondary.

## Recommended direction

**Keep the existing system `TabView(.sidebarAdaptable)` root. Add local list–detail splits, reflow content into usable panes, and make the reader's existing spread option work at Duo widths.** The largest improvements come from content composition, not replacing native chrome.

### Root: system rail, with destination sidebars

Apple Music exposes adaptive tab/sidebar navigation, shelves, and collection content; Books keeps Home/Library and collection choices. Files and Notes use persistent selection beside content. Those are complementary patterns. [Music on iPad](https://support.apple.com/en-euro/guide/ipad/ipad3cf219ca/ipados), [Books organization](https://support.apple.com/en-euro/guide/ipad/ipad5ecae3c6/ipados), [Files basics](https://support.apple.com/en-euro/guide/ipad/ipad4aaf0d7f/ipados).

`App/ContentView.swift:421–450` already declares four titled/symbol tabs plus Search with `.search` role and `.sidebarAdaptable`. Supplied shots show the rail on cover/inner landscape and floating bar on inner portrait. Keep system placement and its iPad sidebar affordance; do not manufacture a second root sidebar or force macOS's `sidebarSplit` onto iOS. A 215–280 pt root sidebar plus a section list would spend too much of 669 or 951 pt on navigation. Keep `AppRouter.selection`, deep links and per-tab paths authoritative. Existing native tab-sidebar expansion is allowed; local navigation must collapse when that expansion leaves insufficient content room.

Use **one visible navigation split at a time**: Library locations | chosen section; queues | queue contents; Account destinations | page; Settings categories | settings page; Inbox items | thread. Entering Inbox or Settings replaces the Account destinations pane, rather than adding a third pane. Work Detail within a constrained detail pane stays one readable column, or temporarily occupies the destination's full content area for its own two-column layout. The reader remains immersive.

### One layout policy, no Duo identity check

`UIComponents/WideLayout.swift` already tests regular **width and height**. That makes the inspector and spread eligibility available on Duo inner display; it is not proof that two useful columns fit. Decisions use the **local** usable width after rail, safe areas, any inspector, and chosen split columns; Dynamic Type may require collapse despite regular/regular.

| State | Recommendation applying to every area below |
|---|---|
| **C — cover 466×678, compact width** | Existing compact stack, card sizes, actions and content order. Respect the native lateral rail and retain T-447's shelf mask/container clamp. No new sidebar or forced two-column form. |
| **P — inner portrait 669×951, regular/regular** | Adaptive grids and readable measures. Two-pane navigation only while both panes remain useful; a roughly 240–260 pt navigation list plus ~360 pt detail is a starting fit test, not a mandate. Long prose/editing can use detail-only with system sidebar access. Keep native horizontal bars. |
| **L — inner landscape 951×669, regular/regular** | Two useful panes; dashboard cards/grids grow in count, not card/text size. Native vertical rail remains. Do not use 951 as content width. |
| **B — Book pose** | Query active `.division` and its margins in local coordinates; allocate content on either side. An approximately 40 pt region is earlier observed evidence, not a constant; do not add margins twice or infer the fold at the content area's midpoint. Retain the same selections/order as flat L and move only what the exclusion requires. |

Implement one small geometry calculation shared where necessary (proposed `UIComponents/AdaptiveContentRegions.swift`): safe content bounds, active exclusions, usable pane rectangles and fit results. Let `NavigationSplitView` own navigation geometry. Use `ArrangementView` or region-aware cell placement only for custom content that needs it; no app-wide replacement navigation framework. Flat iPad/ordinary iPhone have no active fold and take the existing or equivalent adaptive path. Empty space is acceptable when there is little content; enlarged cards or duplicated items are not a density improvement.

For a grid in Book pose, choose even column groups **when they fit**, with a real central exclusion; even column count by itself does not align a grid to a physical fold. Keep item order row-major across panes and down the page, one vertical scroll, stable IDs, and VoiceOver order matching that order. Split horizontal shelves into pane-contained pages so a card never becomes clipped at the fold. Do not merely mask out the middle of a scrolling card.

### Density and preservation contract

Keep every current title, co-author link, fandom, warning/rating/category/completion indicator, progress/download ring, summary disclosure, stats, privacy/reveal control, selection affordance, badge, queue position and action. Retain grouping, sort order, page boundaries and display-mode preferences. Reuse `WorkRow`, `AO3WorkRow`, canonical/sensitive cards, existing menus and `Subject*` styles. A cover-only grid cannot replace detailed result rows. No hidden-mature title leaks in a navigation selection or a new pane. Keep themes, especially Sepia/OLED, and Dynamic Type. New columns may wrap more; they must never silently truncate more information.

Compact iPhone and cover remain unchanged except fixes to native toolbar semantics. iPad gets the **same** wide-layout improvements where geometry permits; that is an intentional shared improvement, not a promise of pixel-identical iPad screens. macOS keeps its root and legacy reader; reuse changes there only when deliberately verified.

## Screen-by-screen plan

All source paths below are relative to `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`. A named proposed file is explicitly marked new.

### Home — Books Home / Music Home

**Model:** a current-reading feature beside related cards, followed by scannable shelves; large windows show more neighbours. Music's iPad Home illustration documents featured and recent content, not a full-width prose form. Use `ScrollView`, existing card components, adaptive grid/layout, and `ArrangementView` for the two leading content regions. The exact hero arrangement is a Kudos recommendation, not a claim that Music uses this component.

**Today/iPad:** `Features/Home/HomeView.swift:147` uses the same `NavigationStack` and vertical sections everywhere; `resumeSection` puts `HomeResumeHero` above a horizontal strip. `HomeResumeHero.swift` fills available width. `HomeCollectionShelves.swift`, `HomeCards.swift` and canonical cards already provide reusable content; no iPad hero composition is waiting behind an idiom gate. T-447 makes shelves safe at their outer edges, not at an internal fold.

| C | P | L | B |
|---|---|---|---|
| Keep current hero above neighbours. | Hero occupies a readable region beside the next reading cards when they fit; otherwise stack. | Hero in one leading region; next reading works beside it, eliminating its empty middle. Lower shelves use two-row card groups where content warrants. | Hero entirely in the leading pane, neighbours in the other; lower card groups exclude the fold. Header/See All belongs with its shelf. |

Preserve the existing first work + next-up-to-four window and See All behavior; do not fetch or synthesize more content to fill space. Queues, pinned collection shelves, Recently Updated and Subscriptions retain order and all visible signals. Update `TabDashboardShell` to match the real composition so launch does not flash a stretched phone skeleton. Files: Home files above, `UIComponents/TabDashboardShell.swift`, `HorizontalScrollViewport.swift`, proposed region helper. **No new control/screen.**

### Library dashboard and sections — Books Library / Files locations

**Model:** Books offers collections and Grid/List/sorting; Files keeps locations beside their contents. Use a **two-column `NavigationSplitView`** for Library locations | existing destination. Keep the dashboard as the initial Library overview; its section and collection destinations also appear in the local list. This adds direct access without deleting the dashboard shelves. Books grid/list behavior is documented in [Organize books](https://support.apple.com/en-euro/guide/ipad/ipad5ecae3c6/ipados); the permanent local locations pane is the Files analogy, not an assertion that Books always shows one.

**Today/iPad:** `Features/Library/LibraryView.swift:128` is a stack and dashboard on iPad too. `LibrarySectionListView.swift` and `Features/Home/HomeSectionListView.swift` already use `CarouselCardGrid` for compact cover mode; `LibraryEntityGridView` serves entity grids. `UIComponents/HorizontalScrollViewport.swift:87` measures its grid container, so grids already gain columns on Duo. `FilterPanelPresentation.swift` now enables inspectors through `WideLayout`; no remaining source `userInterfaceIdiom` gate was found. These are useful iPad paths, not a complete iPad list–detail design.

| C | P | L | B |
|---|---|---|---|
| Current dashboard and pushes. | Locations pane + section only if fit test passes; otherwise selected content with sidebar access. Dashboard/cover grids use fitting columns. | Locations | selected section; hide locations while inspecting work detail if its measure is inadequate. | System split aligns locations/content with fold. When in full-width dashboard, region-aware shelves/grids avoid division. No third work-detail pane. |

Keep sections **Reading Now, Saved for Later, Finished, Downloaded, History, Favorites, Collections**, plus existing Queues, Reading Insights and Recently Deleted entry points. Local Saved for Later remains distinct from AO3 Marked for Later. History keeps dated groups, Favorites keeps its scopes/filters, and Downloaded still means kept. Detailed/ledger modes remain rows; constrain their text width within a content pane rather than turning them into sparse full-width cards. Compact mode uses existing adaptive cover grid. Insights can arrange its existing chart/cards in two regions, keeping all figures; Recently Deleted remains a readable action list with its current recovery categories and confirmations. Neither needs a new dashboard feature.

Files: `LibraryView.swift`, `LibrarySectionListView.swift`, `HomeSectionListView.swift`, `LibrarySectionKind.swift` (reuse routes, no model changes), `ReadingInsightsView.swift`, `RecentlyDeletedView.swift`, shared grid/helper. **New control:** system show/hide-locations and selected-row highlight, because readers need stable context and direct section switching. No new content screen.

### Queues and local collections — Music playlists / Books collections

**Today/iPad:** `Features/Library/ReadingQueueBrowser.swift:288,392` already picks a regular-width layout, a fixed **240 pt HStack sidebar**, and hides the tab bar there. Duo receives it by size class already; it is not a phone-idiom bug. `ReadingQueueOrganizer.swift` has the existing queue tree, Pinned, search/tags and actions. `Collections.swift` supplies list/detail and management; `LibraryEntityGridView` gives all-collections adaptive cards. Local collections and AO3 collections are different surfaces.

**Change:** replace queue HStack navigation with a real `NavigationSplitView`, reusing queue rows/selection and page content; use the same local selection approach for collections. At most one local sidebar: choosing Queues or Collections changes the Library leading list to the corresponding existing organizer, with a clear route back to Library locations. Keep root navigation available in ordinary browsing; hide/minimize it only during the current selection/reorder tasks, not because width is regular.

| C | P | L | B |
|---|---|---|---|
| Existing queue/collection list → page; do not restore T-343's removed bottom switcher. | Existing grids; collapsible local list when content fit allows. | Queue/collection list | chosen contents, like playlists; grid count follows remaining width. | System list split follows division; queue Up Next card, numbered In Line rows and controls stay within their pane. |

Keep queue order, per-queue display choices, pinned states, keep-offline rules, Up Next/In Line, reorder/selection disabled states, row numbers, tags, counts/bytes, Rename/Delete/New and confirmations. A list that requires numbered reordering remains a list. Files: `ReadingQueueBrowser.swift`, `ReadingQueuePageParts.swift`, `ReadingQueueOrganizer.swift`, `ReadingQueues.swift`, `Collections.swift`, `CollectionLedgerRow.swift`, `LibraryEntityGridView.swift`. **New controls:** standard split visibility/selection only; no new queue or collection behavior.

### Browse — News discovery / Music categories

**Model:** discovery uses grouped destinations and editorial card groups, then category navigation; width adds choices per row. It does not require a master-detail thread UI. Use adaptive `LazyVGrid`/existing card layouts and existing stack routes. [News on iPad](https://support.apple.com/en-euro/guide/ipad/ipad741dad50/ipados) is the visual analogy for modular discovery; the precise two-region Kudos arrangement is a recommendation, not a verified News-on-Duo layout. This plan adds no News-style recommendation engine or editorial feed.

**Today/iPad:** `Features/Browse/NativeBrowseView.swift` (`BrowseView`) hosts `MediaBrowserView` in a stack; the latter already has reusable category blocks, recent/jump-back cards and wrapping fandom chips (`CappedFlowLayout`). `FandomListView` supplies the grouped fandom list; `FandomWorksView`/`TagWorksView` supply work results. This is shared, not an iPad-only layout.

| C | P | L | B |
|---|---|---|---|
| Keep current browsing order and routes. | Category cards in two columns when full chip/count content fits, else one. | Two region-width category groups and dense result cards. | Category cards and recent cards live wholly in panes; alphabet/fandom lists use one readable pane or row-major region groups without splitting a family heading from its rows. |

Keep the catalog's counts, downloaded indicators, fandom previews, expansion, search/filter, and Open AO3 Website. Long alphabetical lists are not arbitrarily newspaper-flowed into independently scrolling columns. Apply Search's result presentation policy below to fandom/tag work results. Files: `NativeBrowseView.swift`, `Features/Search/{MediaBrowserView,FandomListView,FandomFamilyRows}.swift`, shared geometry/card layouts. **No new control/screen.**

### Search — Music Search / Files results

**Today/iPad:** `Features/Search/SearchView.swift:136` is a stack; loaded remote results are `SelectableAO3WorkRow`s in a `List`, with hero and pagination. `SearchLocalResultsList.swift` is a mixed List of local work matches, fandoms, tags, collections and an explicit Search AO3 action. Filters already become a regular/regular inspector through `FilterPanelPresentation`. The iPad Search-filter PNG confirms that inspector; result grids do **not** already exist.

**Change:** remote results use a two-column **metadata-rich** card grid when each card fits; refactor the existing `AO3WorkRow` presentation rather than replacing it with a title/cover tile. Local work matches may use the same rich grouping; keep fandom/tag/collection matches as clearly titled list sections. Preserve the explicit transition to AO3 search: a larger screen must not start network search while typing. This follows Music's category/results scan and Files' readable results, rather than adding a live detail-preview fetch.

| C | P | L | B |
|---|---|---|---|
| Existing lists, sheets and search behavior. | Rich two-column results only if summaries/stats/actions fit; otherwise readable single list. | Two result columns, reducing to one as inspector opens. Keep page-wide heading and pagination. | Pair result cells either side of exclusion, one scroll and server order; inspector or narrow pane can reduce results to one pane. Search field and page controls never bridge fold. |

Retain author/coauthor links, all status metadata, Expand All, privacy, bulk selection, and page navigation. Local List swipe actions must remain in the fallback list; a grid must offer the same operations in its existing context menu and selection controls. Do not treat `.adaptive` as fold-aware. Files: `SearchView.swift`, `SearchLocalResultsList.swift`, `AO3WorkRow.swift`, `SearchResultsHero.swift`, `SearchPaginationBar.swift`, `NativeBrowseView.swift` result callers. **No new layout toggle**: automatic reflow is enough. Existing detailed/expanded preferences stay meaningful.

### Account and its pages — Settings / Files navigation; Music profile content

**Model:** a stable destination list beside the chosen account page, with a readable form/detail area. No Apple app is an exact AO3-account analogue; the navigation pattern comes from Settings/Files and work/series lists from Music. Account identity and permissions remain Kudos's own.

**Today/iPad:** `Features/Account/AccountView.swift:151,473` owns a stack and routes. The only size-class adaptation here is shortcut columns at accessibility sizes (`627`); the grouped hub, Dashboard, works/series, Bookmarks, History, Marked for Later, Subscriptions, Collections, Drafts, Inbox, AO3 Preferences, More on AO3 and Settings are not an iPad split waiting for idiom removal. Shared `AO3AccountWorksList`, profile components and entity/card grids already supply presentation pieces. Preserve `AccountShortcutStore` choices, including explicitly choosing none.

| C | P | L | B |
|---|---|---|---|
| Current account hub and pushes. | Destinations | page if useful; longer forms or work detail become detail-only with navigation access. | Destinations | selected page; overview shows profile/shortcuts beside current content if it fits. | System split gives account destinations and page separate panes; entering Inbox/Settings replaces leading content, avoiding nested three-column navigation. |

Page treatment, all using the same C/P/L/B rules:

| Page(s) | Content recommendation / files |
|---|---|
| Account hub, Dashboard | Keep identity, posting pseud, shortcuts, counts and all grouped destinations. Reflow existing cards; no simultaneous loading of every destination. `AccountView.swift`, `AccountShortcuts.swift`, `AO3DashboardView.swift`, `Features/Authors/AuthorDashboardSections.swift`. |
| Works, Series, Subscriptions, Bookmarks, History, Marked for Later | Reuse rich row/grid policy in the detail pane. Keep date groups, bookmark notes/private/recommendation badges, scope/pseud filters, Updated/seen state and pagination. Subscription/history cover-grid modes already adapt through shared cards. `Features/Bookmarks/AO3AccountWorksList.swift`, `Features/Authors/AuthorProfile{View,Components,ContentSections}.swift`, `AO3SeriesDetailView.swift`. |
| AO3 Collections, collection detail/items | Collection index | selected collection, or full content when navigation would squeeze metadata. Retain Works/Bookmarks/People choices and existing management links; a further manager replaces the page rather than adding a third column. `AO3CollectionsList.swift`, `AO3CollectionDetailView.swift`, `AO3CollectionItemsView.swift`, `AO3CollectionFormView.swift`, relevant `Features/Challenges/*View.swift`. Forms use Settings' readable-width pattern, action lists retain every ownership/status/action signal. |
| AO3 Preferences | Keep one settings transaction, dirty state, Save and help, plus all privacy/notification choices. Use bounded Form/List inside the selected account pane; in Book pose keep its controls in one pane, not a control row across the fold. Do not add preference categories/subscreens merely to fill a second pane. `AO3PreferencesView.swift`. |
| More on AO3 | Readable grouped link list with the same destination behavior. It remains a launcher, not a new native version of each linked webpage. `AccountMoreOnAO3View.swift`, `AccountExternalNavCard.swift`, `Features/Browse/BrowseView.swift` (`AO3WebBrowserView`). |
| Drafts, Inbox, app Settings | Dedicated treatments below. |

**New control:** system local destination-list visibility and selection. Keep existing Settings gear and shortcuts pointing to the same routes. No newly designed AO3 page, account feature or network endpoint.

### Settings — iPad Settings

**Model:** category selection on the leading side, current settings form alongside it; related controls remain grouped. The [Settings guide](https://support.apple.com/en-euro/guide/ipad/ipadba23b9b4/ipados) documents the left-side settings navigation. Use `NavigationSplitView` + existing `SettingsDestination`, native `Form`/`List` and system pickers.

**Today/iPad:** `Settings/SettingsHubView.swift` already has the categories and `SettingsDestination` mapping, but pushes full-width `SettingsPageForm`; no iOS split. Settings pages are extracted, so reuse them. Reader spread eligibility now follows `WideLayout` in `SettingsView.swift`; do not redo T-448.

| C | P | L | B |
|---|---|---|---|
| Same hub → page stack. | Categories | selected settings page while it fits; collapse for large type. | Categories | bounded grouped form. | System split aligns around division; form controls and Save/Cancel/import buttons stay in the current pane. |

Keep all existing pages: Appearance, Font, Reader, Listening, Downloads, Preservation, Reading Queues, Library, Backup, Sync Folder, Import, Account, Privacy, About and Privacy/local-data management. Reuse existing values, defaults and importer ownership: one fileImporter per page, no merged form recreating the old multiple-importer bug. Start detail at the previously selected category in-session, or Appearance on first wide entry; selection alone performs no write. Back from Settings returns to Account's previous selection. Files: `SettingsHubView.swift`, `SettingsRoute.swift`, existing `Settings*Page(s).swift`, `AccountView.swift`. **New control:** system category-list visibility/selection. No settings search, new preference or persistent setting added by this round.

### Work Detail — Music album detail

**Model:** identity/art/primary action on one side, content and related items on the other, with a single subject. Use `ArrangementView` on 27.1 or measured side-by-side content regions; this is composition, not master-detail navigation. No new cover artwork is needed. A narrow parent pane retains the present single-column page.

**Today/iPad:** `Features/WorkDetail/WorkDetailView.swift:162,326` assembles one continuous List: hero/status, summary, AO3 actions, tags, facts, archive stats, comments links, page actions, series, My copy. Some header comments still describe old segmented sections; **the actual `pageSections` has no four-way segment to preserve or resurrect**. `WorkDetailIdentityBlock.swift` contains reusable identity, figure strip and resume card. No existing iPad two-column variant.

| C | P | L | B |
|---|---|---|---|
| Current content order and full information. | Prefer one centered readable column at 669; two columns only when the actual container meets minima. | Identity/figures/resume, stats and existing actions leading; summary, tags, facts, comments links and series trailing. | Same two groups, allocated either side of active division; inner scrolls stay in their pane. If parent is already split, expand detail first or retain one safe pane. |

Recommend two independently scrollable **content** regions at wide sizes so Read/Resume remains close while examining long tags; preserve logical accessibility traversal and current summary Show More. Keep errors/progress adjacent to the action that triggered them. Never lose warning tags, author links, dates, kudos/hits/bookmark/comment totals, chapter completeness, or My copy/local controls. Do not add a chapter index: the reader already owns Contents and remote chapter indexing would add behavior/traffic. Files: `WorkDetailView.swift`, `WorkDetailIdentityBlock.swift`, `WorkDetailOverviewSections.swift`, `WorkDetailSections.swift`, `WorkDetailFactsSections.swift`, `WorkDetailFigures.swift`, `WorkProvenanceSections.swift`; reuse existing action model. **No new control/screen.**

### Reader — Books reading surface

**Model:** readable text with temporary controls, one page when narrow, an optional spread where two readable pages fit. [Books reading and appearance controls](https://support.apple.com/en-euro/guide/ipad/ipadc8494b6b/ipados) establish the immersive text/menu model and adjustable text-column count. Automatic Book-pose behavior in Apple Books itself was **not directly verified**; the proposed Duo spread is a readability recommendation, not an HIG requirement.

**Decision:** one column in inner portrait; recommend a two-page spread in inner landscape and Book pose for **paged mode with the existing Two-page spread setting enabled**. Preserve an explicit off choice and Scroll mode. Do not change `readerTwoPage`'s stored/default Boolean as part of layout work; eligibility is already fixed by T-448. A paged off/large-font case and Scroll mode use one readable pane in Book pose, so no line crosses the fold. Do not silently turn scrolling into pagination or display duplicated text in two scroll views.

| C | P | L | B |
|---|---|---|---|
| Existing single page/scroll, side-safe content. | Single page/scroll centered at a readable measure; retain current typography and controls. | Spread when enabled and two page measures fit; otherwise centered single column. Scrolled text has a bounded measure. | Spread gutter contains the active division and its clearance; single-page/scroll fallback is entirely in one pane. Existing chrome clusters live wholly in usable panes. |

Start readability calibration around **55–75 characters per line** for one-page Latin prose; this is a design target, not an Apple rule. Use the current font's real metrics and user margins, not a fixed 800 pt line. Do not shrink text to obtain a spread. At large type collapse to one safe pane while retaining font size. Full background washes can span the fold.

#### What pinned Readium permits, and what it does not solve

`Package.resolved` pins **Readium Swift Toolkit 3.9.0**, revision `de07026e9f825a5791f27a7ac4cd6bb1a784ab8d`; the local checkout at `/Users/cidy02/Library/Developer/Xcode/DerivedData/kudos-polish/SourcePackages/checkouts/swift-toolkit` reports that exact HEAD. Inspected that source, not current upstream documentation:

- `Sources/Navigator/EPUB/Preferences/EPUBPreferences.swift:19,62` has `columnCount` and horizontal `pageMargins`; `Sources/Navigator/Preferences/Types.swift` has `.auto`, `.one`, `.two`. Kudos's `ReadiumReaderStyleMapper.swift` currently maps paged/enabled → `.auto`, disabled → `.one`, scroll → nil. T-448 removes the idiom restriction; it does not force two columns.
- Bundled `Assets/Static/readium-css/ReadiumCSS-after.css:195,450` gates responsive columns and user column overrides with `min-width:60em` or a device-width/orientation media query. `.auto` can therefore stay one column at Duo's usable width; even `.two` alone is **not** a proven escape from those CSS conditions. This is a plausible source explanation for the supplied enabled-but-single-column shot, not a runtime diagnosis from CSS measurement.
- `CSS/CSSProperties.swift:264` exposes `CSSRSProperties.colWidth`, `colCount`, `colGap`, `pageGutter`, `maxLineLength`; Kudos currently configures only the 1px base `pageGutter`. The gap property itself warns that scrolling must account for it. `EPUBNavigatorViewController.Configuration.readiumCSSRSProperties` is a configuration input, not a public live gutter preference. A runtime bridge needs explicit per-resource application and verification; changing the configuration value after open is not established as an update path.
- `EPUBNavigatorViewController` exposes `submitPreferences` (905), `firstVisibleElementLocator` (696) and `evaluateJavaScript` (931). Kudos already uses script setup/loaded-resource hooks and page measurements. No reserved-region/hinge/arrangement handling was found in the toolkit's Swift source. Native arrangement containers do **not** automatically split the HTML flowing within one navigator.
- Kudos's `ReadiumBook.navigatorContentInset` explicitly states paged Readium ignores horizontal content insets; use host sizing/CSS, not left/right inset guesses. Reflowable spread view hosts one reading-order document at a time. Fixed-layout EPUB spread behavior is separate; do not alter it by injecting reflow CSS.

For fixed-layout imports in Book pose, fit a whole page inside a usable pane, with its controls there; only show a pair when each complete page fits either side. Do not crop a fixed page at the fold to imitate a reflowable spread. Verify that fallback separately from AO3 EPUB fixtures.

**Implementation recommendation:** keep **one navigator**, one locator, one speech session. First measure effective computed CSS and real visible columns on the existing local fixture at 669/951 with actual safe areas. Then make the app's effective one/two-column choice and maximum measure explicit for reflowable HTML, through the existing style/script seam. Prefer available preference/RS properties, with the smallest app-owned CSS correction if bundled media queries defeat the chosen layout; no toolkit upgrade/fork in this round. Apply it on every affected resource load and geometry/region change, not just the current DOM once.

For Book pose, convert the region into the navigator's content coordinates. Insets from the side rail make the safe viewport asymmetric: its midpoint can differ from the physical fold. Inscribe an equal-page viewport centered on the actual division within the safe bounds, then choose the inner CSS clearance so neither page's text intersects the expanded exclusion. Keep the existing 1px page-margin calibration; don't increase the base gutter and accidentally multiply all user margins. **Do not just set `colGap = 40`, mask the middle, or mount two `EPUBNavigatorViewController`s.** CSS gap changes can alter scroll extent and turn distance. Prove a turn shows the next passage exactly once on both pages, including a chapter ending on the leading page.

Keep close/title controls within the leading page and fan/menu within the trailing page. Put the existing whole position/TTS card in the trailing pane, sized to fit; if that fails at accessibility sizes, use one safe pane's full width rather than splitting the slider or play control over the fold. Keep selection/color controls in the selected text's pane and all hit targets out of reserved regions. Reader chrome is custom, so root toolbar relocation does not solve it. Preserve explicit content shapes and peel dismissal.

Treat changed **region geometry even at unchanged window size** as reflow input through the existing T-449/T-450 lifecycle. Preserve T-450's element locator/navigation precedence and reuse its lifecycle, rather than designing another hold/restore mechanism. Include gutter, effective columns and max measure in layout invalidation; remeasure page bar, slider and completion. Existing visual metrics divide scroll width by viewport width (`ReadiumBook.swift:1125`): this measures a displayed spread/turn in two-column mode. Recommend retaining that existing turn-based slider metric and documenting/checking it consistently; do not naïvely double page counts. A new logical leaf-page numbering scheme would be separate product work.

Files: `Features/ReaderReadium/{ReadiumReaderView,ReadiumReaderStyleMapper,ReadiumBook,ReaderPageBoxGeometry,ReaderChromeTopBar,ReaderFanMenu,ReaderPositionCard,ReaderPageMetrics,ReaderChapterScrub}.swift`, shared region calculation. The loading fill is `ReaderPageSkeletonFill` inside `ReadiumReaderView.swift:58`; adapt that same fill rather than introducing another reader shell. `ReadiumResizeNavigation.swift` is a **baseline integration seam**, not a request to rewrite T-450. Tests in current reader geometry/metrics/locator/resize suites. **No new reader control or screen**; use existing mode and spread controls.

### Inbox and Comments — Mail / Messages list–thread

**Model:** selectable conversations beside the selected conversation, with list controls near the list and reply controls near the conversation. Mail's pane-local toolbar pattern is explicitly illustrated in the Duo HIG. Use `NavigationSplitView` and reuse the current thread content/model; no parallel copy of the thread state.

**Today/iPad:** `Features/Account/AccountInboxScreen.swift` is a List with action callbacks owned by `AccountView`; a thread pushes via `AccountInboxThreadDestination`. `Features/Comments/CommentsView.swift` is a List of existing top-level thread cards, with `pushedThread` opening `CommentThreadScreen`. `CommentThreadRow.swift` holds the display tree. There is already a dedicated thread screen; there is no iPad list–thread split. Composer is a sheet with bottom safe-area/keyboard relationship.

| C | P | L | B |
|---|---|---|---|
| Current list → thread and composer sheet. | Show list | thread if both fit; detail-only during long reading/composition when needed. | Inbox list | existing selected thread; standalone Comments uses existing root-thread list | selected full thread. | System split aligns list and thread around division; composer stays in an appropriate system presentation, with text and Post/Cancel in a usable region. |

No thread is fetched merely because the screen expanded. Show a passive “Select a conversation” detail until an explicit selection or existing deep link. For standalone Comments, first reuse its present top-level cards in the list; do not invent a preview-summary model or hide existing replies to achieve a tidy pane. Keep all original routes, chapter context, Parent Thread/Thread links, focus highlight, creator roles, read/unread/replied state, timestamps, counters, pagination, retry/stale state and owner-authorized actions. Tag-only Inbox destinations keep their current route. Account/session changes clear selected private detail too. One owner retains model/load/task lifetime across collapse, rotation and presentation changes; no duplicate metadata hydration or comment reads from two mounted roots.

Files: `AccountView.swift`, `AccountInboxScreen.swift`, `AccountInboxViews.swift`, `Features/Comments/{CommentsView,CommentThreadScreen,CommentThreadRow,CommentsModel}.swift` as needed for shared ownership, current thread destination definitions. `CommentThreadScreen` already renders an in-memory subtree without a request; preserve that property. Network services/action implementations unchanged. **New controls:** system split visibility and selected-thread highlight; a passive unselected state. No new messaging capability, inline composer or conversation-summary feature.

### Writing — Notes editing / Files documents

**Model:** a stable document/chapter list with an editor, and readable text rather than a full-width typing surface. [Notes](https://support.apple.com/en-euro/guide/ipad/ipadfeea407c/ipados) provides the editing analogy; the Duo HIG supplies direct Notes split-view fold evidence. Use `NavigationSplitView` for existing draft/chapter selection and keep the native text view mounted.

**Today/iPad:** `Features/Writing/WritingDraftsView.swift` has list/loading destinations; `WritingChaptersView.swift` has chapter rows; `WorkEditView.swift` is a long List form. `WritingTextEditor.swift:81` stretches `WritingNativeTextView` in a VStack; Preview overlays that same editor to preserve undo/selection. It already has recovery/checkpoints, markup tools and chapter actions. No hidden iPad editor split exists.

| C | P | L | B |
|---|---|---|---|
| Current list/form/editor; keyboard tools stay above keyboard. | Readable single editor; use collapsible draft/chapter list when appropriate, collapse when typing needs width. | Existing chapters/drafts | editor, with bounded text measure. Work metadata forms remain bounded rather than two unrelated field columns. | Navigator/list and editor occupy separate panes. If editing without a useful list, place the editor wholly in one pane; do not flow editable text across a hinge. |

Preserve **one `WritingTextController`**, native view identity, selection, undo/redo, raw HTML bytes, recovery key/account isolation, checkpoints, validation and Save/Post semantics through resize. Move layout constraints, not ownership. Keep existing Preview as a toggle/overlay; simultaneous edit/live preview would be a new feature and is excluded. Do not add automatic draft writes to AO3, auto chapter fetches or a fresh form parse on each geometry change. Files: `WritingDraftsView.swift`, `WritingChaptersView.swift`, `WorkEditView.swift`, `AddChapterView.swift`, `WritingTextEditor.swift`, `WritingNativeTextView.swift`, existing form/tag components. **New control:** standard list visibility/selection for existing documents/chapters only. No new editor mode.

## Vertical bars, labels and overflow

The current root `Tab` declarations already provide symbol **and** title. `UIComponents/ToolbarActionCluster.swift`'s `ToolbarIconButton` also uses a real `Label`; `ActionToolbar` forces `.iconOnly`. `WorkCardListControls.swift` supplies a separate custom ellipsis menu, and Search has a bare back Image plus a custom principal text field. Do not call every current toolbar item unlabeled: some already carry the necessary semantics.

Recommendation: retain existing appearance on earlier OS releases; on supported releases migrate toolbar overflow actions to **one `ToolbarOverflowMenu`**, rather than showing both system overflow and a custom More ellipsis. Keep menus for real choices (display mode, scopes) distinctly named/symbolized. Give all remaining image-only toolbar actions a semantic title/symbol (`Label` or system-image Button), letting native toolbar representation adapt. This does not mean forcing all titles visibly into a vertical rail; Apple can use them in overflow/expanded forms. Scope `.iconOnly` styling so it does not defeat that adaptation.

Suggested priority (ordering is a recommendation, not a claim of an unverified priority API):

1. Back/Close, then the active task's completion/cancellation controls.
2. Screen's primary work action: Read/Resume in content; compose/reply for conversation, Save/Post in editor, Filter for results, New for relevant collections/queues.
3. Selection and view choices: Select, Sort/Display, Expand/Collapse and applicable privacy action; keep current filter state/count visible even when actions compress.
4. Sharing, secondary management and destructive actions in system overflow, with existing destructive confirmations and labels.

Use default or `.prefersTabBar` compression on Home/Library/Browse/Account navigation; use `.prefersToolbarItems` for editing/selection tasks where completion actions matter most. Preserve the app's deliberate immersive-reader behavior; do not convert all reader controls into a toolbar in this plan. Leave list controls with their pane. A full search field remains horizontal in its own usable content area when vertical toolbar layout makes the current principal field unusable. Keyboard formatting/reply controls keep their keyboard relationship; they do not move sideways merely because system bars do.

Files: `ToolbarActionCluster.swift`, `WorkCardListControls.swift`, affected toolbar call sites (`HomeView`, `LibraryView`, `SearchView`, Account Inbox, Writing), `ContentView` only if explicit compression needs root scoping. Keep semantic action closures and disabled states unchanged; no broad navigation rewrite.

## New controls and screens

These are the complete layout additions proposed, not new product features:

| Addition | Why it exists |
|---|---|
| System show/hide local navigation and selected-row highlight in Library, queue/collection browser, Account, Settings, Inbox/Comments and existing draft/chapter navigation | Keep context, allow direct switching, and give a route back when compact/detail-only. Uses current destinations and data. |
| Passive unselected thread detail | Avoid opening/fetching a conversation without a user choice. Existing deep links still select their target. |
| Native system overflow presentation | Makes compressed vertical bars discoverable and consolidates existing actions; replaces a presentation, adds no action. |

No new tab, persistent layout preference, Duo mode switch, toolbar simulator/debug control, chapter browser, account page, preview screen or feature-only screen is required. New source helpers/hosts are implementation containers, not new user destinations.

## Feature ideas for the owner

**Outside every round below.** These are optional cross-platform product ideas for Claude-CLI to copy to `docs/android-port/FEATURE-IDEAS.md` for the owner's approval/denial; this task does not edit that file. Rough costs are engineering estimates including tests, not commitments. Existing queues already support pinning; Account already supports custom shortcuts; do not re-propose those as new.

| Idea | Apple model / reader benefit | Rough cost / AO3 traffic |
|---|---|---|
| Find a setting by name | Settings search. Locate reader, download and privacy options without remembering a category. Works on every platform, not a Duo pane requirement. | Small–medium, ~2–4 engineer days for a local route/label index, localization and tests. **No AO3 traffic.** |
| Optional line guide for reading | Books' [Line Guide](https://support.apple.com/en-euro/guide/ipad/ipadc8494b6b/ipados). Dim surrounding text to help track a line. Separate from normal TTS highlighting and from fold avoidance. | Medium–large, ~1–2 weeks for reflow/selection/accessibility and the separate platform readers. **No AO3 traffic.** |
| Back to where I jumped from | Books' [previous reading location](https://support.apple.com/en-euro/guide/ipad/ipadc8494b6b/ipados) control. Return after following Contents/search/bookmark without hunting for the old passage. This is a user navigation-history feature, separate from T-450's internal resize restore. | Medium, ~3–5 days per reader family for bounded locator history, command semantics and UI tests; confirm no equivalent exists at pickup. **No AO3 traffic for a local EPUB.** |

Do not import Music recommendations, News feeds, Notes collaboration, automatic inbox polling or live two-pane previews into this layout project. None is necessary to make existing content native, and several would change data/traffic policy.

## Implementation rounds

Each round is one focused implementation brief for Claude-CLI, with task/branch/review bookkeeping under the project's normal workflow **when implementing**. The planning task itself has no task-board mutation. Do not give one agent overlapping reader ownership while T-450 is being finished. Rounds 1–2 can proceed before reader integration; round 3 consumes the landed T-450 baseline. No implementation may claim visual success before viewing its output.

### Round 1 — readable Home and dashboard content

**Outcome:** opening the inner display immediately shows a composed reading app, and Book pose has no card or text crossing the fold.

**Files:** proposed `UIComponents/AdaptiveContentRegions.swift`; `HorizontalScrollViewport.swift` (only pane/group composition, preserve T-447 behavior); `TabDashboardShell.swift`; `Features/Home/{HomeView,HomeResumeHero,HomeCollectionShelves}.swift`; `Features/Library/LibraryView.swift` dashboard content. No root navigation replacement.

**Brief:** derive usable regions/fit thresholds; put hero beside next reading works; use bounded two-row card groups for wide shelves and pane-aware groups for Book; retain compact branches and original items/order. Extend existing `CarouselCardGrid` only where needed, do not build a second sizing system.

**Risks:** clipping rather than reflowing cards, duplicate items, blank loading width, author/privacy leaks, changing first work/resume behavior, scroll/VoiceOver order, Dynamic Type cards too wide for half a Book display.

**Claude checks:** C Home/Library with 3+ queues and last shelf card; P Home, then L Home/Library, then **same screen L → B → L without relaunch**. See hero/Resume and metadata wholly in one region, lower cards clear of division/rail. Compare ordinary iPhone and full/narrow iPad; Light/Dark/Sepia, default and AX5. Geometry tests include asymmetric safe areas, translated division, margins, inactive region and width too small for two cards; existing `CarouselCardSizingTests` stay green. More empty demo space alone is not failure; missing data is.

### Round 2 — local navigation that feels like Settings and Files

**Outcome:** Library sections and app settings become real large-screen destinations with context, and Account pages stop being stretched forms.

**Files:** `LibraryView.swift`, `LibrarySectionListView.swift`, `ReadingQueueBrowser.swift`, `ReadingQueueOrganizer.swift`, `ReadingQueuePageParts.swift`, `Collections.swift`; `AccountView.swift`, `Settings/{SettingsHubView,SettingsRoute}.swift` and page wrappers; Account preferences/more-page wrappers. Keep action/service files outside scope. Shared route-host extraction is acceptable, no model/schema changes.

**Brief:** install the two-pane local navigation policy, reuse existing routes, replace fixed queue HStack, constrain forms and rich rows. Settings and queue navigation replace the parent leading list; do not nest split views into three visible panes. Include Insights/Recently Deleted/collection management in the route and readable-width audit. No additional page is loaded because its label is visible.

**Risks:** breaking Back/deep links, lost `NavigationPath`, duplicate destination registration, root rail disappearing in regular queues, importer presenters reparented, dirty AO3 Preferences lost on collapse, inspector plus sidebar leaving no useful content.

**Claude checks:** C retains current stacks; P switch Library Reading Now/History/Favorites and Settings Appearance/Reader/Import; L queues, collection and Account page; B each split with the divider aligning to fold. Close/open sidebar and inspector; switch root tabs; return from detail; unfold with a selected queue/settings category and a dirty local preferences fixture. iPhone unchanged, iPad full-width and narrow split tested. Retain existing route/queue selection/filter tests, add collapse-selection/deep-link coverage where state changes; file import dialog remains a manual check with local files.

### Round 3 — readable pages and a real fold-aligned reader spread

**Outcome:** one-page prose has a readable measure; paged/enabled L/B shows two consecutive readable pages with the fold as gutter.

**Files:** reader scope listed above; keep the exact pinned toolkit. T-450 code is consumed, not reimplemented. Prefer a small app CSS/geometry bridge over dependency changes.

**Brief:** first record computed column count, media-query outcome, actual text rectangles and safe viewport; make effective columns/measure explicit; prove Book gutter and pane-contained chrome. Include **reserved-region-only** changes in layout invalidation and retain current navigation precedence. Fixed-layout, Scroll and large-font fallbacks are explicit acceptance cases. A single safe pane is a valid fallback, but does not complete the normal-font enabled-spread acceptance case.

**Risks:** highest round risk: skips/repeats after gap changes, incorrect CSS turn stride, asymmetrical rail shifting gutter off physical fold, stale resource CSS, page-bar/completion mismatch, lost locator or speech focus, fixed-layout corruption. If a CSS proof fails, keep the readable one-pane fallback while correcting the spread implementation; do not claim spread complete or create two competing navigators.

**Claude checks:** C/P single page; L paged spread enabled/disabled and Scroll; B enabled spread and one-pane Scroll/large-font fallback. Toggle **Open ↔ Partially Open at unchanged size**, rotate, fold to C and reopen mid-chapter with chrome up/down, TTS playing/paused, selection, Contents/search/bookmark/slider jumps. Verify exact passages around both page edges and chapter transitions, RTL content, imported fonts, reopen/resume, last-page completion, no control on fold. Run existing `ReadiumReaderTests`, `ReadiumLocatorPreservationTests`, `ReadiumResizeNavigationTests`, `ReadiumProgressPersistenceTests`, `ReadiumProgressParityTests` and page-box/metrics/scrub suites as applicable; add geometry+CSS contract regression for this change. Compare ordinary iPhone and iPad reader settings/turns. No AO3 needed: use local EPUB fixtures.

### Round 4 — work details, discovery and search that use the width

**Outcome:** Music-like work detail composition and dense discovery/results without 800 pt rows.

**Files:** Work Detail section files above; `Features/Search/{SearchView,SearchLocalResultsList,AO3WorkRow,SearchResultsHero,SearchPaginationBar,MediaBrowserView,FandomListView,FandomFamilyRows}.swift`; `Features/Browse/NativeBrowseView.swift`; relevant Account/Authors rich-result callers. Use region helper from round 1 and selection/route host from round 2.

**Brief:** two-region detail when its own container fits; adaptive category groups; rich two-column results; inspector collapses results rather than squeezing them. Preserve detailed rows and metadata; no chapter fetch or detail prefetch. Audit every caller of a changed shared row/card.

**Risks:** lost author hit targets, privacy leak, duplicate row navigation in a grid, disappearing swipes/actions, unstable pagination/order, making a narrow split-detail narrower still, silently restoring obsolete segmented Work Detail.

**Claude checks:** C baseline detail/results; P one-column work and fitting result grid; L long summary/tags/coauthors and expanded search cards; B both detail groups and result pairs around division. Open/close inspector and parent sidebar, select multiple results, reveal a mature card, use every existing card action from fixture data. iPad and iPhone comparisons; AX5 falls back without data loss. Extend `WorkDetailPresentationTests`, `BrowseAndWorkDetailRulesTests` and applicable selection/presentation tests only where behavior changed. Server URL/filter tests must stay unchanged.

### Round 5 — conversations and writing with stable selection

**Outcome:** Inbox/Comments read like Mail, and writing behaves like a native document editor rather than an edge-to-edge form.

**Files:** `AccountView.swift`, `AccountInboxScreen.swift`, `AccountInboxViews.swift`, Comments scope and Writing scope above. Change ownership seams only when needed to mount existing content once.

**Brief:** list | selected thread, draft/chapter | editor, bounded forms and text; one model/controller through folding. Keep current composer sheet and Preview toggle. No automatic first-thread load, background work, simultaneous live preview or changes to write operations.

**Risks:** duplicated Comments models/requests, account-private stale thread, reply draft loss, undo reset from view remount, uncheckpointed text lost on collapse, keyboard covering Post or markup tools.

**Claude checks:** C current list/thread; P collapse/expand and keyboard; L select Inbox thread then reply, select draft/chapter and type/undo/preview; B long thread and long editor with cursor by fold, then B → L → C without losing focus/draft/undo. Use fixtures/local recovery, no live posting. Check own/guest/deleted comments and chapter focus, failing/offline page state; theme/AX5. Keep `AO3InboxAccountTransitionTests`, `CommentsAccountTransitionTests`, `AO3CommentsParseTests`, `CommentSubmissionTests`, `WritingTextEditorTests`, `WritingCheckpointTests`, `WritingLargeChapterLayoutTests` and writing presentation tests green as applicable. Native editing/keyboard/selection remains a visual/manual check; layout does not authorize live writes.

### Round 6 — native rail polish and whole-flow acceptance

**Outcome:** controls remain discoverable through every bar position and compressed state, with no density regressions across the app.

**Files:** `UIComponents/{ToolbarActionCluster,WorkCardListControls}.swift`, scoped toolbar callers, `App/ContentView.swift` only if necessary for policy; tests and operational docs made inaccurate by the implementation. No custom replacement rail.

**Brief:** semantic title+symbol for all toolbar actions, consolidate system overflow on supported OS, task-appropriate compression, search field in a usable area, pane-local controls. Preserve earlier-OS/iPad behavior and the reader's established custom chrome. Inventory every existing action before/after; none may be lost in migrating More.

**Risks:** two ellipsis menus, unreadable expanded labels, forgotten destructive confirmation, unsupported availability on macOS/26.5, primary Save/Filter hidden, root navigation inaccessible in ordinary browsing, keyboard accessory moved incorrectly.

**Claude checks:** C side rail in all root tabs and long action menus; P horizontal bars; L/B rail with Settings, Account, queue select/reorder, Search filters and Writing. Back/Close, disabled actions, VoiceOver names and overflow order tested at AX5, with keyboard and sheets. Full iPad/narrow iPad and ordinary iPhone regression pass; macOS build validates platform guards. For each implementation round run the appropriate tests and project gates; before claiming the stack done run `Scripts/verify.sh`, both-platform builds per AGENTS, adversarial review, and the normal screenshot approval gate. Document what remains manual.

### Pose matrix and pass/fail record for every round

Claude-CLI can use `/Users/cidy02/kudos-tools/duo-pose Open|Closed|Partially Open|Rotate Right`; that capability is supplied context, **not executed or independently validated in this planning pass**. Do not equate “Partially Open” with a guaranteed vertical exclusion: inspect geometry after rotation as well. Capture C 466×678, P 669×951, L 951×669, and Book, plus the **transition without relaunch**. Retain screenshots with fixture, theme, text size, content mode, selected route, pose and measured usable regions. A screenshot filename/debug route alone is insufficient: wait until the intended destination and real content are visible.

Acceptance: all existing information/actions reachable; no text, card, slider or hit target straddles an active division or sits under the side rail; no smaller type to fit panes; no duplicate/missing results; navigation/editor/reader position survives transitions; wide layouts appear by available space on iPad and Duo alike; layout itself adds **zero AO3 requests**. Measured region placement, dependency CSS behavior and native bar compression remain implementation/runtime checks, not claims that this read-only plan has already verified them.
