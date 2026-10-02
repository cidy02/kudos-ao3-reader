# Recently Deleted Specification

This document provides a comprehensive, top-down specification for porting the iOS `RecentlyDeletedView` to Android. The iOS implementation serves as the ultimate source of truth for all layout, behavior, and data rules.

## 1. Screen Tree

The Recently Deleted screen (`RecentlyDeletedView.swift`) is structured as a single vertical scrolling view containing either an empty state or a list of items pending deletion. The screen represents Artboard **1bj** and functions as a recovery window where users can restore items exactly as they were or permanently delete them. Items are grouped by how long is left before their expiry, not by their type, to directly answer the user's primary concern: "what am I about to lose?" (line 15-17).

### Top-Level Navigation
- **Title Bar**: In the default idle mode, the title is empty. In select mode, the title displays the dynamic count of selected items (e.g., "1 selected", "3 selected") (line 69).
- **Wash**: The entire list is layered over a subject wash background using `.subjectScreenWash(palette: palette)` (line 67).

### Empty State (`ContentUnavailableView`)
When there are no deleted or held items, the screen shows a standard empty state instead of the list (lines 56-62).
- **Icon**: A trash can symbol (`systemImage: "trash"`).
- **Label**: "Recently Deleted".
- **Description**: "Items you delete stay here for {windowDays} days. Copies of works you finish without keeping them stay for {heldWindowDays} days." (where `{windowDays}` is 90 and `{heldWindowDays}` is 60).

### List State
If there is at least one item, the screen draws a `List` configured with `.cardList()` (line 237). The list is broken into the following sequential sections:

#### Section 1: Header & Reassurance
- **Header**: A `SubjectHeaderBlock` component.
  - Kicker: "Library"
  - Title: "Recently Deleted"
  - Subtitle: "{count} items" (pluralized properly for 1 item).
  - Page Body Row: Top padding 20, gutter 0.
- **Reassurance Panel**: A text block explaining the consequences of deletion, explicitly answering the fear of deleting items from the source (AO3).
  - Content: "Deleting an item here removes only the copy in Kudos, including its download, your progress, and your notes. The work stays on AO3." (lines 307-308).
  - Styling: `.subjectPanel()` with 14px horizontal and 12px vertical padding. 12.5pt secondary text.

#### Section 2: Deleted Items (Conditional)
Only drawn if there are items explicitly deleted by the user (`!deleted.isEmpty`) (line 207).
- **Section Header**: `SectionRuleHeader` with title "Deleted" and the count of deleted items. Top padding 18, gutter 0.
- **Section Note**: "Kept for {windowDays} days, then removed for good." rendered as 11.5pt secondary text with `SubjectMetrics.accountGutter + 6` padding.
- **Rows**: A `RecentlyDeletedRow` for each deleted entry.

#### Section 3: Finished, Not Kept Items (Conditional)
Only drawn if there are held copies of finished works (`!held.isEmpty`) (line 218).
- **Section Header**: `SectionRuleHeader` with title "Finished, not kept" and the count of held items. Top padding 18, gutter 0.
- **Section Note**: "Works you finished without downloading, favoriting or queuing them. Their copies stay here for {heldWindowDays} days so you can still read them offline, then they're removed. The works stay in your reading history."
- **Rows**: A `RecentlyDeletedRow` for each held entry.

#### Section 4: Delete All Permanently Button (Conditional)
Only drawn if the screen is *not* in select mode (line 231).
- **Button**: Outlined capsule button taking full width. Contains a trash icon and the text "Delete All Permanently". Triggers a bulk permanent deletion confirmation alert.
- Padding: Top 24, gutter `SubjectMetrics.accountGutter`.

## 2. Components

The iOS UI relies on several custom and standard components. Below is an exhaustive list mapping them to existing Android counterparts in `android/app/src/main/java/io/github/cidy02/kudos/ui/subject/SubjectComponents.kt`, highlighting any missing implementations.

### Found in `SubjectComponents.kt`
- **`SubjectHeaderBlock`**: Used for the main "Recently Deleted" header. Parameters map directly (kicker, title, subtitle).
- **`SectionRuleHeader`**: Used for the "Deleted" and "Finished, not kept" section headers. Parameters map directly (title, count).
- **`.subjectScreenWash`**: Used for the background gradient behind the list. Present in Android as a modifier.
- **`.subjectPanel`**: Used for the Reassurance text background. Present in Android as a modifier.

