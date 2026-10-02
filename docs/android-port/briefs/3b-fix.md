# Brief 3b-fix: make Library match iOS and Home

Edit-only. **Do not commit**, push, switch branches, stash or reset. No network. You cannot run
Gradle: write code that compiles by careful reading, and check that every symbol you use exists
with that signature. Claude builds, checks the result on the emulator and sends errors back.

Library was rebuilt in commit afd6d14f, and Home in b476ca47. On the emulator with the demo
library (Dark), Library differs from iOS (`docs/android-port/shots/ios/library-dark.png`) in three
ways. Fix all three.

## 1. Toolbar placement
On iOS the Library's three top-right buttons (+, filter, …) sit **on the large title's row, to the
right of "Library"**, as Home's do. Android draws them in a separate row under the title, on a
hard-edged red band. Do what Home does: Home hands its buttons to the shell through
`home/HomeShellChrome.kt` (read it), and `app/MainScaffold.kt` draws them on the title row. Give
Library the same mechanism by generalising `HomeShellChrome` into a shell-wide chrome holder
that any tab root can fill, or by adding a Library equivalent. Then remove the separate row and
the red band. Library keeps the plain theme backdrop at the top, as on iOS; there is no subject
wash on the Library root.

## 2. One cover card
There are two cover cards: Home's `home/HomeCoverCard.kt` `SubjectWorkCoverCard` (correct: it matches
iOS's purple "DOCTOR WHO" card) and Library's `ui/subject/WorkLibraryComponents.kt` `WorkCoverCard`
(wrong: a green card kicked "DOCTOR WHO (2005) +1"). Make Library use Home's card everywhere it
shows cover cards. Move `SubjectWorkCoverCard` and the helpers it needs from `home/` into
`ui/subject/` (keep the name, and update Home's imports), then delete Library's duplicate
`WorkCoverCard`. Keep `WorkCarouselSection` and `WorkLedgerRow` from `WorkLibraryComponents.kt` if
Home doesn't have equivalents. If Home has equivalents (`home/HomeSectionsUi.kt`), use one of each
and note which one you kept. Adjust `WorkLibraryComponentsTest.kt` to match.

## 3. Shelf counts don't match iOS
iOS's demo Library shows Reading Now 3, Saved for Later 2 and Finished 3. Android shows Saved for
Later 4 and Finished 1 on the same demo data. Find out why by comparing each shelf's rule:
- iOS: `kudos-ao3-reader/Features/Library/LibrarySectionKind.swift` and wherever it filters (search
  `savedForLater`, `finished`, `isQueueOnlyWork`, `isFinished`).
- Android: `library/LibrarySectionKind.kt`, `LibraryQuery.kt`, `LibraryRepository.kt`, `LibraryViewModel.kt`.
- The demo data on each side: `kudos-ao3-reader/App/DemoLibrary.swift` (`samples`, the `finished`
  flags, Saved for Later = works 7 and 13) and `android/.../app/DemoLibrary.kt`.

If an Android shelf rule differs from iOS, fix the rule to match iOS. If the Android demo seed
differs from iOS's, fix the seed. Add a unit test that checks the three shelf counts on the
seeded demo data (see `app/DemoLibraryTest.kt` for seeding in a test).

Write `docs/android-port/briefs/3b-fix-result.md` (under 400 words): what caused each difference and
what you changed.

Don't touch `backup/`, `data/local`, migrations or `library/ReadingQueue*` (another agent is
working on queues).
