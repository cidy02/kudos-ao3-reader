# Brief 3gx (Android): the second half's Android differences, and your own A84a findings

**Write code in this worktree only (`/Users/cidy02/kudos-agent-codex`, branch
`android/agent-codex-3gx`). Do not commit, push, switch branches, sign in, contact
archiveofourown.org, or run Gradle (Claude builds and tests).** Do not edit `TASKS.md`. Create
`docs/android-port/briefs/3gx-result.md` FIRST; for each item give `path:line`, what changed, and
for each test what it does with the change reverted. iOS is the reference
(`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`); Android keeps its Material chrome and what
DECISIONS.md says it keeps. If an item is wrong on reading the code, say so and skip it. If an item
needs an owner decision (it changes what a figure means, removes a feature, or adds a new one),
do not change it: list it under "Owner questions" with the choice and your recommendation.

Sources, in `docs/android-port/audits/`: `A82b-result.md` and `A82b2-result.md` (two independent
Gemini reviews of the second 35 screenshots; tiles iPhone-above-Android at
`/Users/cidy02/kudos-tools/pairs/tiles-a82/<name>.png`), `A84b-result.md` (a Claude code comparison
of the same 35) and your own `A84a-result.md` (the first 35).

Do the Android side of:
1. **A84b's P2, `seriesdetail`:** the series card never shows "Restricted" and names only the first
   work's first fandom (`app/SeriesWorksScreen.kt:236-251`); iOS uses the summary's own flag and
   fandoms (`Features/Authors/AO3SeriesDetailView.swift:55-58`). With it, A82b's series-card
   differences: the bookmark count, the updated date, the Works header figure, the card's layout.
2. A82b/A82b2's other Android differences: `seriesreorder` (drag handles; Draft placement),
   `chsettingsedit` (Android's extra "Assignments sent" row — check iOS; the "4 sign-ups"
   subtitle; the SIGN-UP INSTRUCTIONS header), `parentpicker` (the URL field clipped), `texteditor`
   (Android's extra large "Chapter text" title), `availability` (an extra SETTINGS kicker),
   `authorworksfilter` (the extra "Direction" label), `tagset` (the header wash colour),
   `tagseteditor` (labels and the Save tags button), `privacydata` (Android's extra "Imported fonts"
   row: keep it if DECISIONS.md records it, else report).
3. A84b's Android P3s (its per-screen notes say which side).
4. **Your own A84a P2s and P3s where Android is the side that differs from iOS.** Fix them; where iOS
   is the side that is missing something (for example "Save-failure feedback absent on iOS"), do
   not change Android, list them under "iOS side" so Claude can send them to the iOS lane.
   Pronunciation playback on Android's voice pack is decided (the page says corrections are not
   played yet): skip it.

Tests (Robolectric/JVM, as the suite's others) for every behaviour change, each failing with its
change reverted. Nothing else changes.

## Also: three 3gw items that failed Claude's gate (redo them)

Your 3gw delivery is on `android/agent-codex-3gw` (`fe5df768`). Ten of its 13 items landed; these
three were held back because their tests failed when run:
- **Items 2 and 3 (QueueTags.kt, QueuePageScreen.kt; `TagSheetParityTest`)**: running
  `TagSheetParityTest.editTagPutsMergeBeforeTheRemoveSection` alone **hangs and ends in
  OutOfMemoryError** (the test JVM's heap fills; with the edit dialog's new
  `Column(Modifier.verticalScroll(...))` removed it still hangs past 10 minutes). Find the loop
  (an endless recomposition, a reload that triggers itself, a test wait that can never end) and fix
  it in the app if it is the app. The other two tests in that class only failed after the OOM.
- **Item 7 (FandomListChrome.kt, FandomListScreen.kt; `FandomFilterSheetParityTest`)**:
  `showTagsStaysVisibleAtLargestTextAndAppliesTheChoices` fails at its second assertion: "Show 0
  tags is not displayed" after `performScrollTo()` on "Favourited only". A likely cause: the inner
  scroll's leftover drag reaches the ModalBottomSheet (nested scroll) and moves the sheet, taking the
  pinned button off screen. Also check your own A84a P2 #34 ("Dismiss applies unconfirmed edits"):
  3gw made dismiss call `onApply(draft)`; make dismiss do what iOS's sheet does.
Copy what you need from that branch; the lane has the other ten items.
