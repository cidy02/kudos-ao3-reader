# Account Tab Port Specification

## 1. Screen tree

The Account tab serves as the centralized hub for a user's signed-in AO3 profile and local application data related to reading history. The structure was initially designed as four nested scopes but was subsequently flattened into a continuous vertical layout to improve discoverability.

- **Root View**: `AccountView` (`Features/Account/AccountView.swift:19`)
  - Contains a `NavigationStack` bound to a `$path` variable for deep linking and stack management.
  - Switches between `libraryStyleCompactRoot` (`AccountView.swift:149`) and `standardListRoot` (`AccountView.swift:151`) depending on the `usesLibraryStyleCompactLayout` property. However, compact layout is currently deactivated for scopes since `showsWorkListControls` forces false (`AccountView.swift:536`).
  - The `standardListRoot` (`AccountView.swift:275`) is a `List` configured with the `.cardList()` modifier and `.refreshable` (`AccountView.swift:286`).
  - **Sections** (`AccountView.swift:594`):
    - `shortcutsSection`: Grid of user-selected `AccountShortcut` items (`AccountView.swift:622`).
    - `readingScopeGroups`: Contains Marked for Later, Bookmarks, Collections, and Subscriptions.
    - `writingScopeGroups`: Contains Works, Series, Drafts.
    - `activityScopeGroups`: Contains History, Inbox.
    - `accountGroupSection`: Contains Preferences, More on AO3 (`AccountView.swift:671`).
  - **Overlays and Chrome**:
    - The navigation bar is hidden by default using `#if os(iOS)` toolbar controls (`AccountView.swift:166`), except when the Inbox is in selection mode (`inboxModel.isSelecting`).
    - `floatingChromeRow` is overlaid at the top-trailing edge (`AccountView.swift:169`), housing global actions like settings and filters.

- **Destinations** (`AccountView.swift:171`):
  - `.myCollections` -> `AO3CollectionsList()`
  - `.preferences` -> `AO3PreferencesView()`
  - `.moreOnAO3` -> `AccountMoreOnAO3View()`
  - `.settings` -> `SettingsHubView()`
  - `.dashboard` -> `AO3DashboardView()` (`AccountView.swift:469`)
  - `.drafts` -> `WritingDraftsView()` (`AccountView.swift:470`)
  - `.myWorks` -> `AuthorProfileView` initialized with `title: "Works", tab: .works` (`AccountView.swift:471`)
  - `.mySeries` -> `AuthorProfileView` initialized with `title: "Series", tab: .series` (`AccountView.swift:472`)
  - `.inbox` -> `AccountInboxScreen` (`AccountView.swift:474`)
  - `AO3AccountWorksList.Kind` -> `AO3AccountWorksList` (`AccountView.swift:182`)
  - `SavedWork` -> `WorkDetailView` (`AccountView.swift:196`)
  - `AccountInboxThreadDestination` -> `CommentsView` (`AccountView.swift:204`)

- **Modals and Sheets**:
  - **Login**: `AO3LoginView` presented by `$showingLogin` (`AccountView.swift:219`).
  - **Shortcut Editor**: `AccountShortcutsEditor` presented by `$editingShortcuts` (`AccountView.swift:221`).
  - **Refine Filters**: `AO3FilterPanel` presented by `$showingFilters` (`AccountView.swift:224`).
  - **Inbox Filters**: `AccountInboxFilterSheet` presented by `$showingInboxFilters` (`AccountView.swift:240`).


## 2. Components

The UI relies heavily on shared generic components to maintain visual consistency with the Author Profile screens. Android implementations must accurately port these sizes, colors, and margins.

### `AccountProfileCard` (`Features/Account/AccountComponents.swift:12`)
The user's identity card representing their AO3 session status.
- **Skeleton State** (`AccountComponents.swift:38`):
  - `SkeletonBlock` for avatar: 72x72pt, 8pt corner radius.
  - Three `SkeletonTextLine` items: width 150 (height 20), width 110, width 180, spaced by 9pt.
- **Signed-in Avatar**: `AO3AuthorAvatar`, 56pt size, `isCircular: true` (`AccountComponents.swift:62`).
- **Username** (`AccountComponents.swift:88`): Uses Dynamic Type `nameSize` scaled relative to `.title2` (base 27pt). Font weight `.bold`, tracking `-0.5`, line limit 1, minimum scale factor `0.5`.
- **Posting As Menu** (`AccountComponents.swift:113`): 
  - Text: 13pt, `.medium` weight.
  - Padding: horizontal 13pt, vertical 7pt.
  - Background: `theme.appTheme.glassFill(0.12)` in a `Capsule()`.
  - Hit target: uses `.contentShape(Capsule().inset(by: -7))` to guarantee a 44pt touch area while drawing a 30pt visual height (`AccountComponents.swift:141`).
