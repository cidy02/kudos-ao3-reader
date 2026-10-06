# Brief 3bd: the writing text editor (HTML mode), one field at a time

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; **don't edit `TASKS.md`**. Don't change the backup format or a Room schema. Your sandbox
can't run Gradle or Xcode. Claude builds, tests and commits afterwards, so make what you write
compile by reading the real symbols you use, and say which claims need a test run.

**Android only.** iOS is the reference: read it at `/Users/cidy02/kudos-ios-polish/`, change
nothing there. **When this brief and iOS's code disagree, iOS's code wins**; say so in the
result, and if a question remains, ask it at once and stop rather than guess (put every open
question in your final summary, not only the first). Write
`docs/android-port/briefs/3bd-result.md` as you go.

Read first:
- `docs/WRITING_EDITOR_ARCHITECTURE.md` §0 (D2, D3, D4, D7, D8), §7.6, §8.1 to §8.5, §9.1,
  §9.2 and §10.2. It governs both platforms. iOS ships HTML mode only; so does this brief.
- `briefs/3bc-result.md` and `briefs/3bb-result.md`: what is already on Android under
  `network/ao3/writing/` (the recovery store, the writer, the checkpoint scheduler, AO3's word
  count, the work form as data). **Use them; write no second one.**
- `briefs/3az-result.md` and `briefs/3ba-result.md` with their landing notes (how a pushed
  screen is built and tested here, and what was corrected on landing: a pushed screen leaves
  `statusBars + 76dp` above its header; no invented top buttons; no line heights added to
  shared components; a new file's type names must not repeat a name its package already has).

## What is missing

Android has no place to type a chapter, a summary or a note. iOS has
`Features/Writing/WritingTextEditor.swift` (artboard 1bv) over
`Features/Writing/WritingNativeTextView.swift` (the text view and `WritingTextController`) and
`Models/AO3Markup.swift` (the tags the toolbar inserts). This brief is that one screen and
**only that**: it edits one string and hands it back. It reads nothing from AO3 and sends
nothing.

## Build

Start the result with what iOS has, read from the code: the header and the two notes under it,
word for word; the top buttons; the tag bar (every tag, its label, its order, what it inserts
around a selection and with no selection, where the caret lands) and the format menu; the
"more" menu and which items exist only when the caller passes chapter actions; Undo and Redo;
the in-editor preview (what it parses, what it shows, its empty and failed states); the word
count line in each state; the recovery sheet (when it is offered, its words in each case, its
three actions); every event that forces a checkpoint; what Done does and what leaving without
Done does; every alert and its words.

Then build it on Android:

- **One screen, one string.** It takes the text, a title, an optional rule title, the account
  name, the target and the field (the three parts of the recovery key, as iOS passes them),
  and gives the text back on Done. Nothing else in the app opens it yet: the work form's
  screen is a later brief, and **a tap on a draft keeps opening the browser**. Reach it by a
  demo route only (below).
- **The text field is native** and unstyled: the HTML as typed, no highlighting, no parsing of
  what is already there. Inserting a tag changes only the selection's surroundings. The
  platform owns selection, the keyboard's composing text and undo, as on iOS (quote the comment
  at the top of `WritingNativeTextView.swift`).
- **Typing costs nothing proportional to the chapter (D8).** No keystroke copies the chapter,
  compares it, counts words, encodes, or touches disk. An edit only tells the scheduler that
  it happened. The text is taken once per checkpoint. Say in the result, for the widget you
  chose, what the platform itself does per keystroke on a 510,000-character field, and why you
  chose it over the alternatives (a platform `EditText` in an `AndroidView`; a Compose field
  on `TextFieldState`; others). **Claude measures it** against B1 and B6 on a device with
  `Scripts/make-writing-fixture.py`'s chapter; you cannot, so do not claim a result. Keep the
  widget in one file with a small surface (set text, take text, insert around the selection,
  undo, redo, an "edited" callback), so that a failed measurement replaces one file.
- **Checkpoints and recovery** exactly as §8 and iOS: 3bc's scheduler and writer; the
  sequence number is the scheduler's count; the word count runs off the main thread at open
  and at each checkpoint, and a count that finishes after a newer one started is dropped. A
  checkpoint is forced on Done, on leaving the screen, on restoring a copy, when the app goes
  to the background, and on a low-memory signal; say which Android callbacks you used for the
  last two and why they correspond to iOS's. A failed recovery write shows iOS's alert.
- **The recovery sheet** on opening, from 3bc's `copiesOnOpen`, with iOS's words and three
  actions. Restoring must be undoable in the field, as on iOS.
- **Left out, and listed in the result:** anything that needs AO3 (iOS's "Preview on AO3")
  and the chapter actions (Delete chapter). They arrive with the screens that own them.

## How it must be drawn

Layout, content, order and words are iOS's (artboard 1bv). The top row's buttons are the
app's own Material icon buttons (`ToolbarCircleButton` in `ui/subject/SubjectComponents.kt`),
because navigation and chrome controls on Android are Material's, not iOS's. Everything else
uses the app's tokens and the subject components: no stock Material chips, cards, text-field
decoration or default Material colours. The palette is `tokens.scopePalette`, as the other
account pages. Light, Dark, Sepia and OLED; every new text with a line height; nothing clipped
at `isAccessibilityFontScale()`. The tag bar stays above the keyboard; the field keeps the
caret in view while typing at the end of a long chapter.

## Demo and tests

- A demo route (`nav:` routes are in `ui/subject/DebugRoutes.kt` and `app/`): one that opens
  the editor on a short text of original filler with some markup, and one that opens it on
  the contents of a file Claude can push with adb (say the exact path; debug builds only).
  Seed one recovery copy for the first, so the sheet can be seen. Say both routes in the
  result.
- Tests, none reaching the network (this screen has no client at all: assert that it is
  built without one). Tag insertion as a pure function of text and selection, for every tag,
  with and without a selection, at the start, the end and inside existing markup. iOS's
  `WritingTextEditorTests` and `WritingNativeTextView` cases that apply to what is built
  here, ported with their names (3bc already ported the recovery-only ones). With a virtual
  clock: an edit leads to one recovery write 1.5 s later; continuous edits lead to one within
  20 s; Done forces one; no write when the text has not changed since the last; an older
  count never replaces a newer one. The recovery sheet is offered for a copy that differs and
  not for one that equals the text; Restore replaces the text; Delete removes that file only.
  Compose tests here need a tall window for lazy lists, patient waits, and
  `@GraphicsMode(NATIVE)` when they ask about text.
