# Brief 3cc: a challenge's assignments, with the two maintainer writes

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
questions", and keep going to the end. Write `docs/android-port/briefs/3cc-result.md` as you go.

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
- `audits/R3-result.md`, **section 1** ("Assignments") and **section 5** items 4 to 6
  (`claimPinchHit`, `markAssignmentDefaulted`, `updateAssignments`): a thorough reading of iOS
  with lines, requests and words. **A guide to where to look, not a specification**: open the
  Swift files it names; where the reading and iOS's code disagree, iOS's code wins.
- `briefs/3cb-result.md` with its landing note: the sign-ups list landed on 2026-10-09 with an
  assignments parser of its own for the match join
  (`network/ao3/account/AO3ChallengeSignUps.kt`: `parseAssignments`, `AO3SignUpAssignment`),
  the rule for who may read what (an owner; a moderator; anyone else is refused before a
  request), and how its demo answers the three assignment lists. **Extend that parser and
  those demo pages; write no second one.**
- `briefs/3ba-result.md` and `briefs/3ay-result.md` with their landing notes (Challenge
  Settings, the collection items list, how a challenge write is built and tested here).
- `docs/AO3_NETWORKING_POLICY.md`: say which rule allows each read and each write.
- `OWNER-DECISIONS-ANDROID.md` question 16: until the owner answers, Android reads the first
  page of an assignment list and no more on opening. This screen may read a further page
  **when the reader asks for it** (a "load more" as iOS words it), never by itself.

## What is missing

iOS has `Features/Challenges/ChallengeAssignmentsView.swift`: a challenge's assignments for
its owner or moderator, in iOS's segments, with pinch hits, and two writes for a maintainer:
**claim a pinch hit** (`claimPinchHit`) and **report a default** (`markAssignmentDefaulted`).
On Android the "Assignments" and "Defaults and pinch hits" rows in
`account/AO3ChallengeSettingsScreen.kt` and the "Assignments" action in
`account/AO3CollectionDetailScreen.kt` open AO3's page in the in-app browser.

Leave out, and list in the result with what iOS does: the participant's own default
(`reportAssignmentDefault`, `withdrawSignUpAfterClose`), "Run matching" and "Send
assignments", and anything iOS itself opens on AO3.

## Build

Start the result with what iOS has, read from the code: who sees the screen and each control,
in which state of the challenge; the taps that lead there; **every request for one opening,
in order**, for whom each is made, how often, and what stops a repeat; each segment, section,
row, badge and value and how it is worded in each case (the due date and its badge included);
the bottom action bar, each candidate picker and each confirmation, word for word; both
writes with every field name and value, the headers, the referer, where the token comes
from, what counts as AO3's confirmation and what as a refusal (quote the Swift); what the
screen reads after a write; empty, loading, failure and signed-out states.

Then build it on Android.

- **The reads**: the same as iOS for one opening and no more, each counted in the result
  before anything else, with the rules above: first pages only on opening; nothing for a
  viewer AO3 would refuse (say how iOS decides, and decide before reading); a best-effort
  read (the works-due date) is remembered as attempted. One failing list leaves the others
  on screen, as iOS.
- **The two writes**: one fresh read of the page iOS reads for its token (say which), one
  POST, never retried; the screen changes only on AO3's confirmation and then reads what iOS
  reads; a refusal shows AO3's reason and changes nothing; an unconfirmed answer says so
  alone. While one is in flight the other controls are disabled, as iOS. Through
  `AO3WriteRepository` and the existing authenticated client.
- The three entrance rows open the new screen where iOS opens its screen; anything iOS still
  opens on AO3 stays in the browser.
- Routes: add them to every list their neighbours are in (`Routes.title`,
  `hasSubjectHeader`, `tabBarHiddenBases`), and to `app/AppNavHost.kt`.

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

- The demo answers every page and both writes locally (`network/ao3/DemoNetwork.kt`,
  fixtures under `app/src/debug/assets/fixtures/`, original filler only; **one** demo answer
  per AO3 address, shared with the sign-ups list that already reads three of them): Winter
  Exchange 2026 with assignments of each state iOS distinguishes, at least one open pinch hit
  and one claimed; a claim that succeeds and one AO3 refuses; a default that succeeds and one
  AO3 refuses. The demo signs in as **AO3_Reader**: any row that must be the viewer's own
  carries that name. Relaunching the demo resets it. Say the `nav:` routes and the taps, and
  which demo rows give each case. A route with an `&` in it is cut off by the device's shell:
  say the production taps that reach each case too.
- Tests, none reaching the network: the parsers on each fixture; the reads for one opening,
  counted, for an owner, a moderator and a viewer who is neither; one failing read leaving
  the rest intact; signed out reads nothing; each write's request field for field against
  iOS's, with exactly one token read and one POST; each verdict (confirmed, refused with
  AO3's text, an unconfirmed 2xx, a failed token read, signed out, a session that moves on
  before the POST and one that moves on after it) with iOS's words and the busy flag cleared;
  the other controls disabled while one is in flight; nothing sent on opening or refresh; the
  three entrance rows asking for this screen.