- **More Actions Menu** (`AccountComponents.swift:244`):
  - Icon: 14pt `.semibold` `ellipsis`.
  - Frame: 36pt width, 30pt height. Background matches the `glassFill(0.12)` capsule.
- **Session Status Line** (`AccountComponents.swift:177`):
  - Icon: `.caption` font size. Uses symbols like `checkmark.circle.fill` (green), `arrow.triangle.2.circlepath` (secondary), `checkmark.seal.fill` (green), `xmark.seal.fill` (red), `wifi.exclamationmark` (orange) depending on `sessionHealth`.
  - Text: `.caption` size, `.secondary` color, line limit 1.

### `AccountShortcutGridTile` (`Features/Account/AccountComponents.swift:406`)
Tiles placed inside a `LazyVGrid` (`AccountView.swift:626`).
- **Grid Layout**: 3 columns with 10pt spacing. Drops to 2 columns if `dynamicTypeSize.isAccessibilitySize` and `horizontalSizeClass == .compact` (`AccountView.swift:612`).
- **Tile Surface**: Min height 56pt, padded by 8pt, corner radius 14pt, uses `.subjectPanel()` modifier (`AccountComponents.swift:467`).
- **Icon Block**: 22x22pt frame, `.semibold` 12pt symbol.
  - Background: 6pt radius, `tint.opacity(0.16)` fill.
  - Overlay: `theme.appTheme.glassStroke(0.1)` with `0.5` line width (`AccountComponents.swift:435`).
- **Title**: Scaled relative to `.caption` (base 11.5pt), `.medium` weight. Max 2 lines.
- **Count Indicator**: Scaled relative to `.caption2` (base 11pt), `.medium` weight, monospaced design.

### `AccountInboxItemRow` (`Features/Account/AccountInboxViews.swift:131`)
- **Byline** (`AccountInboxViews.swift:345`): Unread indicator is an 8x8pt circle filled with `.tint`. Username is 14pt (`.subheadline`) semibold. Time elapsed is 11pt (`.caption2`) tertiary.
- **Replied Badge** (`AccountInboxViews.swift:483`): Text "Replied", 11pt (`.caption2`) semibold. Foreground `.green`, background `.green.opacity(0.12)` in a Capsule shape, horizontal padding 8pt, vertical 3pt.
- **Avatar**: Uses `CommentAvatar` with a 40pt size (`AccountInboxViews.swift:418`).
- **Inbox Panel Segment** (`AccountInboxViews.swift:761`):
  - Gaps: 12pt top gap for the first item, 12pt bottom gap for the last item.
  - Border Radii: 14pt on the top corners of the first item, 14pt on the bottom corners of the last item.
  - Background: `glassFill(0.09)` with a `SubjectRowSeparator(inset: 0)` overlay on the bottom edge (`AccountInboxViews.swift:794`).

### Kotlin Equivalents (Android Gaps)
According to `docs/android-port/briefs/1a-result.md`:
- Colors and palettes are resolved through `SubjectPalette` and `KudosTokens`.
- `SubjectChip` and `.Style` are translated to `SubjectChip` and `SubjectChipStyle`.
- iOS `minimumScaleFactor` text shrinking has no direct Compose equivalent ported yet; `sp` scales freely.
- `subjectPanel` stroke is a centered border. The dashed chip stroke is inset by half its width. Selected pill fill uses exact picked hue-derived color `accent` on Compose.


## 3. Data

Data loading is partitioned by scope but centralized in the view's task lifecycle.

