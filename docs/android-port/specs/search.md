# Search Spec (Android Port)

## 1. Screen Tree

The Search feature is a tab root in the application, coordinating both local library and remote AO3 search states. It acts as a primary navigation point, capable of switching between an idle prompt, a live typing search, and a paginated results list. The view hierarchy transitions seamlessly based on the user's input and search phase.

- **Idle Screen (`SearchView.swift:391-426`)**: Displayed when the search query is empty. If the user has saved searches, it displays a `List` of these searches with their name and a salient subtitle of the filters. If no saved searches exist, it displays a `ContentUnavailableView` prompting the user to search their library or AO3.
- **Local Matches List (`SearchLocalResultsList.swift:18-124`)**: Displayed live as the user types, before they submit the search. It is a `List` containing:
  - An explicit action row to search AO3 for the query.
  - "In Your Library": Matching local works.
  - "Fandoms in Your Library": Matching fandom names from the user's library.
  - "Fandoms on AO3": Fandom matches from the cached AO3 catalog.
  - "Your Tags": Matching tags.
  - "Collections": Matching collections.
- **Loading State (`SearchView.swift:293`)**: While the first page of an AO3 search is fetching, an `AO3WorkRowSkeletonList(count: 7)` is displayed to show the shape of incoming results.
- **Loaded Results (`SearchView.swift:297-385`)**: Once the AO3 search completes, a card-based `List` takes over. It comprises:
  - `SearchResultsHero`: The header summarizing the search (subject, tags, filters applied).
  - Top `SearchPaginationBar`: Only shown if there is more than one page.
  - The results list: A `ForEach` over `SelectableAO3WorkRow` components for each matching work.
  - Bottom `SearchPaginationBar`.
- **Search Failed / Empty States (`SearchView.swift:613-630`)**: Replaces the list if the search yields zero results (`ContentUnavailableView.search`) or if the network request fails (a generic `ContentUnavailableView` with a "Try Again" action).
- **Filter Panel Inspector / Sheet (`AO3FilterPanel.swift:39-65`, `SearchView.swift:635-651`)**: Opens via the toolbar filter button or the hero header. On Android (similar to iPhone), it functions as a sheet (`.medium`, `.large` detents). It allows deep customization of AO3 filter parameters.
- **Save Search Sheet (`SaveSearchSheet.swift:22-108`, `SearchView.swift:265-274`)**: A sheet presented with medium and large detents to name and save the current filter set.

## 2. Components

The UI heavily utilizes a custom design language tailored for Kudos.

- **Search Wash (`SearchView.swift:371`)**: A themed `.subjectWash(resultsPalette, height: 600)` applies to the loaded results. This creates a visually distinct background gradient that saturates at the top and fades out, housing the header and filter chips.
- **Search Field (`SearchView.swift:571-584`)**: `GlassFieldBar` with a placeholder of "Library and AO3". It has a `.caption` magnifying glass icon leading, and a `.caption` `xmark.circle.fill` clear button trailing (only visible when not empty).
- **Filter Button (`SearchView.swift:216-222`)**: Appears in the principal toolbar action area. It takes an active state and a badge count (`SearchFilterBadge.count(for: filters)`).
- **Hero Header (`SearchView.swift:336`)**: `SearchResultsHero` is placed with `.pageBodyRow(top: 8, gutter: 0)` to span the full width above the card-based list.
- **Save Search Sheet (`SaveSearchSheet.swift:34-97`)**:
  - **Name Field**: `TextField` with `.plain` style, `font(.system(size: 17))`, padded horizontally by `14` and vertically by `12`. Uses `.subjectPanel()` and is placed with `.pageBodyRow(top: 14, gutter: SubjectMetrics.accountGutter)`.
  - **Explanation Text**: Below the name, using `font(.system(size: 11.5))` and `.secondary` foreground, placed with `.pageBodyRow(top: 6, gutter: SubjectMetrics.accountGutter)`.
  - **Empty Summary Panel**: When no filters exist, text uses `font(.system(size: 12.5))`, `.secondary` foreground, padded horizontally by `14` and vertically by `12`, styled with `.subjectPanel()`.
  - **Summary Chips Panel**: `FlowLayout` with spacing `6` and rowSpacing `6`. Padded horizontally by `14`, vertically by `13`, styled with `.subjectPanel()`. Placed with `.pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)`.
  - **Section Header**: `.pageBodyRow(top: 20, gutter: 0)`.
