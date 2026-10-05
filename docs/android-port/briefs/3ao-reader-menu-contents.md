# Brief 3ao: what the reader's menu holds, against iOS

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; **don't edit `TASKS.md`**. Don't change the backup format or a Room schema. Your sandbox
can't run Gradle or Xcode. Claude builds, tests and commits afterwards, so make what you write
compile by reading the real symbols you use, and say which claims need a test run.

**Android only.** iOS is the reference: read it at `/Users/cidy02/kudos-ios-polish/`, change
nothing there. **When this brief and iOS's code disagree, iOS's code wins**; say so in the
result. Write `docs/android-port/briefs/3ao-result.md` as you go.

## Scope: contents, not looks

The reader's menu (`reader/ReaderFanMenu.kt`, opened from the reader's top-right button) is
drawn as glass pills. **Do not redraw it.** Whether the reader's controls stay glass or become
Android's own is a question with the owner (owner question 12). This brief is only about which
actions the menu holds, in which order, under which names, and what each does.

Start the result with a table of iOS's reader menu (find it from
`Features/ReaderReadium/ReadiumReaderView.swift`): every action in iOS's order, its label and
icon, when it is shown or hidden or disabled (signed in or not, an AO3 work or an imported
file, a selection present, a finished work, a restricted work), and what it does. Beside each:
Android today (present and the same, present and different, or absent) and the Android code
that does the same thing elsewhere, if any. Known from an earlier look: iOS has a Comments pill
and Kudos and Original actions that Android lacks; Android has Mark finished and two selection
pills (Highlight selection, Add note to selection) that iOS lacks or places elsewhere.

## Build

- Bring the menu to iOS's set and order, with iOS's labels and conditions.
- **Add an action only by calling what Android already has.** Comments opens the existing
  comments screen for the work (`Routes.comments`). Kudos uses the existing kudos action the
  work page uses (find it; it is a write to AO3 that the reader starts with a tap: one request
  per tap, the existing confirmation and failure handling, nothing new on the wire). Original
  opens the imported original the way the work page does, if Android can. If an action has no
  existing code behind it, do not build a new feature here: leave it out and list it with what
  it would take.
- **Do not remove what Android has and iOS does not without saying where it went.** Mark
  finished and the two selection pills: find where iOS offers the same thing (the text
  selection menu, the end-of-work page, the work page) and whether Android offers it there
  too. If removing a pill from the menu would leave Android with no way to do the thing, keep
  it and say so; otherwise follow iOS.
- States: an action that needs a sign-in, or an AO3 work, is shown, hidden or disabled exactly
  as on iOS, with iOS's words when the reader taps one they cannot use.
- Use the menu's existing pill and icon-button composables for anything added, unchanged.

## Tests

For each action added or moved: the condition under which it shows, and that its tap calls the
existing entry point (a recording fake is enough; no network, no real write).
