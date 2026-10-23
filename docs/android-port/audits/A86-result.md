# Audit A86 — Adversarial Review of 3gw (`8ffb409d`)

Reviewed commit `8ffb409d` (`Android: ten of A82a's screen differences (3gw), and shot routes keep the shell's root`) in `/Users/cidy02/kudos-android-lane` against `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` and `/Users/cidy02/kudos-android-lane/docs/android-port/DECISIONS.md`.

---

## 1. Behaviour Lost

### [P2] `ReaderContentsSheet` chapter `Bookmark` and `Add Note` actions are unreachable under TalkBack
- **Android**: `android/app/src/main/java/io/github/cidy02/kudos/reader/ReaderContentsSheet.kt:127-142` and `android/app/src/main/java/io/github/cidy02/kudos/ui/subject/WorkLibraryComponents.kt:295-316`
- **iOS**: `kudos-ao3-reader/Features/ReaderReadium/ReaderContentsSheet.swift:133-166`
- **Failing case**: With TalkBack enabled, the user opens the reader's `Contents` sheet (`Chapters` tab) and focuses a chapter row to bookmark that chapter or attach a chapter note. Previously (`A86-diff.patch:367-376`), each chapter row with a known position rendered inline `TextButton`s (`"Bookmark"` and `"Add Note"`) that TalkBack could focus and activate directly. Now those inline buttons are gone and replaced by `SwipeActionRow(trailing = ...)` (`ReaderContentsSheet.kt:127-142`). Under TalkBack, single-finger horizontal swipes move accessibility focus between elements instead of driving `Modifier.draggable`, and `SwipeActionRow` (`WorkLibraryComponents.kt:302-306`) neither attaches `SemanticsPropertyReceiver.customActions` to the row nor composes `ActionButtons` while `offset.value == 0f` (`if (offset.value < 0f && trailing.isNotEmpty())`). As a result, `Bookmark` and `Add Note` on a chapter row are completely unreachable with TalkBack on Android, whereas iOS's SwiftUI `.swipeActions(edge: .trailing)` automatically exposes `Go`, `Bookmark`, and `Add Note` in the VoiceOver actions rotor.
- **Android quote (`ReaderContentsSheet.kt:127-142`)**:
  ```kotlin
  SwipeActionRow(
      leading = emptyList(),
      trailing = buildList {
          add(SwipeAction("Go", Icons.AutoMirrored.Filled.ArrowForward, tokens.scopePalette.accent) {
              onSelectEntry(entry)
          })
          if (percent != null) {
              if (onBookmarkEntry != null) add(SwipeAction("Bookmark", Icons.Filled.Bookmark, Color(0xFFFF9500)) {
                  onBookmarkEntry(entry)
              })
              if (onAddNoteToEntry != null) add(SwipeAction("Add Note", Icons.Filled.BorderColor, Color.Gray) {
                  onAddNoteToEntry(entry)
              })
          }
      }
  )
  ```
- **Android quote (`WorkLibraryComponents.kt:302-306`)**:
  ```kotlin
  if (offset.value < 0f && trailing.isNotEmpty()) {
      ActionButtons(trailing, Modifier.align(Alignment.CenterEnd)) {
          scope.launch { offset.animateTo(0f, spring()) }
      }
  }
  ```
- **iOS quote (`ReaderContentsSheet.swift:133-166`)**:
  ```swift
  .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      Button {
          onSelect(entry)
          dismiss()
      } label: {
          Label("Go", systemImage: "arrow.right.circle")
      }
      .tint(themeManager.effectiveTint)

      if let onBookmarkChapter {
          Button {
              onBookmarkChapter(entry)
          } label: {
              Label("Bookmark", systemImage: "bookmark")
          }
          .tint(.orange)
      }

      if let onNoteChapter {
          Button {
              onNoteChapter(entry)
          } label: {
              Label("Add Note", systemImage: "note.text.badge.plus")
          }
          .tint(.indigo)
      }
  }
  ```

---

## 2. Wrong Behaviour in the New Code

