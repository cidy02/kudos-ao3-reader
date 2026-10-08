# Brief 3bw: the series form (a series the writer owns: read, edit, Save; its works in order)

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
questions", and keep going to the end. Write `docs/android-port/briefs/3bw-result.md` as you go.

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

Read first: `briefs/3bj-result.md` **with its landing note** (the work form's Series picker,
which names a series and cannot change one), `briefs/3l-result.md` and the series page's
result (how an author's series is listed and opened on Android), `briefs/3bg-result.md` (how
a write is built and tested), audit `A4-result.md` **finding A4-2 and its triage** (iOS's
series save did not send the co-creator field until T-362), and
`docs/AO3_NETWORKING_POLICY.md`.

## What is missing

A writer cannot change a series on Android. iOS has `Features/Writing/SeriesEditView.swift`
and `SeriesReorderDestination.swift`, the model `AO3SeriesForm` (`Models/AO3WritingModels.swift`),
its parser (`parseSeriesForm`, `Services/AO3Client+Works.swift`) and its writes
(`Services/AO3WorkActions.swift`: the series save, the reorder of its works, delete if iOS
has it).

## Build

Start the result with what iOS has, read from the code: every way the screen is reached
("Edit series" on a series page, the author's series list, a new series: which of these iOS
does in the app and which it sends to AO3's page); the reads on opening, counted; every
section and row with its words; the creators section (pseuds, the co-creator byline); the
works list and how reordering works (its own screen, its own request); the Save button;
**each request** (address, method, every field, the method override, the token, the
referer); what counts as confirmation, refusal and neither, quoted; every message; Delete
series if present, with its confirmation.

Then build it on Android: the form as data (parser, encoder, one-read repository, fixtures,
tests), the screen, Save, and the reorder, each finished before the next. Whatever iOS opens
on AO3's own page stays in the in-app browser.

- **One POST per tap, never retried.** Through the app's existing authenticated client and
  write path (see `saveTagSetFields` in `network/ao3/writes/AO3WriteRepository.kt`); no new
  HTTP code. The captured form action is checked with `AO3RedirectCookieRelay.isTrustedUrl`.
- **Verdicts with iOS's words.** AO3's validation list is `div#error` holding a `ul`:
  `AO3WriteFormParser.writeErrorMessage` reads it; use it. A page with no notice and no
  error is "didn't confirm" (`AO3CollectionFields.UNCONFIRMED`), never success. The screen
  changes only on AO3's confirmation; nothing typed is lost on any failure.
- **Replay boundary**, as the work form (3bb): keep every control AO3 served; send iOS's
  modeled fields iOS's way and replay the rest as a browser would. **A field AO3 did not
  serve is never sent** (audit A4-1: the work form's chapter text).
- The co-creator byline is sent when it is not empty (`series[author_attributes][byline]`).

## How it must be drawn

As the work form. Tokens only; lists lazy. Light, Dark, Sepia and OLED; nothing clipped at
`isAccessibilityFontScale()`.

## Demo and tests

- The demo answers the reads and writes locally for one series of the demo account (original
  filler; reuse the series the demo's author page already lists): a save that succeeds, one
  AO3 refuses with a reason, a reorder. Say the routes and the taps.
- Tests, none reaching the network: the parser on the fixture; an untouched form against
  what a browser would send; each change against iOS's encoder, the byline included; the
  reads for one opening, counted; one POST per save and per reorder; each verdict with iOS's
  words; the form unchanged after every failure.
