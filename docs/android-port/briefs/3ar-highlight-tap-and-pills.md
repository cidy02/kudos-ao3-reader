# Brief 3ar: tapping a highlight, and the two pills out of the reader's menu

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; **don't edit `TASKS.md`**. Don't change the backup format or a Room schema. Your sandbox
can't run Gradle or Xcode. Claude builds, tests and commits afterwards, so make what you write
compile by reading the real symbols you use, and say which claims need a test run.

**Android only.** iOS is the reference: read it at `/Users/cidy02/kudos-ios-polish/`, change
nothing there. **When this brief and iOS's code disagree, iOS's code wins**; say so in the
result. Write `docs/android-port/briefs/3ar-result.md` as you go.

Read `briefs/3ap-result.md` first, with its landing note: your wrapper landed, with the rule
changed on the emulator to "the native menu holds something" (the WebView's Copy does not have
`android.R.id.copy`). Highlight from the real selection menu was seen to work. Also landed with
it: a highlight is now stored in this reader's envelope (`ReaderLocatorCodec.forStorage`), so it
is drawn; before, it was saved and never shown.

## Part 1: the two pills

Apply your own "Exact pill removal list" from `3ap-result.md` (items 1 to 4), so the reader's
menu holds iOS's pills only. Check each line against the files as they are now.

## Part 2: tapping a highlight on the page

Your table in `3ap-result.md` ("Tapping an existing highlight") says what iOS does and that
Android does nothing: no decoration listener, so a tap on a highlight only toggles the chrome,
and a plain highlight can be edited or deleted only from the Contents sheet.

Port iOS's behaviour (`ReadiumBook.observeHighlightTaps`, `ReadiumReaderView.openHighlight`,
`ReaderNoteEditor`):

- Register a decoration listener for the highlights group with the toolkit's API for the
  version in `gradle/libs.versions.toml` (inspect the cached artifact; do not guess a
  signature). A tap on a highlight opens that annotation's editor and does not toggle the
  chrome; a tap elsewhere behaves as today.
- The editor is the one Android already has for a note (find what Contents' `onSelectAnnotation`
  opens), extended to what iOS's `ReaderNoteEditor` offers for any highlight: its text shown,
  the note added or edited, the colour changed, and Delete Highlight with the existing
  confirmation. Titles and button words are iOS's. Every change goes through the existing
  repository calls (`AnnotationRepository`: find the recolour, note update and delete entry
  points; add nothing that bypasses tombstones or sync).
- Contents' list keeps working as it does, and opens the same editor for a plain highlight
  where today it only jumps to it, if that is what iOS's list does: read it and follow it.
- The reader's own theme tokens for the editor (it is shown over a book page); the existing
  sheet and row components the reader's other sheets use; no stock Material chips or default
  Material colours.

## Tests

The pills are gone from the menu's builder and its tests. For the tap: a recording decoration
event for a known annotation opens the editor state for that id and does not toggle chrome; an
unknown id does nothing; colour, note and delete each call the repository entry point once,
with the annotation's id. No WebView in the tests.

Say what cannot be proved without a device (that the real page delivers the tap).
