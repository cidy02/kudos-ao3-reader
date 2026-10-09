# Brief 3ca: fifteen small differences in behaviour

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
questions", and keep going to the end. Write `docs/android-port/briefs/3ca-result.md` as you go.

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
- `audits/R5-result.md`: a reading that sorted 49 differences between the apps. This brief
  is its **S** rows (fifteen, numbered 6, 10, 12, 13, 14, 18, 19, 24, 32, 33, 34, 36, 37, 38
  and 47 in its table), each with the iOS code and the Android code quoted and a suggested
  smallest change. **A guide to where to look, not a specification**: open both files for
  every row; where the reading and iOS's code disagree, iOS's code wins.
- `audits/A14-result.md`, section 3, for how each row was first described.
- `docs/AO3_NETWORKING_POLICY.md`. **None of these rows may add a request**: each is about
  what a screen shows for a state it already reaches (an empty page, a 404, a signed-out
  reader, a restoring session, a page that failed to load) or about one control.

## The rows

For each of the fifteen, start its section of the result with iOS's code quoted
(`path:line`): the state, the words, the control, and what a tap does. Then make Android do
the same.

1. **Row 6**: a tag page that is empty because of the reader's filters says "No works with
   this tag match your filters." with "Clear Filters", not the sentence for a tag that has
   no works (`browse/TagWorksScreen.kt`). The fandom page too, if iOS has the same pair.
2. **Row 10**: the AO3 dashboard signed out (`account/AO3DashboardScreen.kt`).
3. **Row 12**: the session expiring while preferences are saved
   (`account/AO3PreferencesScreen.kt`).
4. **Rows 13 and 14**: Account while the session is being restored: iOS's header for that
   state and its spoken name (`account/AccountScreen.kt`).
5. **Rows 18 and 19, 32, 33 and 34**: an author or one's own profile that AO3 cannot find:
   iOS's titles and messages for each case and the header above them
   (`author/AuthorProfileScreen.kt`).
6. **Row 24**: a later page of an author's list that fails: iOS keeps what is loaded and
   offers "Try Loading More" in place (`author/AuthorProfileScreen.kt`).
7. **Row 36**: named subscriptions signed out (`account/AccountWorksListScreen.kt`).
8. **Rows 37 and 38**: the comment composer's heading control: iOS's levels and their
   spoken names (`comments/CommentMarkup.kt` and where it is drawn).
9. **Row 47**: an account list whose page has works but none pass the reader's filters
   (`account/AccountWorksListScreen.kt`).

If a row turns out to be the same on both apps already, say so with both `path:line` and
change nothing. If a row turns out to need a request, a new screen or a change across more
than two files, stop on that row, say why under "Open questions", and go on to the next.

## How it must be drawn

With the parts each screen already uses. Words are iOS's, exactly. Tokens only. Every new
text with a line height; nothing clipped at `isAccessibilityFontScale()`.

## Tests

One test per row, none reaching the network, that would fail if the row went back to what
it was: the state reached with a fake repository or client, then the words and the control
asserted, and for the rows with a button, what the button does. No request is added: for
each row assert the count of reads is what it was.