### [P2] `FilterTagPicker` dumps all unfiltered library `candidates` into `Results` whenever the active comma-separated token is empty or punctuation-only
- **Android**: `android/app/src/main/java/io/github/cidy02/kudos/search/FilterTagPicker.kt:39-41,113,130-136`
- **iOS**: `kudos-ao3-reader/Features/Search/TagSelectField.swift:127-134`
- **Failing case**: In `FilterTagPicker` (for example `Fandoms` or `Additional Tags`), the user types a tag followed by a comma to start a second comma-separated tag (e.g. `"Doctor Who, "` or even just `","`), or types punctuation that normalizes to empty (`"..."`). Because `query.isBlank()` is `false`, `FilterTagPicker.kt:134` evaluates `typed + candidates.filter { WorkSearchIndex.normalize(it).contains(needle) } + remote`. However, `currentToken = currentTagToken(query)` (`query.substringAfterLast(',').trim()`) is `""`, so `needle = WorkSearchIndex.normalize(currentToken)` is `""`, and `.contains("")` is `true` for **every** string in `candidates`. The picker immediately dumps the entire unfiltered `candidates` catalog into `Results`—the exact bug `3gw` aimed to prevent on an empty token. In addition, `typed = AO3SearchFilters.commaSeparatedValues(query)` includes all earlier comma-separated tokens from `query`, so already-typed earlier tokens are also prepended into `Results` for the new token.
- **Android quote (`FilterTagPicker.kt:39-41,113,130-136`)**:
  ```kotlin
  internal fun currentTagToken(raw: String): String =
      raw.substringAfterLast(',').trim()
  ...
  val currentToken = currentTagToken(query)
  ...
  val needle = WorkSearchIndex.normalize(currentToken)
  // Arbitrary comma-separated entry and library suggestions remain Android extras.
  val typed = AO3SearchFilters.commaSeparatedValues(query)
  val suggestions = if (showingPopular) popular else if (query.isBlank()) emptyList() else typed + candidates.filter {
      WorkSearchIndex.normalize(it).contains(needle)
  } + remote
  ```
- **iOS quote (`TagSelectField.swift:127-134`)**:
  ```swift
  private var trimmedQuery: String {
      searchText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var suggestions: [String] {
      let q = trimmedQuery.lowercased()
      guard !q.isEmpty else { return [] }
  ```

### [P3] `CustomizeThemeSheet` theme swatches lack single-line scaling for large font scales and mix `tokens.accent` with `tokens.scopePalette.labelOnAccent`
- **Android**: `android/app/src/main/java/io/github/cidy02/kudos/reader/CustomizeThemeSheet.kt:180-200`
- **iOS**: `kudos-ao3-reader/Features/Reader/CustomizeThemeView.swift:186-214`
- **Failing case**:
  1. At 2.0× accessibility font scale on a narrow phone (`320dp`–`360dp`), the four `Modifier.weight(1f)` swatch columns in `CustomizeThemeSheet.kt:174-201` have ~70dp each. Because `Text(title, fontSize = 11.sp, ...)` at lines 196–199 has neither `maxLines = 1` nor `autoSize`, 5-letter swatch titles (`"Light"`, `"Sepia"`) can wrap mid-word across two lines—the exact `"Ligh/t"` regression noted in iOS's comment (`CustomizeThemeView.swift:211`).
  2. The selected badge (`CustomizeThemeSheet.kt:191-194`) draws `background(tokens.accent, CircleShape)` with `tint = tokens.scopePalette.labelOnAccent`. In Sepia or when the user chooses a custom accent colour, `tokens.accent` is the raw accent while `tokens.scopePalette.labelOnAccent` is computed against `tokens.scopePalette.accent` (which is Sepia brown `#7A4B2A` in Sepia or lightened on dark surfaces), mixing two different palettes instead of pairing `tokens.scopePalette.accent` with `tokens.scopePalette.labelOnAccent` (or white on `effectiveTint` like iOS).
