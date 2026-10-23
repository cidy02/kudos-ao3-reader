# I9 result (iOS): the iPhone faults from the first 35 side-by-side screens

*Done (I9 and I9b). Branch `claude/agent-ios-i9` from `7dc23568`. Nothing committed. 19 Swift files changed in all: 14 in I9, and 6 in I9b, one of which (`AO3WorkActionsModel.swift`) I9 also touched. Paths are under `kudos-ao3-reader/`.*

## 1. Sheets drawn Light under Sepia

**Why the three missed Sepia.** `AddToQueueView`, `AddToCollectionView` and `DownloadedDateEditor` are plain `Form`s with neither `.appThemedScroll()` nor `.appThemedRows()`. They drew the system's grouped white and grey in every theme. In the tiles' Sepia column, 64–90% of the sheet is the system grey (242,242,247) and the rows are pure white. Their Dark and OLED columns were the system's dark, not the app's.

The fix is the other sheets' own pattern: `.appThemedScroll()` on the Form and `.appThemedRows()` on each Section. Light is unchanged, because both modifiers do nothing in Light.
- `Features/Library/ReadingQueues.swift:473,501,550` rows, `:554` scroll (`AddToQueueView`).
- `Features/Library/Collections.swift:638,645,669` rows, `:673` scroll (`AddToCollectionView`).
- `Features/WorkDetail/WorkDetailSections.swift:586` row, `:588` scroll (`DownloadedDateEditor`).

**The same miss elsewhere in A82's list: rows left white.** `.appThemedRows()` is `listRowBackground`, which reaches rows only from a row, a ForEach, a Section or a `Group` inside the List (`UIComponents/AppThemeSurface.swift:46` says so). Six A82 screens put it on the `List`/`Form` itself, where it does nothing. Their backdrop was themed, but their cells kept the system's colours.
- In the tiles, `bulktag`'s rows are (255,255,255) under Sepia, where themed rows are (251,240,217).
- `pronunciations`' empty-state card is white under Sepia.

Each now has the modifier on its sections, or on a `Group` where the sections are computed properties (the pattern `AO3WorkActionsModel.swift`, `FilterLanguagePicker.swift` and twelve other screens already use):
- `bulktag`: `UIComponents/WorkBulkTagSheet.swift:43,50,57`
- `pronunciations`: `Features/ReaderReadium/ReaderPronunciationSettingsView.swift:72,86,112,139`
- `pronunciationedit`: the same file, `:377,401`
- `chapterpicker`: `Features/Comments/CommentsView.swift:1062`
- `bulktagstate` (second half, not shot yet): `Features/Writing/BulkTagStatePicker.swift:33`
- `backupimport` (second half, no demo data): `Settings/BackupImportSheet.swift:54` (a `Group`)

`pronunciationedit` and `chapterpicker` open at a part height, so before the fix their cells took the sheet glass's own fill: a shade darker than the page, not white. They now take the app's raised cell colour, as `collectiondetails` (also a part-height sheet) already does. In Sepia that cell is a lighter cream than the page.

