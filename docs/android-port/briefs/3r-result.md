# 3r result: opening a work keeps its place

## iOS rule

Resume (`ReadiumReaderView.swift:1403-1406`, `ReadiumBook.swift:500-525`): a stored Readium locator, otherwise the start of `lastSpineIndex` when that index is past 0. Intra-chapter scroll is not recovered. `legacyReaderProgress` is display-only (`Models.swift:299-304`); neither reader resumes from it.

Writes: open stamps Continue Reading dates and leaves the percent (`ReadiumReaderView.swift:37-48`, `1350-1356`). The first `locationDidChange` of the restored spot is not a read (`ReadiumProgressPersistence.swift:150-160`, `Models.swift:664-669`). A locator is stored only after the position moves by `minProgressionDelta` (0.001). Close with an unchanged locator stamps dates only (`ReadiumReaderView.swift:916-931`). A moved locator clears the macOS percent (`Models.swift:660-669`).

Displayed fraction (`Models.swift:544-604`): `legacyReaderProgress`, else the locator's `totalProgression`, else `(lastSpineIndex + 1) / chapter total` when the total is greater than 1, else `lastScrollFraction` if it is above 0.

## Android before

`restoreTarget` also sought `lastScrollFraction`, including spine 0. Every navigator callback, including the open landing, was saved. That wrote `lastScrollFraction` 0 over the demo's 0.42 and the rings, which ignored `legacyReaderProgress`, dropped to 0%.

## Fix

Open matches the iOS order, with scroll fraction 0 on a spine fallback. `ReaderProgressGate` drops the landing (and a follow-up that only adds `totalProgression`). A later move persists at the repository clock and retires the macOS percent; close without a move only stamps dates. Rings use `readingProgress` (one-line delegate in `LibraryQuery.kt`, which the rings already call). Work Detail's percent uses `publicationProgress`, same as the iOS Activity row.

Tests: locator, legacy-only, spine-only, nothing, and open-then-close keeping 42%, on `ReaderRepository`'s clock. Offline `:app:assembleDebug :app:testDebugUnitTest` exited 0.
