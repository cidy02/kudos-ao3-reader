# Brief 3bx: the work form posts, previews on AO3 and deletes

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
questions", and keep going to the end. Write `docs/android-port/briefs/3bx-result.md` as you go.

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
- A toolbar button handed to the shell must be absent **as a value** until it applies
  (`trailingContent = if (form == null) null else { … }`). Content that tests for the form
  inside itself stays empty when the form arrives after the screen: 3bo's Save was invisible
  until this was fixed on landing.
- In tests: a `waitUntil` on something that is not on screen (a request count) needs
  `compose.waitForIdle()` first; a test function's body returns `Unit`
  (`runBlocking<Unit> { … }`); never `runBlocking` in an `@After` on something that needs
  the main thread (it hung the whole suite); the theme is `KudosThemeMode.Oled`, not `OLED`;
  when two states share a title, wait for the sentence that differs.
- No line heights or other changes to shared components (`ui/subject/`, `settings/`) unless
  the brief names them.
- A reload or a refresh never clears what the writer is in the middle of (audit A22: a
  reload cleared a reply's target and the text went out as a new comment).
- Demo data must really produce what the brief asks to be seen: say which demo rows give
  each case, and check the rule that selects them against those rows.

Read first:
- `briefs/3bo-result.md` and `briefs/3bt-result.md` **with their landing notes**: the work
  form's Save and Edit tags as they stand (`writing/WritingWorkFormScreen.kt`,
  `WritingWorkFormState.kt`, `network/ao3/writes/AO3WriteRepository.kt`: `saveWork`,
  `editWorkTags` and the private `submitWork` they share; the verdict helpers
  `workWriteError` and `workWriteNotice`), and how each was tested and answered by the demo.
- `briefs/3bu-result.md` if it is there (the chapter form, which has its own preview and
  post): build nothing twice, and say what you reuse from it.
- `briefs/3bb-result.md`, "The replay boundary" (a field iOS's encoder leaves out goes back
  with the value AO3 served).
- `docs/WRITING_EDITOR_ARCHITECTURE.md` §0 and §8.7, and `docs/AO3_NETWORKING_POLICY.md`:
  say which rule allows each read and each write.
- `audits/R2-result.md`, sections "Post a draft", "Delete a work or a draft" and "Preview on
  AO3": a first reading of iOS with file and line pointers. **It is a guide to where to
  look, not a specification**: read the Swift yourself.

## What is missing

Android's work form can be saved as a draft or updated, and nothing else. iOS's
`Features/Writing/WorkEditView.swift` also **posts** a draft (its Post panel, the "Post this
work?" alert, the list of what is missing), **previews** it on AO3
(`Features/Writing/WritingPreviewView.swift`, `previewWork` and `postPreview` in
`Services/AO3WorkActions.swift`), and **deletes** a draft or a posted work
(`loadDeleteImplications`, `deleteWork`, `submitDelete`). This brief is those three.

## Build

Start the result by reading the three from iOS's code, line by line, and setting out for
each: who sees the control and in which state of the form (new, draft, posted); the taps
that lead to it; every alert and confirmation with its title, message and buttons, word for
word; **every request, in order**, with the address, every field name and value and where
each comes from, what is sent for an empty value, and the headers; what iOS takes as AO3's
confirmation and what as a refusal (quote the Swift: the selectors, the status codes, the
order they are tried in); each message in each case; what the screen shows while it waits
and after; what is never retried; and what happens to the form, the recovery copies and the
drafts list afterwards.

Then build them on Android.

- **Post.** The Post panel as iOS draws it, with iOS's rows and footnotes in each state.
  What is missing before posting is worked out as iOS works it out
  (`missingRequiredFields`), and shown with iOS's words. Posting follows iOS's path exactly:
  if iOS posts through its preview, so does Android; if a draft that was never saved is first
  saved and then posted, say so and do the same, with the same number of requests. One POST
  per step, never retried; done only on AO3's own word (the helpers `submitWork` already
  uses, unless iOS's post has a different verdict: then that one).
- **Preview on AO3.** iOS's preview screen: what it sends, what it parses out of the answer
  (the rendered blocks, AO3's notice, **the id of the draft AO3 has just created**, which
  the form must adopt so that a later Save or Post does not create a second work), its Post
  and Edit buttons, its waiting and failure states. Long previews are lazy: a preview that
  draws a whole chapter at once froze the editor's own preview (3bd's landing note).
  **A preview creates or changes a draft on AO3: it is a write.** Treat it as one (one POST,
  never retried, the session fence, the verdict).
- **Delete.** iOS reads AO3's confirmation page first (what will go with the work: comments,
  kudos, bookmarks) and shows that in its confirmation. Do the same: one read when the
  writer asks to delete, the confirmation with iOS's words and AO3's counts, then one POST.
  After a confirmed delete the form closes and the drafts list (or wherever the writer came
  from) reads its current page once, as after a confirmed Save. **Nothing in the reader's
  own library is deleted**: a saved copy of the work stays, as on iOS (check, and quote).
- **Never** a retry, a second POST, a write on opening, or a read iOS does not make. The
  session that opened the form is the only one that may write it (the fence 3bo uses).
- All three go through `AO3WriteRepository` and the client it already uses; no new HTTP
  code.

## How it must be drawn

As the form is today (`tokens.scopePalette`, the form's sections, rows, footnotes and its
alert), with iOS's layout and words for the new parts. A destructive action is drawn as the
app's other destructive rows are (find one in `settings/` or `account/` and use the same
token). The preview screen is a pushed screen inside the form's route, like the tags editor:
`ProvidePushedShellChrome`, `statusBars + 76dp` above its header. Tokens only: no stock
Material buttons, cards or default colours. Light, Dark, Sepia and OLED; every new text
with a line height; nothing clipped at `isAccessibilityFontScale()`; long lists lazy.

## Demo and tests

- The demo answers every request locally (`network/ao3/DemoNetwork.kt`; one answer per AO3
  address, shared with what already reads it): a draft that posts, a draft AO3 refuses to
  post with a reason, a new work whose preview creates the draft (and a later Save that
  must then update that draft, not create another), a posted work that deletes, and a
  delete AO3 refuses. Relaunching the demo resets it. Say the routes and the taps for each.
- Tests, none reaching the network: each request field for field and in order against iOS's
  (a recording client), for a new work, a draft and a posted work; exactly the requests iOS
  makes for each action, counted; each verdict (confirmed, refused with AO3's text, an
  unconfirmed 2xx, a session that changed, signed out) with iOS's words; the form unchanged
  after any failure, with everything typed; **the draft id adopted after a preview, proven
  by the address of the next Save**; the second tap while one is in flight ignored; the
  confirmation showing AO3's counts; nothing sent on opening; the saved library copy
  untouched by a delete.