**Outside A82's list, same container-level `.appThemedRows()`** (fixed in I9b, below):
- `Features/Support/WhatsNew.swift:74`
- `Features/ReaderReadium/ReaderSpeechSettingsSheet.swift:32` (the reader's new speech sheet, `shot:readerspeech`)
- `Features/ReaderReadium/ReaderSpeechDeveloperSettingsView.swift:115`
- `Features/Account/AccountShortcuts.swift:157`

See I9b.

**Checked and fine:**
- `readercontents` and `readerfind` have no app theming, but they sit on the reader's glass sheet with the reader's colour scheme, and both reviews called them a match.
- Every other List/Form screen in A82's list already themes both its backdrop and its rows (`.cardList()` with `.pageBodyRow`/`.cardRow`, or `.appThemedScroll()` with section-level or `Group`-level rows).

## 2. Text cut with "…" at the largest text (AX5)

- **`addworks` title ("Add to Neon rer…" at every size) and `bookmarkform` title ("Bookmark on A…" at AX5).**
  - New `wrappingInlineTitle(_:)`, `UIComponents/SubjectScreen.swift:145`. On iOS it keeps `.navigationTitle` and puts the same text in the bar's principal slot: `.headline`, up to two lines, centred, `minimumScaleFactor(0.8)`.
  - The title is capped at `.xxLarge`, because the bar does not grow. The system's own inline title stops at about 1.2× (measured on the tiles: 9 px cap height at default, 11 px at AX5), which is about where `.xxLarge` puts `.headline` (21 pt).
  - On macOS it is plain `.navigationTitle`.
  - Used at `Features/Library/AddLibraryWorksSheet.swift:108` and `Features/WorkDetail/AO3WorkActionsModel.swift:229`. Their toolbar blocks were only re-indented.
- **`addworks` rows at AX5** (`AddLibraryWorksSheet.swift:132,138`). The title's line limit is lifted at the accessibility sizes, and the byline is non-compact there, as `AuthorProfileComponents.swift:349` already does. This fixes "Tea in the Jasmine…" and "by uncle_ir…".
- **`collectionreorder`** (`Features/Library/NewCollectionSheet.swift:302,314`). At the accessibility sizes the position number goes above the title (`AnyLayout`, as `HomeResumeHero.swift:252` and `AuthorProfileView.swift:395` do) and the title's line limit is lifted.
  - Beside the number, "Unanswered" was wider than its column, so it broke mid-word ("Unanswere / d Is Not U…"). Lifting the line limit alone would still have split it.
- **`chapterpicker`** (`Features/Comments/CommentsView.swift:1044`). The chapter name's `.lineLimit(1)` becomes unlimited at the accessibility sizes. It then wraps like "All Comments" in the same list ("Chapter / 1") instead of "Chapt… ✓".

Not changed, seen while looking:
- `bookmarkform` at AX5 hyphenates "Recom-mend" beside its switch (fixed in I9b, below).
- The chapter picker's short sheet is a fixed height for three or fewer chapters (`CommentsView.swift:1097`), so at AX5 it scrolls.

## 3. Save Search

- **The title.** `.subjectScreenWash(palette:)` ends in `hidesNavigationBarChrome()`, which sets `navigationTitle("")` for pages that name themselves in a header block. The innermost title wins: New queue, New collection and Tags set theirs before the wash, and theirs show.
  - Save Search set its title after the wash, so it never showed. It is now set before the wash (`Features/Search/SaveSearchSheet.swift:88`).
  - **Same order:** `Features/Account/AccountInboxFilterSheet.swift` ("Inbox Filters", A82 `inboxfilter`). Fixed in I9b, below.
- **The name.** It is pre-filled in real use.
  - "Save Search…" calls `presentSaveDialog()` (`Features/Search/SearchView.swift:844`), which seeds `defaultSavedSearchName(for:)`: "Star Wars" for `tagsearch:Star Wars`. This is already tested in `KudosTests/SearchPanelRulesTests.swift:58-69`.
  - Only the DEBUG shot skipped it, by setting `showingSaveDialog = true` directly. The shot now calls `presentSaveDialog()` (`SearchView.swift:292`, `#if DEBUG`), so it shows what a reader sees.

## I9b: the same-pattern misses I9 left (asked for 2026-10-22)

Same rules as I9: compile only, nothing committed. Six files, five of them new to this branch.

**`.appThemedRows()` on the container, moved to where it works:**
- `Features/ReaderReadium/ReaderSpeechSettingsSheet.swift:30` (the new `readerspeech` pair). The Form holds one `ReaderSpeechSettingsSection` view, so the modifier goes on that view. That reaches each of its sections, the way `Settings/SettingsView.swift:30` already themes the same view inside a `Group`.
- `Features/ReaderReadium/ReaderSpeechDeveloperSettingsView.swift:69,90,105,116`: on each of its four sections.
- `Features/Account/AccountShortcuts.swift:141,149,158`: on each of its three sections.
- `Features/Support/WhatsNew.swift:74`: **removed**, not moved. Its rows are already `.cardRow()` cards (`:70`), which set their own row background, so the List-level call was dead. The page looks the same.

**A title set after `.subjectScreenWash`:**
- **Fixed:** `Features/Account/AccountInboxFilterSheet.swift:62`. "Inbox Filters" is now set before the wash (`:66`), as Save Search's is; it is a sheet with no header block.
- **Swept:** every modifier chain after `.subjectScreenWash(` or `.hidesNavigationBarChrome()` in the app. After I9, fifteen still set a title after it: Inbox Filters (fixed here), the two select-mode counts below, and twelve pushed pages that name themselves in their own header (a `SubjectHeaderBlock`, or Work Detail's hero), where the blank bar is intended:
  - Settings, a settings page, a collection page, queue details, Manage tags, the grid pages
  - the series editor, reorder and remove-works pages
  - Collections and gifts, and the series picker
  - Work Detail
- **Flagged, not changed: two select-mode counts.** These are pushed screens, not sheets, and I couldn't see select mode.
  - `Features/Library/RecentlyDeletedView.swift:73` and `Features/Library/ReadingQueueOrganizer.swift:311` (the queues grid) both say "1bg's grammar: the title bar takes the count while selecting". They set `navigationTitle(isSelecting ? "N selected" : "")` *after* the wash, so by the same rule the count is probably never shown.
  - Home's section list met this by putting the count in the principal slot (`HomeSectionListView.swift:155`, "The wash empties the navigation title").
  - Moving each title above its wash is a two-line fix, once someone has seen it in select mode.

**`bookmarkform` "Recom- / mend" at AX5:** `Features/WorkDetail/AO3WorkActionsModel.swift:215-216,250`. A small `toggle(_:isOn:)` puts the label above its switch at the accessibility sizes, as Android does at its largest size. At other sizes it is the ordinary `Toggle`.
- VoiceOver reads the toggle's own label. The visible text above it is hidden from VoiceOver, so the label is not read twice.
- No other toggle in the app was changed (there are 93); this is the one A82 showed.

**Build and lint (I9b):**
- iOS (arm64 simulator SDK) and macOS: **BUILD SUCCEEDED**, with the same derived-data paths as I9, and no compiler warnings in the six files.
- SwiftLint: all six files are 0 → 0 against HEAD's copies.
- Not run: tests, any simulator.

## Tests

None added. All three items are SwiftUI modifier placement or debug routing: the project has no view-inspection or snapshot tests to hold them, and the one rule involved (the default name) is already covered. The check is the next side-by-side shot of these screens.

This is the pixel check used above. Run it on a re-shot tile: the iPhone Sepia column should show about 0% pure white and 0% system grey (except Light-only artwork). With the changes reverted, `addtoqueue`, `addtocollection` and `downloaddate` return to 64–90% system grey, and `bulktag` and `pronunciations` to 25–29% white.

```python
from PIL import Image
im = Image.open("tiles-a82/<name>.png").convert("RGB")
px = [im.getpixel((x, y)) for x in range(620, 912, 4) for y in range(120, 680, 4)]
print(sum(p == (255, 255, 255) for p in px) / len(px), sum(p == (242, 242, 247) for p in px) / len(px))
```

## Build and lint

- **iOS:** `xcodebuild build`, `generic/platform=iOS Simulator`, `ARCHS=arm64`, `CODE_SIGNING_ALLOWED=NO`, `-derivedDataPath ~/Library/Developer/Xcode/DerivedData/kudos-agent-ios-ios`: **BUILD SUCCEEDED**.
  - A first build with both simulator architectures compiled every file, then failed to link x86_64: the vendored MuPDF has no x86_64 simulator slice (`_fz_count_pages` and others, from `KudosMuPDF.o`). That is the environment, not this change; arm64 links.
- **macOS:** `xcodebuild build`, `platform=macOS`, `-derivedDataPath …/kudos-agent-ios-mac`: **BUILD SUCCEEDED**.
- **Compiler warnings:** none new. The two warnings in touched files are on lines this change doesn't touch (`ReadingQueues.swift:114`, `ReaderPronunciationSettingsView.swift:439`).
- **SwiftLint:** every touched file has the same count as HEAD's copy: 12 files 0 → 0, `CommentsView.swift` 2 → 2 (`file_length`, `type_body_length`), `Collections.swift` 1 → 1 (`orphaned_doc_comment`), with the same rules.
- **Not run:** tests, and any simulator, as briefed. Nothing has been seen on screen; the next side-by-side shot is the check.

## Workspace notes

- This worktree had no `Packages`/`Vendor`. I linked both to `~/kudos-ios-integrate` as `~/kudos-ios-polish` does; they show as untracked (`.gitignore`'s `Packages/` and `Vendor/` don't match symlinks), so commit named files.
- Builds used `-clonedSourcePackagesDirPath ~/Library/Developer/Xcode/DerivedData/kudos-agent-ios-packages`, a copy-on-write clone of kudos-polish's resolved packages, with `-disableAutomaticPackageResolution`. A cold resolve fails on a swift-toolkit revision mismatch and missing binary artifacts.
- A first `xcodebuild -list` without a derived-data path made `DerivedData/AO3_App_OpenSource-dhfqohqnpjgqywbscwveyifqhvda` (a partial package fetch, 23:43). I deleted it.