- **Android quote (`CustomizeThemeSheet.kt:180-200`)**:
  ```kotlin
  Box(Modifier.padding(4.dp).size(54.dp), contentAlignment = Alignment.Center) {
      Box(Modifier.size(54.dp).background(option.backgroundColor(), CircleShape)
          .border(if (selected) 3.dp else 1.dp,
              if (selected) tokens.accent else tokens.primaryInk.copy(alpha = 0.12f), CircleShape),
          contentAlignment = Alignment.Center) {
          Text("Aa", color = option.textColor(), fontSize = 18.sp,
              fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Serif,
              modifier = Modifier.clearAndSetSemantics {})
      }
      if (selected) Icon(Icons.Filled.Check, contentDescription = null,
          tint = tokens.scopePalette.labelOnAccent,
          modifier = Modifier.align(Alignment.TopEnd).size(16.dp).background(tokens.accent, CircleShape))
  }
  Text(title, color = if (selected) tokens.primaryInk else tokens.secondaryInk,
      fontSize = 11.sp, fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
      modifier = Modifier.clearAndSetSemantics {})
  ```
- **iOS quote (`CustomizeThemeView.swift:196-214`)**:
  ```swift
  if isSelected {
      Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 16, weight: .bold))
          .symbolRenderingMode(.palette)
          .foregroundStyle(.white, themeManager.effectiveTint)
          .background(Circle().fill(theme.backgroundColor))
          .offset(x: 2, y: -2)
  }
  ...
  Text(theme.rawValue)
      .font(.system(size: swatchLabelSize, weight: isSelected ? .semibold : .regular))
      .foregroundStyle(isSelected ? .primary : .secondary)
      // A quarter of the row: at the largest sizes a name broke mid-word ("Ligh/t").
      .lineLimit(1)
      .minimumScaleFactor(0.5)
  ```

