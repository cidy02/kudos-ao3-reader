# Brief 3bd — one-field HTML editor

## iOS reference inventory (read before implementation)

Reference worktree: `/Users/cidy02/kudos-ios-polish/`, read only. Sources:
`WritingTextEditor.swift`, `WritingNativeTextView.swift`, `AO3Markup.swift`,
`AO3Client+Authors.swift::parseRichText/appendRuns/normalizedRuns`,
`AuthorProfileComponents.swift::AO3RichTextView`, and `WritingTextEditorTests.swift`.

The navigation title is the caller's `title`. The section header is
`ruleTitle ?? title`, with the last completed count: no count before the initial
async result; `0 words`, `1 word`, or locale-formatted `N words` afterwards.
It remains the last checkpoint's count during typing and in preview/recovery/error
states. There is no separate live count or saved timestamp line.

The two notes, verbatim, are **below the field**, not below the header:

- `Recovery copy on this device · Save from the work form` (right aligned).
- `AO3 supports only certain formatting. The toolbar adds formatting that AO3 can keep when you post.` (below the tag row).

Top actions in order: Preview (becomes Edit), Undo, Redo, More, Done. Undo/Redo
and the tag row are disabled during preview; More still offers plain paste.
iOS has no Format button. **Format is macOS-only**, grouped as `Text` and
`Blocks & links`, with labels `Name  <tag>`. Android follows iOS here.
More: `Paste as plain text`; only a caller with chapter actions adds
`Preview on AO3`; only one with a nonnil deleteName adds `Delete chapter`.

Tag row order is below. Labels are the literal `<tag>` above the lowercased name.
`a` prints `<a href>`. Coordinates are UTF-16. Ordinary pairs retain selection
on its original words; with no selection the caret is between the pair. Existing
HTML is untouched outside the selection, and subsequent tags nest inside it.

| Tag label | Name | Replacement / new selection |
|---|---|---|
| `<strong>` | Bold | `<strong>S</strong>`; S selected / caret inside |
| `<em>` | Italic | `<em>S</em>`; S selected / caret inside |
| `<u>` | Underline | `<u>S</u>`; S selected / caret inside |
| `<s>` | Strike | `<s>S</s>`; S selected / caret inside |
| `<sup>` | Superscript | `<sup>S</sup>`; S selected / caret inside |
| `<sub>` | Subscript | `<sub>S</sub>`; S selected / caret inside |
| `<small>` | Small | `<small>S</small>`; S selected / caret inside |
| `<code>` | Code | `<code>S</code>`; S selected / caret inside |
| `<p>` | Paragraph | `<p>S</p>`; S selected / caret inside |
| `<br>` | Line break | `<br>S`; S selected / caret after br |
| `<blockquote>` | Quote | `<blockquote>S</blockquote>`; S selected / caret inside |
| `<ul>` | Bullets | Nonblank trimmed lines become `<li>line</li>`, joined by newline, inside `<ul>\n…\n</ul>`; items selected. Empty/blank selection: `<ul>\n<li></li>\n</ul>`, caret inside li |
| `<ol>` | Numbers | Same as ul, using ol |
| `<h3>` | Heading | `<h3>S</h3>`; S selected / caret inside (not h1–h6) |
| `<hr>` | Divider | Preserve S, append hr on its own line. Add newline before unless selection end is at start or follows newline; add newline after unless next character is newline. Caret after the inserted replacement |
| `<a href>` | Link | Prompt first; valid HTTP/HTTPS/mailto only. `<a href="URL">S</a>`; S selected / caret in body. Escape &, quotes, <, > in URL. Invalid URL writes nothing |
| `<details>` | Spoiler | `<details><summary></summary>S</details>`; caret in empty summary, selected text becomes hidden body |

Native source comment, verbatim:

> A native, plain-text HTML buffer. Inserting tags never parses or normalizes
> existing markup; the platform text system owns selection, IME and undo.
>
> A keystroke costs O(1) here (docs/WRITING_EDITOR_ARCHITECTURE.md D8): an edit
> bumps `revision` and calls `onEdit`. The text itself is read only when a
> checkpoint asks for it with `takeCheckpoint()`. It used to be copied and
> compared on every keystroke, then handed to the form and the recovery store.

