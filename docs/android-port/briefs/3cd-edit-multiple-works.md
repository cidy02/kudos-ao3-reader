# Brief 3cd: Edit multiple works, with the own-works bulk bar and a posted work's way to its form

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
questions", and keep going to the end. Write `docs/android-port/briefs/3cd-result.md` as you go.

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

- **A write that has been sent** (rules of 2026-10-09, each from an audit): in
  `AO3WriteRepository`, `requireCollectionSession` is called only **before** the POST; after
  it, `movedOnAfterWrite(expectedGeneration, response)?.let { return it }` and nothing that
  throws. A state class shows the repository's verdict as it is, clears its busy flag on
  every path out while it is active (a `finally`), and never puts "was not withdrawn" in front
  of `AO3CollectionFields.UNCONFIRMED`. The token and `_method` go in the body always.
- In tests: work done in `withContext(Dispatchers.Default)` is off the test clock, so wait in
  real time on its effect; never wait for text that is already on screen before the action
  (wait on the thing the action changes); a screen that reads on another thread outlives the
  test, so do not close its database or client in `@After`.

Read first:
- `audits/R4-result.md`, both sections (Edit multiple works; a writer's own works list and
  its entrances to the work form) and `audits/R2-result.md`: readings of iOS with lines,
  requests and words. **A guide to where to look, not a specification**: open the Swift files
  they name; where a reading and iOS's code disagree, iOS's code wins.
- `briefs/3bt-result.md` (Edit tags), `briefs/3bo-result.md` (the work form's Save) and
  `briefs/3bx-result.md` (Post, Preview, Delete) **with their landing notes**: the work form
  on Android as it stands, how its writes are built, confirmed and tested, and what was
  corrected on landing. `briefs/3by-result.md` for the author's works list and its sort.
- `docs/AO3_NETWORKING_POLICY.md`: say which rule allows each read and each write.

## What is missing

1. **A posted work's way to its form.** iOS lets a writer reach the work form from an own
   work's row in their own works list (`Features/Authors/AuthorProfileView.swift` and the
   files R4 section 2 names). Read what iOS offers there (a swipe, a menu, which actions, for
   which rows) and what each opens. On Android an own posted work can be reached only through
   Drafts or a debug route.
2. **Edit multiple works.** iOS's own-works list has a Select mode with a bulk bar
   (`Features/Authors/OwnWorksBulkBar.swift`) and `Features/Writing/EditMultipleWorksView.swift`
   with its writes in `Services/AO3WorkActions.swift` (`loadBulkEditForm`, `bulkEditWorks`,
   and the bulk Delete, `deleteWorks`). Android has none of it. The select mode the author's
   works list already has (for reading actions) is where this goes: do not make a second one.

## Build

Start the result with what iOS has, read from the code and set out for both parts: who sees
each control (own works only: say how iOS decides "own", and that it never guesses from a
displayed pseud); the taps; **every request, in order**, with what stops a repeat; the bulk
bar's actions and which are enabled for which selection; the bulk form's header, sections,
rows, choices (from the form AO3 served: never a list written into the app), footnotes and
confirmations, word for word; each write with every field name and value, the headers, the
referer, where the token comes from, and what counts as AO3's confirmation and what as a
refusal (quote the Swift); what is read after a write; what is never retried.

Then build both on Android.

- **The entrances**: what iOS offers on an own work's row, opening the existing work form
  (`writing/WritingWorkFormScreen.kt`) or Edit tags as iOS does. No new read: the row already
  knows the work's id. Not offered for a work that is not the signed-in writer's own.
- **Edit multiple works**: the bulk bar in the existing Select mode, for own works only;
  iOS's form and confirmations; each write one fresh read of the page iOS reads for its form
  and token, one POST, never retried, the list changed only on AO3's confirmation and then
  read as iOS reads it; a refusal keeps the selection and the form with AO3's reason; an
  unconfirmed answer says so alone. **Bulk Delete** only after iOS's confirmation naming the
  count and titles, exactly as iOS words it. Nothing here touches the reader's library copies
  (say what iOS does, and do the same).
- Through `AO3WriteRepository` and the existing authenticated client; no new HTTP code.
- Routes, if any are new: in every list their neighbours are in, and in `app/AppNavHost.kt`.

## How it must be drawn

As the writing screens already on Android (`writing/WritingWorkFormScreen.kt`,
`WritingEditTagsScreen.kt`) and the author's works list (`author/AuthorProfileScreen.kt`): the
subject header, the form's sections, rows and panels, the list's existing selection bar,
`tokens.scopePalette`. Layout, content, order
and words are iOS's; the top row's buttons are the app's Material icon buttons. Tokens only:
no stock Material chips, cards, text-field decoration or default Material colours. Light,
Dark, Sepia and OLED; every new text with a line height; nothing clipped at
`isAccessibilityFontScale()`; a pushed screen leaves `statusBars + 76dp` above its header;
long lists lazy.

## Demo and tests

- The demo answers every page and write locally (`network/ao3/DemoNetwork.kt`; the shared
  mutable answers for the demo's works are `DemoWorkSaves` there: extend them, and keep
  **one** answer per AO3 address): the demo writer **AO3_Reader** with at least three own
  posted works in their own works list, an edit that succeeds for all, one AO3 refuses for a
  title you choose, a bulk delete that succeeds and one AO3 refuses. Relaunching the demo
  resets it. Say the `nav:` routes, the production taps, and which demo rows give each case.
- Tests, none reaching the network: each request field for field against iOS's (a recording
  client), for one work and for several, with exactly one preparation read and one POST per
  write; each verdict (confirmed, refused with AO3's text, an unconfirmed 2xx, a failed
  preparation read, signed out, a session that moves on before the POST and one that moves on
  after it) with iOS's words and every busy flag cleared; the bulk bar and the row actions
  absent for someone else's works and for a signed-out reader; the selection kept after a
  refusal and cleared after a confirmation as iOS does; nothing sent on opening, selecting or
  cancelling; the reader's library untouched by a bulk delete.
