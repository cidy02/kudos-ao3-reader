# Brief 3gz (Android): what the re-review of the first 36 screens still found (A88a)

**Write code in this worktree only (`/Users/cidy02/kudos-agent-codex`, branch `android/agent-codex-3gz`).
Do not commit, push, switch branches, sign in, contact archiveofourown.org, or run Gradle (Claude builds
and tests).** Do not edit `TASKS.md`. Write `docs/android-port/briefs/3gz-result.md` first; per item
`path:line`, what changed, and per test what it does with its change reverted. iOS is the reference
(`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`); Android keeps its Material chrome and what
`docs/android-port/DECISIONS.md` says it keeps. If an item is wrong on reading the code, say so and skip
it. Tiles (iPhone row above Android; Dark, Light, Sepia, OLED, largest) are PNGs in
`/Users/cidy02/kudos-tools/pairs/tiles-a88/<name>.png` if you can read images; the two reviews are
`/Users/cidy02/kudos-agent-flash/docs/android-port/audits/A88a-result.md` (Gemini) and
`/Users/cidy02/kudos-agent-ios/docs/android-port/briefs/A88a-cli-result.md` (Claude-CLI).

1. `queuetags` (the queue's tag manager, `library/QueueTags.kt` `QueueTagManager`/`TagRows`/`BoxMenuRow`):
   the tag rows have almost no vertical padding (iOS rows are full list rows), the two footnotes ("Unused
   tags stay here…", "A tag you use here…") start at the screen edge instead of the page's gutter, and
   the Add row is an outlined text field inside the card where iOS has a plain "+ New tag … Add" row
   (Android already draws that style in Add to Queue's new-queue row, `works/detail/WorkDetailForms.kt`).
2. `fandomworks` (a fandom's works, `browse/FandomWorksScreen.kt`): iOS shows the page's fandom as a
   filter chip ("Doctor Who") and counts it ("1 FILTERS"); Android shows no chip and "0 FILTERS". Match.
3. `newcollection` at font scale 2.0: the sheet title is cut to "New collect…" (`library/CollectionEditorSheet.kt`
   header row). iOS shows it whole. Let it wrap or shrink to fit, keeping Cancel and Done reachable.
4. Colour swatches (New Queue, Edit Queue, a collection's details, New Collection): iOS draws each swatch
   in the theme's variant of its hue (darker in Dark and OLED, paler in Light and Sepia: find iOS's swatch
   colour code, e.g. `SubjectPalette` / the swatch grid in `NewReadingQueueSheet.swift` / `Collections.swift`);
   Android draws the same mid tones in every theme. Use the same per-theme rule.
5. `formattingtray` (`comments/CommentMarkup.kt` formatting sheet): iOS's tray has a Done; Android's has a
   title only. Add Done in the header as the app's other sheets do.
6. `chapterpicker` (comments, browse by chapter): Android draws each chapter as its own card; iOS groups
   them in one card with separators. Match.
7. `pagejump` (`ui/components/KudosPaginationBar.kt` `PageJumpSheet`): the Nearby tiles use
   `MaterialTheme.colorScheme.primaryContainer`/`surfaceVariant`, which the Kudos theme never sets, so the
   selected tile is Material's default purple. Use the Kudos palette (`LocalKudosTokens`, the scope
   palette's accent and label colours), as iOS's `tileBackground` does.
8. Browse works pages' wash (`fandomworks`, `tagworks`): Android's is green where the iPhone's is peach
   for the same fandom. Find how each app picks the page's palette (the hue's input) and match iOS's.
9. `pronunciations` empty state: iOS's card has a speech-bubble "A" icon above "No corrections yet"; add it.
10. `collectionreorder`: Android has ⌃/⌄ buttons where iOS has drag handles. If DECISIONS.md does not keep
    the buttons as Android's, use drag handles with the existing accessibility move actions, as 3gx did for
    the series reorder (`writing/WritingSeriesScreen.kt`).

Tests (Robolectric/JVM, as the suite's others; avoid dialog windows under Robolectric, test the content
composable as 3gy did) for every behaviour change, each failing with its change reverted.
