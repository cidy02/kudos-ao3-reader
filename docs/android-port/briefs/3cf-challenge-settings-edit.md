# Brief 3cf: Challenge Settings, the edit form and its Save

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
questions", and keep going to the end. Write `docs/android-port/briefs/3cf-result.md` as you go.

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
- `audits/R8-result.md`, its first section: an index of iOS's edit form by Gemini. **A guide
  to where to look, not a specification**: its line numbers are approximate and its request
  list is unchecked.
- iOS's code, line by line: `Features/Challenges/ChallengeSettingsEditView.swift`,
  `Features/Challenges/ChallengeSettingsEditSections.swift`, the model and form types they use,
  and the service that reads and saves the form (`Services/AO3ChallengeActions.swift` and what
  it calls).
- `briefs/3ba-result.md` **with its landing note**: the read-only Challenge Settings screen on
  Android (`account/AO3ChallengeSettingsScreen.kt`, `network/ao3/account/AO3ChallengeSettings.kt`)
  and owner question 16 (iOS walks sign-up pages without a cap; Android reads one page).
- `briefs/3at-result.md`, `briefs/3bl-result.md` and `briefs/3cb-result.md` with their landing
  notes: how an AO3 form is read as served, changed in memory, encoded and saved on Android
  (every control AO3 served goes back unless the reader changed it; one fresh token; one POST
  never retried; AO3's named error is a refusal, its notice or a redirect is done, any other
  2xx is `AO3CollectionFields.UNCONFIRMED`; after a POST the verdict comes from
  `movedOnAfterWrite`; busy flags cleared in `finally`).
- `docs/AO3_NETWORKING_POLICY.md`: say which rule allows each read and the write.

## What is missing

Android shows a challenge's settings and cannot change them. On iOS a moderator edits them in
`ChallengeSettingsEditView` and saves. This brief is that form and its one write, for both
kinds of challenge (a gift exchange and a prompt meme).

## Build

Start the result with what iOS has, read from the code: who is offered the edit form and from
where; **every request for one opening, in order, counted**; every section in order with its
header; every row with its label, how its value is worded, whether it can be changed and
when it cannot (quote each condition: prompts already posted, a reveal already happened, the
time zone unreadable); every footnote and warning, word for word; the top buttons in each
state; the discard confirmation; the "Save and Reveal" confirmation and exactly when it is
asked; the save request field for field (the address, the method override, every field name
and where its value comes from, what is sent for a field the moderator did not touch and for
one AO3 served that the app does not model); what counts as AO3's confirmation and what as a
refusal (quote the code); each message for each verdict; what the screen does after.

Then build it on Android.

- **Reads:** the same as iOS for one opening and no more, through the existing authenticated
  client. If iOS walks page after page of anything, Android reads the first page only (owner
  question 16) and the result says so.
- **The form is AO3's.** Every control the edit page served is kept and sent back as served
  unless the moderator changed it; nothing is invented, nothing dropped. Dates are sent in
  the form AO3 served them; where iOS refuses to edit a date (time zone unreadable, a reveal
  in the past) Android refuses too, with iOS's words.
- **Save** is one fresh read for the token only if iOS makes one (say which), and one POST,
  never retried. A second tap while it is out sends nothing. The screen changes only on AO3's
  confirmation; a refusal keeps what was typed and shows AO3's reason.
- **"Save and Reveal"** is asked exactly when iOS asks it, with iOS's words, and nothing is
  sent until it is confirmed.
- **Leaving with changes** asks as iOS asks.
- **Links iOS opens on AO3** (run matching, delete challenge) open the same address in the
  in-app browser. No new write beyond Save.
- Through the existing write path (`network/ao3/writes/AO3WriteRepository.kt`); no new HTTP
  code. The read-only screen gets iOS's way into the form, for the people iOS offers it to.

## How it must be drawn

As the read-only screen and the AO3 collection form (`account/`, brief 3at): the subject
header, form rows, text field rows, switches and pickers those screens already use;
`tokens.scopePalette`; the top row's buttons are the app's Material icon buttons. Tokens
only: no stock Material chips, cards, text-field decoration or default Material colours.
Light, Dark, Sepia and OLED; every new text with a line height; nothing clipped at
`isAccessibilityFontScale()`; long lists lazy; a pushed screen leaves `statusBars + 76dp`
above its header.

## Demo and tests

- The demo answers the edit pages and the save locally (`network/ao3/DemoNetwork.kt`, fixtures
  under `app/src/debug/assets/fixtures/`, original filler only), for Winter Exchange 2026 (a
  gift exchange) and Summer Prompt Meme: **one** demo answer per AO3 address, shared with any
  screen that already reads it. Save succeeds unless a field holds a value you choose for the
  purpose, which the local answer refuses with AO3's kind of message. Relaunching resets it.
  Say the routes and the taps.
- Tests, none reaching the network: the reads for one opening, counted, for each kind; the
  untouched form's body equal to the browser's own submission of the fixture, field for field;
  each kind of change (a text, a switch, a number, a date, a choice) changing exactly its
  fields; the body for each kind of challenge beside iOS's; one POST per Save and none on a
  second tap while it is out; each verdict (confirmed, refused with AO3's text, an
  unconfirmed 2xx, a failed read, signed out, the session changed after the POST) with iOS's
  words; "Save and Reveal" asked when iOS asks and nothing sent before it is confirmed; each
  field that cannot be changed refusing the change; nothing sent on opening. Compose tests
  here need a tall window for lazy lists, patient waits, and `@GraphicsMode(NATIVE)` when
  they ask about text; the repository takes `parseDispatcher = Dispatchers.Unconfined`.
