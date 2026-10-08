# Brief 3bn: Work Detail's series preservation and bookmark sheet, as iOS

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
questions", and keep going to the end. Write `docs/android-port/briefs/3bn-result.md` as you go.

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

Read first: `audits/A7-result.md`, the triage at its foot (what was found and where),
`docs/AO3_NETWORKING_POLICY.md` (what the app may read when it saves a series, and how it is
paced), `docs/DATA_AND_PERSISTENCE_INVARIANTS.md` (preservation), and
`briefs/3f-result.md` if present (how Work Detail was rebuilt on Android).

## What is wrong

1. **Series preservation.** On iOS, saving a work that belongs to an AO3 series can save the
   whole series: Work Detail presents "Preserve Series?" with **Preserve Entire Series** and
   **Only This Work**, an auto-preserve switch with its threshold, and **Cancel Series
   Preservation** while it runs; and Save for Later auto-preserves a small series when the
   reader has switched that on. Android has an older block inside its add-to-queue dialog
   (`works/WorkDetailScreen.kt`, "Also add works from this AO3 series"), builds its prompt
   with a fixed threshold of 5, and **never reads the reader's "Auto-preserve small series"
   setting**: the switch and threshold on Settings › Reading queues do nothing.
2. **The AO3 bookmark sheet** on Work Detail is a stock Material dialog; iOS's is a form.

## Build

Start the result with what iOS does, read from the code (`Features/WorkDetail/WorkDetailView.swift`,
`Features/WorkDetail/AO3WorkActionsModel.swift`, `Services/ReadingQueueService.swift`,
`Features/Library/ReadingQueues.swift`, the settings pages that hold the switch and
threshold): **every rule**: when the series prompt is offered and when it is not; what is
read to learn the series' size, when, and what happens if that read fails; when a series is
preserved without asking (the setting, the threshold, "the first AO3 page shows the full
series"); what preserving does work by work, in what order, with what pause, to which
queues or the library, and what is skipped (works already held, restricted works, a failure
in the middle); what Cancel does to works already saved and to the rest; the result
sentence in each case; every word of the sheet and of the progress row. Then the bookmark
sheet: every field, header, footer, placeholder, default, validation and button, and the
request it makes (already built on Android: `AO3WriteRepository.createBookmark`; do not
change what it sends).

Then on Android:

- **Make the behaviour iOS's**, in the existing code paths (`library/SeriesPreservation.kt`,
  `library/ReadingQueueRepository.kt`, the Save for Later path, `works/WorkDetailScreen.kt`):
  the reader's setting and threshold decide auto-preservation exactly as on iOS; the prompt
  is offered when iOS offers it; Cancel stops as iOS's does. Every rule you change cites the
  Swift line it matches. No new kind of AO3 request, no faster pace, no read ahead: if iOS
  reads something Android does not, add it only if the networking policy names it.
- **Draw both sheets as iOS's**: the series sheet and its progress and result rows, and the
  bookmark sheet, with the app's own form components (see how
  `account/AO3CollectionFormScreen.kt` and `writing/` build a form). The old series block
  leaves the add-to-queue dialog only if iOS has nothing there; say what iOS has there.
- **Data safety:** nothing here may remove a work, a queue membership or a download. If a
  rule of iOS's would, stop that part and put it under Open questions.

## How it must be drawn

Layout, content, order and words are iOS's. Tokens only: no stock Material dialogs, chips,
cards, outlined buttons, text-field decoration or default Material colours, and no new
colour token. Light, Dark, Sepia and OLED; every new text with a line height; nothing clipped
at `isAccessibilityFontScale()`.

## Demo and tests

- The demo: a library work in a small series that fits one AO3 page, one in a series that
  spans two pages, and one whose series page fails, all answered locally
  (`network/ao3/DemoNetwork.kt`; one answer per address, shared with whatever already reads
  it). Say the routes and the taps for: the prompt, Only This Work, Preserve Entire Series
  with a Cancel part-way, auto-preserve on Save for Later with the setting on and off, and
  the bookmark sheet.
- Tests, none reaching the network: each of iOS's rules as a case (the setting off; on with
  a series at, under and over the threshold; a series that spans pages; a failed size read;
  works already held; Cancel after the second work); the reads made, counted, and their
  pacing with a virtual clock; the threshold coming from the setting and not a constant; the
  bookmark sheet's fields reaching the existing write unchanged; nothing removed.

## Added 2026-10-08 (from audits A8 and A4, and from landing 3bm)

- Audit A8 found the same series controls missing from the queue sheet: iOS's
  `Features/Library/ReadingQueues.swift` (about lines 500-535) has "Add Series to Selected
  Queues", **"Cancel Series Addition"** while it runs, the completion line, and the footnote
  "Kudos adds series works only after you choose Add Series, one work at a time." Android's
  `works/WorkDetailScreen.kt` has the first only. Build the rest with this brief.
- The bookmark write's verdict: AO3's validation list (`#error li`) is a refusal, read by
  `AO3WriteFormParser.writeErrorMessage`; the sheet stays open with what was typed and shows
  AO3's reason (notes over 5,000 characters is the case to test).
- A row with a long label shows a short value as its `trailing` content, not as `value`. No
  stock Material `Button`, progress ring colours or unstyled `Text`.