- **Model Instantiation**: `AccountView` receives `AO3AuthService`, `AppRouter`, and `ThemeManager` from the environment. `localWorks` are retrieved via `@Query` (`AccountView.swift:25`).
- **Activation** (`AccountView.swift:377`): `activateVisibleContent()` selectively triggers network tasks based on the currently selected `AccountTab` to prevent over-fetching. For example, the Inbox feed (`inboxModel.activate(auth: auth)`) is only prefetched when the user visibly selects `Activity > Inbox`.
- **Sorting and Filtering**:
  - **Bookmarks** (`Features/Bookmarks/AO3BookmarksWorksBrowser.swift`): `AO3BookmarksFilter` allows filtering by `.all`, `.recs`, `.private`, and `.withNotes`. The `withNotes` parameter evaluates as `!notes.isEmpty` based on `AO3RichText` (`AO3BookmarksWorksBrowser.swift:53`).
  - **Marked For Later** (`Features/Bookmarks/AO3MarkedForLaterWorksBrowser.swift`): `AO3MarkedForLaterFilter` has `.all`, `.updated`, and `.downloaded`. The `updated` flag is determined by `SubscriptionWatermarks.newChapterCount(for: work, watermarks: watermarks) > 0` (`AO3MarkedForLaterWorksBrowser.swift:68`). `downloaded` evaluates the local `.isDownloaded` state (`AO3MarkedForLaterWorksBrowser.swift:74`). Groups rows into `updatedSinceYouLooked` (Cover cards layout) and `everythingElse` (Ledger row layout).
  - **Subscriptions** (`Features/Bookmarks/AO3SubscriptionsWorksBrowser.swift`): Filtered by `.all` and `.updated`. Subscriptions initially return sparse data (`isIndexOnly()`); they are asynchronously enriched via `AO3SparseWorkEnricher` limited to 3 concurrent in-flight fetches (`AO3SubscriptionsPageEnrichment.swift:22`).
  - **History** (`Features/Bookmarks/AO3HistoryWorksBrowser.swift`): Uses `AO3HistoryProgressFilter` and is grouped chronologically using `AO3HistoryVisitGrouping`.

## 4. Interactions

- **Taps**:
  - `AccountProfileCard`: Tapping the avatar or username triggers `onViewProfile` which appends `AO3AuthorRoute` to the path (`AccountView.swift:565`).
  - `AccountShortcutGridTile`: Action routes through `openShortcut(_:)` matching enum cases to navigation routes (`AccountView.swift:652`).
  - `AccountInboxItemRow`: The visible card body is covered by a hidden `.contentShape(Rectangle())` button to handle opening the comment thread. Overlaid buttons catch chapter link taps and reply taps (`AccountInboxViews.swift:187`).

- **Menus & Pickers**:
  - **Posting As**: Native iOS `Menu` displaying the user's fetched pseuds plus "Account Default". Sets preference in `AO3AuthService` (`AccountComponents.swift:166`).
  - **More Actions (Inbox)**: Includes "Open Thread", "Chapter Comments", "Copy Link", "Mark Read/Unread", and a `.destructive` "Delete From Inbox" role (`AccountInboxViews.swift:429`).
  - **Toolbar Controls**: When `isInboxVisible` and `model.isSelecting`, the global toolbar is usurped by `SelectAllButton` and `AccountInboxBulkActionBar` (`AccountInboxViews.swift:53`).

- **Swipe Actions**:
  - iOS uses `.swipeActions(edge: .trailing, allowsFullSwipe: false)`.
  - **History**: "Delete from history" (`AO3HistoryWorksBrowser.swift:141`).
  - **Subscriptions**: "Unsubscribe" (`AO3SubscriptionsWorksBrowser.swift:368`).
  - **Inbox**: "Mark Read" / "Mark Unread", and "Delete". Crucially, `allowsFullSwipe` is false so a user cannot accidentally trigger a destructive network request with a long flick (`AccountInboxViews.swift:676`).
  - **Marked for Later**: Does not use a swipe action for the `unmark` operation. It uses a dedicated `SubjectChip` button styled as "Unmark" (`clock.badge.xmark`) positioned explicitly underneath the ledger row or cover card (`AO3MarkedForLaterWorksBrowser.swift:392`).

- **Pull-to-refresh**:
  - Triggered by `.refreshable` (`AccountView.swift:286`). Asynchronously calls `refreshCurrentTab()`, which bumps the integer `@State private var listReloadToken` or explicitly awaits `model.refresh(auth: auth)` depending on the active scope (`AccountView.swift:427`).


## 5. Strings

Verbatim text values extracted from the codebase to ensure parity:

- **Profile & Auth**:
  - `"AO3 Account"`, `"Posting as"`, `"Account Default"`
  - `"Session verified"`, `"Signed in · verified"`, `"Session expired"`, `"Checking session…"`
  - `"Not signed in"`
  - `"Log in to see your AO3 works, bookmarks, subscriptions, history and inbox. Your sign-in stays on this device."`
