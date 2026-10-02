# 3b-fix — Library parity with iOS & Home

## 1. Toolbar Placement & Red Wash

- **Cause:** `LibraryScreen.kt` had `.subjectScreenWash(tokens.scopePalette)` on its root Box, rendering a hard red band at the top. The +, filter, and more buttons were placed in an in-list `LibraryTopActions` row below the large title rather than beside it.
- **Change:** Added `library/LibraryShellChrome.kt` (mirroring `home/HomeShellChrome.kt`). `MainScaffold.kt` renders `LibraryToolbarActions` directly on the large title row aligned with "Library", reserving 144.dp (160.dp in select mode). Removed the red `subjectScreenWash` and the in-list action row; Library now keeps the plain theme backdrop matching iOS.

## 2. One Cover Card

- **Cause:** Home used `SubjectWorkCoverCard` (with djb2 fandom hashing matching iOS's purple Doctor Who cover and parenthetical fandom trimming), whereas Library used a duplicate `WorkCoverCard` in `ui/subject/WorkLibraryComponents.kt` (which generated green hue 120° and added a `+1` badge for secondary fandoms).
- **Change:** Moved `SubjectWorkCoverCard` and its helpers (`HomeCardMetrics`, `HomeStatusArrangement`, `rememberWorkDownloading`, `SubjectRemoteCoverCard`, etc.) from `home/HomeCoverCard.kt` to `ui/subject/SubjectWorkCoverCard.kt`. Deleted `HomeCoverCard.kt` and Library's duplicate `WorkCoverCard`/`WorkStatusTray`. Updated Home, Library (`LibrarySubjectWorkCard`), and tests to use `SubjectWorkCoverCard`. Kept `WorkCarouselSection` and `WorkLedgerRow` in `WorkLibraryComponents.kt` for Shelves/Ledger toggling.

## 3. Shelf Counts Parity

- **Cause:**
  - *Finished (Android 1 vs iOS 3):* `LibraryRepository.observeSnapshot()` observed `observeSavedWorks()`, which filtered `isProtected && !isQueueOnlyWork`. This dropped "Tea in the Jasmine Dragon" (`isProtected == false`) and "Lighthouse Hours" (`isQueueOnlyWork == true`), leaving only "What the River Keeps".
  - *Saved for Later (Android 4 vs iOS 2):* Android matched `w.isQueuedForLater || (w.isSaved && !w.isQueuedForLater)`. Since `isQueuedForLater` checked membership in *any* queue, works in custom queues matched. Furthermore, pre-filtering `!isQueueOnlyWork` in `buildState` stripped works 7 & 13 ("Paper Cranes" and "Stars Over Tatooine").
- **Change:**
  - In `LibraryRepository.kt`, switched `observeSnapshot()` to `observeLibraryWorks()` and populated `inSavedForLater` using `workRepository.savedForLaterWorkIds()`.
  - In `LibraryQuery.kt`, passed visible works to `shelfSource`, restricted `continueReading` and `downloaded` by `!isQueueOnlyWork`, matched `savedForLater` on `inSavedForLater || (isSaved && !isQueuedForLater)` (yielding 2), and kept all finished works on `finished` (yielding 3).
  - Added unit test `demoLibraryShelfCountsMatchIos` in `DemoLibraryTest.kt` asserting Reading Now == 3, Saved for Later == 2, and Finished == 3.
