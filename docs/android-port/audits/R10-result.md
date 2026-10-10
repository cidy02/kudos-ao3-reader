# Reader Port Audit: iOS vs Android

## 1. The top bar
- **iOS:** `ReaderChromeTopBar` (`Features/ReaderReadium/ReaderChromeTopBar.swift:7`)
- **What it shows/does:**
  - A close button. `accessibilityLabel("Close reader")`.
  - A title pill. Condition: `if !titleHidden`. Contains:
    - The title: `Text(title)`.
    - An author line. Condition: `if !author.isEmpty`. Contains: `Image(systemName: "person.fill")` and `Text(author)`.
    - The pill acts as a button. Condition: `if let onOpenDetails`. Uses `accessibilityHint("Opens work details")`.
- **Android:** `ReaderChromeTopBar` (`reader/ReaderChromeTopBar.kt:46`)
- **Differences:**
  - The close button icon. iOS uses `chevron.left`. Android uses `Icons.AutoMirrored.Filled.ArrowBack`.
  - The title pill accessibility. iOS uses `accessibilityHint("Opens work details")`. Android uses `contentDescription = "$title${if (author.isNotBlank()) ", by $author" else ""}. Opens work details"`.

## 2. The fan menu and its pills
- **iOS:** `fanPills` (`Features/ReaderReadium/ReadiumReaderView.swift:1903`) and `fanRoundActions` (`1226`)
- **What it shows/does:**
  - "Contents" / "Contents · [percent]%".
  - "Bookmarks & Highlights".
  - "Find in Work". Condition: `isEnabled: ReaderSearchModel.isSearchable(book.publication)`.
  - "Comments". Condition: `if ao3WorkID != nil`.
  - "Rebuild from Original". Condition: `if WorkReconversion.candidate(for: work)?.isStale == true`.
  - "Themes & Settings".
  - Share link. Condition: `if let shareURL`.
  - "Give kudos" / "Kudos given". Condition: `if let ao3WorkID`.
  - "View the original file this work was converted from". Condition: `if let original = originalDocumentURL`.
  - "Read aloud" / "Stop reading aloud". Long press opens settings.
  - "Lock rotation" / "Unlock rotation".
  - "Add bookmark" / "Remove bookmark".
- **Android:** `readerFanPills` (`reader/ReaderFanMenu.kt:94`) and `roundActions` (`reader/ReaderScreen.kt:559`)
- **Differences:**
  - "Rebuild from Original". iOS shows `"Rebuild from Original"`. Android: not found.
  - "Comments" icon. iOS uses `bubble.left.and.bubble.right`. Android uses `Icons.Filled.ChatBubbleOutline`.
  - "Themes & Settings" icon. iOS uses `textformat.size`. Android uses `Icons.Filled.TextFields`.
  - "View the original file this work was converted from" icon. iOS uses `doc.text.magnifyingglass`. Android uses `Icons.Filled.FindInPage`.
  - "Read aloud" icon. iOS uses `waveform.circle.fill` / `waveform`. Android uses `Icons.AutoMirrored.Filled.VolumeUp`.
  - Read Aloud long press destination. iOS: `showingSpeechSettings = true`. Android: `showDisplaySheet = true`.
  - "Lock rotation" icon. iOS uses `lock.rotation` / `lock.open.rotation`. Android uses `Icons.Filled.ScreenLockRotation` / `Icons.Filled.ScreenRotation`.

## 3. The position card and its scrubber
- **iOS:** `ReaderPositionCard` (`Features/ReaderReadium/ReaderPositionCard.swift:16`)
- **What it shows/does:**
  - Optional mini player. Condition: `if showsMiniPlayer`.
  - Optional hairline separator. Condition: `if showsMiniPlayer`.
  - "Page …" (if measuring) or "Page [page] of [pageCount]".
  - "[min] left in chapter". Condition: `if let minutes = chapterRemainingMinutes`.
  - Scrub slider.
  - Work line summary.
- **Android:** `ReaderPositionCard` (`reader/ReaderPositionCard.kt:131`)
- **Differences:**
  - Monospaced formatting. iOS uses `.monospacedDigit()`. Android uses `TextStyle(fontFeatureSettings = "tnum")`.

