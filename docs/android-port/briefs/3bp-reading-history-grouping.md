# Brief 3bp: Reading History groups its rows (Time, State, Fandom, Flat) and can undo "abandoned"

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; **don't edit `TASKS.md`**. Don't change the backup format or a Room schema. Your sandbox
can't run Gradle or Xcode. Claude builds, tests and commits afterwards, so make what you write
compile by reading the real symbols you use, and say which claims need a test run.

**Android only.** iOS is the reference: read it at `/Users/cidy02/kudos-ios-polish/`, change
nothing there. **When this brief and iOS's code disagree, iOS's code wins**; say so in the
result. Decide questions about demo fixtures, test data, file placement and naming yourself and
list them under "Decided without asking". Do not stop for a question: decide it the more
sparing way (fewer reads, nothing sent that iOS does not send), write it under "Open
questions", and keep going to the end. Write `docs/android-port/briefs/3bp-result.md` as you go.

**Standing rules from the owner and from earlier landings** (each cost a fix; follow them):
- A read AO3 will refuse is not made, and a "best-effort" read remembers that it was
  attempted, not only that it succeeded (owner, 2026-10-07).
- A screen reads what it draws from its collected state (`val state by x.collectAsState()`
  then `state.names`), never from a function that reads a flow's `.value`: the second does
  not redraw when the value changes (3bh).
- A screen that takes another's place inside one route gets the shell's top row back by
  itself; give it `ProvidePushedShellChrome` and nothing else.
- In tests: do not assert `hasVisualOverflow` on a short label (assert `!didOverflowHeight`
  and that the last line is not ellipsized); when several values share a panel, count the
  matches or match by the row; an API marked experimental needs its `@OptIn`; Compose tests
  need a tall window for lazy lists, patient waits and `@GraphicsMode(NATIVE)`.
- A brief's file name must not contain the word "prompt" (`.gitignore`).
- A list of rows is lazy, drawn with the form's own parts (`writingSuggestionPanel`, the
  form's failure and loading rows); no stock Material `Button`, progress ring colours or
  unstyled `Text` (3bm).
- A row with a long label shows a short value as its `trailing` content, not as `value`
  (3bm: the shared row gives a long label the width and the value one letter a line).

Read first: `briefs/3u-result.md` and its fixes' results **with their landing notes** (the
Library's section lists on Android: `library/LibraryScreen.kt`, `LibrarySectionKind.kt`,
`LibrarySectionQuickFilter.kt`, `LibraryQuery.kt`), and
`docs/DATA_AND_PERSISTENCE_INVARIANTS.md` (a change the backup carries bumps the row's
modified time).

## What is missing

Audit A8 (a string check) found that Android's Reading History is one flat list. iOS's is
artboards **1ah** and **1ai**: the same rows under a scope strip with four groupings, a tally
line that follows the grouping, an Abandoned group that is derived, and a button that undoes
it. The pieces on iOS: `Features/Library/LibraryHistoryGrouping.swift` (pure rules, with
`LibraryHistoryGroupingTests`), `Features/Library/LibrarySectionListView.swift`
(`showsGroupingStrip`, `historyGrouping`, `isAbandonedRow`, the muted kicker, `swipeableRow`),
`Features/Library/ReadingHistoryFactsStrip.swift` (`MoveBackToInProgressButton`),
`Services/ReadingLogService.swift` (`isAbandoned`, its threshold) and
`Services/WorkLifecycle.swift` (`keepInProgress`). Android already stores
`keepInProgressOverride` on `SavedWork` and carries it in backups; nothing sets or reads it.

## Build

Start the result with what iOS has, read from the code: the strip (its four titles, order,
default, where the choice is stored and that it is per device); for each grouping every
bucket title, the fixed order, the rule that puts a work in a bucket (quote the time buckets
and their boundaries, the five state buckets and why there are five, the fandom family rule
and its ranking) and what an empty bucket does; the tally line in each case, word for word;
what an Abandoned row looks like (the muted kicker, the cover hue) and exactly when a row is
abandoned (every condition and the threshold); the button, its words, what it writes and
what the row does afterwards; and which of this the other section kinds share (none, if so).

Then build it on Android for the History section only.

- The rules as **pure functions with iOS's tests ported by name** (`LibraryHistoryGroupingTests`
  and the `isAbandoned` cases), taking the clock and the calendar as arguments.
- The strip drawn with the app's own scope strip (see how Favorites' quick filters and the
  prompt meme's filter draw theirs); the buckets as lazy sections with the list's existing
  rows; the tally line where the list's subtitle is today.
- **"Move back to In progress"** sets `keepInProgressOverride` through the repository that
  owns `SavedWork` writes, in one transaction, bumping the modified time the merge uses (find
  how "Mark as Finished" does it and do the same). It reads and sends nothing.
- The chosen grouping is device-local in `SettingsRepository` (never in the backup), default
  as iOS.
- **No network at all**, no schema change, no backup key.
- Selection mode, swipe actions, the long-press menu and the toolbar keep working inside
  groups exactly as they do in the flat list today; say how you checked each.

## How it must be drawn

Layout, order and words are iOS's (1ah, 1ai). Tokens only; the list's palette as today.
Light, Dark, Sepia and OLED; every new text with a line height; nothing clipped at
`isAccessibilityFontScale()`; the list stays lazy.

## Demo and tests

- The demo library (`kudosDemoLibrary`) must show at least three time buckets, an Abandoned
  row and a "Read, not finished" row: extend the demo seed if it does not (say what you
  added), without changing what other screens' tests count.
- Tests: the ported rule tests; the tally line in each grouping; a state count of zero is
  left out; the button sets the override, bumps the modified time, and the row leaves
  Abandoned without a reload; the override survives an export and import (`BackupMappers`);
  the stored grouping is not in the backup; the other section kinds show no strip.

## Added 2026-10-08 (from the landings since this was written)

- A section header is drawn in capitals (`SectionRuleHeader`): a test that waits for a
  header's text must ask for "IN PROGRESS", not "In progress".
- Text actions and action rows use the palette's accent (`tokens.scopePalette.accent`;
  `SettingsActionRow` already does): the raw `tokens.accent` cannot be read in Dark.
- A `SubjectFormRow` given a `trailing` slot draws no `value`, even when the slot is empty:
  pass one or the other.
- A selection holds only rows on screen: when a strip, a chip or a filter hides a row, it
  leaves the selection (`LibrarySelection.visible`, already wired into the section lists;
  keep it working when rows are grouped).
- Do not write helper scripts or scratch files into the worktree.
