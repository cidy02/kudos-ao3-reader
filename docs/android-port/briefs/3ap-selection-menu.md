# Brief 3ap: Highlight and Add Note from the reader's text selection menu

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; **don't edit `TASKS.md`**. Don't change the backup format or a Room schema. Your sandbox
can't run Gradle or Xcode. Claude builds, tests and commits afterwards, so make what you write
compile by reading the real symbols you use, and say which claims need a test run.

**Android only.** iOS is the reference: read it at `/Users/cidy02/kudos-ios-polish/`, change
nothing there. **When this brief and iOS's code disagree, iOS's code wins**; say so in the
result. Write `docs/android-port/briefs/3ap-result.md` as you go.

## What is wrong

On iOS, selecting text in the reader offers Highlight and Add Note in the system's own
selection menu (`ReadiumBook.selectionEditingActions`, dispatched to
`createAnnotationFromSelection`). On Android the selection menu offers only the system's
actions, and the two things live as pills in the reader's menu ("Highlight selection", "Add
note to selection": `reader/ReaderFanMenu.kt`), which you kept in brief 3ao for that reason
(`briefs/3ao-result.md`, "Selection pills"). A reader has to select, dismiss, open another menu
and tap; and the pills are there when nothing is selected.

## Build

- Add Highlight and Add Note to the reader's text selection menu, with iOS's labels, in iOS's
  order relative to the system's Copy and the rest. Read how the Readium navigator is hosted
  (`reader/readium/ReadiumNavigatorHost` and its fragment configuration) and use the toolkit's
  own way of customizing the selection action mode for the version in `gradle/libs.versions.toml`
  (inspect the cached artifact's API; do not guess a signature).
- Each calls the entry point the pills call today, with the current selection: read what
  "Highlight selection" and "Add note to selection" do in `ReaderScreen`/`ReaderViewModel` and
  reuse it, so a highlight or note made from either place is the same record. Clear the
  selection afterwards as iOS does.
- When that works, remove the two pills from the reader's menu, leaving it with iOS's pills
  only, and update `ReaderFanMenuTest` and anything else that lists them. If the toolkit cannot
  carry a custom action in the version in use, keep the pills, change nothing, and say exactly
  what stops it.
- An existing highlight tapped on iOS offers its own actions (edit note, change colour, delete:
  read what iOS has). Say what Android does today on a tap of a highlight and list any
  difference; do not build that here.
- No change to how highlights are stored, drawn or synced, and none to the menu's look.

## Tests

The selection menu's added items exist with iOS's labels and call the recording entry points
with the selection's locator and text; with nothing selectable they are absent; the fan menu no
longer lists the two pills. No network.