### Missing from `SubjectComponents.kt`
- **`RecentlyDeletedRow`** (Lines 575-716): The primary list row component representing a deleted entry.
  - Contains a `SubjectKicker` (kicker string like "Work" or "Local collection", with `ruleWidth` `SubjectMetrics.kickerRuleWidth` and `ruleSpacing` 5).
  - Title: 16.5pt semibold text, maximum 2 lines.
  - Detail Line: 11.5pt secondary text, maximum 2 lines. (If the item has author identities, this delegates to `AO3AuthorBylineView` instead of plain text, combining the stops for accessibility).
  - Remaining Days (Trailing Edge): Stacks the figure (e.g., "3d") over the label ("LEFT"). Figure is 13pt bold, monospaced digit. Its color is `Color.subjectAmber` if urgent (less than 7 days), otherwise `Color.primary`. The label "LEFT" is 9pt secondary text.
  - Row Styling: Wraps contents in a horizontal stack with 14px horizontal and 12px vertical padding. Modifies it with `.subjectCard(palette: palette)`.
  - Missing Android support: Needs to be implemented from scratch, incorporating the custom typography and conditional amber coloring for urgency.
- **`WorkSelectionBubble`**: A trailing selection indicator visible when the screen is in select mode. Displays a checkmark when selected. Not present in `SubjectComponents.kt`.
- **Card List Modifiers**: The `.cardList()` and `.subjectCard()` modifiers used to style the overall list and individual rows are missing or need verification against Android's standard material lists.

## 3. Data

The screen aggregates multiple data sources into a unified, flattened list. The primary concept is the `RecentlyDeletedEntry` (line 427), which standardizes works, collections, and reading queues.

### Data Sources
- **Deleted Works**: `SavedWork` entities where `isPendingDeletion` is true.
- **Deleted Collections**: `WorkCollection` entities where `isPendingDeletion` is true.
- **Deleted Reading Queues**: `ReadingQueue` entities where `isPendingDeletion` is true.
- **Held Works**: `SavedWork` entities where `freedAt != nil`, `!isPendingDeletion`, `isFinished`, `!isProtected`, and `hasEPUB`.

### Sorting and Grouping
- Items are flattened into a single list and sorted primarily by `daysRemaining` in ascending order (soonest to expire first) (line 347).
- They are grouped structurally into two sections: explicitly "Deleted" items and "Held Copies" (`isHeldCopy`).

### Time Windows
- **Deleted Window**: Derived from `PreservedWorkService.recoveryWindow`, evaluating to 90 days (`windowDays`, line 326).
- **Held Window**: Derived from `WorkLifecycle.freedCopyWindow`, evaluating to 60 days (`heldWindowDays`, line 330).

### Android Mapping
On Android, these sources will likely map to DAOs or Repositories such as `SavedWorkRepository`, `WorkCollectionRepository`, and `ReadingQueueRepository`. A unified ViewModel will be required to fetch from all three, construct a unified `RecentlyDeletedEntry` model, calculate the days remaining, sort them, and expose the UI state.

## 4. Interactions

The screen supports diverse interaction patterns depending on the mode.

### Idle Mode Interactions
- **Row Tap**: Disabled or non-interactive (no navigation destination is pushed).
- **Swipe Actions** (Trailing Edge) (line 624):
  - **Restore**: Deep blue tint. Triggers the item's `restore()` closure.
  - **Delete**: Destructive tint (red). Opens a confirmation alert asking to delete permanently. Note: For held copies, the label is "Remove", but the icon is always `trash.fill`.
  - Order: "Delete" sits outermost (closest to the trailing edge) with "Restore" to its left.
- **Long-press Menu** (Context Menu) (line 633):
  - Identical actions to swipe: "Restore" and "Delete Permanently" (or "Remove Copy").
- **Delete All Button**: Tap triggers a global alert to wipe all items.
- **Toolbar (Top Right)**: Contains a More Menu ("…") holding a single "Select" action to enter select mode.

### Select Mode Interactions
- **Row Tap**: Toggles the item's inclusion in the `selection` set. Swipe and long-press actions are disabled.
- **Toolbar (Top Right)**: Shows a "Select All" button (or "Deselect All" if all are currently selected).
- **Bottom Action Bar** (lines 164-188):
  - **Restore** (Left): Restores all selected items. Disabled if selection is empty.
  - **Delete Permanently** (Center): Prompts a bulk delete confirmation alert. Disabled if selection is empty.
  - **Done** (Right): Checkmark icon to exit select mode.
- **Pull-to-Refresh**: None. This is a local database query screen, not a remote API screen.

## 5. Strings

This section catalogs every user-visible string on the screen, verbatim, including dynamically generated text.