Preview commits composition, hides the keyboard, snapshots the raw buffer and
parses a body fragment off-main. It uses the existing iOS rich-text parser:
paragraph/div/blockquote/headings as paragraph blocks, li as bullet blocks;
bold/italic/safe links and br preserved, horizontal whitespace normalized within
runs. Other tags do not gain extra rendering features. Scripts' data nodes are
not displayed. Empty input produces a blank rendered preview. Loading shows a
spinner. Failure: `Couldn't render this HTML` / `Your text is unchanged. Tap Edit to go back to it.`
Ordered lists also show bullets; headings use paragraph styling; u/s/sup/sub and
code do not get special run attributes; hr/images have no rendered text, tables
have no grid and details have no collapsible control. The renderer's own default
`.body` font overrides the editor's outer serif modifier; Android uses body-sized
preview text and keeps the raw field serif. This follows the concrete renderer.
Only the still-active generation publishes. The native field stays mounted so
selection and undo survive; preview does not rewrite source or force a checkpoint.

Opening offers all differing earlier-session copies, newest first, excluding
this session. Heading: `Recover unfinished text?`. Multiple copies have `Local copy`
with saved dates. Message: `A recovery copy was saved on this device DATE.`
When originalDigest differs from the current form's digest, also:
`The text on the form has changed since this copy began. Review the copy before restoring it.`
The complete raw copy is reviewable/selectable. Actions: `Restore local copy`
(one undoable replacement then immediate checkpoint), `Keep form text` (dismiss,
no deletion), `Delete this local copy` (delete only the selected file; others remain).
No swipe/backdrop dismissal.

Checkpoint triggers: 1.5 seconds idle, 20 seconds from first pending edit,
Done, departure, Restore, any nonactive scene phase, memory warning. Only explicit
commands/Done/departure/Restore commit composition. Idle/lifecycle/memory leave
composing text alone. A changed revision takes one text snapshot; equal text skips
write/count. Sequence is scheduler.checkpointCount. Initial and checkpoint counts
run off-main; a result older than the newest started count is dropped.

**iOS code wins over “hands it back on Done”:** checkpoints update the parent
binding even before Done; leaving without Done commits composition and checkpoints
into the parent too. Done does the same then dismisses. Recovery is never an AO3
save; no copy is deleted on Done. Android provides an optional checkpoint callback
alongside Done so callers can preserve that behavior.

Alerts: `Editor error` / `OK`; write message
`Local recovery could not be saved: ERROR`; read message
`The local recovery copy could not be read: ERROR`; deletion uses the user-facing
error directly. Link alert `Insert link`, placeholder `https://example.com`, initial
`https://`, `Insert` / `Cancel`; invalid link goes to Editor error with
`Enter an HTTP, HTTPS, or mailto link.` Chapter-only alert:
`Delete “NAME”?` / `This will delete all comments on the chapter as well and cannot be undone.`
with `Delete on AO3` / `Cancel`; not built in this brief.

## Work log

Clean start on `android/agent-codex-3bd`. Brief overrides TASKS/commit/build rules.
Read the mandated writing sections, previous brief results/landing notes, project
onboarding/map/test/persistence guidance and actual Android symbols. No AO3 client
belongs to this editor. Implementation and test evidence recorded below as work proceeds.

## Android implementation

New files in `android/app/src/main/java/io/github/cidy02/kudos/writing/`:

- `WritingNativeTextField.kt`: the entire EditText adapter. Set/take text, changed
  checkpoint snapshots, selection-only insertion, platform Undo/Redo/plain paste,
  composition commit, appearance and preview hiding. `TextWatcher.afterTextChanged`
  increments a revision and calls the scheduler, without taking/comparing text.
  Programmatic replacement goes through Editable outside a batch, so Android's
  own UndoInputFilter records a separate operation. Restore uses the same path.
- `WritingMarkup.kt`: pure UTF-16 splice. Existing `CommentMarkupTag` supplies names,
  elements and order; p/br are writing-only additions. The older comment toolbar's
  insertion implementation differs from current iOS (lists/hr/details), so it is
  not called or changed. Writing uses the reference's actual splice semantics.
- `WritingEditorSession.kt`: one field/session, with 3bc's actual scheduler, writer,
  store and AO3 word counter. Initial/checkpoint counts run on Default, recovery
  reads/writes/deletes on 3bc's serial IO executor. The scheduler's sequence is used
  unchanged. Each count sets its sequence before launching; stale results cannot
  publish. The scope outlives Compose disposal until queued recovery writes finish,
  then cancels its remaining tasks. Explicit commands alone finish composition.
- `WritingBufferPreview.kt`: Jsoup body-fragment counterpart of iOS's limited rich
  preview parser (no Android rich-text renderer existed to reuse). Paragraph/list
  blocks and bold/italic/link runs, script DataNodes ignored, matching the source
  read above. Preview cannot serialize or alter HTML. Safe links are rendered
  visually, with no browser-launch action under this brief's no-AO3-contact rule;
  remote images are never loaded. This is a display-only preview, not rich mode.
