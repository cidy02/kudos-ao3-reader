# Brief 3bu: the chapter form (a chapter of a posted work or a draft: read, edit in memory, Save and Post)

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
questions", and keep going to the end. Write `docs/android-port/briefs/3bu-result.md` as you go.

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

Read first: `briefs/3bm-result.md` **with its landing note** (the work form's Chapters list:
a row opens nothing yet, and "Add chapter" opens nothing), `briefs/3bb-result.md` and
`briefs/3bf-result.md` (the work form as data and as a screen: the same shapes apply),
`briefs/3bd-result.md` (the text editor, with the recovery key it takes), `briefs/3bg-result.md`
(how a write is built and tested), audit `A4-result.md` with its triage, and
`docs/AO3_NETWORKING_POLICY.md`.

## What is missing

Android can list a work's chapters and cannot open one. iOS has
`Features/Writing/AddChapterView.swift` (a new chapter and an existing one), its model
`AO3ChapterForm` (`Models/AO3WritingModels.swift`), its parser (`Services/AO3Client+Works.swift`)
and its writes (`AO3WorkActions.createChapter`, `updateChapter`, the chapter's delete, and
`updateWorkTotals`, in `Services/AO3WorkActions.swift`).

## Build

Start the result with what iOS has, read from the code: how the screen is reached (the
Chapters list's rows, "Add chapter") and what it is given; the one read on opening for a new
chapter and for an existing one; every section and row, its words, what it opens (the text
editor's account, target and field for each text: they are the recovery key); the position
and "this chapter is the last" controls and what each changes; co-creators if shown; the
publication date; every button in each state (a new chapter, a draft chapter, a posted
chapter) and **the request each sends** (address, method, every field, which submit button
name, the referer, the token), including the second request iOS makes for the work's total
(`updateWorkTotals`: when, with what, and what the screen says if the first succeeded and
the second did not); Delete chapter (its confirmation, its request); what counts as
confirmation, refusal and neither for each, quoted; every message; what the Chapters list
and the work form do after each kind of success (count the reads).

Then build on Android, in this order, finishing each before the next:

1. The chapter form as data: parser, encoder (the replay boundary below), one-read
   repository, with fixtures and tests, as 3bb did for the work.
2. The screen, editing in memory, reached from the Chapters list's rows and "Add chapter".
3. Save (a draft chapter), Post, Update (a posted chapter), and the work-total request.
4. Delete chapter, with iOS's confirmation.

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
- Posting a chapter notifies subscribers and cannot be undone: iOS's confirmation words,
  exactly, before that request.
- The two-request case (the chapter, then the work's total) is sequential, never parallel;
  a failure of the second is said as iOS says it and the first is not repeated.

## How it must be drawn

As the work form. Tokens only; lists lazy. Light, Dark, Sepia and OLED; nothing clipped at
`isAccessibilityFontScale()`; a pushed screen leaves `statusBars + 76dp` above its header.

## Demo and tests

- The demo answers every read and write locally for the posted work 995006 and the draft
  995001 (original filler): a new chapter, an existing chapter, one refusal with AO3's
  reasons, the total's request succeeding and failing. Say the routes and the taps.
- Tests, none reaching the network: the parser on each fixture; an untouched form against
  what a browser would send; each change against iOS's encoder; the reads for one opening,
  counted; exactly one POST per button, and two only where iOS sends two, in order; each
  verdict with iOS's words; the form unchanged after every failure; Delete only after its
  confirmation; the Chapters list after each success.
