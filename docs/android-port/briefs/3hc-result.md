# Brief 3hc — A88c Android follow-up (part two)

> **Claude, on landing (2026-10-23):** item 7 (the works pages' card dates) is **not landed**: owner
> Q28 is open and keeps each app's own date form until answered. Three iOS quotes below cite the wrong
> file, though the code is real: Add Works' byline code is in `Features/Library/AddLibraryWorksSheet.swift`
> (not `UIComponents/AO3AuthorNavigation.swift`), the Draft chip is in `Features/Writing/SeriesEditView.swift`
> (not `UIComponents/SubjectStateBadge.swift`), and the date formatters are in
> `UIComponents/WorkStatLabel.swift` (not `Features/Search/AO3WorkRow.swift`).

Implemented the seven items on `android/agent-gemini-3hc`, in this worktree only
(`/Users/cidy02/kudos-agent-codex2`). This result file was written before editing
code and updated with final line numbers after the changes. No Gradle, sign-in,
AO3 traffic, commits, pushes, branch changes, or `TASKS.md` edits were performed.
Files owned by brief 3hb were left untouched.

## Per-item changes and verbatim iOS references

Android paths below are relative to
`android/app/src/main/java/io/github/cidy02/kudos/`. iOS paths are relative to
`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`.

### 1. `collectionreorder`

- **Android changes:** `library/CollectionReorderSheet.kt:167-250`
  (`CollectionReorderContent`). Placed all ordered work rows inside one shared
  `.subjectPanel()` card (`Modifier.fillMaxWidth().subjectPanel().testTag("Collection reorder rows")`)
  inside a single list item, with
  `SubjectRowSeparator(modifier = Modifier.testTag("Collection reorder separator"))`
  between adjacent rows (`if (index > 0)`), and removed the per-row
  `8.dp` list spacing and individual rounded background/border cards while keeping
  `key(work.id)`, `zIndex`, `boundsInRoot`, long-press drag reordering, TalkBack
  `Move up` / `Move down` custom actions, and drag handles.
- **iOS reference:** `Features/Library/NewCollectionSheet.swift:246-255`:
  ```swift
                      ForEach(PanelSegment.keyed(ordered, id: \.id), id: \.key) { segment in
                          let offset = segment.offset
                          let work = segment.element
                          orderRow(work, position: offset + 1)
                              .subjectPanelSegmentRow(
                                  isFirst: offset == 0,
                                  isLast: offset == ordered.count - 1,
                                  gutter: gutter
                              )
                      }
  ```

### 2. `newcollection` and `collectiondetails`

- **Android changes:** `library/CollectionEditorSheet.kt:166-299`
  (`CollectionEditorSheet` / extracted `CollectionEditorContent`).
  - When creating a collection (`!editing`, `newcollection`), under
    `SubjectFieldLabel("Collection", Modifier.padding(top = 12.dp))`, placed the
    `Name` field, `Description` field, and `SubjectHueSwatchRow` inside one shared
    `.subjectPanel()` card (`Modifier.fillMaxWidth().subjectPanel().testTag("Collection panel")`)
    separated by `SubjectRowSeparator(modifier = Modifier.testTag("Collection panel separator"))`,
    with `Modifier.padding(horizontal = 14.dp, vertical = 11.dp)` on the swatch row
    and `12.dp` horizontal / `8.dp` vertical padding around each outlined field
    inside the card.
  - When editing collection details (`editing`, `collectiondetails`), under
    `SubjectFieldLabel("Colour", Modifier.padding(top = 10.dp))`, wrapped
    `SubjectHueSwatchRow` in its own `.subjectPanel()` card
    (`Modifier.fillMaxWidth().subjectPanel().testTag("Collection colour panel")`)
    with `Modifier.padding(horizontal = 14.dp, vertical = 11.dp)`, keeping the
    colour footnote and multi-line `Description` section below it.
- **iOS reference (`newcollection`):** `Features/Library/NewCollectionSheet.swift:48-51`
  and `Features/Library/NewCollectionSheet.swift:106-125`:
  ```swift
                      SubjectFieldLabel(text: "Collection", style: .formGroup)
                          .pageBodyRow(top: 18, gutter: SubjectMetrics.gutter)
                      collectionPanel
                          .pageBodyRow(top: 8, gutter: SubjectMetrics.gutter)
  ```
  ```swift
      private var collectionPanel: some View {
          VStack(spacing: 0) {
              SubjectFormRow(label: "Name", arrangement: .control) {
                  TextField("Comfort reads", text: $name)
                      .multilineTextAlignment(.trailing)
              }
              SubjectRowSeparator()
              SubjectFormRow(label: "Description", arrangement: .control) {
                  TextField("Optional", text: $collectionDescription)
                      .multilineTextAlignment(.trailing)
              }
              SubjectRowSeparator()
              SubjectHueSwatchRow(selection: $hue, pickedHex: $colorHex)
              // The row insets `SubjectFormRow` gives the labels above it, so the
              // first swatch lines up under "Name" instead of touching the card.
              .padding(.horizontal, 14)
              .padding(.vertical, 11)
          }
          .subjectPanel()
      }
  ```
- **iOS reference (`collectiondetails`):** `Features/Library/Collections.swift:186-220`:
  ```swift
      private var detailsColourSection: some View {
          Section {
              SubjectHueSwatchRow(
                  selection: Binding(
                      get: { collection.hue },
                      set: { newValue in
                          collection.hue = newValue
                          // Not `markMembershipChanged` — a colour is not a
                          // choice about contents, and stamping that clock here
                          // would make recolouring a collection override a
                          // removal made on another device.
                          collection.markModified()
                          saveDetails(reason: "Saving collection colour failed")
                      }
                  ),
                  // The row writes this after `selection`, every time.
                  pickedHex: Binding(
                      get: { collection.colorHex },
                      set: { newValue in
                          guard collection.colorHex != newValue else { return }
                          collection.colorHex = newValue
                          collection.markModified()
                          saveDetails(reason: "Saving collection colour failed")
                      }
                  )
              )
          } header: {
              SubjectFieldLabel(text: "Colour", style: .formGroup)
          } footer: {
              Text(collection.hue == nil
                  ? "Kudos picks this colour from the collection name. Renaming it may change the colour."
                  : "Your chosen colour stays the same if you rename the collection.")
          }
          .appThemedRows()
      }
  ```

### 3. `newqueue`

- **Android changes:** `library/QueueEditorSheet.kt:224-231` and `:297-360`
  (extracted `QueueSeedPanel` and updated `SeedRow`). Added
  `SubjectRowSeparator(inset = 43.dp, modifier = Modifier.testTag("Queue seed separator"))`
  between the `Empty` and `Saved for Later` rows inside the `.subjectPanel()` card,
  and updated `SeedRow` to use `padding(horizontal = 13.dp, vertical = 11.dp)`,
  `horizontalArrangement = Arrangement.spacedBy(11.dp)` between the radio mark and
  its label column, and `verticalArrangement = Arrangement.spacedBy(2.dp)` between
  the title and subtitle.
- **iOS reference:** `Features/Library/NewReadingQueueSheet.swift:263-270` and
  `Features/Library/NewReadingQueueSheet.swift:279-294`:
  ```swift
      private var seedPanel: some View {
          VStack(spacing: 0) {
              seedRow(.empty)
              SubjectRowSeparator(inset: 43)
              seedRow(.savedForLater)
          }
          .subjectPanel()
      }
  ```
  ```swift
              HStack(spacing: 11) {
                  radioMark(isSelected: isSelected)
                  VStack(alignment: .leading, spacing: 2) {
                      Text(seed.title)
                          .font(.system(size: seedTitleSize))
                      if let subtitle = seedSubtitle(seed) {
                          Text(subtitle)
                              .font(.system(size: seedSubtitleSize))
                              .foregroundStyle(.secondary)
                              .fixedSize(horizontal: false, vertical: true)
                      }
                  }
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
              .padding(.horizontal, 13)
              .padding(.vertical, 11)
  ```

### 4. `addworks`

- **Android changes:** `library/AddLibraryWorksSheet.kt:85-193`
  (extracted `AddLibraryWorksContent` and updated its `VerifiedAuthorByline` call)
  and `works/detail/WorkDetailIdentity.kt:129-144`, `:188-235`. Added
  `tinted: Boolean = true` to `VerifiedAuthorByline` / `AuthorBylineRow` (defaulting
  to `true` so all existing callers keep their accent link styling), and in
  `AddLibraryWorksContent` passed `includesBy = true, tinted = false` so every row's
  byline prefixes `"by"` and renders all author names in `tokens.secondaryInk`
  (while keeping verified author routes tappable).
- **iOS reference:** `Features/Library/AddLibraryWorksSheet.swift:145-156`,
  `UIComponents/AO3AuthorNavigation.swift:143-147`, and
  `UIComponents/AO3AuthorNavigation.swift:219-223`:
  ```swift
                  if !work.author.isEmpty {
                      AO3AuthorBylineView(
                          displayText: work.author,
                          identities: work.verifiedAuthorIdentities,
                          font: .caption,
                          compact: !dynamicTypeSize.isAccessibilitySize,
                          onOpenRoute: { route in
                              dismiss()
                              router.openAuthorProfile(route)
                          }
                      )
                  }
  ```
  ```swift
          HStack(alignment: .firstTextBaseline, spacing: 0) {
              if includesBy {
                  Text("by ")
                      .foregroundStyle(.secondary)
              }
  ```
  ```swift
              } else {
                  Text(text)
                      .fontWeight(emphasized ? .semibold : .regular)
                      .foregroundStyle(.secondary)
              }
  ```

### 5. `chapterpicker`

- **Android changes:** `comments/CommentsScreen.kt:36`, `:341-359`, `:521`,
  `:757-796`, `:831-854`, `:872`, `:897-920`. Replaced `Icons.Outlined.Book` with
  the open-book `Icons.AutoMirrored.Outlined.MenuBook` (`chapterPickerBookIcon`),
  threaded `palette: SubjectPalette = LocalKudosTokens.current.scopePalette` into
  `ChapterPickerSheet` and `ChapterPickerContent`, and coloured the `All Comments`
  and chapter row icons and labels (plus the active checkmark, spinner, and
  selected `All Comments` total) with `palette.accent`.
- **iOS reference:** `Features/Comments/CommentsView.swift:201`,
  `Features/Comments/CommentsView.swift:1012-1027`,
  `Features/Comments/CommentsView.swift:1061-1074`, and
  `UIComponents/SubjectSurface.swift:1362-1365`:
  ```swift
              .subjectScreenWash(palette: palette, washHeight: 480)
  ```
  ```swift
                          HStack {
                              Label("All Comments", systemImage: "bubble.left")
                              Spacer()
                              if let total = model.page?.totalComments {
                                  Text(total.formatted())
                                      .foregroundStyle(
                                          model.scope == .all ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary)
                                      )
                              }
                              if model.scope == .all {
                                  Image(systemName: "checkmark")
                                      .foregroundStyle(.tint)
                              }
                          }
                          .foregroundStyle(model.scope == .all ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
  ```
  ```swift
                              HStack {
                                  Label(chapter.displayName, systemImage: "book")
                                      .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                                  Spacer()
                                  if chapter == model.selectedChapter, model.scope == .byChapter {
                                      Image(systemName: "checkmark")
                                          .foregroundStyle(.tint)
                                  }
                              }
                              .foregroundStyle(
                                  chapter == model.selectedChapter && model.scope == .byChapter
                                      ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary)
                              )
  ```
  ```swift
      func screenTint(_ palette: SubjectPalette) -> some View {
          accentTint(palette.tint, on: palette.theme)
              .environment(\.screenTint, palette.tint)
      }
  ```

### 6. The "DRAFT" badge (`seriesremove`, `seriesreorder`)

- **Android changes:** `writing/WritingSeriesScreen.kt:161-163`. Checked every call
  site of `SubjectStateBadge` (`ui/subject/SubjectComponents.kt:260`): its other
  call sites (`SensitiveWorkRow.kt:573` for Private/Rec,
  `AuthorProfileComponents.kt:310-312` for Complete/Restricted, and
  `WritingDraftsScreen.kt:295` for draft expiry) match iOS `SubjectStateBadge`
  (`UIComponents/SubjectStateBadge.swift:12`, `Text(title.uppercased())`). On
  `SeriesReorderView` and `SeriesRemoveWorksView`, iOS uses `SubjectChip(text: "Draft", style: .neutral, palette: ...)`
  instead of `SubjectStateBadge`. Replaced `SubjectStateBadge("Draft", tokens.secondaryInk)`
  in `WritingSeriesScreen.kt:161` with
  `SubjectChip(text = "Draft", style = SubjectChipStyle.Neutral, palette = palette, modifier = Modifier.semantics { contentDescription = "Draft" })`.
- **iOS reference:** `Features/Writing/SeriesEditView.swift:419-421`,
  `Features/Writing/SeriesEditView.swift:559`, and
  `UIComponents/SubjectStateBadge.swift:11-13`:
  ```swift
              if row.isDraft {
                  SubjectChip(text: "Draft", style: .neutral, palette: accountPalette)
              }
  ```
  ```swift
              if row.isDraft { SubjectChip(text: "Draft", style: .neutral, palette: palette) }
  ```
  ```swift
      var body: some View {
          Text(title.uppercased())
              .font(.system(size: 9.5, weight: .semibold))
  ```

### 7. The works pages' card dates (`fandomworks`, `tagworks`)

- **Android changes:** `ui/components/SensitiveWorkRow.kt:281` and `:450-457`.
  Formatted `dateText` with `WorkDetailDates.displayDate(dateText)` in both the
  ledger card (`bookmark?.date ?: WorkDetailDates.displayDate(dateText)`, leaving
  bookmark dates untouched as iOS `bookmarkMetadataRow` does) and the standard card
  (`val displayDate = WorkDetailDates.displayDate(dateText)`), matching iOS
  `AO3WorkRow` (`Features/Search/AO3WorkRow.swift:220`, `:329`, `:382`). Updated
  `SensitiveWorkRowLedgerTest.kt:58` and `:103` to expect `"Updated 07/09/2026"` for
  a work row while keeping `"Bookmarked 07 Jul 2026"` on a bookmark row.
- **iOS reference:** `UIComponents/WorkStatLabel.swift:1090-1117`,
  `Features/Search/AO3WorkRow.swift:220`, `Features/Search/AO3WorkRow.swift:329`,
  and `Features/Search/AO3WorkRow.swift:382`:
  ```swift
      private static let parseFormatters: [DateFormatter] = parseFormats.map { format in
          let formatter = DateFormatter()
          formatter.locale = Locale(identifier: "en_US_POSIX")
          formatter.calendar = Calendar(identifier: .gregorian)
          formatter.timeZone = TimeZone(secondsFromGMT: 0)
          formatter.dateFormat = format
          formatter.isLenient = false
          return formatter
      }

      private static let displayFormatter: DateFormatter = {
          let formatter = DateFormatter()
          formatter.locale = Locale(identifier: "en_US_POSIX")
          formatter.calendar = Calendar(identifier: .gregorian)
          formatter.timeZone = TimeZone(secondsFromGMT: 0)
          formatter.dateFormat = "MM/dd/yyyy"
          return formatter
      }()

      static func displayDate(_ rawText: String) -> String {
          for formatter in parseFormatters {
              if let date = formatter.date(from: rawText) {
                  return displayFormatter.string(from: date)
              }
          }
          return rawText
      }
  ```
  ```swift
                          TagChip(text: WorkStat.displayDate(work.dateUpdated), symbol: "calendar.badge.clock")
  ```
  ```swift
          let updated = WorkStat.displayDate(work.dateUpdated)
  ```
  ```swift
                          Text(bookmark.date)
  ```

## Regression tests and behaviour with each change reverted

Test paths below are relative to
`android/app/src/test/java/io/github/cidy02/kudos/`.

| Test (`path:line`) | What it exercises | How to revert & what fails |
| --- | --- | --- |
| `app/Brief3hcContentTest.kt:89` — `collectionReorderRowsShareOneCardWithSeparators` | Renders `CollectionReorderContent` with three works, asserts one `"Collection reorder rows"` panel and two `"Collection reorder separator"` nodes, and verifies adjacent rows touch across only the hairline separator (`<= 1.dp`). | Revert `CollectionReorderSheet.kt:167-250` back to `itemsIndexed` with `Arrangement.spacedBy(8.dp)` and per-row background cards: fails on missing `"Collection reorder rows"` / `"Collection reorder separator"` nodes and the 8.dp vertical gap between rows. |
| `app/Brief3hcContentTest.kt:126` — `collectionEditorGroupsNameDescriptionAndSwatchesInOneCardAndWrapsColourOnDetails` | Renders `CollectionEditorContent` in creation mode (`editing = false`) and edit mode (`editing = true`), asserting that creation mode groups `NAME`, `DESCRIPTION`, and the swatches inside `"Collection panel"` with two `"Collection panel separator"` dividers below `"COLLECTION"`, and edit mode wraps the swatches inside `"Collection colour panel"`. | Revert `CollectionEditorSheet.kt:223-281` so `Name`, `Description`, and `SubjectHueSwatchRow` sit directly in the outer scroll column without `.subjectPanel()` wrappers: fails on missing `"Collection panel"` / `"Collection colour panel"` ancestors and separators. |
| `app/Brief3hcContentTest.kt:173` — `queueSeedRowsHaveHorizontalGapAndIndentedSeparator` | Renders `QueueSeedPanel`, asserts `"Queue seed separator"` sits vertically between `"Empty"` and `"Saved for Later"` and is inset past the radio button, checks the horizontal gap between `"Queue seed radio Empty"` and `"Empty"` is at least `10.dp`, and verifies clicking `"Saved for Later"` selects it. | Revert `QueueEditorSheet.kt:311` and `:340-349` (remove `SubjectRowSeparator` and `Arrangement.spacedBy(11.dp)`): fails on missing `"Queue seed separator"` and the `>= 10.dp` radio-to-label gap assertion. |
| `app/Brief3hcContentTest.kt:210` — `addLibraryWorksPrefixesByAndUsesSecondaryInkForVerifiedAndUnverifiedAuthors` | Renders `AddLibraryWorksContent` with both an unlinked author (`uncle_iroh_fan`) and a verified registered author (`undertow`), asserting two `"by"` prefixes and checking via `GetTextLayoutResult` that both author names render in `tokens.secondaryInk` (`FontWeight.Normal`) while clicking `undertow` still dispatches `onDismiss` and `openAuthor`. | Revert `AddLibraryWorksSheet.kt:187-192` (remove `includesBy = true, tinted = false`): fails on missing `"by"` nodes and because `"undertow"` renders in `scopePalette.accent` instead of `tokens.secondaryInk`. |
| `app/Brief3hcContentTest.kt:267` — `chapterPickerUsesOpenBookIconAndPaletteAccentOnAllRowLabels` | Renders `ChapterPickerContent` with a custom amber `SubjectPalette`, asserts `chapterPickerBookIcon` is `Icons.AutoMirrored.Outlined.MenuBook` (not `Icons.Outlined.Book`), and checks via `GetTextLayoutResult` that `"All Comments"`, the selected `"1. Arrival"`, and the unselected `"2. Departure"` all use `palette.accent` (plus the comment total when `isScopeAll = true`). | Revert `CommentsScreen.kt:36, 757, 834-853, 898-909` back to `Icons.Outlined.Book` and `tokens.primaryInk` / `tokens.accentInk`: fails on the icon equality assertion and on unselected/selected chapter label colours not equalling `palette.accent`. |
| `app/Brief3hcContentTest.kt:309` — `seriesDraftBadgeRendersMixedCaseDraftInReorderAndRemoveModes` | Renders `WritingSeriesContent` in both reorder mode and remove-works mode on the series fixture, asserting `"Draft"` is displayed as text (`"DRAFT"` does not exist) and `GetTextLayoutResult` reports `"Draft"`. | Revert `WritingSeriesScreen.kt:161-162` back to `SubjectStateBadge("Draft", tokens.secondaryInk)`: fails because the visible text is `"DRAFT"` instead of `"Draft"`. |
| `ui/components/SensitiveWorkRowLedgerTest.kt:52` & `app/Brief3hcContentTest.kt:340` — `sensitiveWorkRowFormatsDatesWithDisplayDateOnStandardAndLedgerCards` | Renders `SensitiveWorkRow(dateText = "09 Jul 2026")` in both `ledger = false` and `ledger = true` modes plus a `LedgerBookmark` row (`"07 Jul 2026"`), asserting `"07/09/2026"` and `"Updated 07/09/2026"` appear on work cards while `"Bookmarked 07 Jul 2026"` remains unformatted on bookmark cards. | Revert `SensitiveWorkRow.kt:281` and `:451-455` back to raw `dateText`: fails on missing `"07/09/2026"` and `"Updated 07/09/2026"` in both standard and ledger modes. |