- **Summary Chip (`SaveSearchSheet.swift:150-179`)**:
  - Font: `.system(size: 12)`. Padding: `.horizontal, 9`, `.vertical, 4`.
  - Inclusion types determine color:
    - Included: `.green` foreground, `.green.opacity(0.15)` fill, `.green.opacity(0.35)` stroke.
    - Excluded: `.red` foreground, `.red.opacity(0.15)` fill, `.red.opacity(0.35)` stroke.
    - Facet: `.primary` foreground, `theme.appTheme.glassFill(0.10)` fill, `theme.appTheme.glassStroke(0.16)` stroke.
- **Local Matches Sub-Components (`SearchLocalResultsList.swift:83-85`)**: AO3 Fandom work count uses `font(.caption)` and `.secondary` foreground.

*Kotlin Component Mapping:* Use `GlassFieldBar` equivalent for the search bar, `SubjectPalette` for colors (e.g., `LocalSubjectPalette.current`), `Modifier.subjectScreenWash` for the background gradient, and `SubjectPanel` modifiers for cards. Font sizes should map closely to `sp` equivalent of `.system(size: X)`, recognizing that iOS uses strict points while Android will scale with user settings. (See `docs/android-port/briefs/1a-result.md`).

## 3. Data

Search unifies local SwiftData models and remote AO3 scraping.

- **Local Queries (`SearchView.swift:452-510`)**: 
  - Text normalization occurs via `WorkSearchIndex.normalize(query)`.
  - Limits: Works display up to `20` matches. Fandoms (Library), Tags, and Collections each display up to `12` matches (`prefix(12)`). AO3 cached fandoms have no explicit hard cap in the prefix code block, but rely on the upstream limits and filter out already-seen fandoms from the local library matches.
  - Sort Orders: `savedWorks` are fetched by `dateAdded` reverse (`.reverse`). `allTags` by `name`. `collections` by `dateAdded` reverse.
  - Debounce: User typing is debounced by `150` milliseconds (`SearchView.swift:465`) before hitting the local `computeLocalMatches()`.
  - Trigger Keys: Local matches re-evaluate when `localQuery`, `workCount`, `tagCount`, `collectionCount`, or `catalogRevision` change.
- **Remote AO3 Queries**:
  - Bound to `AO3SearchFilters`, representing the state of the `AO3FilterPanel`.
  - `loadToken` is incremented whenever a search is superseded, discarding stale loads (`SearchView.swift:49`, `664`, `683`).
  - `requestedPage` ensures that if a page load fails (e.g., page 7), "Try Again" re-attempts page 7 rather than falling back to page 1 (`SearchView.swift:34`).
- **Android Repo Counterpart**: Use Kotlin Coroutines (`delay(150)`) for debouncing. Room DAO queries should handle the sorting (`ORDER BY dateAdded DESC`). Normalize using localized lowercase/diacritic folding to match `WorkSearchIndex`. 

## 4. Interactions

- **Toolbar & Chrome**:
  - Tapping the Filter button opens the `AO3FilterPanel`.
  - "Select" in the `WorkListMoreMenu` enters bulk selection mode. While selecting local works, a bottom bar on iOS (primary action bar on macOS/Android) presents `WorkBulkActionBar`.
  - Focus and Back: The root search acts as a full-screen mode replacing the idle Browse-by-fandom state. Back stepping (`edgeSwipeToGoBack`, `SearchView.swift:251`) steps back through history states (results -> Browse -> previous tab).
- **Tag Drill-Down (`SearchView.swift:750-782`)**:
  - Tapping a tag pushes the current filter configuration into `filterHistory`.
  - Restoring pops the history, restoring the exact `AO3WorkSummary` array and pagination without refetching from AO3.
- **Pull-to-Refresh (`SearchView.swift:372`)**: Applies `refreshable` to the loaded results view, re-fetching the current page from AO3. `cancelRefreshOnTabChange` acts as a lifecycle hook to terminate pending loads if the user switches away from the Search tab.
- **Selection (`SearchLocalResultsList.swift:101-110`)**:
  - `SensitiveWorkRow` provides a long-press menu and toggles selection via `onToggleSelection: { toggle(work) }`.

