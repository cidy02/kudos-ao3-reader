# Home Porting Spec

**Source:** `kudos-ao3-reader/Features/Home/HomeView.swift`

## 1. Screen tree
The Home dashboard is a progressive layout hosted inside a `NavigationStack` with the large inline title "Home" (`HomeView.swift:150`). When in `isSelecting` mode, the title dynamically changes to "X Selected" (`WorkSelectionTitle.text(selectedCount:)`). The page background is `themeManager.appTheme.cardBackdrop.ignoresSafeArea()` (matches `KudosTokens.background` in Kotlin). 

The root is a `ScrollView` wrapped in a `.refreshable` block, meaning pull-to-refresh is available. 
The internal structure is a `VStack` (alignment `.leading`, spacing: 22, vertical padding: 12) containing:
1. `resumeSection` (Reading Now hero and strip)
2. `readingQueuesCarousel` (Reading Queues)
3. `HomeCollectionShelves` (One shelf per flagged local collection)
4. `localSection(.recentlyUpdated)` (Recently Updated carousel)
5. `subscriptionsSection` (Subscriptions carousel)

When empty or loading, sections display a `SectionEmptyState`. When the user enters `isSelecting` mode (via the toolbar), cards swap to `SensitiveWorkCoverCard` styled for selection, the floating tab bar is hidden, and a `WorkBulkActionBar` appears at the bottom edge.

## 2. Components
* **`SubjectKicker`**: Used in the hero for the primary fandom name. Size 9.5pt, rule spacing 7pt. Kotlin equivalent: `SubjectKicker` exists in `SubjectComponents.kt`.
* **`HomeResumeHero`** (`HomeResumeHero.swift:96`): A rich card showing the top in-progress work (`readingNow[0]`).
  * **Shape & Fill**: `SubjectMetrics.heroRadius` (14). Background is `carouselCardSurface`, overlaid with `subjectPalette.cardWash`, stroked with `subjectPalette.cardBorder` (0.5pt), and shadowed with `carouselCardShadow` (offset Y: +2, radius: +6).
  * **Typography**: Title is `titleSize` (31pt, bold, tracking -0.62). Metadata line is `metadataSize` (13pt), separated by "·" (opacity 0.35).
  * **Visuals**: Contains a `WorkStatusIconGrid` (4-signal tray, `tileSize` 22) in the top-trailing corner, and a `WorkReadingOrDownloadRing` (68pt size) on the bottom-leading edge.
  * **Action**: "Resume" Button is a drawn shape (not a real SwiftUI Button to avoid touch conflicts). Uses `buttonSize` (14pt, semibold), `solidButtonLabel` on `solidButtonFill` capsule, padding H:18, V:10.
  * **Kotlin**: Missing (build it).
* **`WorkCarouselSection`** (`WorkCarouselSection.swift:41`): A section with a `SectionRuleHeader` and a horizontal `ScrollView` of cards.
  * Header uses `SectionRuleHeader` (animated collapse toggle with a snappy 0.22s animation, See All chevron).
  * Cards are laid out in an `HStack` (spacing 12, padding H:16, V:6) with `.scrollClipDisabled()` so shadows aren't cut off by the scroll view boundaries.
  * Kotlin: Missing (build it).
* **`CanonicalWorkCoverCard`** & **`SensitiveWorkCoverCard`**: Standard cover card. `CanonicalWorkCoverCard` switches to a richer local card if the work exists locally, or falls back to an enriched `AO3WorkCoverCard` (fetching metadata silently via `EnrichingAO3WorkCoverCard`).
  * Kotlin: Missing (build it as `WorkCoverCard`).
* **`SectionEmptyState`**: An `HStack` (spacing 8) with a `systemImage` (`.tertiary`) and `message` text (`.subheadline`, `.secondary`), padded vertically by 8pt.

## 3. Data
All sections cap the displayed cards at 12 (`.prefix(12)`) in the carousels.
* **Reading Now**: `works.filter { $0.isInProgress && !$0.isQueueOnlyWork && visible($0) }.sorted { recency($0) > recency($1) }`. Recency is `lastReadDate ?? dateAdded`. The hero is index `0`, and the carousel strip is indices `1...4` (max 5 visible total). (`HomeSections.swift:54`)
* **Reading Queues**: `readingQueues.filter { $0.kind == .custom }.sorted { $0.sortOrder < $1.sortOrder }`.
* **Collections Shelves**: `collections.filter { $0.showsOnHome && !$0.isPendingDeletion }.sorted...`. Works within follow `collection.inReadingOrder`. (`HomeCollectionShelves.swift:9`)
* **Recently Updated**: `works.filter { $0.hasUpdate && !$0.isQueueOnlyWork && visible($0) }`. Sorted descending by `lastUpdateCheck`.
* **Subscriptions**: Loaded via `auth.accountSubscriptions()`. Merged with the local library works via `CanonicalWorkMerge.remoteLed` to show richer local data where possible, while preserving AO3's subscription order. (`HomeView.swift:101`)
* **Android source**: `io.github.cidy02.kudos.home.HomeViewModel` (or equivalent module repository).

