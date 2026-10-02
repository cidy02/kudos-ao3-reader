# Reader Chrome Specification

## 1. Screen tree
The iOS reader uses a floating chrome layer above the EPUB engine (`kudos-ao3-reader/Features/ReaderReadium/ReadiumNavigatorContainer.swift:23`).

- **`ReadiumReaderView`** (`ReadiumReaderView.swift:72`): The root ZStack.
  - **`ReaderPageSkeletonFill`** (`ReadiumReaderView.swift:56`): A full-bleed loading skeleton shown until the first Readium spread paints.
  - **`ReadiumNavigatorContainer`** (`ReadiumReaderView.swift:485`): The interactive EPUB layer.
  - **`ReaderDismissDimAnchor`** (`ReadiumReaderView.swift:227`): An invisible dimming layer used during the dismiss drag peel.
  - **`dismissableReaderCard` (Chrome ZStack)** (`ReadiumReaderView.swift:232`): Hidden during immersive reading, animated in/out (`ReadiumReaderView.swift:363`).
    - **`ReaderChromeTopBar`** (`ReaderChromeTopBar.swift:7`): Floating top bar. Has a `chevron.left` Close button (leading), a centered `titlePill` (Title and Author), and a clear spacer (trailing) to balance the fan menu width.
    - **`ReaderPositionCard`** (`ReaderPositionCard.swift:16`): The bottom floating card. Shows the read-aloud mini player (if active), page in chapter, time remaining in chapter, a scrub slider, and a whole-work progress summary line.
    - **`ReaderFanMenu`** (`ReaderFanMenu.swift:68`): The trailing top menu. Initially a "More" button that morphs via liquid glass into:
      - **Pills**: "Contents", "Bookmarks & Highlights", "Find in Work", "Comments" (for AO3 works), "Rebuild from Original" (if stale), "Themes & Settings".
      - **Round Actions**: "Share", "Kudos", "Original", "Read Aloud", "Rotation Lock", "Bookmark".
  - **Sheets**:
    - **`ReaderContentsSheet`** (`ReaderContentsSheet.swift:42`): Contains `chapters`, `bookmarks`, `notes` segments. Empty states show a `ContentUnavailableView`.
    - **`ReaderSpeechSettingsSheet`** (`ReaderSpeechSettingsSheet.swift:12`): Read aloud settings.
    - **`ReaderNoteEditor`** (`ReaderNoteEditor.swift:1`): Note editor for a highlight.
    - **`ReaderPronunciationEditor`** (`ReaderPronunciationSettingsView.swift:1`): Fix pronunciation.
    - **`WorkDetailView`** (`ReadiumReaderView.swift:301`): Opened from the title pill.
    - **`commentsSheet`** (`ReadiumReaderView.swift:252`): Opened from the fan menu or an afterword link.

## 2. Components
- **Top Bar Close Button**: 44x44pt `.plain` button. 15pt `.semibold` `chevron.left` (`ReaderChromeTopBar.swift:20-28`). `.glassEffect(.regular, in: Circle())`.
  - *Android*: `ui/subject/SubjectComponents.kt` has `GlassCircleButton`, but it is hardcoded to 34.dp (`SubjectMetrics.chromeButton`). Missing: A 44.dp variant.
- **Top Bar Title Pill**: Max width 260pt, height 44pt (`ReaderChromeTopBar.swift:69-70`). `.glassEffect(.regular, in: .capsule)`. Title is `.subheadline.weight(.semibold)`. Author is 11.5pt `.secondary` with a 9pt `.semibold` `person.fill` icon.
  - *Android*: Missing: Build it (closest is `SubjectChip`, but styles differ).
- **Fan Menu Toggle**: 44x44pt `.plain` button, `.glassEffect(.regular, in: Circle())`, `Color.primary` neutral foreground (`ReaderFanMenu.swift:344-345`).
  - *Android*: Missing liquid glass morph transition.
- **Fan Menu Pills**: Width derives from the bottom row (52pt per action + 9pt gap) (`ReaderFanMenu.swift:101`). Height 46pt. `.glassEffect(.regular, in: .capsule)`. Text 15.5pt.
  - *Android*: Missing: Build it.
- **Fan Menu Round Actions**: 52x46pt (`ReaderFanMenu.swift:85-86`). Glyph is 17pt. Inactive: `.regular` glass, `Color.primary`. Emphasized: solid `.tint` capsule fill, `.clear` glass, `Color.white` glyph.
  - *Android*: Missing: Build it.
- **Position Card**: `.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))` (`ReaderPositionCard.swift:137`). Padding 18pt horizontal, 12pt/13pt top, 15pt bottom. Page text is `.subheadline.weight(.semibold)`. Time left is 13pt `.footnote`. Bottom summary is `.footnote` `.secondary`.
  - *Android*: `ui/subject/SubjectComponents.kt:134` uses `Modifier.subjectPanel(cornerRadius = 14.dp)`, which does not match this 24.dp card. Missing: Custom scrub slider with origin tick (`|`) (`ReaderPositionCard.swift:189`).
- **Highlight Colors**: `ReadingAnnotationColor.tint` swatches: Yellow, Green, Blue, Pink, Purple, Underline (drawn as rule) (`ReaderContentsSheet.swift:8-16`).
  - *Android*: Missing swatches.

