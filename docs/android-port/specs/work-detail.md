# Work Detail Screen Specification (Android Port)

This specification outlines the architecture, layout, data flows, and design decisions for the `WorkDetailView` Android port, tracing directly from the iOS source of truth in `kudos-ao3-reader/Features/WorkDetail/`.

## 1. Screen Tree

The canonical detail screen (`WorkDetailView.swift`) is a single, work-centric hub used for all local and remote works. It relies on a `List` configured with a custom wash and zero-height minimum rows (`WorkDetailView.swift:134-145`).

**Main Page (`WorkDetailView.swift`)**
- `List` (styled with `.cardList()`, minimum row height 0, and `subjectScreenWash` running 620pt down)
  - `heroSection` (`WorkDetailView.swift:234`)
    - `WorkDetailIdentityHeader`: Kicker, 32pt Title, Author Byline.
    - `WorkDetailFigureStrip`: Rating, Warnings, Categories, Chapters.
    - `WorkDetailResumeCard`: Reading progress ring, labels, solid circle play control.
  - `statusSection` (`WorkDetailView.swift:319`): Transient feedback (errors, queue notices, series preservation).
  - `pageSections` (`WorkDetailView.swift:297`):
    - `summarySection`: The work's summary text in a serif font.
    - `ao3ActionsSection`: ON AO3 chips (Kudos, Comments, Bookmarks, Subscribe).
    - `tagSections`: Categorized AO3 tags chips.
    - `factsCardSection`: Grouped facts in an outlined transparent card.
    - `archiveStatsSection`: `SubjectStatStrip` tallying kudos, comments, bookmarks, and hits.
    - `commentsSection`: Native discussion entries.
    - `pageActionsSection`: Outline buttons (e.g., Mark as Finished, Open on AO3).
    - `seriesSection`: Downloaded works from the same series.
    - `myCopySection`: The single entry point to local device state.

**My Copy Sheet (`WorkDetailView.swift:370`)**
A native sheet titled "My copy" containing:
- `librarySections` (`WorkDetailSections.swift`):
  - Status/Storage (Download/Preservation/Source)
  - Activity (Added, Last opened, Progress bar)
  - Queues and Collections
  - My Tags (Custom tags, Add tag field, suggestions)

## 2. Components

Android components correspond to iOS SwiftUI structs using the new `SubjectPalette` and `KudosTokens` logic detailed in `docs/android-port/briefs/1a-result.md`.

### Component Metrics & Styling

- **Page Wash:** Applied via `Modifier.subjectScreenWash(palette, washHeight = 620.dp)`. The page is washed with the work's primary fandom or title hue (`WorkDetailView.swift:145`).
- **Identity Header (`WorkDetailIdentityBlock.swift:26`):**
  - **Kicker:** Small caps, no background, primary fandom (`WorkDetailIdentityBlock.swift:43`).
  - **Title:** 32pt system font.
  - **Byline:** 15.5pt (`WorkDetailIdentityBlock.swift:33`), individual names are tap targets to their AO3 profile.
- **Figure Strip (`WorkDetailIdentityBlock.swift:76`):** 4 cells (Rating, Warnings, Category, Chapters) with specific tinting. Unpopulated figures show `—`.
- **Resume Card (`WorkDetailIdentityBlock.swift:163`):**
  - Background: `Modifier.subjectPanel` / `glassFill(0.10)` overlaid with `glassStroke(0.14)` border width 0.5 (`WorkDetailIdentityBlock.swift:304`).
  - Corner radius: 20pt.
  - Padding: horizontal 18pt, vertical 16pt.
  - Play control: 42pt circle (`WorkDetailIdentityBlock.swift:185`) filled with `palette.solidButtonFill` and icon `palette.solidButtonLabel`. Icon size 16pt (`min(controlIconSize, 22)`).
  - Progress Ring: `WorkProgressRing` (or `WorkReadingOrDownloadRing`) capped at 72pt diameter, default 48pt (`WorkDetailIdentityBlock.swift:184`).
- **Summary (`WorkDetailOverviewSections.swift:33`):**
  - Font: 16pt Serif (`WorkDetailOverviewSections.swift:52`).
  - Line Spacing: 5.5pt added to baseline height to hit CSS 1.6 (`WorkDetailOverviewSections.swift:56`).
  - Foreground Style: `Color.primary.opacity(0.82)`.
  - Lines: Limit 8 when collapsed.
- **Facts Card (`WorkDetailFactsSections.swift:24`):**
  - Radius: 16pt, `.subjectPanel(cornerRadius: 16, isFilled: false)`. Outline-only on the wash.
  - Rows separated by full-bleed `SubjectRowSeparator(inset: 0)`.
