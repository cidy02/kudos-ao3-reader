# Brief 3bt: the work's Edit tags screen (a posted work's tags, their own page and Save)

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
questions", and keep going to the end. Write `docs/android-port/briefs/3bt-result.md` as you go.

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

Read first: `briefs/3bh-result.md` **with its landing note** (the tags editor in `writing/`,
already built: reuse it, write no second one), `briefs/3bf-result.md` (the work form's
screen: its "Edit tags" row shows a value and opens nothing), `briefs/3bb-result.md` (the
parser and encoder already know AO3's `edit_tags` form: `AO3WorkFormKind.EditTags`),
`briefs/3bg-result.md` (how a write is built and tested here), audits `A4-result.md` (its
triage) and `docs/AO3_NETWORKING_POLICY.md`.

## What is missing

On a posted work, "Edit tags" opens nothing. iOS has `Features/Writing/EditTagsView.swift`
with `AO3WorkActions.editTags` / `loadEditTagsForm` (`Services/AO3WorkActions.swift`): the
tags of a posted work on their own page, so a tag fix never opens the text.

## Build

Start the result by reading iOS's screen and its write from the code, line by line: who sees
the row; the one read on opening (address, for whom, what is shown while it loads and when
it fails); every section and row with its words; which tag kinds can be changed and how (the
pickers and the editor each opens); what is required; the Save button and when it is
disabled; **the request** (address, method, every field and where each value comes from,
what is sent for an emptied kind, the referer, which token); what counts as confirmation, as
refusal and as neither, quoted; every message; what the work form under it does after a
save (iOS re-reads the edit form and replaces only the tag fields: count that read).

Then build it on Android: the screen, the read, the Save, and the work form's "Edit tags"
row opening it.

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
- **After a confirmed save** the work form under this screen takes the new tags the way
  iOS's does. Count the reads this costs and make none iOS does not make.

## How it must be drawn

As the work form and its tags editor. Tokens only; lists lazy; a row with a long label shows
a short value as `trailing` content. Light, Dark, Sepia and OLED; nothing clipped at
`isAccessibilityFontScale()`.

## Demo and tests

- The demo answers the read and the POST locally for the posted work 995006
  (`network/ao3/DemoNetwork.kt`, original filler): a save that succeeds and one AO3 refuses
  with a reason (say the trigger). Say the route and the taps.
- Tests, none reaching the network: the parser on the fixture; an untouched form against what
  a browser would send; each kind of change against iOS's encoder; one read on opening, one
  POST per save, none on opening; each verdict with iOS's words; the form unchanged after
  every failure; the work form's tags after a confirmed save; a second tap in flight sends
  nothing.
