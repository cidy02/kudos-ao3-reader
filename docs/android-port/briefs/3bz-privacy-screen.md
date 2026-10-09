# Brief 3bz: the Privacy screen as iOS has it

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
questions", and keep going to the end. Write `docs/android-port/briefs/3bz-result.md` as you go.

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
- `audits/R6-result.md`, section "Read Aloud downloads on Privacy" (it lists Android's screen
  as it stands, row by row) and `audits/R1-result.md`. Guides to where to look, not
  specifications: read the Swift yourself.
- `briefs/3bq-result.md` with its landing note, and how `settings/PrivacyDataScreen.kt`,
  `works/WorkRepository.kt` (`observeHistoryOnlyWorks`, `observePositionedWorks`,
  `observeFreeableCopies`) and `settings/SettingsChrome.kt` are built today.
- `docs/DATA_AND_PERSISTENCE_INVARIANTS.md`: nothing in this brief may delete or change the
  reader's data except the Clear actions that already exist.

## What is wrong

`settings/PrivacyDataScreen.kt` shows figures that are not measured: "Reading positions 0",
"Local collections 0", "Saved searches 0", "Caches Unknown" are written into the code,
whatever the device holds, while the row below them says "Clear reading positions · N
works". iOS's `Features/Account/PrivacyDataView.swift` measures what it shows, and has two
sections Android lacks.

## Build

Start the result with what iOS has, read from the code: the header; **every section in
order** ("Stored on this device", "Clear", "AO3 session", "Read Aloud downloads") with every
row, its label, how its value is computed and worded (the byte formatter, the count wording,
which rows appear only when their figure is not zero), every footnote word for word, and
every confirmation with its title, message and buttons. For "Stored on this device", name
the function that measures each figure and exactly which files or records it counts.

Then make Android's screen the same.

- **Stored on this device: measured, never written in.** Each row iOS has, with its figure
  measured on this device the way iOS measures it (the same files and records; Android's
  own storage layout, named in the result: where reading copies, kept originals, imported
  fonts, the draft recovery store and the caches live). Measuring happens off the main
  thread, once when the screen opens and again after a Clear action; a row shows nothing
  misleading while it waits (say what iOS shows then, and do the same). A figure Android
  cannot measure is left out, with the reason in the result, never shown as "0" or
  "Unknown".
- **Clear**, under its own header as on iOS: the existing actions, their existing
  confirmations and their existing effects, unchanged. Check each against iOS's (label,
  value wording, the confirmation's words) and list any difference; change words only.
- **AO3 session**: iOS's rows in each state (signed in, not signed in), its destructive
  "Remove AO3 session" with iOS's confirmation, and its footnote, including the session
  notice iOS appends. Removing the session is the app's existing sign-out
  (`AO3AuthRepository.logout`), nothing new, and nothing is sent to AO3 that the existing
  sign-out does not send (say what it sends).
- **Read Aloud downloads**: iOS's two paragraphs, word for word, where iOS puts them.
- Android's opening card ("No ads or tracking, and no separate Kudos account") is not on
  iOS in that form: say what iOS has in its place and do that.

## How it must be drawn

With the parts the screen already uses (`SubjectHeaderBlock`, `SectionRuleHeader`,
`SubjectFormRow`, `subjectPanel`, the destructive row style used elsewhere in `settings/`).
Layout, content and words are iOS's. Tokens only. Light, Dark, Sepia and OLED; every new
text with a line height; nothing clipped at `isAccessibilityFontScale()`.

## Demo and tests

- Demo: `nav:` route to the screen (say it); the demo library must give every measured row
  a figure that is not zero, so say which demo data gives each.
- Tests, none reaching the network: each measured figure against a small set of real files
  and rows in a temporary folder and an in-memory database (not zero, and changing when a
  file is added); the rows that hide at zero; each section's rows and words in each sign-in
  state; "Remove AO3 session" calling sign-out only after its confirmation; the Clear
  actions' effects unchanged (the existing tests still pass); nothing measured on the main
  thread.