### Static Strings
- Navigation Title (Idle): ""
- Navigation Title (Selecting): "{count} selected"
- Empty State Title: "Recently Deleted"
- Empty State Note: "Items you delete stay here for {windowDays} days. Copies of works you finish without keeping them stay for {heldWindowDays} days."
- Header Kicker: "Library"
- Header Title: "Recently Deleted"
- Reassurance Text: "Deleting an item here removes only the copy in Kudos, including its download, your progress, and your notes. The work stays on AO3."
- Section 1 Title: "Deleted"
- Section 1 Note: "Kept for {windowDays} days, then removed for good."
- Section 2 Title: "Finished, not kept"
- Section 2 Note: "Works you finished without downloading, favoriting or queuing them. Their copies stay here for {heldWindowDays} days so you can still read them offline, then they're removed. The works stay in your reading history."
- Actions: "Select", "Restore", "Delete Permanently", "Done", "Cancel", "Delete All Permanently", "Select All", "Remove", "Remove Copy"
- "LEFT" (for days remaining label).
- Restore Error Title: "Couldn't Restore"

### Dynamic Formats and Plurals
- Header Subtitle: "{count} items" or "{count} item"
- Days Remaining: "{x}d" (e.g., "3d")

### Dynamic Deletion Messages (Lines 377-408)
#### Work Deletion Message
Constructed dynamically based on what the work actually contains:
- Components (joined by commas and " and "):
  - Download: "the download"
  - Progress: "your place at {place}" (e.g., "chapter 4" or "42%"). Note: "Ch 4" is transformed to "chapter 4".
  - Highlights: "your {count} highlight" or "your {count} highlights".
  - Bookmarks: "your {count} bookmark" or "your {count} bookmarks".
- Sentence: "Kudos removes {list} from this device. You can't undo this."
- Fallback (if no components): "Kudos removes this item from your device. You can't undo this."

#### Container Deletion Message (Collections / Queues)
- 0 works: "It holds no works. You can't undo this."
- 1 work: "The 1 work in it stays in your Library. You can't undo this."
- N works: "The {count} works in it stay in your Library. You can't undo this."

#### Held Copy Deletion Message
- "Kudos removes this work's copy from your device now. The work stays in your reading history, and you can download it again from AO3."

#### Bulk Deletion Message
- Alert Title: "Delete 1 item permanently?" or "Delete {count} items permanently?"
- Message: "Kudos will permanently remove each item and any download, progress, or notes stored with it. The works stay on AO3. You can't undo this."

#### Global Delete All Message
- Alert Title: "Delete 1 item permanently?" or "Delete all {count} items permanently?"
- Message: "Kudos will permanently remove every item here and any download, progress, or notes stored with it, and the copies of finished works. The works stay on AO3. You can't undo this."

#### Restore Failure Message
- 1 failed: "Kudos could not save the restored {noun}. It is still scheduled for permanent deletion, so try again."
- N failed: "Kudos could not save {count} of the restored items. They are still scheduled for permanent deletion, so try again."

### Entry Specific Strings
- Kickers: "Downloaded work", "Work", "Finished work", "Local collection", "Reading queue".
- Reading States: "unread", "part-read", "finished", "read, file freed".
- Container Detail: "{count} works · deleted {date}" or "{count} work".
- Work Detail: "{author} · {words} words · {state}".

## 6. Owner Decisions

The iOS codebase contains explicit ownership comments marking specific design decisions (search for `owner, 2026-`).

1. **Menu Placement**: "Select lives in the '…', as on every other list (owner, 2026-10-01)." (line 152).
2. **Sectioning**: "Two sections (owner, 2026-10-01): what you deleted, kept for 90 days, and the copies of works you finished without keeping, held for 60. Each is soonest to expire first." (line 195).

## 7. Android Gaps

To fully realize Artboard 1bj on Android, several gaps in the current `SubjectComponents.kt` and foundation layers need to be addressed:
1. **`RecentlyDeletedRow`**: A completely new Compose function must be built to support the 4-line layout (kicker, title, detail, remaining days), accommodating the custom amber color logic for items expiring in under 7 days.
2. **Selection UI**: `WorkSelectionBubble` is missing. A standard Material 3 checkbox might suffice, but if custom bubble styling is desired to match iOS's checkmark pill, it must be created.
3. **Card Modifiers**: The `.subjectCard()` and `.cardList()` styling elements are absent and need equivalent Compose extensions to provide the appropriate glass backgrounds and rounded corners.
4. **Bottom Action Bar**: Android will need a robust implementation of a contextual action bar anchored to the bottom of the screen (or substituting a traditional TopAppBar CAB) for bulk Restore/Delete actions during select mode.
5. **Dynamic String Assembly**: The complex, grammatically correct list joining for the `workDeletionMessage` (combining downloads, progress, highlights, and bookmarks into a localized sentence) will require a dedicated formatter utility in Kotlin.
