# Queues (iOS to Android Port Spec)

> Claude review (2026-10-02): structure and the toolbar claim check out against `ReadingQueueBrowser.swift`, but this spec cites few iOS lines. Treat it as a map and read the iOS files it names before building.

## 1. Screen tree
The queues experience consists of three primary screens in the iOS codebase:

1. **`AllReadingQueuesGridView` (Organizer)**
   - Reached via "See all" from the Home Queues carousel.
   - **Header:** `SubjectHeaderBlock` ("Home › Queues"), Search field (`queueSearchField`), Stat strip (`SubjectStatStrip`).
   - **Tag Rail:** Horizontal scroll of tag chips for filtering.
   - **Pinned Section:** Pinned queues listed with `organizerRow` (has `swipeActions` and `QueueCardMenu`).
   - **All Queues Section:** Saved for Later and custom queues.
   - **Empty State:** `ContentUnavailableView` ("No matching queues").

2. **`ReadingQueueBrowserView` (Browser & Works List)**
   - The queue switcher and works list for a selected queue.
   - **iPad/Mac:** Split view with `List` (sidebar) containing queue rows and "New Queue" button.
   - **Page Content:**
     - **Empty State:** `ContentUnavailableView` ("Add works...").
     - **Detailed List Mode:**
       - `subjectHeaderSection` (`SubjectHeaderBlock`, `QueueSelectionStatusRow` or `QueueHeaderDetails`).
       - "Up Next" Section (front of queue work using `ledgerRow`).
       - "In Line" Section (remaining works).
     - **Compact Grid Mode:** 
       - Same headers stacked in a `ScrollView`.
       - "Up Next" Section (single `SensitiveWorkRow` on `WorkLedgerCardBackground`).
       - "In Line" Section (`LazyVGrid` of `SensitiveWorkCoverCard`).
     - **Toolbar:** Add Works, Filter, More Menu (Hide mature, Select, Reorder, Display Mode, Queue Settings).

3. **`ReadingQueueSettingsView` / Sheets**
   - **`ReadingQueueSettingsView`:** "Queue details" offering Description, Tags, Colour, Keep works offline, and "Manage all tags".
   - **`QueueTagManagerView` / `QueueTagSheet`:** For adding/removing queue-level tags.
   - **`NewReadingQueueSheet` / `EditReadingQueueSheet`:** Form for Name, Colour (`SubjectHueSwatchRow`), Tags, Offline toggle, and "Start from" radio list.

## 2. Components
Key UI components from iOS and missing from `SubjectComponents.kt`:
- **`SubjectHeaderBlock`**: Present in Android.
- **`SubjectStatStrip`**: Present in Android.
- **`SubjectChip`**: Present in Android.
- **`SubjectFieldLabel`, `SubjectFormRow`**: Missing from `SubjectComponents.kt`. Used heavily in settings and forms.
- **`QueueProgressStrip`**: Missing. A custom canvas drawing the pill-shaped progress bar (finished/in-progress/unread segments).
- **`QueuePeekTile`**: Missing. A 44pt 2x2 grid previewing the first 4 works of a queue.
- **`WorkLedgerCardBackground`**: Missing. The specific wash/border wrapper for the "Up Next" ledger row in grid mode.
- **`QueueSelectionStatusRow`**: Missing. Draws the queue name and "N / total" count when in select mode.
- **`SubjectHueSwatchRow`**: Missing. The colour picker row for New/Edit Queue.
- **`QueueHeaderDetails`**: Missing. The compound component under the header containing the progress strip, legend, queue tags, and quick filter pills.

## 3. Data
**iOS Sources & Rules (`ReadingQueueService.swift` / `ReadingQueueOrganizer.swift`):**
- **All Queues:** `Query(sort: \ReadingQueue.sortOrder)` filtering out `isPendingDeletion`.
- **Works in Queue:** `queue.memberships` sorted first by `sortOrderInQueue` (asc), then by `queuedAt` (desc). Soft-deleted works are excluded (`!isPendingDeletion`).
- **Data Model:** `ReadingQueue` stores `name`, `kind` (`.savedForLater` or `.custom`), `sortOrder`, `hue`, `colorHex`, `keepsWorksOffline`, `notes`, `isPinned`, and `tags`.
- **Queue Progress:** Computed via `ReadingQueueFacts.progress`, splitting reading states into `finished`, `inProgress`, and `unread`/`freedHistory`.
- **Up Next Work:** `ReadingQueueFacts.upNext`, the first work in queue order not yet finished.
- **Android Eq:** Closest Android repositories would be `QueueRepository`, `WorkRepository`, `TagRepository`. Data projection for works matching queue filters and ordering is needed.