- `WritingTextEditorScreen.kt`: caller text/title/optional rule title/account/target/
  field, Done and Back callbacks, optional checkpoint callback. Uses scopePalette,
  SectionRuleHeader, subject wash and ToolbarCircleButton. No new shared-component
  line heights. New text specifies line heights; tag controls have at least 48dp
  touch height, horizontal scrolling, and no fixed text height. Accessibility word
  count moves beneath the shared header to avoid its fixed one-line count clipping.
  The native field is mounted through preview and fills the remaining viewport.
  IME padding places the tag row above the keyboard; native EditText scrolls its
  selection into view. Status bars + 76dp precede the screen's header.
- `WritingEditorDemoScreen.kt`: debug-only local short/file entrances. No auth,
  repository or network client. No work-form integration.

Only existing `app/Routes.kt`, `app/AppNavHost.kt` and `ui/subject/DebugRoutes.kt`
were edited for destinations/chrome. Neither Account nor WritingDraftsScreen nor
WritingWorkDestination changed: draft taps continue opening the browser.

Lifecycle equivalents: a LifecycleEventObserver fires on **ON_PAUSE and ON_STOP**,
matching inactive/background scene phases and §8.1. Application-context
**ComponentCallbacks2.onTrimMemory(level >= TRIM_MEMORY_RUNNING_LOW)** and
**onLowMemory()** fire memory checkpoints, matching iOS's memory notification.
Neither callback commits composing text. Callbacks are registered only while the
editor is mounted and unregistered on disposal. Android does not provide the iOS
beginBackgroundTask assertion here; queued in-process IO survives screen disposal,
not guaranteed OS process death. Verify suspension/process-death behavior on device.

The recovery sheet uses copiesOnOpen directly, selectable raw text, saved-date
selection for multiple copies, digest warning calculated off-main and the three
reference actions. No swipe/backdrop dismissal. Restore is undoable and immediately
checkpoints. Keep leaves files intact; Delete calls the existing deleteCopy with
only the selected Copy. Errors use the reference's alert title/action/prefixes,
with Android's local exception description for ERROR.

Left out: **Preview on AO3 and Delete chapter**, their chapter-action callbacks and
chapter-delete confirmation. They belong to the owning screens. No rich mode,
mode bridge, Save/Post, work form, network request, new recovery writer/store,
backup-format change or Room schema change.

## Widget choice and the unmeasured native cost

Chosen: **platform EditText in AndroidView**, owned once per field session. It
avoids a String/TextFieldValue snapshot being emitted to Compose at every edit,
and leaves selection, IME and undo to Android. A state-based Compose field using
TextFieldState could also avoid value callbacks, but brings a second text/undo
system; the platform adapter is closer to iOS and easier to replace as one file.
Legacy value-based Compose fields would expose whole-buffer values on each edit.
No dependency or custom undo stack was added. CodeMirror remains D2's fallback if
Claude's measurements fail; it is not part of this HTML-only patch.

Read the installed SDK's **android-37.0** source, not a benchmark:
`SpannableStringBuilder.replace/change/moveGapTo`,
`Editor.UndoInputFilter.handleEdit/recordEdit` and `EditOperation.forceMergeWith`,
`TextView.handleTextChanged/updateAfterEdit/useDynamicLayout`.
The platform mutates its gap buffer (gap movement/growth may move large spans),
records old/new *edited ranges* for undo, merges adjacent undo strings, updates
selection/IME/spans, relayouts affected text and scrolls/invalidates the caret.
A large paragraph, gap movement or growing undo group can cost more than the edit;
forced undo merges can copy the complete buffer. IME/extracted text, spell checking
and accessibility may add platform work. There is **no universal O(1) claim for
Android itself on a 510,000-character field**. Application callbacks never copy,
compare, encode, count or write the chapter per keystroke. Snapshot/equality work
happens at changed checkpoints; toolbar commands may copy the selected span.

**No B1/B6 result is claimed.** Claude must measure Scripts/make-writing-fixture.py's
510,000-character chapter on a Pixel 6a class device: B1 ≤16ms p95/no >33ms hitch,
B6 ≤300ms. Also inspect B3 snapshot/equality cost (canonical Unicode comparison
adds normalization work), B5 recovery time, typing at the very end with the IME,
large selections, composing Japanese/Chinese, Undo/Redo after Restore, and memory.
The EditText file is the replacement boundary if the gate fails.

## Debug routes

