# Browse Porting Specification

This specification details the porting of the iOS Browse experience to Android. The iOS implementation in `kudos-ao3-reader/Features/Browse` and `kudos-ao3-reader/Features/Search` serves as the source of truth.

## 1. Screen tree

The iOS Browse experience is a multi-step drill-down using a shared `NavigationStack`. It starts at media categories, descends to fandom lists, and finally to work results.

1. **`MediaBrowserView`** (`Features/Search/MediaBrowserView.swift`)
   - **Loading State:** `CategoryCardSkeletonList` renders placeholders.
   - **Jump Back In Section:** A horizontal scroll of up to 3 `jumpBackInCard`s showing the most recently read fandoms.
   - **Categories List:** Full-width `SubjectPanel` rows (`categoryPanel` on iOS) for each `AO3MediaCategory`.
     - Includes a `SubjectKicker`, the category name, a `statsLine` (fandom count, work count, downloaded count).
     - Contains a `FandomChipCluster` showing up to 12 featured fandom chips and a "+N more" chip, plus "Recently read" `TagChip`s.
   - **Open AO3 Website Row:** A dashed, rounded button to launch the fallback web view.
   - **Instructions Text:** Footer text beneath the list.
2. **`FandomListView`** (`Features/Search/FandomListView.swift`)
   - **Pushed when:** A category card is tapped.
   - **Loading State:** `FandomRowSkeletonList`.
   - **Header:** `SubjectHeaderBlock` with the category name and tally subtitle.
   - **Sort Rail:** `FandomListSortRail` containing chips for A-Z / Size sort and a "Group variants" toggle.
   - **List Content:**
     - **Empty/Filtered State:** `ContentUnavailableView` stating no matches.
     - **A-Z Mode:** `FandomLetterHeader` sections grouped by starting letter.
     - **Items:** `FandomFamilyBlock` (for grouped families) or `FandomListRow` (for single fandoms).
   - **Overlay:** An alphabetical scrubbing index on the trailing edge.
3. **`FandomWorksView` / `TagWorksView`** (`Features/Browse/NativeBrowseView.swift`)
   - **Pushed when:** A fandom or family is tapped.
   - **Loading State:** `AO3WorkRowSkeletonList`.
   - **Hero Header:** `SearchResultsHero` providing the result total, active filter labels, and a sort menu.
   - **Pagination:** `SearchPaginationBar` at the top and bottom of the list.
   - **Work Cards:** `SelectableAO3WorkRow` wrapped in a `cardRow`.
   - **Empty States:** "No matching works" (when over-filtered) or "No works found" (true zero).
4. **`AO3WebBrowserView`** (`Features/Browse/BrowseView.swift`)
   - **Fallback Browser:** Displayed for raw AO3 URLs or the "Open AO3 Website" button.
   - **Header:** Native toolbar with Back, Forward, `GlassFieldBar` (address), Bookmark, and Done buttons.
   - **Banner:** Overlay for successful EPUB import / bookmark actions.

## 2. Components

Key components used in the iOS implementation and their status in Android (`SubjectComponents.kt`):

- **`SubjectPanel`**: Used for category rows on iOS. Draws a tinted glass ground with a leading symbol and optional content block below. **Missing** in Android (Android only has the `Modifier.subjectPanel`, not the container composable).
- **`SubjectKicker`**: Accent-coloured uppercase label with a short rule. **Present** in Android.
- **`SubjectHeaderBlock`**: Large page header with a kicker, title (32sp), and subtitle. **Present** in Android.
- **`SubjectChip`**: Used in `FandomListSortRail`. Supports Neutral, Tinted, Dashed, and Pill styles. **Present** in Android.
- **`FilterButton`**: Used in toolbars with a numeric badge. **Present** in Android.
- **`FandomChipCluster`**: Wraps fandom chips up to a limit (12), rendering a "+N more" remainder chip. **Missing** in Android.
- **`TagChip`**: Minimal button used for "Recently read" fandoms. **Missing** in Android.
- **`FandomLetterHeader`**: A-Z section header with the letter, count, and hairline. **Missing** in Android.
- **`FandomListSortRail`**: Horizontal scrolling rail of sort chips and toggles. **Missing** in Android.
- **`FandomFamilyBlock`**: Complex row showing a parsed family title, aliases, a total count, and a list of disambiguated members beneath a vertical hairline. Sizes: Member row uses `subheadline` for the title, `caption` for the count. **Missing** in Android.
- **`SearchPaginationBar`**: Row with Previous/Next buttons and page numbers. **Missing** in Android.
- **`SearchResultsHero`**: Standardised 1k page head with stats and sort dropdown. **Missing** in Android.
- **`GlassFieldBar`**: Address/search bar for the web view. **Missing** in Android.

## 3. Data

- **Media Categories (`MediaBrowserView`)**:
  - Fetched via `AO3Client.shared.categories` (from `/media`).
  - **Derived Stats**: Fandom count, work count, and downloaded count are derived off the main actor by cross-referencing the cached `FandomCatalog` and the local `library` of `SavedWork`s.
  - **Jump Back In**: Selects up to 3 most recently read fandoms from the local library.