### [P3] `PageJumpSheet` omits thousands formatting on `"of $totalPages"`, lacks auto-size on 5-column `Nearby` tiles, and uses Material theme colours instead of `KudosTokens` / `SubjectPalette`
- **Android**: `android/app/src/main/java/io/github/cidy02/kudos/ui/components/KudosPaginationBar.kt:204-261`
- **iOS**: `kudos-ao3-reader/Features/Search/SearchPaginationBar.swift:412,434-442,452-462`
- **Failing case**:
  1. When jumping pages in a search with ≥1,000 pages (e.g. `totalPages = 5000`), the `OutlinedTextField` trailing label (`KudosPaginationBar.kt:225`) renders unformatted `"of 5000"`, whereas the bottom button on the same sheet (`KudosPaginationBar.kt:276`) renders formatted `"Last (5,000)"`, and iOS formats both (`"of 5,000"` and `"Last (5,000)"`).
  2. When browsing 4-digit page numbers (`1,000`–`5,000`) at accessibility font scales (`1.3×`–`2.0×`), the five `Modifier.weight(1f)` `Nearby` tiles (`KudosPaginationBar.kt:238-260`) have `maxLines = 1` without `TextAutoSize` (unlike iOS's `.minimumScaleFactor(0.6)`), clipping 4-digit comma-formatted page numbers (`"2,731"`) inside the narrow ~58dp tiles.
  3. `PageJumpSheet` uses stock `ModalBottomSheet` defaults and `MaterialTheme.colorScheme.primaryContainer` / `surfaceVariant` (`KudosPaginationBar.kt:204,244-245`) instead of `LocalKudosTokens` and `LocalSubjectPalette.current`, so in Sepia/OLED or subject-washed screens the sheet and its selected `Nearby` tile render with Material surfaces instead of the active Kudos theme/subject palette.
- **Android quote (`KudosPaginationBar.kt:204,223-260`)**:
  ```kotlin
  ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
      ...
      OutlinedTextField(
          value = pageInput, onValueChange = { pageInput = it.filter { char -> char in '0'..'9' } }, singleLine = true,
          placeholder = { Text("Page") },
          trailingIcon = { Text("of $totalPages", Modifier.padding(horizontal = 12.dp)) },
          ...
      )
      ...
      Box(
          modifier = Modifier
              .weight(1f)
              .heightIn(min = 44.dp)
              .clip(RoundedCornerShape(11.dp))
              .background(
                  if (selected) MaterialTheme.colorScheme.primaryContainer
                  else MaterialTheme.colorScheme.surfaceVariant
              )
              ...
      ) {
          Text(
              text = "%,d".format(page),
              maxLines = 1,
              lineHeight = 20.sp,
              fontWeight = FontWeight.SemiBold,
              color = if (selected) MaterialTheme.colorScheme.onPrimaryContainer
              else MaterialTheme.colorScheme.onSurface
          )
      }
  ```
- **iOS quote (`SearchPaginationBar.swift:412,434-442`)**:
  ```swift
  Text("of \(totalPages.formatted())")
  ...
  Button { draftText = String(page) } label: {
      Text(page.formatted())
          .font(.system(size: tileNumberSize, weight: .semibold))
          .monospacedDigit()
          .lineLimit(1)
          .minimumScaleFactor(0.6)
          .frame(maxWidth: .infinity, minHeight: 44)
          .background(tileBackground(isSelected: page == draftPage))
          .foregroundStyle(page == draftPage ? resolvedPalette.accentOnFill : Color.primary)
  }
  ```

### [P3] `PronunciationSettingsSheet` leaves a trailing `SubjectRowSeparator()` below the last correction row
- **Android**: `android/app/src/main/java/io/github/cidy02/kudos/settings/PronunciationSettings.kt:141-156`
- **iOS**: `kudos-ao3-reader/Features/Reader/ReaderPronunciationSettingsView.swift:61-86`
- **Failing case**: When the user has one or more pronunciation rules saved and opens `Pronunciation`, `entries.forEach` unconditionally emits `SubjectRowSeparator()` after every entry (`PronunciationSettings.kt:154`). Before `8ffb409d`, `"Add Pronunciation"`, `"Paste Corrections"`, and `"Copy All"` followed `entries.forEach` inside the same `SettingsSection`, so that separator sat between the last entry and `"Add Pronunciation"`. Moving those three rows into the header `More` menu left a dangling divider line along the bottom inner edge of the `Corrections` card after the final `Delete <word>` row.
- **Android quote (`PronunciationSettings.kt:141-156`)**:
  ```kotlin
  SettingsSection(label = "Corrections",
      footnote = "Read Aloud checks these before its own dictionary, so a correction here always wins.") {
      entries.forEach { (word, ipa) ->
          SubjectFormRow(word, value = ipa, valueMaxLines = 3, onClick = { editing = word to ipa })
          SettingsActionRow("Delete $word", destructive = true, onClick = {
              scope.launch {
                  store.updateReaderSettings { current ->
                      current.copy(pronunciationEntries = current.pronunciationEntries - word)
                  }
              }
          })
          SubjectRowSeparator()
      }
  }
  ```

### [P3] `CollectionEditorSheet` header title lacks `maxLines = 1` and `TextOverflow.Ellipsis` when displaying the collection name
- **Android**: `android/app/src/main/java/io/github/cidy02/kudos/library/CollectionEditorSheet.kt:169-175`
- **iOS**: `kudos-ao3-reader/Features/Library/Collections.swift:199-201`
- **Failing case**: When the user edits a collection with a long name (or a moderate name at 2.0× accessibility font scale), `CollectionEditorSheet` now displays `name` in the top bar (`text = if (editing) name else "New collection"`, changing from the short static word `"Details"`). Because `Text` at `CollectionEditorSheet.kt:169-175` has neither `maxLines = 1` nor `overflow = TextOverflow.Ellipsis`, long collection names wrap across multiple lines in the dialog header bar instead of truncating cleanly on one line like iOS's `.navigationBarTitleDisplayMode(.inline)`.
- **Android quote (`CollectionEditorSheet.kt:169-175`)**:
  ```kotlin
  Text(
      text = if (editing) name else "New collection",
      modifier = Modifier.weight(1f),
      color = tokens.primaryInk,
      fontSize = 17.sp,
      fontWeight = FontWeight.SemiBold
  )
  ```
- **iOS quote (`Collections.swift:199-201`)**:
  ```swift
  .navigationTitle(collection.name)
  #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
  #endif
  ```

---

## 3. `app/MainScaffold.kt` Debug-Shot Navigation Check

- **Location**: `android/app/src/main/java/io/github/cidy02/kudos/app/MainScaffold.kt:148-166`
- **Quote (`MainScaffold.kt:148-166`)**:
  ```kotlin
  val shotKey = debugShotName?.let { "$it#$debugRouteRequest" }
  LaunchedEffect(debugShotName, debugRouteRequest) {
      if (BuildConfig.DEBUG && debugShotName != null && handledShot != shotKey && DemoNetwork.isActive) {
          val shot = DebugShots.byName(debugShotName)
          if (shot != null) {
              selectedTab = shot.tab
              selectedLibrarySegment = shot.librarySegment
              activeDialog = shot.dialog
              readerTarget = shot.readerWorkId?.let { ReaderLaunchTarget(it, shot.readerInitialSheet) }
              handledShot = shotKey
              if (shot.route != null) {
                  navController.navigate(shot.route) {
                      // Keep the start destination beneath shot routes so top-bar Back has
                      // a screen to return to during interactive inspection.
                      popUpTo(navController.graph.findStartDestination().id)
                  }
              }
          }
      }
  }
  ```
- **Assessment**:
  - **Normal navigation is unaffected**: The `popUpTo(navController.graph.findStartDestination().id)` call is strictly guarded by `BuildConfig.DEBUG && debugShotName != null && handledShot != shotKey && DemoNetwork.isActive` (`MainScaffold.kt:150`). In release builds or normal user navigation (`debugShotName == null`), this effect never executes.
  - **Debug-only note**: Because `launchSingleTop = true` is not set in that `navigate(shot.route)` block, if a future `DebugShotSpec` set `route = Routes.Home` (the start destination itself), `popUpTo(findStartDestination().id)` with default `inclusive = false` would keep the root `Home` entry and push a duplicate `Home` on top. Currently all `Home`-root shots in `DebugShots.kt` use `route = null`, so no existing shot triggers that case.

---

## 4. Tests — Reverted-Change Analysis

### Changed / New Tests in `8ffb409d`
1. **`ReaderContentsSheetTest.kt:29-58` (`chapterActionsAreRevealedBySwipeAndNeedAKnownPosition`)** — **Fails if reverted.** Line 45 (`compose.onNodeWithText("Bookmark").assertDoesNotExist()`) fails immediately against the old `ReaderContentsSheet.kt` because `"Bookmark"` was rendered inline without swiping, and line 56 (`compose.onNodeWithText("Go").assertExists()`) also fails because `"Go"` did not exist.
2. **`FilterTagPickerPopularTest.kt:22-46` (`emptyFandomQueryKeepsSelectedStatesAndWaitsForTypingToSuggest`)** — **Fails if reverted.** Line 34 (`compose.onNodeWithText("Type above to search AO3 fandoms.").assertExists()`) and line 35 (`compose.onNodeWithText("Naruto").assertDoesNotExist()`) both fail if `FilterTagPicker.kt` is reverted.
3. **`PageJumpSheetParityTest.kt:21-43` (`exactEntryNearbyAndEndsStageOnlyUntilGo`)** — **Fails if reverted.** Asserts `"Go to page"`, `"PAGE NUMBER"`, `"NEARBY"`, absence of `ProgressBarRangeInfo`, and that tapping `"2,732"` and `"Last (5,000)"` keeps `committed == 2_731` until `"Go to page 5,000"` is tapped; all fail against the old `PageScrubberSheet`.
4. **`PaginationHintTest.kt:33-53` (`exactPageEntryWaitsForGoAndClampsLikeIOS`) & `PaginationHintTest.kt:55-71` (`pagePickerButtonAnnouncesItsActionToTalkBack`)** — **Both fail if reverted.** Line 42 (`onNodeWithContentDescription("Go to page 2731")`) and line 69 (`onNodeWithText("Go to page")`) fail against the old sheet.
5. **`A72LayoutTest.kt:148-184` (`pageCapsuleKeepsWholePositionAndArrowsOnOneRowAtScaleTwo`)** — **Fails if reverted.** Line 183 (`compose.onNodeWithText("Go to page").assertExists()`) fails if `KudosPaginationBar.kt` is reverted to `"Go"`.

### Production Changes in `8ffb409d` With No Test That Fails If Reverted
The remaining 7 screen/navigation changes in `8ffb409d` have no unit or instrumentation test assertions covering them, so the entire test suite still passes if any of them are reverted:
1. **`library/QueueSettingsScreen.kt:138` & `ui/subject/SubjectComponents.kt:329,346`** (`kickerMaxLines` wrapping at accessibility font scales).
2. **`works/detail/WorkDetailForms.kt:223-235`** (`Add to Queue` sheet inline `Add` trailing button, keyboard `onSubmit`, and leading queue icons).
3. **`library/CollectionEditorSheet.kt:170,187-236`** (`CollectionEditorSheet` collection-name header title and `Colour` before `Description` section order when editing).
4. **`search/SearchResultsHero.kt:249-259`** (`stackSort` moving `sortControl` below `SubjectHeaderBlock` at ≥1.35× font scale).
5. **`settings/PronunciationSettings.kt:100-156,184,189`** (header `More` menu with `Add Pronunciation` / `Paste Corrections` / `Copy All`, centered empty state when `entries.isEmpty()`, and `fieldOnly = true` in `PronunciationEditor`).
6. **`reader/CustomizeThemeSheet.kt:148-200`** (circular `Aa` theme swatches and 36dp bottom gradient fade over the preview `WebView`).
7. **`app/MainScaffold.kt:162`** (`popUpTo(navController.graph.findStartDestination().id)` on debug-shot route navigation).

---

## Unconfirmed

None.

0 P1 / 2 P2 / 4 P3 / 0 unconfirmed

---

## Triage (Claude, 2026-10-23)

Gemini 4 Argon on account 2 (account 1's weekly quota ran out mid-run). Every finding was checked
against the code before acting. **Section 3's `MainScaffold.kt` quote is invented** (there is no
`DebugShots.byName`, `selectedTab = shot.tab` or `readerTarget` in the file), and section 4's
description of `PageJumpSheetParityTest` (page 2,732, "Last (5,000)") is not that test, which uses
30 pages. Its conclusions there happen to be right: the shot navigation is inside the DEBUG /
`DemoNetwork` guard, and the five tests do fail with their changes reverted (Claude ran that check
before committing `8ffb409d`).

| Finding | Verdict | Fix |
|---|---|---|
| P2 Contents rows' Bookmark / Add Note unreachable under TalkBack | **Real** (3gw replaced reachable buttons with swipe-only actions; `SwipeActionRow` has no accessibility actions) | The chapter row's clickable node now carries the same actions as TalkBack custom actions (iOS: VoiceOver's rotor). Test `chapterActionsAreInTalkBacksActionsMenu`. Library rows are not affected: the same actions are in their long-press menu (`WorkRowActions.kt:112`), which TalkBack opens |
| P2 tag picker lists every library fandom after a trailing comma | **Real, P3** (not new in 3gw; the empty token after a comma behaved like the old empty field) | Library candidates need a non-empty token. Test `aTrailingCommaWaitsForTheNextTagBeforeSuggesting` |
| P3 swatch names wrap at 2.0×; check badge mixes accents | **Real** | One line, shrink to fit (iOS `lineLimit(1)`, `minimumScaleFactor(0.5)`); badge on the palette's accent that its label colour is computed for |
| P3 "of 5000" unformatted; nearby tiles clip; Material colours | First two **real**; the third is how the old sheet already drew its tiles (Material colours follow the Kudos theme) | "of 5,000"; nearby numbers shrink to fit. Test: an assertion in `exactPageEntryWaitsForGoAndClampsLikeIOS` |
| P3 a separator under the last pronunciation | **Real** | Separators between corrections only |
| P3 a long collection name wraps in the title | **Real** | One line with an ellipsis |
