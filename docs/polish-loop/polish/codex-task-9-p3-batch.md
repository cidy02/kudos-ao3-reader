TASK: four small P3 fixes, one commit-sized change each (list files per fix).
1. L3-B1-7 — spec 1ad: Reading Now's pill rail is "All · Offline · WIP". Library and Home Reading Now show only
   All · WIP (`LibraryCompletionPills`, Features/Library/LibraryCompletionPills.swift, used by
   LibrarySectionListView and HomeSectionListView). Add an Offline pill (works with a readable EPUB —
   `WorkReaderPreparation.hasReadableEPUB(for:)`), counted over the same filtered set as the other pills, and
   narrowing the list when selected. Home's Recently Updated already has a pill enum (`HomeUpdatePill` in
   HomeSectionListView.swift) — reuse its Offline predicate rather than writing a second one.
2. L3-B4-2 — Browse's failed-load state (Features/Search/MediaBrowserView.swift, `loadFailure`) always shows
   `wifi.slash`, even when the message is "That work or page couldn't be found". Pick the symbol from the error
   kind: offline/unreachable → wifi.slash; anything else → exclamationmark.triangle. `UserFacingError`
   (Services/UserFacingError.swift) already classifies errors.
3. Collection mosaic (Features/Library/Collections.swift / UIComponents/StackedWorkCover.swift): two-line work
   titles in the 2×2 cells break mid-word ("Unanswere / d"). Keep word wrapping (no mid-word break): e.g.
   `.lineLimit(2)` with `.minimumScaleFactor(0.85)` and `.truncationMode(.tail)`, or hyphenation off.
4. L3-AX-2 residual — WorkStatusIconGrid (UIComponents/WorkStatLabel.swift): at accessibility sizes the Gen ☉
   glyph (`genSymbolSize`) draws larger than its tile and is clipped. Cap it to the tile (e.g. min with
   `scaledTileSize * 0.9`) so it stays inside at every size.