## 4. The Contents sheet's tabs, rows, and empty states
- **iOS:** `ReaderContentsSheet` (`Features/ReaderReadium/ReaderContentsSheet.swift:42`)
- **What it shows/does:**
  - Three tabs: "Contents", "Bookmarks", "Highlights".
  - Contents tab. Lists chapters. Swipe actions: "Go", "Bookmark", "Add Note". Condition for Bookmark/Add Note: `if chapterStartPercent(section) != nil`.
  - Bookmarks tab. Lists bookmarks. Empty state: "No Bookmarks Yet", "Bookmarks you add while reading will appear here." Swipe actions: "Delete".
  - Highlights tab. Lists highlights. Empty state: "No Highlights Yet", "Highlights and notes you add while reading will appear here. Swipe a row to delete, or tap to edit." Swipe actions: "Delete".
- **Android:** `ReaderContentsSheet` (`reader/ReaderContentsSheet.kt:45`)
- **Differences:**
  - Contents tab actions. iOS uses swipe actions: `"Go"`, `"Bookmark"`, `"Add Note"`. Android lacks swipe actions, using inline `TextButton("Bookmark")` and `TextButton("Add Note")`.
  - Contents tab action condition. iOS: `if chapterStartPercent(section) != nil`. Android: `if (onBookmarkEntry != null)` and `if (onAddNoteToEntry != null)`.
  - Annotations tab actions. iOS uses swipe actions: `"Delete"`. Android lacks swipe actions, using inline `TextButton("Delete")`.
  - Highlights tab empty state icon. iOS uses `systemImage: "highlighter"`. Android uses `icon = Icons.Filled.BorderColor`.

## 5. Find in Work
- **iOS:** `ReaderSearchView` (`Features/ReaderReadium/ReaderSearchView.swift:229`)
- **What it shows/does:**
  - Search field placeholder "Find in Work".
  - Clear search button. Condition: `if !query.isEmpty`.
  - Empty state (idle): "Find in Work", "Search the text of this work. Tap a result to jump to that passage."
  - Empty state (failed): "Couldn't Search".
  - Empty state (no results): system default `ContentUnavailableView.search`.
  - Result row actions: "Go", "Bookmark", "Copy".
- **Android:** `ReaderSearchSheet` (`reader/ReaderSearchSheet.kt:131`)
- **Differences:**
  - Empty results string. iOS uses `ContentUnavailableView.search(text: query)`. Android uses `"No Results for “$query”"`, `"Check the spelling or try a new search."`.
  - Clear search icon. iOS uses `xmark.circle.fill`. Android uses `Icons.Filled.Cancel`.
  - Failed state icon. iOS uses `exclamationmark.triangle`. Android uses `Icons.Filled.Warning`.

## 6. The note editor
- **iOS:** `ReaderNoteEditor` (`Features/ReaderReadium/ReaderNoteEditor.swift:8`)
- **What it shows/does:**
  - Section "Highlighted". Condition: `if !annotation.selectedText.isEmpty`.
  - Section "Note" with a `TextEditor`.
  - Section "Colour" with swatches.
  - Section with "Delete Highlight" button.
  - Toolbar with "Cancel" and "Done" button (`checkmark`).
- **Android:** `AnnotateDialog` (`reader/ReaderScreen.kt:1131`)
- **Differences:**
  - The view type. iOS uses a `Form` in a `NavigationStack`. Android uses an `AlertDialog`.
  - The delete action. iOS includes a `"Delete Highlight"` button. Android: not found (searched `reader/ReaderScreen.kt` for "Delete" in AnnotateDialog).
  - The confirm button. iOS uses `Image(systemName: "checkmark")` with `accessibilityLabel("Done")`. Android uses `"Save note"` or `"Highlight"`.

## 7. The text selection menu
- **iOS:** `kudosFixPronunciation` (`Features/ReaderReadium/ReadiumBook.swift:74`)
- **What it shows/does:**
  - System floating selection menu. Actions: "Highlight", "Add Note", "Fix Pronunciation".
- **Android:** `ReaderSelectionContainer` (`reader/readium/ReaderSelectionContainer.kt:41`)
- **Differences:**
  - "Fix Pronunciation" action. iOS includes `"Fix Pronunciation"`. Android: not found (searched `reader/readium/ReaderSelectionContainer.kt` for "Pronunciation").