Use the existing fixture-only network block (`--ez kudosDemoLibrary true`) so
unrelated application startup work also stays offline. No sign-in/demo-signed-in
extra is needed. Debug builds only:

- `--es kudosDebugRoute nav:writing-editor-demo`: original filler and markup,
  Chapter text / Chapter 13. Seeds one differing E1 copy under the demo field key
  using a fixed demo UUID, if that seed file is absent, so opening shows recovery.
  Previous real demo checkpoints can add copies on later openings.
- `--es kudosDebugRoute nav:writing-editor-fixture`: reads exactly
  **`/sdcard/Android/data/io.github.cidy02.kudos/files/writing-editor-fixture.html`**
  (external app files directory). Missing/unreadable file shows its local error;
  no filler fallback or network request.

Claude can push the generated fixture with:

```sh
adb shell mkdir -p /sdcard/Android/data/io.github.cidy02.kudos/files
adb push /path/to/generated/chapter.html /sdcard/Android/data/io.github.cidy02.kudos/files/writing-editor-fixture.html
adb shell am force-stop io.github.cidy02.kudos
adb shell am start -n io.github.cidy02.kudos/.MainActivity --ez kudosDemoLibrary true --es kudosDebugRoute nav:writing-editor-fixture
```

For the short route substitute `nav:writing-editor-demo`. Routes are registered
only in BuildConfig.DEBUG, and the demo composable itself also checks DEBUG.

## Offline tests written; not executed

**36 @Test cases across five new files** in `src/test/java/io/github/cidy02/kudos/writing/`:

- `WritingTextEditorTests`: exact reference tag/link case, all 17 tags with empty
  and Unicode selections at start/end/inside markup, nested tags, divider newline
  context and preservation, lists/blank lines, unsafe URLs/unknown tags/invalid
  ranges (including split surrogate refusal), rich preview content/empty state,
  and preview generation fencing.
- `WritingNativeTextFieldTests`: real attached EditText source/appearance/selection,
  native Undo/Redo, undoable Restore, Japanese composing-text commit, idle snapshot
  preserving composition, changed-back checkpoint suppression and distinct tag
  undo steps. Uses Application rather than KudosApplication, so app startup does
  not install unrelated networking. Native graphics enabled.
- `WritingEditorSessionTests`: virtual-clock 1,500ms/20,000ms schedules, Done force,
  unchanged/typed-then-deleted suppression, out-of-order counts, differing/equal
  recovery opening, Restore and selected-file-only Delete, failure wording,
  leave-without-Done parent checkpoint and write completion. Also drives a real
  checkpoint through the existing writer/E1 store and inspects the complete file.
  Constructor/screen-signature assertions enforce absence of client/auth/form
  dependencies. IO jobs are joined instead of using sleeps.
- `WritingTextEditorScreenTest`: chrome and raw Done delivery, exact notes,
  preview retaining field/selection and disabling Undo/Redo, recovery words/
  warning/actions/undo, Keep preserving its file, overflow omissions/error alert,
  Light/Dark/Sepia/OLED at double font scale, initial singular/plural/empty word
  counts, ON_PAUSE/ON_STOP/trim-memory checkpoint triggers without committing IME,
  and failed-preview words. Tall `w411dp-h1600dp` window, 15-second waits, and
  `@GraphicsMode(NATIVE)` for text assertions. Uses a callback shell host, not the
  full application/network stack.
- `WritingEditorRoutesTest`: both nav launch strings, title and pushed/tab-hidden
  metadata. Actual AppNavHost wiring is source-inspected, not runtime verified.

All six applicable iOS editor/markup/preview test names are retained:
`tagInsertionPreservesSelectedMarkupAndEscapesLinkAttributes`,
`nativeEditorPreservesSourceSelectionUndoAndRecovery`,
`aTagNestsInsideAnEnclosingOne`, `selectionsAtTheBufferEdgesAndACaret`,
`thePreviewParsesTheBufferAsAO3HTML`, `onlyTheCurrentPreviewParsePublishes`.
A static name comparison found none missing. Recovery-only names remain in 3bc's
existing suites and were not duplicated.

## Verification and handoff

Performed: source/API review, SDK source inspection for native undo/IME/layout,
`javap` checks of the installed Android public methods, cached Material3 bottom
sheet signature and mirrored Undo/Redo icon classes, static iOS test-name/count
comparison, tracked diff whitespace check and new-file whitespace scan.
No Gradle, Xcode, Kotlin compilation, test execution, emulator, device measurement
or visual inspection. **No compilation, passing-test, visual-parity, typing-latency
or process-death claim is made.**

