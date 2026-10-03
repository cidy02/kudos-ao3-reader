# Brief 3e: Recently Deleted and local collections, redesigned as iOS draws them

Edit-only. **Do not commit**, push, switch branches, stash or reset. No network. You cannot run
Gradle: write code that compiles by careful reading. Declare every value before use, and check every
symbol you call exists with that signature (your last brief failed to compile on exactly that).
Claude builds and checks on the emulator.

## Read first
- `docs/android-port/specs/recently-deleted.md` and `docs/android-port/specs/collections.md`: the porting specs.
- `docs/android-port/LIVING-PROMPT.md` §1. **iOS code wins over the artboards.** Behaviour must be
  identical. Android already has the behaviour for both screens (Recently Deleted's two sections and
  60-day holds came in commit 2d8d6290); this brief is the look, plus anything the spec shows is
  missing.
- iOS: `kudos-ao3-reader/Features/Library/RecentlyDeletedView.swift`, `Collections.swift`,
  `NewCollectionSheet.swift`, `CollectionLedgerRow.swift`, and how Library's Collections shelf opens
  them.
- The patterns already in the lane: the subject header block, floating pushed chrome
  (`app/PushedShellChrome.kt`, commit 2ce36329), `ui/subject/SubjectWorkCoverCard.kt`,
  `WorkLibraryComponents.kt` (`WorkLedgerRow`), the queue sheet (`library/QueueEditorSheet.kt`) with
  `SubjectHueSwatchRow` and the HSV picker, and `SubjectToggle`.

## Build
1. **Recently Deleted (1bj)**: the subject header, the "Deleted" (90 days) and "Finished, not kept"
   (60 days) sections with iOS's section notes, rows showing days left, the row actions and
   confirmations with iOS's exact strings, and Select in "…".
2. **Collections**: the collections grid or list screen, a collection's page (header block with
   the collection's wash, its works in reader order, toolbar actions), and **New / Edit Collection**
   as one sheet, like the queue sheet: name, colour (five swatches plus the dashed "+" HSV picker,
   storing `colorHex` exactly), keep downloads (`SubjectToggle`), Show on Home, and description. The
   sheet's wash follows the picked colour (T-350).
3. **The "+" toolbar button** is a **filled accent circle with a white plus** on iOS (see
   `shots/ios/queue-neon-reread-dark.png`); Android draws an outlined one. Fix `ToolbarAddButton` in
   `ui/subject/SubjectComponents.kt` so every screen gets the iOS look.

Add repository functions only where none exist (`updateCollection` with colour, keep, Show on Home and
description), stamping `lastModifiedAt` as the existing ones do.

Don't touch `backup/`, `data/local` entities or migrations, `browse/` (another agent is there), or
`app/MainScaffold.kt` beyond registering the new routes' chrome. Write
`docs/android-port/briefs/3e-result.md` (under 300 words).
