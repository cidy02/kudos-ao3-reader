# Brief 3bj: the work form's association pickers

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
questions", and keep going to the end. Write `docs/android-port/briefs/3bj-result.md` as you go.

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

Read first: `briefs/3bf-result.md` and `briefs/3bh-result.md` **with their landing notes** (the
work form's screen and its tags editor, in `writing/`; the Series, Add to collections, Gift
recipients, Co-creators and Inspired by rows show a value and open nothing), `briefs/3bb-result.md`
with its landing note (how the form encodes these fields, and iOS's extra read of the account's
collections that 3bb left to this brief), and `docs/AO3_NETWORKING_POLICY.md`.

## What is missing

Five rows of the work form open nothing. iOS opens the screens in
`Features/Writing/WorkAssociationPickers.swift`. This brief is those five, changing the form in
memory. It sends nothing.

## Build

Start the result with what iOS has, read from the code, for each of the five: the header and
its words; every row, field, placeholder and footnote, word for word; what can be chosen,
typed, removed and reordered; how the row on the form words its value afterwards; the limits
AO3 puts on it and how iOS reports them; and **every request**: which address, when, for
whom, how long iOS waits after a keystroke, what cancels one, what happens when one fails.
Then say, for each, exactly which fields of the form change and what the encoder sends after.

Then build them on Android and make the five rows open them.

- **Every change goes into the `AO3WorkForm`** so that `form.parameters(submit)` is what iOS
  would send after the same taps (3bb's encoder already has iOS's rules for series,
  collections, gifts, co-creators and the inspired-by work; if a rule is missing there, add it
  there with iOS's test, not in the screen).
- **The reads.** Count them in the result before anything else. iOS reads the first page of
  the account's own collections when the form loads, to offer them in the collections picker.
  On Android that read is made when the collections picker is first opened, once per form,
  not when the form loads: a writer who never opens the picker costs AO3 nothing. Any
  name suggestions go through the app's existing autocomplete path with iOS's wait, one read
  per settled term, none on opening. Nothing is read ahead. No writes.
- Where iOS draws something whose only purpose is a write not built yet (removing the work
  from a series on AO3, for one), show the value without the control and list it.

## How it must be drawn

Layout, content, order and words are iOS's. The work form's own components, the tags editor's
field and chips, `tokens.scopePalette`. The top row's buttons are the app's Material icon
buttons. Tokens only: no stock Material chips, cards, text-field decoration or default
Material colours. Light, Dark, Sepia and OLED; every new text with a line height; nothing
clipped at `isAccessibilityFontScale()`; `statusBars + 76dp` above each header; long lists
lazy; fields and suggestions stay above the keyboard.

## Demo and tests

- The demo answers what the pickers read locally (one answer per address, shared with
  whatever already reads it): the account's collections page, and each suggestion address
  with a term that returns several names, one that returns none and one that fails. Reach
  them from the three work form routes.
- Tests, none reaching the network: for each picker, each kind of change against the
  encoder's output for all three forms, with every other field of the round trip untouched;
  the collections read made once, on first opening the picker, and not on loading the form;
  one read per settled term (a virtual clock); a failed read leaving the picker usable;
  nothing sent (a client whose POST throws); the rows that still wait (Chapters, Add
  chapter, Edit tags) open nothing.
