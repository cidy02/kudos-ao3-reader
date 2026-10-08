# Brief 3br: the reader finishes a work at its real end, and the position card scrubs the chapter

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
questions", and keep going to the end. Write `docs/android-port/briefs/3br-result.md` as you go.

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

Read first: `audits/A5-result.md`, findings A5-2 and A5-3 **with the triage at its foot**;
`briefs/3j-result.md`, `briefs/3q-result.md` and `briefs/3ao-result.md` with their landing
notes (the reader's chrome, its sessions, its menu); `reader/ReaderPositionCard.kt`,
`reader/ReaderProgressDisplay.kt`, `reader/EndOfWorkActions.kt`,
`reader/readium/ReadiumProgressAdapter.kt`, `reader/readium/ReadiumNavigatorHost.kt`, and the
Readium Kotlin toolkit's sources for the version in `android/gradle/libs.versions.toml` (in
the Gradle cache: read the navigator's real API, do not guess it).

## What is wrong

Two rules in Android's reader differ from iOS's, and both change what a reader's library
says about their reading.

1. **A work is marked finished too early.** `EndOfWorkActions.isAtEndOfPublication` says
   "at the end" at 98.5% of the whole book (or 95% of the last chapter). On a long work that
   is thousands of words early. The work leaves Continue Reading, and an unprotected copy
   starts its 60-day hold at that moment. iOS (`Features/ReaderReadium/ReadiumReaderCompletion.swift`,
   `ReadiumBook.swift` near `onReachedPublicationEnd`, `ReadiumReaderView.swift` near
   `freeEPUBIfFinished`) finishes only when the **trailing edge of the last reading-order
   resource is on screen**, and starts the hold when the reader leaves.
2. **The position card scrubs the wrong thing.** Its thumb is the whole book's progress, its
   label says "Seek within chapter", its minutes say "left in chapter" and are the whole
   work's, and a drag jumps to the start of some chapter and saves that place. iOS
   (`ReadiumReaderView.swift` near `goToProgressionInCurrentResource`, `ReadiumBook.swift`
   near "swipe-scale", `ReaderTimeEstimate.swift`) shows the page within the current chapter
   and seeks within it.

## Build

Start the result with iOS's rules read from the code, line by line: what "at the end" is, in
paginated and in scrolled reading, and why a threshold was rejected (quote the comment); what
happens on reaching the end (what is set, what is not, when the copy's hold starts, what the
reader sees); the position card's every number and word (the percent, the chapter line, the
page line, the minutes, the thumb's range, what a drag does while dragging and on release,
the accessibility label and value).

Then say what Readium's Kotlin navigator gives for each: the visible range of the current
resource (or the last page of a paginated resource, or the scroll extent), in both reading
modes. **If the toolkit cannot say that the trailing edge is on screen**, do the most
sparing thing: never finish on a threshold of the whole book; finish only in the last
reading-order resource and only at the navigator's own end (say exactly what you used), and
put the gap under "Open questions".

Then change Android:

- Finished at the real end only. The hold starts on leaving the reader, as iOS (the close
  path already holds a finished copy: check that it does and that nothing holds earlier).
  A work finished by the reader's own Mark as Finished is unchanged.
- The position card as iOS: the thumb and its label within the chapter; a drag seeks within
  the current resource and never changes chapter; minutes left in the chapter where iOS
  shows that, and in the work where iOS shows that.
- No change to how a position is stored or to the backup.

## How it must be drawn

The card as it is today (tokens, layout); only its numbers, words and behaviour change.

## Tests

The end rule as a pure function with cases for both modes: a long work at 98.5% that is not
at its end; the last page of the last chapter; a last chapter of one page; a one-chapter
work. The two existing tests that pin the thresholds (`EndOfWorkActionsTest`) change to
iOS's rule. The card: the thumb's value from a chapter position; a drag's target stays in
the chapter for the first, a middle and the last chapter; the words. That finishing does not
start the hold and leaving does.