- **Fandom Lists (`FandomListView`)**:
  - Fetched via `/media/<name>/fandoms`.
  - **Grouping**: Fandom tags are processed via `FandomFamily.grouped`, parsing disambiguations (e.g., "(Anime & Manga)", "- All Media Types") to merge sibling tags under one `FandomFamily` title.
  - **Sorting**: "A-Z" (`.alphabetical`) or "Most works" (`.familyTotal`).
  - **Filtering**: Local substring search, plus complex toggles (`hideRPF`, `favouritedOnly`, etc.).
- **Fandom Works (`FandomWorksView` / `TagWorksView`)**:
  - For a single tag, requests `/tags/<name>/works`.
  - For a family (multiple sibling tags), runs a union search via `/works/search` with the query clause derived from `AO3FandomUnion.queryClause(filterIDs:)`.
  - **Sort Order**: Explicitly seeds `.dateUpdated` so the filter panel reflects the true AO3 listing default instead of `.relevance`.
- **Android Sources**: Android currently lacks the deep `FandomCatalog` caching and `FandomFamily` grouping logic. It relies on basic network calls, meaning the heavily derived `CategoryStats` and disambiguation parsing must be built in the repository layer.

## 4. Interactions

- **MediaBrowserView**:
  - **Pull-to-refresh**: Invalidates caches and reloads categories.
  - **Category Tap**: Pushes `FandomListView` for that category. Zooms using `workCardTransitionNamespace`.
  - **Jump Back In Tap**: Pushes `FandomWorksView` directly for that specific fandom.
  - **Chip Tap**: Pushes `FandomWorksView` directly.
  - **Open Website Tap**: Presents `AO3WebBrowserView` modally.
- **FandomListView**:
  - **Alphabetical Scrubbing**: Drag gesture on the trailing `letterIndex` scrolls the list to the chosen letter header.
  - **Filter Button (Top Right)**: Opens the `FandomListFilterSheet`.
  - **Family Header Tap**: Pushes `FandomWorksView` with all sibling tag names included.
  - **Family Member Tap**: Pushes `FandomWorksView` with only that specific member tag.
- **FandomWorksView**:
  - **Filter Button**: Opens `AO3FilterPanel`.
  - **More Menu**: Contains "Mature Reveal" toggle, "Select", and "Expand All".
  - **Select Mode**: Enters a bulk selection state (`RemoteWorkSelectionController`) replacing the toolbar, allowing multi-work actions.
- **AO3WebBrowserView**:
  - Bottom banner pops up on successful EPUB download ("Saved “Title” to Library").

## 5. Strings

- `"Browse"`
- `"Jump Back In"`
- `"Open AO3 Website"`
- `"Browse fandoms from AO3. Tap a category to see its fandoms."` (iOS)
- `"Recently read"`
- `"%d works"`
- `"%d fandoms"`
- `"%d downloaded"`
- `"Couldn't load fandoms"`
- `"Try Again"`
- `"No matching fandoms"`
- `"No fandom in %@ matches your search and filters."`
- `"Clear Search and Filters"`
- `"No matching works"`
- `"No works in this fandom match your filters."`
- `"Clear Filters"`
- `"No works found"`
- `"AO3 has no works for this fandom right now."`
- `"Couldn't load works"`
- `"Select"`
- `"Group variants"`
- `"All %d tags"`
- `"Filter works in this fandom"`
- `"Filter, %d active"`
- `"Search %@"` (e.g. "Search Anime & Manga")
- `"AO3 Website"`
- `"Search AO3 or enter a URL"`
- `"Back"`
- `"Forward"` (macOS only)
- `"Add Bookmark"`
- `"Done"`
- `"Saved “%@” to Library"`
- `"Couldn't save EPUB."`
- `"Bookmarked “%@”"`

## 6. Owner decisions

- **MediaBrowserView**: `"N downloaded" is the EPUBs on this device (owner, 2026-09-28).` (Counts kept copies, not works merely fetched to read).
- **FandomListView**: `// 1an.2: "I have downloads from" — kept copies, not ones fetched only to read (owner, 2026-10-01).`
- **FandomListView**: `// Top right, like every other filtered list (owner, 2026-10-01).` (Placement of the filter action in the toolbar).

## 7. Android gaps

The Android codebase lacks several key pieces required to replicate this interface:

1. **Fandom Title Disambiguation Engine**: iOS parses out "(Anime & Manga)", "- All Media Types", and "RPF" to merge siblings into a `FandomFamily`. Android does not have this parser (`FandomDisplayName.split`).
2. **Offline Stat Derivation**: The heavy background pass that intersects cached full-category fandom lists with the local library to generate downloaded counts, family counts, and the Jump Back In list.
3. **Union Search Query Clause**: `AO3FandomUnion.queryClause` logic which requests a proper tag-ID union instead of a naive intersection when querying for a family.
4. **Composables**:
   - `SubjectPanel` container.
   - `FandomChipCluster` and `TagChip`.
   - `FandomFamilyBlock` (the visual grouping of sibling tags).
   - `FandomListSortRail`.
   - `SearchResultsHero` and `SearchPaginationBar`.
   - The trailing alphabetical scrubber for `LazyColumn`.
5. **Zoom Transitions**: `workCardTransitionNamespace` is heavily relied upon in iOS to pair cards with their pushed screens. Android Navigation Compose shared element transitions must be rigged to replicate this continuous zoom effect.
