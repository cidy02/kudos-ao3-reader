# Brief 3cb: a challenge's sign-ups list, and withdrawing a sign-up

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
questions", and keep going to the end. Write `docs/android-port/briefs/3cb-result.md` as you go.

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
- `audits/R3-result.md`, **section 3** ("The Sign-Ups List for a Challenge, and Withdrawing or
  Deleting a Sign-Up") and **section 5.1** (`withdrawSignUp`): a thorough reading of iOS with
  lines, requests and words. **A guide to where to look, not a specification**: open the
  Swift files it names; where the reading and iOS's code disagree, iOS's code wins.
- `briefs/3bl-result.md`, `briefs/3ba-result.md` and `briefs/3ay-result.md` with their landing
  notes: the sign-up form, Challenge Settings and the collection items list as they stand on
  Android, how a challenge write is built, confirmed and tested here, and what was corrected
  on landing.
- `docs/AO3_NETWORKING_POLICY.md`: say which rule allows each read and the write.
- `OWNER-DECISIONS-ANDROID.md` question 16 (Challenge Settings reads the first assignments
  page only on Android until the owner answers): the same holds here.

## What is missing

1. **Withdrawing a sign-up.** iOS's `Features/Challenges/ChallengeSignUpView.swift` has a
   Withdraw section on an existing sign-up, a confirmation, and one write
   (`Services/AO3ChallengeActions.swift`, `withdrawSignUp(slug:signUpID:)`). Android's
   `account/AO3ChallengeSignUpScreen.kt` has none of it.
2. **The sign-ups list.** iOS's `Features/Challenges/ChallengeSignUpsView.swift`
   (`ChallengeSignUpsView` and `ChallengeSignUpDetailView`): a challenge's sign-ups for its
   owner or moderator, and one participant's sign-up read. On Android the "Sign-ups" rows in
   `account/AO3ChallengeSettingsScreen.kt` and `account/AO3CollectionDetailScreen.kt` open
   AO3's page in the in-app browser.

Leave out, and list in the result with what iOS does: the after-close withdrawal
(`withdrawSignUpAfterClose`, `reportAssignmentDefault`), everything about assignments beyond
what the list itself shows, and the prompt tags editor.

## Build

Start the result with what iOS has, read from the code and set out for both parts: who sees
each control and in which state of the challenge; the taps that lead to it; **every request
for one opening, in order**, for whom each is made, how often, and what stops a repeat; the
write, with every field name and value, the headers, the referer, what counts as AO3's
confirmation and what as a refusal (quote the Swift); every message word for word; what the
screen shows while it waits and after; what is never retried.

Then build both on Android.

- **Withdraw**: the section, the row, iOS's confirmation and words. One fresh read of the
  page iOS reads for its token (say which), one POST, never retried; on AO3's confirmation
  what iOS does (it leaves the screen and reports "Sign-up withdrawn."); a refusal keeps the
  form as it is with AO3's reason; an unconfirmed answer says so alone. Through
  `AO3WriteRepository` and the existing authenticated client, as `saveChallengeSignUp` does.
- **The list**: iOS's header, filters or segments, rows, values, empty, loading, failure and
  signed-out states, its "load more" as iOS words it, and the participant read. Rows open
  what iOS opens. **The reads**: the same as iOS for one opening and no more, each counted in
  the result before anything else. Where iOS walks page after page of assignments to join
  them to sign-ups, Android reads the first page of each only, shows what that gives, and
  puts the question in "Open questions" (question 16's rule). A read AO3 will refuse for this
  viewer (not an owner or moderator) is not made: say how iOS decides who may see the list,
  and do the same before reading.
- The two "Sign-ups" rows open the new list where iOS opens its list; anything iOS still
  opens on AO3 stays in the browser.
- Routes: add them to every list its neighbours are in (`Routes.title`, `hasSubjectHeader`,
  `tabBarHiddenBases`), and to `app/AppNavHost.kt`.

## How it must be drawn

As the challenge screens already on Android (`account/AO3ChallengeSettingsScreen.kt`,
`AO3CollectionItemsScreen.kt`, `AO3ChallengeSignUpScreen.kt`): the subject header, the
challenge sections and rows, the app's chips, `tokens.scopePalette`. Layout, content, order
and words are iOS's; the top row's buttons are the app's Material icon buttons. Tokens only:
no stock Material chips, cards, text-field decoration or default Material colours. Light,
Dark, Sepia and OLED; every new text with a line height; nothing clipped at
`isAccessibilityFontScale()`; a pushed screen leaves `statusBars + 76dp` above its header;
long lists lazy.

## Demo and tests

- The demo answers the list's pages and the withdraw locally (`network/ao3/DemoNetwork.kt`,
  fixtures under `app/src/debug/assets/fixtures/`, original filler only; **one** demo answer
  per AO3 address, shared with whatever screen already reads it): Winter Exchange 2026 with
  a few sign-ups of each state iOS distinguishes and a second page; a withdraw that succeeds
  and, for one sign-up you choose, one AO3 refuses. Relaunching the demo resets it. Say the
  `nav:` routes and the taps, and which demo rows give each case.
- Tests, none reaching the network: the parsers on each fixture; the reads for one opening,
  counted, for an owner, a moderator and a viewer who is neither; one failing read leaving
  the rest of the screen intact, as iOS; signed out reads nothing; the withdraw request field
  for field against iOS's, with exactly one token read and one POST; each verdict (confirmed,
  refused with AO3's text, an unconfirmed 2xx, a failed token read, signed out, a session
  that moves on before the POST and one that moves on after it) with iOS's words and the busy
  flag cleared; nothing sent on opening or refresh; the two entrance rows asking for this
  screen.
