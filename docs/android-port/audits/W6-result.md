# W6: The Words on Android's Reader Beside iOS's

- **Android strings found**: 94
- **DIFFERS**: 5
- **NO IOS STRING**: 24
- **iOS strings with no Android string**: 4

---

## 1. Differences and Strings Missing on iOS

| Android String (`path:line`) | iOS String (`path:line`) | Status | Notes / Searched Words |
|---|---|---|---|
| `contentDescription = "$title${if (author.isNotBlank()) \", by $author\" else \"\"}. Opens work details"` (`reader/ReaderChromeTopBar.kt:104`) | `.accessibilityHint(onOpenDetails == nil ? "" : "Opens work details")` (`Features/ReaderReadium/ReaderChromeTopBar.swift:75`) | DIFFERS | Android combines title, author, and action into a single `contentDescription`. iOS sets accessibility hint `"Opens work details"` and combines child elements (`Text(title)` + author `accessibilityLabel`). |
| `title = "No Chapters"` (`reader/ReaderContentsSheet.kt:108`) | — | NO IOS STRING | Searched `Features/ReaderReadium/ReaderContentsSheet.swift` for `"No"`, `"Chapters"`, `"available"`. iOS provides no empty-state view for chapters. |
| `message = "No chapters available."` (`reader/ReaderContentsSheet.kt:109`) | — | NO IOS STRING | Searched `Features/ReaderReadium/ReaderContentsSheet.swift` for `"No"`, `"chapters"`, `"available"`. |
| `title = { Text(if (state.asNote) "Add note" else "Highlight") }` (`reader/ReaderScreen.kt:1141`) | `navigationTitle(annotation.hasNote ? "Edit Note" : "Add Note")` (`Features/ReaderReadium/ReaderNoteEditor.swift:64`) / `EditingAction(title: "Highlight", ...)` (`Features/ReaderReadium/ReadiumBook.swift:75`) | DIFFERS | Casing differs when creating a note: Android dialog title displays `"Add note"`; iOS note editor title displays `"Add Note"`. |
| `Text("Color", style = MaterialTheme.typography.labelLarge)` (`reader/ReaderScreen.kt:1153`) | `Section("Colour")` (`Features/ReaderReadium/ReaderNoteEditor.swift:41`) | DIFFERS | Spelling differs: Android uses US English `"Color"`; iOS uses British English `"Colour"`. |
| `Text(if (state.asNote) "Save note" else "Highlight")` (`reader/ReaderScreen.kt:1202`) | — | NO IOS STRING | Searched `Features/ReaderReadium/ReaderNoteEditor.swift` and `ReadiumBook.swift` for `"Save"`, `"note"`, `"button"`. iOS uses a checkmark icon with `.accessibilityLabel("Done")` (`ReaderNoteEditor.swift:87`). |
| `Text(text = "Display & Themes", ...)` (`reader/ReaderScreen.kt:951`) | — | NO IOS STRING | Searched `Features/ReaderReadium/` Settings/Theme files for `"Display"`, `"Themes"`, `"Settings"`. (Note: defined on iOS in `ReadiumReaderView.swift:1579` as `readerSheetTitle`). |
| `SettingsGroupLabel("Appearance", ...)` (`reader/ReaderScreen.kt:962`) | — | NO IOS STRING | Searched `Features/ReaderReadium/` Settings/Theme files for `"Appearance"`, `"Theme"`, `"Customize"`. (Note: defined on iOS in `Settings/SettingsView.swift:34`). |
| `if (it == ReaderColorTheme.Oled) "OLED" else it.name` (`reader/ReaderScreen.kt:968`) | — | NO IOS STRING | Searched `Features/ReaderReadium/` Settings/Theme files for `"OLED"`, `"Sepia"`, `"Dark"`. (Note: defined on iOS in `Settings/SettingsView.swift:88`). |
| `contentDescription = "Theme"` (`reader/ReaderScreen.kt:969`) | — | NO IOS STRING | Searched `Features/ReaderReadium/` Settings/Theme files for `"Theme"`, `"Picker"`, `"Selection"`. (Note: defined on iOS in `Settings/SettingsView.swift:37`). |
| `SettingsActionRow(label = "Customize Theme…", ...)` (`reader/ReaderScreen.kt:974`) | — | NO IOS STRING | Searched `Features/ReaderReadium/` Settings/Theme files for `"Customize"`, `"Theme"`, `"Tune"`. (Note: defined on iOS in `Settings/SettingsView.swift:43`). |
| `SubjectFormRow("Bold Text", ...)` (`reader/ReaderScreen.kt:981`) | — | NO IOS STRING | Searched `Features/ReaderReadium/` Settings/Theme files for `"Bold"`, `"Text"`, `"Toggle"`. (Note: defined on iOS in `Settings/SettingsView.swift:301` as `"Bold text"`). |
| `SubjectSliderRow(label = "Letter spacing", ...)` (`reader/ReaderScreen.kt:986`) | — | NO IOS STRING | Searched `Features/ReaderReadium/` Settings/Theme files for `"Letter"`, `"spacing"`, `"Slider"`. |
| `formatValue = { "%.2f em".format(it) }` (`reader/ReaderScreen.kt:990`) | — | NO IOS STRING | Searched `Features/ReaderReadium/` Settings/Theme files for `"Letter"`, `"spacing"`, `"em"`. |
| `SubjectSliderRow(label = "Word spacing", ...)` (`reader/ReaderScreen.kt:995`) | — | NO IOS STRING | Searched `Features/ReaderReadium/` Settings/Theme files for `"Word"`, `"spacing"`, `"Slider"`. |
| `formatValue = { "%.2f em".format(it) }` (`reader/ReaderScreen.kt:999`) | — | NO IOS STRING | Searched `Features/ReaderReadium/` Settings/Theme files for `"Word"`, `"spacing"`, `"em"`. |
| `SettingsGroupLabel("Text Size", ...)` (`reader/ReaderScreen.kt:1005`) | — | NO IOS STRING | Searched `Features/ReaderReadium/` Settings/Theme files for `"Text"`, `"Size"`, `"Slider"`. (Note: defined on iOS in `Settings/SettingsView.swift:49`). |
| `TextSizeSlider(..., unit = "%", ...)` (`reader/ReaderScreen.kt:1011`) | — | NO IOS STRING | Searched `Features/ReaderReadium/` Settings/Theme files for `"unit"`, `"font"`, `"percent"`. |
| `SettingsSection(label = "Reading", ...)` (`reader/ReaderScreen.kt:1019`) | — | NO IOS STRING | Searched `Features/ReaderReadium/` Settings/Theme files for `"Reading"`, `"Layout"`, `"Section"`. (Note: defined on iOS in `Settings/SettingsReadingPages.swift:14`). |
| `footnote = "On a wide screen, Paged mode can show two pages side by side."` (`reader/ReaderScreen.kt:1021`) | — | NO IOS STRING | Searched `Features/ReaderReadium/` Settings/Theme files for `"wide"`, `"screen"`, `"Paged"`. (Note: defined on iOS in `Settings/SettingsView.swift:150` as `"On iPad and Mac, Paged mode can show two pages side by side."`). |
| `footnote = "Choose whether you turn pages or scroll while reading."` (`reader/ReaderScreen.kt:1023`) | — | NO IOS STRING | Searched `Features/ReaderReadium/` Settings/Theme files for `"turn"`, `"pages"`, `"scroll"`. (Note: defined on iOS in `Settings/SettingsView.swift:152`). |
| `title = { scroll -> if (scroll) "Scrolled" else "Paged" }` (`reader/ReaderScreen.kt:1030`) | — | NO IOS STRING | Searched `Features/ReaderReadium/` Settings/Theme files for `"Scrolled"`, `"Paged"`, `"Layout"`. (Note: defined on iOS in `Settings/SettingsReadingPages.swift:46`). |
| `contentDescription = "Layout"` (`reader/ReaderScreen.kt:1031`) | — | NO IOS STRING | Searched `Features/ReaderReadium/` Settings/Theme files for `"Layout"`, `"Picker"`, `"Segmented"`. (Note: defined on iOS in `Settings/SettingsView.swift:118`). |
| `SubjectFormRow("Two-page spread", ...)` (`reader/ReaderScreen.kt:1037`) | — | NO IOS STRING | Searched `Features/ReaderReadium/` Settings/Theme files for `"Two-page"`, `"spread"`, `"Toggle"`. (Note: defined on iOS in `Settings/SettingsView.swift:125`). |
| `SubjectFormRow("Keep screen awake", ...)` (`reader/ReaderScreen.kt:1049`) | — | NO IOS STRING | Searched `Features/ReaderReadium/` Settings/Theme files for `"Keep"`, `"screen"`, `"awake"`. (Note: defined on iOS in `Settings/SettingsView.swift:133`). |
| `formatValue = { "%.1f×".format(it) }` (`reader/ReaderScreen.kt:1090`) | `String(format: "%.0f%%", rate * 100)` / `"Default"` (`Features/ReaderReadium/ReaderSpeechSettingsSection.swift:628-629`) | DIFFERS | Formatting template differs: Android displays speed as e.g. `"1.0×"`; iOS displays percentage e.g. `"100%"` (or `"Default"`). |
| `formatValue = { "%.1f".format(it) }` (`reader/ReaderScreen.kt:1099`) | `String(format: "%.2f×", pitch)` / `"Default"` (`Features/ReaderReadium/ReaderSpeechSettingsSection.swift:633-634`) | DIFFERS | Formatting template differs: Android displays pitch as e.g. `"1.0"`; iOS displays multiplier e.g. `"1.00×"` (or `"Default"`). |
| `SettingsGroupLabel("Font", ...)` (`reader/ReaderScreen.kt:1104`) | — | NO IOS STRING | Searched `Features/ReaderReadium/` Settings/Theme files for `"Font"`, `"Catalog"`, `"Family"`. (Note: defined on iOS in `Settings/SettingsView.swift:158`). |
| `contentDescription = "Selected"` (`reader/ReaderScreen.kt:1113`) | — | NO IOS STRING | Searched `Features/ReaderReadium/` Settings/Theme files for `"Selected"`, `"Font"`, `"Check"`. |

