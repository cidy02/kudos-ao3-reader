# Brief 3by: the Account shortcuts editor, and an author's works sorted and filtered

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
questions", and keep going to the end. Write `docs/android-port/briefs/3by-result.md` as you go.

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
- A toolbar button handed to the shell must be absent **as a value** until it applies
  (`trailingContent = if (form == null) null else { … }`). Content that tests for the form
  inside itself stays empty when the form arrives after the screen: 3bo's Save was invisible
  until this was fixed on landing.
- In tests: a `waitUntil` on something that is not on screen (a request count) needs
  `compose.waitForIdle()` first; a test function's body returns `Unit`
  (`runBlocking<Unit> { … }`); never `runBlocking` in an `@After` on something that needs
  the main thread (it hung the whole suite); the theme is `KudosThemeMode.Oled`, not `OLED`;
  when two states share a title, wait for the sentence that differs.
- No line heights or other changes to shared components (`ui/subject/`, `settings/`) unless
  the brief names them.
- A reload or a refresh never clears what the writer is in the middle of (audit A22: a
  reload cleared a reply's target and the text went out as a new comment).
- Demo data must really produce what the brief asks to be seen: say which demo rows give
  each case, and check the rule that selects them against those rows.

Read first:
- `audits/R1-result.md`, sections "Account shortcut editor" and "Works sort and completion on
  an author": a first reading of iOS with file and line pointers. **A guide to where to
  look, not a specification**: read the Swift yourself.
- `briefs/3az-result.md` and `briefs/3bq-result.md` with their landing notes (how a pushed
  account screen and a device-local layout choice are built and tested here: the choice is
  kept in `SettingsRepository` under iOS's own key, outside `KudosSettings` and the backup).
- `docs/AO3_NETWORKING_POLICY.md`: say which rule allows the one read part 2 changes.

Two small features Android lacks. Neither writes to AO3.

## Part 1: the Account shortcuts editor

iOS: `Features/Account/AccountShortcuts.swift` (`AccountShortcutsEditor`,
`AccountShortcutStore`) and the "SHORTCUTS" section of `Features/Account/AccountView.swift`.
On Android the grid is fixed and its header's "See all" does nothing
(`account/AccountScreen.kt`, `onSeeAll = { /* TODO implement shortcut editor */ }`).

Start the result with what iOS has, read from the code: every shortcut that can be chosen,
its title, symbol and destination; the default set and order; how the choice is stored (the
key, the encoding, what an unknown or missing value means) and that it is not in the backup;
the editor's title, both section headers, every row with its accessibility label, the
footer and when it shows, "Reset to Default" and when it is disabled, Done; reordering, if
iOS has it; and what the Account screen shows for an empty choice.

Then build it: the editor as a pushed screen reached from the header's "See all", the store
under iOS's key in `SettingsRepository` (device-local, as 3bq's Favorites choices), and the
Account grid drawn from the chosen shortcuts in their order. A destination Android does not
have yet stays out of the list and is named in the result.

## Part 2: an author's works, sorted and filtered

iOS: the works sort sheet on an author's profile (`Features/Search/AO3FilterPanel.swift`,
`WorksSortPresentation`; `Models/AO3WorksSort.swift`; `applyWorksSort` and the request in
`Services/AO3AuthorProfileService.swift`). On Android the author's Works tab always asks
for AO3's default order (`author/AuthorProfileScreen.kt`; `AO3AuthorUrls.userWorksUrl` can
already carry a sort).

Start the result with what iOS has: where the control sits and what it shows for each
choice; every sort and its direction, the completion choices, and the default; the sheet's
words, including its footer ("AO3 applies this choice to all matching works, not only the
page you can see."); what Apply, Reset and a dismiss each do (**a dismiss applies nothing**:
audit A20); the request it makes, with every query name and value, and what is left out when
a choice is AO3's default; that it goes back to page 1; and which of the profile's lists
have it (works only, or series and bookmarks too).

Then build it. **One read per Apply, the page asked for, nothing else**; the choice lives
for the screen (or as long as iOS keeps it: say which, and do the same); a late answer for
an older choice is dropped (the profile already guards its loads: use that guard).

## How it must be drawn

With the parts the Account and author screens already use (`tokens.scopePalette`, the
subject header, section headers, form rows, panels, the app's chips and its sheets). Layout,
content and words are iOS's; top-row buttons are the app's Material icon buttons. Tokens
only. Light, Dark, Sepia and OLED; every new text with a line height; nothing clipped at
`isAccessibilityFontScale()`; a pushed screen leaves `statusBars + 76dp` above its header.

## Demo and tests

- Demo: say the route and the taps for each part. The demo's author pages must answer the
  sorted request locally (`network/ao3/DemoNetwork.kt`; one answer per AO3 address, shared
  with what already reads it): a different order must be visibly different.
- Tests, none reaching the network: the store's defaults, round trip, unknown and missing
  values, and that a backup restore leaves it alone; the grid following the choice; the
  editor's add, remove, reset and its footer; the author request for every sort, direction
  and completion choice against iOS's query, with defaults left out; one read per Apply and
  none on a dismiss; page 1 after Apply; a late answer dropped.
