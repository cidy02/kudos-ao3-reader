# Brief I9 (iOS): what the first 35 side-by-side screens found on the iPhone

Work in `/Users/cidy02/kudos-agent-ios` (branch `claude/agent-ios-i9`, from `claude/polish-loop`
7dc23568). You may edit code there and compile it: `xcodebuild build` for iOS (simulator SDK,
`CODE_SIGNING_ALLOWED=NO`) and macOS, each with a `-derivedDataPath` under
`~/Library/Developer/Xcode/DerivedData/kudos-agent-ios-*` (never the `kudos-polish*` ones, which
are Claude's). Do not run tests, boot a simulator, commit, push, switch branches, sign in, or
contact archiveofourown.org. Do not edit `TASKS.md`. Write `docs/android-port/briefs/I9-result.md`
as you go (`path:line` per item; for a code change worth a test, the test and what it does with
the change reverted — tests are written, Claude runs them). SwiftLint must stay at baseline
(`swiftlint lint` on the files you touch, compared with HEAD's copies). Keep macOS building.

Two independent Gemini reviews (`docs/android-port/briefs/A82a-result.md`, `A82a2-result.md`;
tiles iPhone-above-Android at `/Users/cidy02/kudos-tools/pairs/tiles-a82/<name>.png`, columns
Dark, Light, Sepia, OLED, Sepia at AX5) found these iPhone faults:

1. **Sheets drawn Light under Sepia**: `addtoqueue` (`AddToQueueView`, `Features/Library/ReadingQueues.swift`),
   `addtocollection` (`AddToCollectionView`, `Features/Library/Collections.swift`), `downloaddate`
   (`DownloadedDateEditor`, `Features/WorkDetail/WorkDetailSections.swift`). New List/Form views need
   `.appThemedScroll()` / `.appThemedRows()` (and a sheet may need the app's colour scheme); find
   why these three miss Sepia and fix them the way the other sheets do. Check the other sheets in
   A82's list for the same miss and fix any you find.
2. **Text cut with "…" at the largest text (AX5)**: `addworks` (`AddLibraryWorksSheet`: the title
   "Add to Neon rer…" is cut at every size, the work titles and "by author" at AX5),
   `collectionreorder` (`CollectionReorderSheet`: a title split mid-word and cut), `bookmarkform`
   (`AO3BookmarkComposer`: "Bookmark on A…"), `chapterpicker` (the Comments chapter picker in
   `Features/Comments/CommentsView.swift` ~L326: "Chapt… ✓"). Android shows each in full;
   wrap or reflow as the app's other T-425-style AX fixes do.
3. **`savesearch`** (`Features/Search/SaveSearchSheet.swift`): the sheet shows no "Save Search"
   title and an empty Name (Save disabled) although its caption says "The name comes from your
   search". Find whether the name is pre-filled in real use (the shot opens it over
   `tagsearch:Star Wars`); fix the title, and the pre-fill if it is really missing.

Nothing else changes. Message the "Android parity with iOS" session when done.
