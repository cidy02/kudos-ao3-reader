# 3hi: Reading Insights' cards and figures, as iOS's (A102, main screens)

Same setup as 3he–3hh; their briefs are in this worktree's `docs/android-port/briefs/`.
- **Where:** `/Users/cidy02/kudos-agent-codex`, branch `android/agent-codex-3he`, at 3hh `dbd42c89` or later.
- **Rules:** no Gradle, no sign-in or AO3 traffic, no schema or backup changes, never revert anyone's work.
- **Committing:** if the git index can't be written, leave the edits uncommitted and say so.
- **Report:** write `docs/android-port/audits/3hi-result.md`.

## 1. Insights' blocks are tinted subject cards
iOS draws each of Reading Insights' six blocks with `.subjectCard(palette: palette)`
(`Features/Library/ReadingInsightsView.swift:186, 280, 341, 421, 448, 484`). That modifier is `SubjectCardBackground`
in `UIComponents/SubjectSurface.swift` (~400–418): the theme's card surface, the palette's `rowWash` laid over it,
and a 0.5 pt `rowBorder` stroke, at the row radius.

Android draws the same blocks with the neutral `subjectPanel()` (`library/ReadingStatisticsScreen.kt:373, 500, 533,
553, 587, 612`). Measured in the middle of "Your library":

| Theme | iPhone | Android |
|---|---|---|
| Dark | (60,27,31) | (33,33,35) |
| Light | (240,218,218) | (230,230,234) |
| Sepia | (237,221,194) | (222,209,180) |

Add one shared modifier in `ui/subject/`, e.g. `Modifier.subjectCard(palette, cornerRadius = SubjectMetrics.rowRadius)`.
It is iOS's: card surface, `palette.rowWash` over it, `palette.rowBorder` at 0.5 dp. The palette already has
`rowWash` and `rowBorder` (`ui/subject/SubjectPalette.kt:135, 163`), and `ui/subject/WorkLibraryComponents.kt:167`
draws a similar row background; reuse what fits rather than duplicating it.

Use it for the six Insights blocks, with the page palette (the same palette the page's wash and accents use).
Match which block is which by reading both files side by side. The period capsule (iOS `:209`, glass) and the
fandom bars stay as they are.

Then check iOS's other `.subjectCard(` sites against Android, and use the new modifier where Android draws a neutral
panel instead:
- `Features/Account/AO3CollectionDetailView.swift`
- `AO3CollectionItemsView.swift`
- `AO3CollectionsList.swift`
- `Features/Bookmarks/AO3BookmarksWorksBrowser.swift`
- `AO3MarkedForLaterWorksBrowser.swift`
- `Features/Challenges/ChallengeAssignmentsView.swift`
- `Features/Library/FavoriteAffinityRow.swift`
- `RecentlyDeletedView.swift`

Most already look tinted on Android. List what you found for each.

## 2. "words read" uses iOS's compact figures
iOS writes `stats.wordsRead.formatted(.number.notation(.compactName))` (`ReadingInsightsView.swift:505`): 202,6xx
words → "203K". Android's `formatCompactNumber` (`library/ReadingStatisticsScreen.kt:768`, used at `:576`) always
keeps a decimal: "202.6K".

The shared `Int.compactCount()` in `ui/subject/SubjectComponents.kt` (~105–131) already reproduces Foundation's
compact notation, so use it. Delete `formatCompactNumber` if nothing else uses it; check its tests and update them.

## Tests (they will be run; the last batch's were not, and five failed)
Claude-Code's gate found five of 3he–3hg's tests broken because they were never compiled or run. Avoid these:
- Espresso isn't a test dependency here. To draw a dialog's pixels, use Robolectric's
  `ShadowDialog.getLatestDialog()` and its window's Compose root, as `Parity3hfSheetsTest.dialogComposeRoot()` does.
- In the unmerged tree, a clickable row's own node holds no text. Match its children instead
  (`hasParent(hasAnyDescendant(hasText(...)))`).
- A dialog with a text field never idles under Robolectric. Host the content inline.
- Compile-check by reading only what exists in this repo's test dependencies (`android/app/build.gradle*`).

- A rendered check that an Insights block's fill is the tinted card in Dark and Light. It should match the palette's
  card surface plus row wash, not the glass panel, and fail with `subjectPanel()` restored.
- `compactCount` gives "203K" for 202,600 on the words-read path.