## 5. Strings

- `SearchView.swift`:
  - `"Search"`
  - `"Back"`
  - `"Select"`
  - `"Saved Searches"`
  - `"Search above for works in your Library or on AO3. To explore by fandom, use the Browse tab."`
  - `"Search Kudos"`
  - `"Search your Library or AO3 by title, author, or tag. You can browse fandoms and categories in the Browse tab."`
  - `"Saved Search"`
  - `"Search failed"`
  - `"Try Again"`
- `SearchLocalResultsList.swift`:
  - `"Search AO3 for “\(query)”"`
  - `"Archive of Our Own"`
  - `"In Your Library"`
  - `"Fandoms in Your Library"`
  - `"Fandoms on AO3"`
  - `"Your Tags"`
  - `"Collections"`
- `SaveSearchSheet.swift`:
  - `"Name"`
  - `"The name comes from your search. You can change it to anything."`
  - `"You haven't chosen any filters, so only the name will be saved."`
  - `"Only the choices you changed are saved."`
  - `"What gets saved"`
  - `"Save Search"`
  - `"Cancel"`
  - `"Save"`

## 6. Owner Decisions

Several critical product decisions have been documented by the owner that dictate how the UI and logic must behave. Do not deviate from these behaviors without explicit approval.

1. **Global actions live in the top-right chrome** (`FandomFamilyRows.swift:212`, `FandomListView.swift:238`): The owner specified (2026-10-01) that global actions like Filter always sit in the top-right navigation bar space.
2. **Filter is the toolbar's one way in** (`SearchResultsHero.swift:27`): The `1k` specification originally had a dashed Filter chip at the end of the chip rail. This was removed (owner, 2026-10-01); the toolbar Filter button is the only ingress point for the panel.
3. **Downloads count EPUBs strictly** (`MediaBrowserView.swift:764`): "N downloaded" specifically refers to the EPUBs physically present on the device (owner, 2026-09-28).
4. **"I have downloads from"** (`FandomListView.swift:67`): Refers strictly to explicitly *kept copies* (favorites/downloads), not temporary files fetched automatically simply to read the work (owner, 2026-10-01).

Additionally, per `TASKS.md`:
- **UI Consistency**: UI modernization must preserve or improve information density. Any visually cleaner design that reduces scannability or hides metadata is considered a regression.

## 7. Android Gaps

When porting this robust Search to Android (Kotlin/Compose), the following gaps and differences must be accounted for:

1. **Text Normalization**: Swift's `String.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)` handles the heavy lifting for `WorkSearchIndex`. The Android equivalent (e.g., `java.text.Normalizer` with regex replacements) must match the exact same Unicode rules, lest the local search index diverge and fail to find records the iOS app finds.
2. **SwiftData vs Room**: `SearchView` heavily relies on SwiftData's `@Query` to automatically observe table row counts (`savedWorks.count`). In Compose, this necessitates robust `Flow` observation in the ViewModel to pass state down, ensuring the `LocalMatchKey` reacts exactly to count changes.
3. **Debounce Cancellation**: `Task.sleep` inside `.task(id:)` is used to debounce user keystrokes, and is automatically cancelled by SwiftUI when `localMatchKey` changes. Compose's `LaunchedEffect(key1)` with `delay(150)` provides the exact same cancellation semantics, but requires careful implementation to not leak coroutines or block the UI thread.
4. **View Paging**: iOS utilizes `ScrollViewReader` with `proxy.scrollTo(paginationTopID, anchor: .top)` to snap to the top when the user changes pages. Compose will require a `LazyListState` and `animateScrollToItem(0)`.
5. **Wash Gradient & Safe Area**: The `subjectScreenWash` assumes a continuous safe-area bleed. Compose's WindowInsets will need to be configured so the background gradient draws behind the transparent system status bar without pushing the `SearchResultsHero` down into an incorrect offset.
6. **Navigation Hierarchy**: `SearchView`'s unique behavior where a root back edge swipe (`edgeSwipeToGoBack`) pops through the `Browse` mode rather than immediately closing the tab must be implemented via custom `BackHandler` interceptors in Compose.