Claude must compile Android and run the full test/lint gate, especially all five
new suites and 3bc's checkpoint/recovery/word-count suites, existing WritingDrafts,
account destinations, navigation and demo network-block regressions. Every new
behavioral assertion above still needs that run. Then inspect both debug routes
with the local network block, all four themes, accessibility font scale, keyboard
open/closed, long-chapter end typing, selection/Undo/Redo/plain paste/Restore,
link alert and invalid URL, empty/failed preview, multiple recovery copies,
background/foreground and memory callbacks. Screenshot approval remains with the
human/Claude. Device B1/B6 and suspension/process-death evidence are required before
accepting the native widget; fixture file-reading is demo setup, separate from
mounting the editor with an already-owned form string for B6.

No commit, push, branch switch, TASKS.md edit, sign-in, AO3 contact, iOS edit,
backup-format/schema modification, stub, helper-script file or .orig file.
Changes remain uncommitted in this worktree for Claude to build/test/commit.

**Open questions: none.** Outstanding evidence is compilation/tests, screenshots,
IME/undo/lifecycle checks and device budgets, not an unanswered product decision.

**Landing note (Claude, 2026-10-07).** Landed with three changes. Gate green (1,830 tests).
Nothing in the app opens the editor yet: two debug routes only. A draft tap still opens the
browser.

**Read against iOS:** the tag list and its order, every insertion rule (the divider's line
rule, lists, the spoiler, link escaping), the recovery sheet's words and three actions, the
checkpoint triggers, Done and leaving.

**Changed on landing.**

1. **The preview dropped text typed outside a block tag.** With `<p>one</p>` followed by a
   loose line, Preview showed only "one". iOS's preview does the same: its parser
   (`AO3Client.parseRichText`) keeps only block elements once the text has one. Codex had
   copied that faithfully. Both apps now put each stretch of loose text into a paragraph of
   its own before parsing, as AO3 does when it posts (`wrapLoose` here, `wrapLooseText` in
   iOS's `WritingBufferPreview`, T-358). One new test with the same cases on both; it fails
   with the fix switched off.
2. **The preview is a lazy list.** A full-length chapter is over a thousand paragraphs; drawn
   all at once it froze the screen (231 and 93 skipped frames on the emulator; none after).
3. **The recovery sheet shows the copy a line at a time.** One text block holding a whole
   chapter froze the sheet's opening (a 243-frame stall on the emulator; gone after).

**The widget's measurement, as far as an emulator can take it.** With
`Scripts/make-writing-fixture.py`'s 510,000-character chapter pushed to the app's files:

- It opens, counts 91,473 words, jumps to the end, takes typing at the start and at the end,
  inserts a tag, checkpoints (a 519,031-byte recovery copy), previews and closes.
- Frame times while typing 36 characters (`dumpsys gfxinfo`), median / 90th / 95th / 99th:
  two lines of text 129 / 150 / 200 / 200 ms; the chapter near its start 125 / 200 / 200 /
  250 ms; the chapter at its end 133 / 150 / 200 / 200 ms. **The chapter's length adds
  nothing a keystroke can feel here.** The numbers themselves are this emulator's floor on a
  busy Mac (every frame of every screen is late on it), so they say nothing about B1's 16 ms.
- Opening: the chapter's first frame cost about 30 more skipped frames than two lines of text
  (80 against 50). That is the platform laying out the whole chapter once. It is the figure
  B6 (300 ms) is about, and it needs a phone.

**Still owed before the native text field is accepted (design document §9.2, OD5):** B1 and
B6 on a Pixel 6a class phone; a kill of the app mid-typing and the recovery after it;
Japanese or Chinese composing text on a real keyboard. The owner's Pixel was not attached.

Seen on the emulator in airplane mode, Dark and Light: the editor with its header, word
count, both notes and the tag bar above the keyboard; typing, a tag at the caret, Undo and
Redo; the preview; the recovery sheet with one copy and with two; Restore (undoable), Keep,
Done (the copy stays, as on iOS); the More menu ("Paste as plain text" only). Not seen: the
link alert, Delete this local copy, Sepia, OLED, large text (all in tests), a low-memory
checkpoint.

Left for polish (P3): a strip of page colour shows under the tag bar; the recovery sheet is
taller than its content and its three actions are plain text buttons.

For emulator scripts: `adb shell input text` drops and repeats keys when the Mac's load is
high (it typed "HHell" for "Hello" at a load of 70; correct at 12). The field must be tapped
first. Do not name a shell variable `P` beside `tapshot.sh`'s helpers: they overwrite it.
