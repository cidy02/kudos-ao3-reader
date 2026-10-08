# Brief 3bm: the work form's Chapters list (reading only)

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
questions", and keep going to the end. Write `docs/android-port/briefs/3bm-result.md` as you go.

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

Read first: `briefs/3bf-result.md`, `briefs/3bh-result.md` and `briefs/3bj-result.md` **with
their landing notes** (the work form's screen in `writing/`, its tags editor and its
pickers; the Chapters, Add chapter and Edit tags rows show a value and open nothing), and
`docs/AO3_NETWORKING_POLICY.md`.

## What is missing

The work form's **Chapters** row opens nothing. iOS opens
`Features/Writing/WritingChaptersView.swift` (part of artboard 1bo): the work's chapters, read
from AO3's own chapter index (`/works/<id>/navigate`) by the parser Comments already uses
(`AO3Client.chapterIndex`). This brief is that list, **reading only**. Each row on iOS opens
the chapter's edit form (`AddChapterView`), which is a later brief.

## Build

Start the result with what iOS has, read from the code: the header and its subtitle in each
case (loading, one chapter, several, none); each row (number, title, AO3's date and how it is
worded, a draft chapter's mark if any); what a row opens; loading, failure, empty and
signed-out states and their words; what makes the list read again (the `reload` counter, a
return from a pushed screen, pull to refresh if any); **the one request**, for whom, and what
the screen shows when it fails.

Then build it on Android and make the form's Chapters row open it (the row exists only for a
work AO3 already has, as on iOS).

- **One read** per opening and per refresh the reader asks for: the chapter index of that
  work, through the existing authenticated client. Android already reads and parses AO3's
  chapter index for Comments: find that code and **use it; write no second parser**. If its
  model lacks something this screen shows (the date, a draft mark), extend that one parser
  with a test, and say so. Signed out reads nothing. Count the reads in the result first.
- **Rows open nothing yet.** A chapter row's only purpose on iOS is to open the chapter's edit
  form, which is not built: show each row without a disclosure mark or click action, add no
  sentence in its place, and say so in the result so the next brief wires it.
- Nothing is sent. Add chapter and Edit tags keep opening nothing.

## How it must be drawn

Layout, content, order and words are iOS's. The work form's own components (`writing/`), the
subject header, `tokens.scopePalette`. The top row's buttons are the app's Material icon
buttons. Tokens only: no stock Material chips, cards or default Material colours, and no new
colour token. Light, Dark, Sepia and OLED; every new text with a line height; nothing clipped
at `isAccessibilityFontScale()`; `statusBars + 76dp` above the header; the list lazy.

## Demo and tests

- The demo already answers `/works/<id>/navigate` for some addresses
  (`network/ao3/DemoNetwork.kt`): give work 995006 (the posted demo work, two posted chapters
  of five) its own local answer with two chapters, one with a long title, and share it with
  whatever else reads that address. Reach the list from `nav:writing-work-posted-demo`.
- Tests, none reaching the network: the parser on the fixture, including what this screen
  adds; one read per opening and none after; a failed read; signed out; the form's Chapters
  row opening this screen for a posted work and absent or inert where iOS has none; the
  chapter rows having no click action; nothing sent (a client whose POST throws).