---

## 2. Matching Strings

| Android String (`path:line`) | iOS String (`path:line`) | Status | Notes |
|---|---|---|---|
| `contentDescription = "Close reader"` (`reader/ReaderChromeTopBar.kt:74`) | `.accessibilityLabel("Close reader")` (`Features/ReaderReadium/ReaderChromeTopBar.swift:36`) | SAME | Close button accessibility label |
| `title = percent?.let { "Contents · $it%" } ?: "Contents"` (`reader/ReaderFanMenu.kt:97`) | `guard let percent = book.totalProgression.map({ Int(($0 * 100).rounded()) }) else { return "Contents" }\nreturn "Contents · \(percent)%"` (`Features/ReaderReadium/ReadiumReaderView.swift:1944-1945`) | SAME | Contents menu pill title with progress percentage |
| `title = "Bookmarks & Highlights"` (`reader/ReaderFanMenu.kt:102`) | `title: "Bookmarks & Highlights"` (`Features/ReaderReadium/ReadiumReaderView.swift:1909`) | SAME | Bookmarks & Highlights menu pill title |
| `title = "Find in Work"` (`reader/ReaderFanMenu.kt:106`) | `title: "Find in Work"` (`Features/ReaderReadium/ReadiumReaderView.swift:1914`) | SAME | Find in Work menu pill title |
| `title = "Comments"` (`reader/ReaderFanMenu.kt:111`) | `title: "Comments"` (`Features/ReaderReadium/ReadiumReaderView.swift:1925`) | SAME | Comments menu pill title |
| `title = "Themes & Settings"` (`reader/ReaderFanMenu.kt:116`) | `title: "Themes & Settings"` (`Features/ReaderReadium/ReadiumReaderView.swift:1937`) | SAME | Themes & Settings menu pill title |
| `accessibilityLabel = if (given) "Kudos given" else "Give kudos"` (`reader/ReaderFanMenu.kt:130`) | `accessibilityLabel: work.hasGivenKudos ? "Kudos given" : "Give kudos"` (`Features/ReaderReadium/ReadiumReaderView.swift:1237`) | SAME | Kudos round action accessibility label |
| `accessibilityLabel = "View the original file this work was converted from"` (`reader/ReaderFanMenu.kt:150`) | `accessibilityLabel: "View the original file this work was converted from"` (`Features/ReaderReadium/ReadiumReaderView.swift:1257`) | SAME | Original document action accessibility label |
| `contentDescription = "More"` (`reader/ReaderFanMenu.kt:207`) | `.accessibilityLabel("More")` (`Features/ReaderReadium/ReaderFanMenu.swift:354`) | SAME | Closed fan menu toggle button accessibility label |
| `accessibilityLabel = "Share"` (`reader/ReaderScreen.kt:564`) | `.accessibilityLabel("Share")` (`Features/ReaderReadium/ReaderFanMenu.swift:174`) | SAME | Share action accessibility label |
| `accessibilityLabel = if (speechActive) "Stop reading aloud" else "Read aloud"` (`reader/ReaderScreen.kt:584`) | `accessibilityLabel: speechActive ? "Stop reading aloud" : "Read aloud"` (`Features/ReaderReadium/ReadiumReaderView.swift:1276`) | SAME | Read Aloud round action accessibility label |
| `accessibilityLabel = if (isOrientationLocked) "Unlock rotation" else "Lock rotation"` (`reader/ReaderScreen.kt:611`) | `accessibilityLabel: rotationLocked ? "Unlock rotation" : "Lock rotation"` (`Features/ReaderReadium/ReadiumReaderView.swift:1304`) | SAME | Rotation lock round action accessibility label |
| `accessibilityLabel = if (isBookmarked) "Remove bookmark" else "Add bookmark"` (`reader/ReaderScreen.kt:630`) | `accessibilityLabel: isBookmarked ? "Remove bookmark" : "Add bookmark"` (`Features/ReaderReadium/ReadiumReaderView.swift:1317`) | SAME | Bookmark round action accessibility label |
| `tabs = listOf("Contents", "Bookmarks", "Highlights")` [0: `"Contents"`] (`reader/ReaderContentsSheet.kt:70`) | `case .chapters: "Contents"` (`Features/ReaderReadium/ReaderContentsSheet.swift:33`) | SAME | Contents sheet segmented tab label |
| `tabs = listOf("Contents", "Bookmarks", "Highlights")` [1: `"Bookmarks"`] (`reader/ReaderContentsSheet.kt:70`) | `case .bookmarks: "Bookmarks"` (`Features/ReaderReadium/ReaderContentsSheet.swift:34`) | SAME | Bookmarks sheet segmented tab label |
| `tabs = listOf("Contents", "Bookmarks", "Highlights")` [2: `"Highlights"`] (`reader/ReaderContentsSheet.kt:70`) | `case .notes: "Highlights"` (`Features/ReaderReadium/ReaderContentsSheet.swift:35`) | SAME | Highlights sheet segmented tab label |
| `Text("Bookmark", color = tokens.secondaryInk)` (`reader/ReaderContentsSheet.kt:144`) | `Label("Bookmark", systemImage: "bookmark")` (`Features/ReaderReadium/ReaderContentsSheet.swift:151`) | SAME | Chapter row bookmark action button |
| `Text("Add Note", color = tokens.secondaryInk)` (`reader/ReaderContentsSheet.kt:149`) | `Label("Add Note", systemImage: "note.text")` (`Features/ReaderReadium/ReaderContentsSheet.swift:158`) | SAME | Chapter row add note action button |
| `title = "No Bookmarks Yet"` (`reader/ReaderContentsSheet.kt:163`) | `emptyTitle: "No Bookmarks Yet"` (`Features/ReaderReadium/ReaderContentsSheet.swift:81`) | SAME | Bookmarks tab empty-state title |
| `message = "Bookmarks you add while reading will appear here."` (`reader/ReaderContentsSheet.kt:164`) | `emptyMessage: "Bookmarks you add while reading will appear here."` (`Features/ReaderReadium/ReaderContentsSheet.swift:83`) | SAME | Bookmarks tab empty-state message |
| `title = "No Highlights Yet"` (`reader/ReaderContentsSheet.kt:185`) | `emptyTitle: "No Highlights Yet"` (`Features/ReaderReadium/ReaderContentsSheet.swift:88`) | SAME | Highlights tab empty-state title |
| `message = "Highlights and notes you add while reading will appear here. Swipe a row to delete, or tap to edit."` (`reader/ReaderContentsSheet.kt:186`) | `emptyMessage: "Highlights and notes you add while reading will appear here. " + "Swipe a row to delete, or tap to edit."` (`Features/ReaderReadium/ReaderContentsSheet.swift:90-91`) | SAME | Highlights tab empty-state message |
| `val title = annotation.chapterTitle.ifBlank { "In this work" }` (`reader/ReaderContentsSheet.kt:213`) | `annotation.chapterTitle.isEmpty ? "In this work" : annotation.chapterTitle` (`Features/ReaderReadium/ReaderContentsSheet.swift:215`) | SAME | Bookmark row fallback chapter title |
| `Text(text = "$percent%", ...)` (`reader/ReaderContentsSheet.kt:233`) | `Text("\(Int((annotation.progression * 100).rounded()))%")` (`Features/ReaderReadium/ReaderContentsSheet.swift:224`) | SAME | Bookmark row progress percentage |
| `Text("Delete", color = MaterialTheme.colorScheme.error)` (`reader/ReaderContentsSheet.kt:240`) | `Label("Delete", systemImage: "trash")` (`Features/ReaderReadium/ReaderContentsSheet.swift:190`) | SAME | Bookmark row delete action button |
| `val title = annotation.chapterTitle.ifBlank { "In this work" }` (`reader/ReaderContentsSheet.kt:252`) | `annotation.chapterTitle.isEmpty ? "In this work" : annotation.chapterTitle` (`Features/ReaderReadium/ReaderContentsSheet.swift:215`) | SAME | Highlight row fallback chapter title |
| `Text(text = "$percent%", ...)` (`reader/ReaderContentsSheet.kt:283`) | `Text("\(Int((annotation.progression * 100).rounded()))%")` (`Features/ReaderReadium/ReaderContentsSheet.swift:224`) | SAME | Highlight row progress percentage |
| `contentDescription = "Delete"` (`reader/ReaderContentsSheet.kt:329`) | `Label("Delete", systemImage: "trash")` (`Features/ReaderReadium/ReaderContentsSheet.swift:190`) | SAME | Highlight row delete button accessibility label |
| `Text("Find in Work", ...)` (`reader/ReaderSearchSheet.kt:154`) | `case .readerFind: "Find in Work"` (`Features/ReaderReadium/ReadiumReaderView.swift:1578`) | SAME | Search sheet header title |
| `ToolbarCircleButton(onClick = dismiss, accessibilityName = "Done")` (`reader/ReaderSearchSheet.kt:157`) | `.accessibilityLabel("Done")` (`Features/ReaderReadium/ReadiumReaderView.swift:1649`) | SAME | Search sheet confirmation button accessibility label |
| `if (query.isEmpty) Text("Find in Work", color = tokens.secondaryInk)` (`reader/ReaderSearchSheet.kt:187`) | `TextField("Find in Work", text: $query)` (`Features/ReaderReadium/ReaderSearchView.swift:287`) | SAME | Search field placeholder text |
| `contentDescription = "Clear search"` (`reader/ReaderSearchSheet.kt:196`) | `.accessibilityLabel("Clear search")` (`Features/ReaderReadium/ReaderSearchView.swift:307`) | SAME | Clear search button accessibility label |
| `SearchEmptyState("Find in Work", ...)` (`reader/ReaderSearchSheet.kt:204`) | `ContentUnavailableView("Find in Work", ...)` (`Features/ReaderReadium/ReaderSearchView.swift:322`) | SAME | Search idle empty-state title |
| `SearchEmptyState(..., "Search the text of this work. Tap a result to jump to that passage.")` (`reader/ReaderSearchSheet.kt:204`) | `description: Text("Search the text of this work. Tap a result to jump to that passage.")` (`Features/ReaderReadium/ReaderSearchView.swift:323`) | SAME | Search idle empty-state description |
| `SearchEmptyState("Couldn't Search", ...)` (`reader/ReaderSearchSheet.kt:209`) | `ContentUnavailableView("Couldn't Search", ...)` (`Features/ReaderReadium/ReaderSearchView.swift:329`) | SAME | Search error state title |
| `SearchEmptyState("No Results for “$query”", ...)` (`reader/ReaderSearchSheet.kt:213`) | `ContentUnavailableView.search(text: query)` (`Features/ReaderReadium/ReaderSearchView.swift:334`) | SAME | Empty results state title template |
| `SearchEmptyState(..., "Check the spelling or try a new search.")` (`reader/ReaderSearchSheet.kt:213`) | `ContentUnavailableView.search(text: query)` (`Features/ReaderReadium/ReaderSearchView.swift:334`) | SAME | Empty results state description |
| `SearchGroupTitle("This Chapter")` (`reader/ReaderSearchSheet.kt:218`) | `Section("This Chapter")` (`Features/ReaderReadium/ReaderSearchView.swift:362`) | SAME | Current chapter results section heading |
| `Text("Searching…", color = tokens.secondaryInk)` (`reader/ReaderSearchSheet.kt:225`) | `Text("Searching…")` (`Features/ReaderReadium/ReaderSearchView.swift:366`) | SAME | Current chapter in-progress search text |
| `listOf("Copy" to copy, "Bookmark" to onBookmark, "Go" to onGo)` [`"Go"`] (`reader/ReaderSearchSheet.kt:308, 320`) | `Label("Go", systemImage: "arrow.forward.circle")` (`Features/ReaderReadium/ReaderSearchView.swift:425`) | SAME | Search result swipe action label |
| `listOf("Copy" to copy, "Bookmark" to onBookmark, "Go" to onGo)` [`"Bookmark"`] (`reader/ReaderSearchSheet.kt:308, 320`) | `Label("Bookmark", systemImage: "bookmark")` (`Features/ReaderReadium/ReaderSearchView.swift:432`) | SAME | Search result swipe action label |
| `listOf("Copy" to copy, "Bookmark" to onBookmark, "Go" to onGo)` [`"Copy"`] (`reader/ReaderSearchSheet.kt:308, 320`) | `Label("Copy", systemImage: "doc.on.doc")` (`Features/ReaderReadium/ReaderSearchView.swift:439`) | SAME | Search result swipe action label |
| `CustomAccessibilityAction("Go")` (`reader/ReaderSearchSheet.kt:346`) | `Label("Go", systemImage: "arrow.forward.circle")` (`Features/ReaderReadium/ReaderSearchView.swift:425`) | SAME | Custom accessibility action name |
| `CustomAccessibilityAction("Bookmark")` (`reader/ReaderSearchSheet.kt:347`) | `Label("Bookmark", systemImage: "bookmark")` (`Features/ReaderReadium/ReaderSearchView.swift:432`) | SAME | Custom accessibility action name |
| `CustomAccessibilityAction("Copy")` (`reader/ReaderSearchSheet.kt:348`) | `Label("Copy", systemImage: "doc.on.doc")` (`Features/ReaderReadium/ReaderSearchView.swift:439`) | SAME | Custom accessibility action name |
| `Text("Cancel", color = tokens.accent)` (`reader/ReaderNoteEditor.kt:77`) | `Button("Cancel")` (`Features/ReaderReadium/ReaderNoteEditor.swift:68`) | SAME | Note editor cancellation button |
| `Text(if (annotation.note.isBlank()) "Add Note" else "Edit Note", ...)` (`reader/ReaderNoteEditor.kt:79`) | `navigationTitle(annotation.hasNote ? "Edit Note" : "Add Note")` (`Features/ReaderReadium/ReaderNoteEditor.swift:64`) | SAME | Note editor title |
| `ToolbarCircleButton(..., accessibilityName = "Done")` (`reader/ReaderNoteEditor.kt:85`) | `.accessibilityLabel("Done")` (`Features/ReaderReadium/ReaderNoteEditor.swift:87`) | SAME | Note editor confirmation button accessibility label |
| `SettingsSection(..., label = "Highlighted", ...)` (`reader/ReaderNoteEditor.kt:90`) | `Section("Highlighted")` (`Features/ReaderReadium/ReaderNoteEditor.swift:23`) | SAME | Highlighted passage section label |
| `SettingsSection(..., label = "Note")` (`reader/ReaderNoteEditor.kt:101`) | `Section("Note")` (`Features/ReaderReadium/ReaderNoteEditor.swift:35`) | SAME | Note input section label |
| `contentDescription = "Note"` (`reader/ReaderNoteEditor.kt:108`) | `Section("Note")` (`Features/ReaderReadium/ReaderNoteEditor.swift:35`) | SAME | Note input field accessibility label |
| `SettingsSection(..., label = "Colour")` (`reader/ReaderNoteEditor.kt:111`) | `Section("Colour")` (`Features/ReaderReadium/ReaderNoteEditor.swift:41`) | SAME | Color picker section label |
| `contentDescription = option.displayName` (`"Yellow"`, `"Green"`, `"Blue"`, `"Pink"`, `"Purple"`, `"Underline"`) (`reader/ReaderNoteEditor.kt:122`) | `.accessibilityLabel(option.title)` (`"Yellow"`, `"Green"`, `"Blue"`, `"Pink"`, `"Purple"`, `"Underline"`) (`Features/ReaderReadium/ReadingAnnotationColorPicker.swift:20`) | SAME | Annotation color swatch accessibility labels |
| `SettingsActionRow("Delete Highlight", ...)` (`reader/ReaderNoteEditor.kt:145`) | `Label("Delete Highlight", systemImage: "trash")` (`Features/ReaderReadium/ReaderNoteEditor.swift:57`) | SAME | Delete highlight destructive action row |
| `menu.add(..., "Highlight")` (`reader/readium/ReaderSelectionContainer.kt:96`) | `EditingAction(title: "Highlight", ...)` (`Features/ReaderReadium/ReadiumBook.swift:75`) | SAME | Text selection action menu item |
| `menu.add(..., "Add Note")` (`reader/readium/ReaderSelectionContainer.kt:101`) | `EditingAction(title: "Add Note", ...)` (`Features/ReaderReadium/ReadiumBook.swift:77`) | SAME | Text selection action menu item |
| `contentDescription = swatch.displayName` (`"Yellow"`, `"Green"`, `"Blue"`, `"Pink"`, `"Purple"`, `"Underline"`) (`reader/ReaderScreen.kt:1174`) | `.accessibilityLabel(option.title)` (`"Yellow"`, `"Green"`, `"Blue"`, `"Pink"`, `"Purple"`, `"Underline"`) (`Features/ReaderReadium/ReadingAnnotationColorPicker.swift:20`) | SAME | Annotate dialog color swatch accessibility labels |
| `label = { Text("Note") }` (`reader/ReaderScreen.kt:1193`) | `Section("Note")` (`Features/ReaderReadium/ReaderNoteEditor.swift:35`) | SAME | Annotate dialog note field label |
| `TextButton(onClick = onDismiss) { Text("Cancel") }` (`reader/ReaderScreen.kt:1206`) | `Button("Cancel")` (`Features/ReaderReadium/ReaderNoteEditor.swift:68`) | SAME | Annotate dialog cancel button |
| `ToolbarCircleButton(onClick = onDone, accessibilityName = "Done")` (`reader/ReaderScreen.kt:957`) | `Button("Done") { dismiss() }` (`Features/ReaderReadium/ReaderSpeechSettingsSheet.swift:37`) | SAME | Settings sheet confirmation button |
| `SettingsGroupLabel("Read Aloud", ...)` (`reader/ReaderScreen.kt:1054`) | `header: { Text("Read Aloud") }` (`Features/ReaderReadium/ReaderSpeechSettingsSection.swift:191`) / `navigationTitle("Read Aloud")` (`Features/ReaderReadium/ReaderSpeechSettingsSheet.swift:33`) | SAME | Read Aloud section label |
| `Text(text = "Voice", ...)` (`reader/ReaderScreen.kt:1058`) | `LabeledContent("Voice", value: selectedVoiceLabel)` (`Features/ReaderReadium/ReaderSpeechSettingsSection.swift:135`) / `navigationTitle("Voice")` (`Features/ReaderReadium/ReaderSpeechSettingsSection.swift:586`) | SAME | Voice row label / navigation title |
| `Text("Automatic (best available)", ...)` (`reader/ReaderScreen.kt:1073`) | `"Automatic (best available)"` (`Features/ReaderReadium/ReaderSpeechSettingsSection.swift:54, 59, 569`) | SAME | Automatic voice selection label |
| `SubjectSliderRow(label = "Speed", ...)` (`reader/ReaderScreen.kt:1086`) | `Text("Speed")` (`Features/ReaderReadium/ReaderSpeechSettingsSection.swift:158`) | SAME | Speed slider row label |
| `SubjectSliderRow(label = "Pitch", ...)` (`reader/ReaderScreen.kt:1095`) | `Text("Pitch")` (`Features/ReaderReadium/ReaderSpeechSettingsSection.swift:171`) | SAME | Pitch slider row label |