## 4. Interactions
- **Taps:** Tap queue card to open `ReadingQueueBrowserView`. Tap works to open Reader. Tap tag chips to filter organizer. Tap "New Queue" or "+" to open `NewReadingQueueSheet`.
- **Long-press Menus:** On queue cards/rows (`QueueCardMenu`): "Edit Queue", "Pin" / "Unpin", "Delete Queue". Disabled while in select mode. Saved for Later has no menu.
- **Swipe Actions:** 
  - Queue rows: "Edit" (blue), "Delete" (destructive).
  - Work rows in Browser: "Remove" (destructive).
- **See All:** Chevron on Home Queues carousel opens the `AllReadingQueuesGridView`.
- **Select Mode:** Entered via "..." -> "Select". Replaces bottom bar (or primary action) with Bulk actions: "Pin", "Tag", "Delete", and "Done" checkmark. Title changes to "N selected". Drag handles stay live during select.
- **Reorder:** Reorder chosen from "..." -> "Reorder". Enables drag-and-drop. Requires clearing filters first. Modifies `sortOrderInQueue` for works, or `sortOrder` for custom queues.
- **Pull-to-refresh:** Triggers `WorkMetadataRefresh.refresh` for visible works in the queue browser.

## 5. Strings
* "Home"
* "Library"
* "Queues"
* "Search queues, tags and works"
* "Clear Search and Filters"
* "Pinned"
* "All queues"
* "No matching queues"
* "Your search and tag filter don't match any queues."
* "Select"
* "Reorder"
* "Clear Filters to Reorder"
* "Pin", "Unpin"
* "Tag"
* "Delete"
* "Edit"
* "Done"
* "Works"
* "Offline"
* "Storage"
* "nothing kept yet"
* "Up Next"
* "In Line"
* "Add Works"
* "No matching works"
* "Your filters don't match any works in this queue."
* "Clear Filters"
* "Description"
* "Details"
* "Manage all tags"
* "Colour"
* "From queue name"
* "Keep works offline"
* "Order", "Manual"
* "Last read", "Never"
* "Add tag"
* "New tag"
* "Your tags"
* "You have no tags yet. Add one above."
* "Edit queue"
* "New queue"
* "Name"
* "Start from"
* "Empty"
* "Saved for Later"
* "Copy N works. They stay in Saved for Later."
* "You have no works in Saved for Later to copy."
* "When this is off, the queue keeps only your list. It doesn't download or keep copies, so it uses no extra storage."
* "Works you add here are downloaded and kept for offline reading."

## 6. Owner decisions
- **2026-09-28:** "the drag is a mode chosen from '...', not always on." (ReadingQueueOrganizer)
- **2026-10-01:** "queues had no menu where works and collections do" so `QueueCardMenu` was added for long-press. (QueueCardMenu)
- **2026-10-01:** "Edit Queue is this sheet too", combining New Queue and Edit Queue sheets. (NewReadingQueueSheet)
- **2026-10-01:** "The iPhone's bottom switcher bar (All Queues, the queue pill, New Queue) is gone" and replaced by a unified browser navigation. (ReadingQueueSwitcher)

## 7. Android gaps
- **`QueuePeekTile` & `QueueProgressStrip`:** Android lacks the canvas-based continuous progress strip with segment gaps and the 2x2 miniature cover grid tile.
- **`SubjectHueSwatchRow`:** Android lacks the horizontal scrolling colour picker row used for custom queue hues.
- **`SubjectFormRow` / `SubjectFieldLabel`:** Android `SubjectComponents.kt` is missing these standard list row components used throughout the queue details and settings sheets.
- **`WorkLedgerCardBackground`:** Missing the wrapper that makes the "Up Next" work stand out in the compact grid.
- **Queue Hue/Color Hex:** Android database may not yet have `hue` (Double) and `colorHex` (String) fields on its Queue model, as these were added to iOS to decouple colour from the queue's name hash.
- **KeepOffline Rules:** Android needs to port the `KeepOffline.queueKeeps` behavior logic which determines if works download automatically based on the `keepsWorksOffline` queue property.
