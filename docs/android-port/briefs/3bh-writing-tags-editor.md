# Brief 3bh: the work form's tags editor

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; **don't edit `TASKS.md`**. Don't change the backup format or a Room schema. Your sandbox
can't run Gradle or Xcode. Claude builds, tests and commits afterwards, so make what you write
compile by reading the real symbols you use, and say which claims need a test run.

**Android only.** iOS is the reference: read it at `/Users/cidy02/kudos-ios-polish/`, change
nothing there. **When this brief and iOS's code disagree, iOS's code wins**; say so in the
result. Decide questions about demo fixtures, test data, file placement and naming yourself and
list them under "Decided without asking". Stop only for a question about what the app reads
from or sends to AO3, or what it does to the reader's stored data; even then finish everything
the question does not block first, and put every open question in your final summary. Write
`docs/android-port/briefs/3bh-result.md` as you go.

Read first:
- `briefs/3bf-result.md` **with its landing note**: the work form's screen
  (`writing/WritingWorkFormScreen.kt`, `writing/WritingWorkFormState.kt`), whose Fandoms,
  Relationships, Characters and Additional tags rows show a count and open nothing.
- `briefs/3bb-result.md` with its landing note: how the form encodes the four comma lists.
- How Android already asks AO3 for tag suggestions:
  `network/ao3/search/AO3TagAutocompleteRepository.kt` and its use in `search/` (the search
  filters' tag picker). **Use it; write no second one.**

## What is missing

The four tag rows of the work form open nothing. iOS opens
`Features/Writing/WritingTagsEditor.swift` (artboard 1bu) with
`Features/Writing/WritingTagConvenience.swift`. This brief is that editor, wired to the four
rows, changing the form in memory. It sends nothing.

## Build

Start the result with what iOS has, read from the code: the header and its words for each of
the four kinds; the field, its placeholder and what Return, a comma and a paste of several
names do; the chosen chips, their order, how one is removed and reordered if it can be; the
suggestions panel (when it appears, its rows, the canonical badge, the row for the typed term
and its words in each case, the cap, the empty and failed states); every footnote and count,
word for word (read the long comment at the top of the file: it says what the screen must not
claim); the "convenience" rows (tags the writer used before, tags from their other works):
where each list comes from, where iOS keeps it, whether its backup carries it, and how it is
ordered and capped; limits AO3 puts on a tag's length or a list's size and how iOS reports
them; what Done and Back do; and **every request**: which address, when, how long iOS waits
after a keystroke, what cancels one, and what is never asked.

Then build it on Android and make the four rows open it.

- **The lists go back into the form** so that `form.parameters(submit)` is what iOS would send
  after the same taps: names trimmed as iOS trims them, order kept, duplicates handled as iOS
  handles them. That is what the tests check.
- **Suggestions** through the existing repository: one read per settled term, with iOS's
  wait, cancelled when the term changes or the screen closes; none on opening; nothing read
  ahead; never the tag search page iOS's comment rules out. No new kind of request.
- **The convenience lists.** A list that needs a read iOS makes elsewhere (the writer's other
  works) is left out here if Android has not got that data yet: say so and list it. A list
  iOS keeps on the device is kept in Android's existing settings store in the corresponding
  way; the backup format does not change. If iOS's backup or sync carries it, stop and ask.
- **Nothing that writes to AO3.** iOS's separate Edit tags screen is another brief.

## How it must be drawn

Layout, content, order and words are iOS's (1bu). The work form's own components and
`tokens.scopePalette`; the app's chips for the chosen tags; the text field row the AO3
collection form already has. The top row's buttons are the app's Material icon buttons.
Tokens only: no stock Material chips, cards, text-field decoration or default Material
colours. Light, Dark, Sepia and OLED; every new text with a line height; nothing clipped at
`isAccessibilityFontScale()`; `statusBars + 76dp` above the header; long lists lazy; the
field and the suggestions stay above the keyboard.

## Demo and tests

- The demo answers the suggestion address locally for each of the four kinds (if it already
  does for the search filters, share that answer: one answer per address), with a term that
  returns several names, one that returns none and one that fails. Reach it from the three
  work form routes (`nav:writing-work-new-demo`, `-draft-demo`, `-posted-demo`).
- Tests, none reaching the network: adding by Return, by a comma, by a suggestion and by a
  paste; removing; duplicates; iOS's trimming and limits; each change against the encoder's
  output for all three forms, with every other field of the round trip untouched; one read
  per settled term and none for a term replaced inside the wait (a virtual clock); no read on
  opening; a failed read leaves typing possible; nothing sent (a client whose POST throws);
  the four rows open the editor and the rows that still wait open nothing. Compose tests here need a tall window for lazy
  lists, patient waits, and `@GraphicsMode(NATIVE)` when they ask about text. **Do not assert
  `hasVisualOverflow` on a short label**: a text narrower than its row reports a width
  overflow it does not have; assert `!didOverflowHeight` and that the last line is not
  ellipsized. When several values share a panel, a matcher by sibling finds all of them:
  count them, or match by the row.