## 4. Interactions
* **Taps**: 
  * Work card -> Pushes `LocalWorkDestination.reader(work)` (straight to reader, NOT details). Opening an updated work marks its current chapters as seen.
  * Queue card -> Pushes `AllReadingQueuesDestination(initialQueueID: queue.id)` (Browser view).
* **See All (Section header)**: 
  * Reading Now: Only appears if `readingNow.count > 5`. Deep links to `router.showLibrarySection(.readingNow, from: "Home")`.
  * Other sections: Opens full lists on Home's own stack: `HomeSectionKind`, `SubscriptionsRoute`, or `AllReadingQueuesDestination(nil)` (Grid view).
* **Pull-to-refresh**: Calls `refreshHome()`, refreshing metadata via `WorkMetadataRefresh.refresh` for up to 24 visible works (Reading Now prefix 12 + Recently Updated prefix 12), plus reloading subscriptions from AO3. (`HomeView.swift:132`)
* **Select Mode**: Triggered via the toolbar's Select button.
  * Tab bar hides.
  * Navigation title changes to "Select Works" or "X Selected".
  * Top right toolbar changes to "Select All" / "Deselect All".
  * A bottom bar (`WorkBulkActionBar`) appears with three sections:
    1. **Delete** (Trash, destructive, left side). Prompts with an alert explaining the 90-day restore period.
    2. **Actions** (Pill in the middle, `.regularMaterial` capsule). Opens a menu with: Bulk Download, Favorite, Save for Later, Add to Queue, Add to Collection, Tag (applies same local tags to multiple works), Mark Finished.
    3. **Done** (Checkmark, right side). Exits select mode.
* **Long-press (Context Menu)**: Defined in `LocalWorkContextMenuModifier` (`WorkCardActions.swift:76`). Includes: Read (book), Comments (if ID exists), Select (checklist), Download, Favorite/Unfavorite, Save/Remove for Later, Add to Queue, Mark Finished/Unfinished, Add to Collection, Rebuild from Original (if candidate), Work Details, Delete (trash, red tint).
* **Toolbar (Top Right)**:
  * "New Queue" (`plus` icon). Opens `NewReadingQueueSheet`.
  * "More" menu (`ellipsis`, only if works exist or hasMature): Contains "Privacy" (`MatureRevealToggle`) and "Select" (`checklist`).

## 5. Strings
* **Navigation title**: "Home"
* **Section titles**: "Continue Reading" (for the Reading Now section), "Reading Queues", "Recently Updated", "Subscriptions"
* **Empty states**:
  * Reading Now (Strong Empty State): Title "Continue Reading", text "You aren't reading anything yet. Open a work from your Library or find one in Browse.", plus two CTA buttons: "Browse AO3" (`.borderedProminent`) and "Open Library" (`.bordered`). (Icon: `book`)
  * Queues: "Use + above to make a reading queue and plan what you want to read next."
  * Recently Updated: "None of the works in your Library has a new chapter yet." (Icon: `sparkles`)
  * Subscriptions (Logged out): "Log in to AO3 to see updates from works and series you subscribe to." (Icon: `bell`)
  * Subscriptions (Failed): "Couldn't load your subscriptions. Pull down to try again."
  * Subscriptions (Empty): "You have no work or series subscriptions yet. When you subscribe on AO3, updates appear here."
  * Collections: "Add works to this collection to see them here." (Icon: `square.stack`)
* **Card Footers**: "+\(new) new", "Updated", "Ready to resume", "Last opened"
* **Context Menus**: "Read", "Comments", "Select", "Favorite", "Unfavorite", "Save for Later", "Remove from Later", "Add to Queue", "Mark Finished", "Mark Unfinished", "Add to Collection", "Rebuild from Original", "Work Details", "Delete".
* **Bulk Action Bar**: "Delete" (trash), "Actions", "Done" (checkmark). "Select All", "Deselect All", "Select Works", "X Selected".

## 6. Owner decisions
* `"The 'New queue' card that led this shelf is the toolbar's '+' now (owner, 2026-10-01: global actions live in the top-right chrome)."` (`HomeView.swift`) - Prevents UI shifting when rows are empty.
* `"Privacy now lives inside [WorkListMoreMenu], so it needs a home even with no local works."` (`HomeView.swift`) - Ensured the More menu stays visible for the Privacy toggle.
* `"A subscribed work that's also saved locally renders once, as its richer local card, in AO3's own subscription order."` (`HomeView.swift:101`) - Avoids duplicates while maximizing card data density.
* `resumeSection`: "The caret collapses the strip of next-up covers, not the hero: the hero is the point of the section, and a section that can hide its own subject is a section with nothing left to show."

## 7. Android gaps
* Missing `HomeResumeHero` implementation (`ui/subject` currently lacks it).
* Missing `WorkCarouselSection` and `SectionRuleHeader` components for standardizing carousels.
* Missing a robust `CanonicalWorkCoverCard` that handles the merge of remote and local data visually.
* Missing `WorkBulkActionBar` and global select mode logic for the Home screen.