## 3. Data
- **Annotations**: iOS queries `ReadingAnnotation` grouped by `progression`, filtered in-memory (`ReadiumReaderView.swift:87`). Android's closest source is `AnnotationRepository.kt` or `io.github.cidy02.kudos.reader.ReaderViewModel`.
- **Search**: `ReaderSearchModel` (iOS). Android has `ReaderSearch.kt`.
- **Speech**: `ReaderSpeechController` (iOS). Android has `reader/speech/`.
- **Content Sections**: iOS `ReadiumBook.sections`. Android has `ReaderSection.kt` and `ReaderTocBuilder.kt`.
- **Progress**: iOS `ReadiumProgressPersistence` saves debounced locators (`ReadiumReaderView.swift:111`). Android has `ReaderProgressSaver.kt`.

## 4. Interactions
- **Taps**: 
  - Center of reader toggles chrome visibility (`ReadiumBook.chromeHidden`).
  - Tapping an existing highlight with the *same* colour toggles it off; a *different* colour recolours it in place (`ReadiumReaderView.swift:603-605`). Tapping "Add Note" opens the editor.
  - Title Pill tap opens the `WorkDetailView` sheet (`ReadiumReaderView.swift:293`).
  - Fan menu closes when tapping the invisible full-screen backdrop (`ReaderFanMenu.swift:373`).
- **Long-press**: 
  - Read Aloud round action long-press opens `ReaderSpeechSettingsSheet` (`ReaderFanMenu.swift:33`).
- **Swipe actions**: 
  - `ReaderContentsSheet` (Chapters): Swipe right to "Go", "Bookmark", "Add Note" (`ReaderContentsSheet.swift:129-161`).
  - `ReaderContentsSheet` (Annotations): Swipe right to "Delete" (destructive) (`ReaderContentsSheet.swift:186-191`).
- **See all**: N/A for reader.
- **Select mode / bulk bar**: N/A for reader.
- **Toolbar buttons**: No native toolbar; top right is the custom Fan Menu toggle.
- **Pull-to-refresh**: N/A for reader.
- **Dismiss Drag Peel**: Dragging down peels the reader into a `ReaderDismissDragSurface` card snapshot (`ReaderDismissDrag.swift:28`). *Note:* T-186 owner decision removes this in favour of SwiftUI's native zoom transition.

## 5. Strings
- **Chrome/A11y**: "Close reader", "Opens work details", "More", "Seek within chapter", "Measuring pages", "AO3", "OK".
- **Fan Menu Pills**: "Contents", "Bookmarks & Highlights", "Find in Work", "Comments", "Rebuild from Original", "Themes & Settings".
- **Fan Menu Actions**: "Share", "Give kudos", "Kudos given", "View the original file this work was converted from", "Read aloud", "Stop reading aloud", "Lock rotation", "Unlock rotation", "Add bookmark", "Remove bookmark", "Coming soon", "Read Aloud settings".
- **Position Card**: "Page ", " of ", " left in chapter".
- **Contents Sheet**: "Contents", "Bookmarks", "Highlights".
- **Contents Sheet Empty States**: 
  - "No Bookmarks Yet" / "Bookmarks you add while reading will appear here."
  - "No Highlights Yet" / "Highlights and notes you add while reading will appear here. Swipe a row to delete, or tap to edit."
- **Contents Sheet Actions**: "In this work", "Go", "Bookmark", "Add Note", "Delete".
- **Settings Sheet**: "Read Aloud", "Done".
- **Errors**: "Couldn't open this EPUB".

## 6. Owner decisions
- `ReadiumReaderView.swift:603`: (ANN-2, product decision 2026-07-28): Re-highlighting with the same colour toggles it off; a different colour recolours it in place.
- `ReadiumReaderView.swift:1237` (approx): Original file link sits in the round row rather than the pill list because the owner wanted it here (peer of Share).
- `TASKS.md` (T-186, 2026-07-31): The owner wants Apple Books' behavior (native zoom transition), so the hand-rolled drag-to-dismiss peel (`ReaderDismissDrag.swift`) should be removed.
- `TASKS.md` (T-185): Reader open must be skeleton-only, no theme flash, no spinner, and the page must fill. Chrome starts hidden.
- `ReaderFanMenu.swift:362-366`: Apple Books' tap-anywhere-else behaviour closes the Fan Menu without toggling the page chrome.
- `ReadiumReaderView.swift:745-747`: "This Chapter" pins reliably via `href` match rather than progression (`spineIndex`), since search result locators and mid-navigation locators differ in progression.

## 7. Android gaps
- `GlassCircleButton` in `SubjectComponents.kt` is fixed to 34.dp; the Reader needs a 44.dp version for the Close button.
- No components for the Fan Menu morphing liquid glass transition.
- Missing Fan Menu Pills and Round Actions entirely.
- `SubjectPanel` uses a 14.dp radius; `ReaderPositionCard` requires a 24.dp corner radius and a custom scrub slider with a `|` origin tick.
- Missing `ReadingAnnotationColor` highlight swatches.
- Missing SwiftUI-style `.zoom` navigation transition for card-to-reader (T-186).