---

## 3. iOS Strings with No Android String (Fan Menu and Contents Sheet Only)

| iOS String (`path:line`) | Three Words Searched in Android `reader/` | Status | Notes |
|---|---|---|---|
| `ReaderFanMenuPill(id: "rebuild", title: "Rebuild from Original", ...)` (`Features/ReaderReadium/ReadiumReaderView.swift:1932`) | `"Rebuild"`, `"from"`, `"Original"` | NO ANDROID STRING | Pill offered on converted EPUBs when the source document is newer. Absent from Android's fan menu. |
| `.accessibilityHint(pill.isEnabled ? "" : "Coming soon")` / `.accessibilityHint(action.isEnabled ? "" : "Coming soon")` (`Features/ReaderReadium/ReaderFanMenu.swift:158, 217`) | `"Coming"`, `"soon"`, `"accessibilityHint"` | NO ANDROID STRING | Accessibility hint applied to disabled fan pills and round actions. |
| `Button("Read Aloud settings", action: longPress)` (`Features/ReaderReadium/ReaderFanMenu.swift:222`) | `"Read"`, `"Aloud"`, `"settings"` | NO ANDROID STRING | Accessibility custom action exposing long-press destination for VoiceOver. Android attaches `longPressAction` without an explicit named action. |
| `Label("Go", systemImage: "arrow.forward.circle")` (`Features/ReaderReadium/ReaderContentsSheet.swift:135`) | `"Go"`, `"swipe"`, `"chapter"` | NO ANDROID STRING | Full-swipe action on Contents chapter rows navigating to the chapter. Android Contents sheet chapter rows provide tap navigation only. |

## Triage (Claude, 2026-10-10)

94 strings. Most of the 24 "no iOS string" rows are strings iOS keeps in its Settings files,
outside the files this brief named (Flash says so row by row): not differences.

- **"Color"** in the reader's highlight dialog where both apps say "Colour" everywhere else
  (iOS `ReaderNoteEditor.swift:41`): **fixed** (`reader/ReaderScreen.kt`).
- Read-aloud speed and pitch are shown differently (Android "1.0×" and "1.0"; iOS a percentage
  and "×", or "Default"). A lead, P3: look at both screens before choosing.
- **iOS only, leads:** the fan menu's **"Rebuild from Original"** pill (Android offers it from
  the Library row's menu, not in the reader); a named accessibility action for Read Aloud's
  long press ("Read Aloud settings"), without which a TalkBack reader may not reach those
  settings; and "Go" as a swipe on a chapter row (Android: a tap). None checked on a device.

