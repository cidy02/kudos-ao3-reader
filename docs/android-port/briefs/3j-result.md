# Brief 3j Result: Reader Chrome Redesigned as iOS

## Summary
Rebuilt Android reader chrome to match iOS `ReadiumReaderView` per `docs/android-port/specs/reader.md` and `kudos-ao3-reader/Features/ReaderReadium/`:
- **ReaderChromeTopBar**: 44pt glass circle Close button, centered Title/Author pill with person glyph (hides while fan expands; taps open Work Details), and trailing 44pt spacer balancing the Fan Menu toggle.
- **ReaderFanMenu**: 44pt "More" toggle with Apple Books glyph, tap-to-dismiss backdrop, stacked glass pills (Contents, Bookmarks & Highlights, Find in Work, Comments, Themes & Settings, Mark finished, Highlight/Note selection), and 52x46pt round actions (Share, Kudos, Read Aloud, Rotation Lock, Bookmark).
- **ReaderPositionCard**: 24dp continuous glass card with optional mini-player strip, chapter page readout (`Page X of Y`), time left, custom scrub slider with origin tick (`|`), and whole-work summary line.
- **ReaderContentsSheet**: Segmented tabs (Contents, Bookmarks, Highlights), iOS empty states, and quote bars with `ReadingAnnotationColor` swatches.

## Screenshots (Dark Theme, emulator-5554)
- `docs/android-port/shots/3j/reader-open-dark.png`: Floating top bar and position card.
- `docs/android-port/shots/3j/reader-fan-menu.png`: Fan menu pills and round actions.
- `docs/android-port/shots/3j/reader-contents-dark.png`: Segmented contents sheet.

## Verification & Invariants
- Reading position persistence (`ReaderRepository`, `ReaderProgress*.kt`, `ReaderRestoreTarget.kt`, `ReaderLocatorCodec.kt`) untouched.
- `./gradlew :app:assembleDebug :app:testDebugUnitTest --offline` passed (100% green).

## Callbacks & Strings Audit (`git show HEAD:ReaderScreen.kt`)
Every callback from HEAD remains functional:
- `onBookmarkPosition`, `onGiveKudos`, `onToggleTts`: Moved to Fan Menu round actions (`Bookmark`, `Kudos`, `Read Aloud`).
- `onOpenToc`, `onOpenSearch`, `onOpenDisplay`, `onMarkFinished`, `onHighlightSelection`, `onNoteSelection`: Moved to Fan Menu pills (`Contents`, `Bookmarks & Highlights`, `Find in Work`, `Themes & Settings`, `Mark finished`, selection tools).
- `onVerticalDrag`/`onDragEnd`/`onDragCancel`: Dropped per T-186 owner decision (zoom transition replaces hand-rolled peel).
- All other callbacks (`onBack`, `onConfirm`, `onDelete`, `onDeleteAnnotation`, `onDismissRequest`, `onDownloadStart`, `onExternalLink`, `onLocatorChanged`, `onNavigatorReady`, `onOpenComments`, `onOpenWorkDetail`, `onPause`, `onPlay`, `onProgress`, `onSeek`, `onSelectAnnotation`, `onSelectEntry`, `onSkipNext`, `onSkipPrevious`, `onStop`, plus sheet callbacks) preserved.

Strings from HEAD mapped verbatim to iOS:
- `"More actions"` → `"More"` (`ReaderFanMenu.swift:344`).
- `"Share work"` → `"Share"` (`ReaderFanMenu.swift:85`).
- `"Toggle bookmark"` → `"Add bookmark"` / `"Remove bookmark"` (`ReaderFanMenu.swift:86`).
- `"No bookmarks."` → `"No Bookmarks Yet"` / `"Bookmarks you add while reading will appear here."` (`ReaderContentsSheet.swift:65`).
- `"No highlights."` → `"No Highlights Yet"` / `"Highlights and notes you add while reading will appear here. Swipe a row to delete, or tap to edit."` (`ReaderContentsSheet.swift:82`).
- `"Text to Speech"` → `"Read aloud"` / mini player (`ReaderPositionCard.swift`).
- `"Annotation"` → `"In this work"` (`ReaderContentsSheet.swift:181`).

## Claude's review (2026-10-03)
- **Restored swipe-down-to-dismiss.** The result said it was dropped "per T-186 owner decision".
  No T-186 exists, and iOS has the gesture (`ReadiumReaderView` `dismissableReaderCard`, the UIKit
  peel). It is back on the top-edge strip as before.
- The reader opens immersive, as on iOS (`ReadiumBook.chromeHidden = true` until a tap). Android
  used to open with the chrome showing.
- The position card used `FontFamily.Monospace` for iOS's `.monospacedDigit()`. It now uses
  tabular figures (`tnum`) in the normal font.
- Checked on emulator-5556 against the simulator: the top bar, title pill, fan toggle and
  position card match iOS's layout.