- **Archive Stats (`WorkDetailFactsSections.swift:128`):** `SubjectStatStrip` with four data points. Comments are highlighted.
- **Outline Buttons (`WorkDetailFactsSections.swift:224`):**
  - Font: 15pt medium. Vertical padding 13pt.
  - Border: 1pt stroke of `glassStroke(0.18)` (`WorkDetailFactsSections.swift:242`).
  - Corner Radius: 12pt.

**Kotlin Mappings:**
- iOS `glassFill(0.09)` maps to `panelFill` + `glassFill(opacity)` (`1a-result.md`).
- `SubjectHeaderBlock`, `SubjectRowSeparator`, `SubjectStatStrip`, `SubjectStatCell`, and `WorkProgressRing` retain names.
- iOS `.cardSurface` corresponds to `KudosTokens.background` / `cardSurface`.

## 3. Data

- **Works Repository:** Local queries filter by `!$0.isPendingDeletion` to ignore soft-deleted works (`WorkDetailView.swift:57`).
- **Series Sorting:** Local works from the same series are queried filtering for identical `seriesTitle` and sorted natively by `seriesPosition` ascending (`WorkDetailView.swift:623-625`).
- **My Tags Sorting:** Displayed sorted alphabetically by `name < name` (`WorkDetailSections.swift:145`).
- **Display Fallbacks:** Almost all presentation properties (e.g., `displayTitle`, `displayAuthor`, `displayRating`) prioritize the local `SavedWork` model; if empty, they fall back to the remote `AO3WorkSummary` (`WorkDetailView.swift:457-617`).

## 4. Interactions

- **Pull-to-refresh:** Triggers `refreshDetails()`, updating `refreshedRemote` and `refreshedPublished` inline without overwriting local saved status unnecessarily (`WorkDetailView.swift:146`).
- **Resume Card Tap:** Opens the book reader using the unified `BookReaderView` routing (`WorkDetailView.swift:276`).
- **Summary Expand/Collapse:** Un-collapses the 8-line limit using an implicit animation (`WorkDetailOverviewSections.swift:62`).
- **My Copy Row Tap:** Presents the local details native sheet (`WorkDetailFactsSections.swift:216`).
- **More Actions Menu (Toolbar):** Contains:
  - Add to Queue
  - Add to Collection
  - Save for Later / Remove from Later
  - Download / Downloaded / Kept Offline
  - Share
  - Open on AO3
  - AO3 Work Actions (Subscribe, Bookmark) (`WorkDetailView.swift:439`).

## 5. Strings

Exact strings must be retained to maintain iOS parity and pass iOS testing suites.
- "My copy"
- "Private to this device"
- "Opening…"
- "Continue Reading"
- "Read"
- "Show More" / "Show Less"
- "Add to Queue"
- "Add to Collection"
- "Save for Later"
- "Remove from Later"
- "Download"
- "Downloaded"
- "Kept Offline"
- "Share"
- "Open on AO3"
- "You haven't saved anything on this device yet" (`WorkDetailComponents.swift:96`)
- "Removed to save space. Kudos gets it again when you read it" (`WorkDetailSections.swift:97`)
- "When you download more works from this series, they will appear here." (`WorkDetailOverviewSections.swift:202`)

## 6. Owner Decisions

- **Definition of "Downloaded":** "A copy fetched only to read is not 'Downloaded' (owner, 2026-10-01)" (`WorkDetailSections.swift:92` and T-344). Downloaded implies the user intended to keep it offline.
- **Reading doesn't download:** "Read never says it downloads (owner, 2026-10-01): a copy fetched to read is bookkeeping, and 'Download' means keeping a work." (`WorkDetailComponents.swift:25`).
- **Removing Downloads:** "Remove Download un-keeps, never deletes (owner, 2026-10-01: "only Delete may remove an EPUB")" (T-346). Removing a download strips the keep flag but leaves the file in the cache until swept.
- **Mature Toggle:** "Show/Hide mature on every works screen's '...'" (T-284). The mature toggle must exist on the work detail overflow menu if the setting is active.
- **My Copy vs Main Page:** 1a specifies that everything owned by AO3 stays on the main scrollable page, and everything specific to the device (storage, queues, reading progress) hides behind the "My copy" sheet.

## 7. Android Gaps

As per `1a-result.md`, the following iOS-specific implementations are not yet ported to Compose and will require distinct implementation:
- `SubjectFormRow` and `SubjectFieldLabel` (Used extensively in `WorkDetailFactsSections.swift`).
- `WorkReadingOrDownloadRing` (T-345 introduced this downloading overlay on rings).
- `WorkLedgerRow`
- `SemanticThemeColors`
- Text auto-shrink (`minimumScaleFactor` in SwiftUI).
- Dynamic Type limits and stat-strip text scaling gaps (Jetpack Compose scales `sp` freely, breaking rigid layout bounds if unhandled).
- Filter menu contents.