- **Inbox**:
  - `"Inbox"`, `"Select All"`, `"Couldn't update Inbox"`, `"AO3 couldn't update your Inbox."`
  - `"A comment here is unavailable"`
  - `"Showing cached AO3 data"`
  - `"No comments yet"`: `"Comments on your works and replies to your comments appear here from your AO3 inbox."`
- **Shortcuts Editor**:
  - `"Shortcuts"`, `"On the grid"`, `"Not on the grid"`, `"Reset to Default"`
  - `"If you choose none, the grid is hidden. You can still find every destination in the sections below."`
- **Shortcuts Grid Labels**:
  - `"Dashboard"`, `"Marked for Later"`, `"Bookmarks"`, `"Collections"`, `"Subscriptions"`, `"Works"`, `"Series"`, `"Drafts"`, `"History"`, `"Inbox"`, `"Preferences"`, `"More on AO3"`
- **Filter Pills**:
  - `"All"`, `"Recs"`, `"Private"`, `"With notes"` (Bookmarks)
  - `"All"`, `"Updated"`, `"Downloaded"` (Marked for Later)
  - `"New since you last looked"`, `"All works"` (Subscriptions groups)
- **Footers / Helper Copy**:
  - Bookmarks: `"These are your AO3 bookmarks. Each row shows that bookmark's note, tags, date, privacy and recommendation status. The filters apply to X of Y pages."`
  - Marked for Later: `"Your Marked for Later list is stored on AO3. Unmarking a work here also removes it from that list on AO3. You're viewing X of Y pages."`
  - Subscriptions: `"Your subscriptions are stored on AO3. Unsubscribing here also unsubscribes you on AO3. You're viewing X of Y pages."`


## 6. Owner decisions

Specific product rationale annotated by the repository owner (`owner, 2026-` and `TASKS.md` references) that dictate implementation quirks:

- **Flattened Hub (`AccountView.swift:574`)**: "Flattened, per the owner: shortcuts, the three scopes in order, then the account's own two pages." The segmented control (which previously swapped scopes) was completely removed because navigating sub-menus "was a level of navigation that existed only to reach navigation."
- **Group Naming (`AccountView.swift:585`)**: "One group per scope, named for the scope — per the owner." Group headers specifically replace the segmented control titles.
- **Shortcut Grid Layout (`AccountView.swift:606`)**: The 3x2 grid algorithm is explicitly allowed to drop to 2 columns on compact widths with accessibility fonts, but on regular widths (iPad/macOS) it always keeps 3 columns "even at those sizes — it has the room, and dropping a column there just leaves two over-wide tiles and wasted space (owner-reported)."
- **Inbox Select Controls (`AccountInboxScreen.swift:218`)**: "Filter stays a button; Select lives in the '…', as on every other list (owner, 2026-10-01 — 1l draws it as its own glass button)."
- **Downloaded Flag (`AO3MarkedForLaterWorksBrowser.swift:72`)**: The `isDownloaded` check is evaluated against local filesystem copies and is "kept, not just fetched to read (owner, 2026-10-01)."
- **VoiceOver Grouping (`AccountInboxViews.swift:182`)**: The inbox notification card collapses all internal buttons into a single accessibility element (`.accessibilityElement(children: .ignore)`) and surfaces secondary actions (reply, chapter comments) through the iOS accessibility rotor (`.accessibilityActions { ... }`). (UI-2/T91-RF10).


## 7. Android gaps

Features and logic not yet ported or differing from iOS according to `docs/android-port/briefs/1a-result.md` and codebase analysis:

- **Missing Layouts**: `SubjectFormRow`, `SubjectFilterRail`, and `WorkLedgerRow` have not been ported to Android.
- **Missing Filters UI**: The internal contents of filter menus (e.g., `AccountInboxFilterSheet`) are unimplemented in the Android catalog.
- **Typography Scaling**: iOS `minimumScaleFactor` text shrinking has no direct Compose equivalent implemented; Android `sp` units currently scale freely without capping bounds. The stat-strip Dynamic Type cap is notably not applied.
- **Theme Sync**: The Android design catalog preview currently does not save or write theme settings to local persistence.
- **Dimming Elements**: `WorkReadingOrDownloadRing` and background download dimming states are absent.
- **Color Fidelity**: Selected pill fills and accented glass elements use the exact picked hue-derived `accent` color natively in Compose, rather than emulating the Swift float opacity derivation.
- **Icon Assets**: The `AccountIconSquare` used in shortcuts does not exist; Android substitutes `AccentIconSquare`.
