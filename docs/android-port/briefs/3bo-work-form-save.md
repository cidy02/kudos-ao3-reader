# Brief 3bo: the work form saves (Save draft and Update; no Post, no Delete)

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
questions", and keep going to the end. Write `docs/android-port/briefs/3bo-result.md` as you go.

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

Read first: `briefs/3bf-result.md` **with its landing note** and its section "AO3 operations
for the Save brief" (the form's screen, in `writing/`: it loads, shows and changes a work in
memory and sends nothing); `briefs/3bb-result.md` with its landing note (the encoder:
`form.parameters(submit)` sends iOS's modeled fields iOS's way and replays every other served
control as a browser would; **this brief changes nothing in it**); `briefs/3an-result.md`,
`briefs/3aw-result.md` and `briefs/3bg-result.md` with their landing notes (how a write to AO3
is built, confirmed and tested on Android: one POST never retried, the screen changed only on
AO3's confirmation, iOS's exact words for each verdict, the captured form action checked with
`AO3RedirectCookieRelay.isTrustedUrl`); `briefs/3az-result.md` (the drafts screen and
`WritingWorkDestination`); and `docs/AO3_NETWORKING_POLICY.md`: say which rule allows the
write.

## What is missing

The work form can be filled in and cannot be saved, and nothing in the app opens it: a tap on
a draft and New Work still open AO3's page in the in-app browser. iOS saves from
`Features/Writing/WorkEditView.swift` through `AO3WorkActions.saveWork` and
`submitWorkForm` (`Services/AO3WorkActions.swift`). This brief is **Save** (a new work or a
draft: Save draft; a posted work: Update) and the two entry points. Post, Delete, Preview on
AO3 and the chapter screens are later briefs.

## Build

Start the result by reading iOS's Save again from the code, line by line, and setting it out:
who sees the Save button and when it is disabled; what it is called in each case; the one
request (address, method, every header, the referer, where the token comes from and whether
it is the one the form was served with or a fresh one; the body is `form.parameters(submit)`
with which `submit` in each of the three cases); the session checks before and after
(`requireWorkSession`, the generation fence); **what `submitWorkForm` counts as AO3's
confirmation, as a refusal, and as an answer it cannot judge**, quoted; every message, word
for word, in each case; what the screen shows while it waits; what happens to the form, to
the screen under it and to the text editor's recovery copies after a success and after a
failure; what is never retried.

Then build it on Android.

- **One POST per tap, never retried, never a second.** Through the app's existing
  authenticated client and write path (see how 3bg's `saveTagSetFields` does it); no new HTTP
  code. The body is exactly `form.parameters(submit)` from 3bb's encoder: add no field, drop
  none, reorder none. The token is whichever iOS sends (say which).
- **The Save button** in the top row, as iOS: its name in each case, disabled while a save is
  in flight. A new work with nothing typed: do what iOS does (say what that is).
- **Verdicts with iOS's words.** Confirmed: what iOS does (it closes the form). Refused: the
  form stays exactly as typed, with iOS's alert and AO3's reason. An answer that is neither:
  as iOS; if iOS treats an unjudged 2xx as success, say so in the summary as a question and
  do the more careful thing (keep the form open, say that AO3 did not confirm).
- **Nothing typed is lost on any failure**: a failed token, a refusal, a network error, a
  session that changed (iOS: "Your AO3 session changed. Reopen this form before saving.")
  all leave the form's fields and the editor's recovery copies as they were.
- **After a confirmed save**, the screen under the form shows the change the way iOS's does.
  Read how iOS's drafts screen learns of it and do the same; **count the reads this costs**
  and make no read iOS does not make.
- **The two entry points.** A tap on a draft and New Work open this form, as on iOS
  (`WritingWorkDestination`, the drafts screen). Whatever iOS still opens in the browser
  stays in the browser. A posted work's own entry (if iOS has one outside the drafts screen)
  is listed in the result and left for its brief.
- **Left out and listed:** Post and its panel, Delete, Preview on AO3, the refreshes after a
  chapter or tag screen writes (those screens do not write on Android yet).

## How it must be drawn

As the form is today. The Save button is the top row's text action as the collection form's
and the tag set's Save are drawn. iOS's alert as the app's own alert (see the collection
form's). Tokens only. Light, Dark, Sepia and OLED; nothing clipped at
`isAccessibilityFontScale()`.

## Demo and tests

- The demo answers the POST locally (`network/ao3/DemoNetwork.kt`): a new work saved as a
  draft, the draft 995001 saved, the posted work 995006 updated, and one refusal you choose
  a trigger for (a title AO3's local answer refuses with AO3's own error markup). Relaunching
  resets it. Say the routes and the taps.
- Tests, none reaching the network: the request field for field against iOS's for each of the
  three cases (a recording client), including a form changed through the screen; exactly one
  POST per save and none on opening; each verdict with iOS's words; the form unchanged after
  every kind of failure; the session-changed case; the Save button disabled in flight; a
  second tap while one is in flight sends nothing; the drafts screen's tap and New Work
  asking for this form.

## Added 2026-10-08 (audits A4 and A5, and landings since this was written)

- **A work with more than one chapter has no chapter text box on AO3's edit page.** The
  parser records that (`AO3WorkChapterDraft.contentServed`), the encoder already leaves the
  text out, and the form hides its "Work text" row (audit A4-1, fixed on both apps). Test
  Save on such a form: the body has the chapter's title and no
  `work[chapter_attributes][content]`.
- `AO3WriteFormParser.writeErrorMessage` reads AO3's validation list (`#error li`). A page
  with no notice and no error is `AO3CollectionFields.UNCONFIRMED`, never success.
- Text actions and action rows use the palette's accent (`tokens.scopePalette.accent`;
  `SettingsActionRow` already does): the raw `tokens.accent` cannot be read in Dark.
- A `SubjectFormRow` given a `trailing` slot draws no `value`, even when the slot is empty
  (3bl's Fandoms row showed nothing): pass one or the other.
- A section header is drawn in capitals: a test that waits for its text must ask for
  "REQUIRED", not "Required".