## 8. Display & Themes and "Customize Theme"
- **iOS:** `ReaderOptionsForm` (`Settings/SettingsView.swift:15`)
- **What it shows/does:**
  - Section "Appearance".
  - "Customize Theme…".
  - Section "Text Size".
  - ReaderLayoutSection.
  - ReaderSpeechSettingsSection.
- **Android:** `ReaderDisplaySheet` (`reader/ReaderScreen.kt:912`)
- **Differences:**
  - Re-used settings component. iOS re-uses the global `ReaderOptionsForm`. Android defines a dedicated `ReaderDisplaySheet`.
  - Speech settings grouping. iOS groups them in `ReaderSpeechSettingsSection()`. Android renders them inline.

## 9. The read-aloud controls, speech settings sheet
- **iOS:** `ReaderSpeechSettingsSheet` (`Features/ReaderReadium/ReaderSpeechSettingsSheet.swift:12`)
- **What it shows/does:**
  - A dedicated sheet containing `ReaderSpeechSettingsSection`.
- **Android:** Inline in `ReaderDisplaySheet` (`reader/ReaderScreen.kt:1054`)
- **Differences:**
  - Sheet architecture. iOS uses a dedicated `ReaderSpeechSettingsSheet` for "Read Aloud". Android includes them in `ReaderDisplaySheet`.

## 10. The end-of-work actions
- **iOS:** `ReadiumReaderCompletion` (`Features/ReaderReadium/ReadiumReaderCompletion.swift:20`)
- **What it shows/does:**
  - Silently marks finished when `visibleLast.progression.upperBound == 1.0`.
- **Android:** `EndOfWorkActions` (`reader/EndOfWorkActions.kt:10`)
- **Differences:**
  - No differences.

## 11. The dismiss gesture
- **iOS:** `ReadiumNavigatorContainer` (`Features/ReaderReadium/ReadiumNavigatorContainer.swift:154`)
- **What it shows/does:**
  - Interactive dismissal gesture.
- **Android:** `ReaderScreen` (`reader/ReaderScreen.kt:493`)
- **Differences:**
  - The gesture mechanism. iOS uses the system zoom transition (`WorkCardZoomTransition.swift`): `"dragging the page collapses it back into the card it came from."`. Android uses a custom `detectVerticalDragGestures`: swipe down from the top edge.

## 12. Tap, double tap, long press, and swipe on the page
- **iOS:** `ReadiumReaderView` (`Features/ReaderReadium/ReadiumReaderView.swift`)
- **What it shows/does:**
  - Tap toggles floating chrome (`chromeVisible`).
- **Android:** `ReadiumNavigatorHost` (`reader/ReaderScreen.kt:453`)
- **Differences:**
  - No differences.


## Gap Size Table
| iOS Control | iOS Path:Line | Android Path:Line |
| --- | --- | --- |
| "Rebuild from Original" Fan Pill | `Features/ReaderReadium/ReadiumReaderView.swift:1930` | not found |
| "Fix Pronunciation" Selection Action | `Features/ReaderReadium/ReadiumBook.swift:79` | not found |
| "Delete Highlight" button in Note Editor | `Features/ReaderReadium/ReaderNoteEditor.swift:53` | not found |
| Swipe actions on Chapters | `Features/ReaderReadium/ReaderContentsSheet.swift:129` | `reader/ReaderContentsSheet.kt:142` |
| Swipe actions on Annotations | `Features/ReaderReadium/ReaderContentsSheet.swift:186` | `reader/ReaderContentsSheet.kt:239` |
| Dedicated Speech Settings Sheet | `Features/ReaderReadium/ReaderSpeechSettingsSheet.swift:12` | `reader/ReaderScreen.kt:1054` |
| Dismiss zoom gesture | `Features/ReaderReadium/ReadiumNavigatorContainer.swift:154` | `reader/ReaderScreen.kt:493` |
| "Find in Work" Empty State system string | `Features/ReaderReadium/ReaderSearchView.swift:334` | `reader/ReaderSearchSheet.kt:213` |
