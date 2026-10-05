# Brief 3ar result: highlight taps and reader pills

**Landing note (Claude, 2026-10-05).** Landed as written; it compiled and passed first time.
Gate green (1,507 tests). Seen on the emulator with a real page: a tap on a highlighted word
opens the editor ("Add Note", the passage, a note field, six colours) and does not toggle the
reader's controls; choosing Blue and typing a note, then Done, stored both and the word is
drawn blue; a tap elsewhere toggles the controls as before; the reader's menu holds iOS's
pills only. Checked later the same day: Underline is drawn as an underline; Cancel after a
colour change keeps the colour (it is saved at once, as on iOS); a row in the reader's
Highlights list opens the same editor; Delete Highlight asks first, Cancel keeps it, Delete
removes it from the page and leaves a deletion record for sync.

Status: implementation complete; compilation, tests and device review pending on `android/agent-codex-3ar`, only in this worktree. No commits, pushes, branch switches, TASKS edits, sign-in, AO3 traffic or build/test execution.

## Reference and API inspection

Read `3ap-result.md`, including Claude’s landing note: the native selection wrapper now checks that the native menu holds something, and creation stores an Android locator envelope so the highlight draws. Preserve both fixes and the wrapper.

Read-only iOS reference: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Features/ReaderReadium/ReadiumBook.swift` (`observeHighlightTaps`), `ReadiumReaderView.swift` (`openHighlight`, `goToAnnotation`) and `ReaderNoteEditor.swift`. iOS opens the editor for every highlight from the page and Contents, titles it Add Note / Edit Note, shows Highlighted / Note / Colour, saves colour immediately, trims the note on Done, and offers Cancel / Delete Highlight. Android’s stored note kind remains supported alongside highlights; no storage migration.

Readium is pinned to 3.3.0 in `android/gradle/libs.versions.toml`. Inspected the cached `readium-navigator-3.3.0.aar` with `javap`: `DecorableNavigator.addDecorationListener(String, Listener)`, `removeDecorationListener(Listener)` and `Listener.onDecorationActivated(OnActivatedEvent): Boolean`. The event carries decoration, group, rect and point. The navigator stops dispatch at the first listener returning true.

## Verification still required

Claude must compile and run the Android tests; Gradle/Xcode are prohibited in this pass. Device/emulator verification with a local EPUB must prove a real page delivers decoration taps, highlights open without toggling chrome, ordinary taps still toggle chrome, and sheet colours/layout/focus are correct. No visual/runtime success is claimed.

## Implemented changes

Removed exactly items 1–4 of 3ap’s pill removal list, checked against the current builder, call site and tests. Native selection callbacks and the shared selection recording function remain.

`ReadiumNavigatorHost` registers `ReaderHighlightDecorationListener` for `highlights` and removes it alongside the input listener. It uses the current Compose callback. Highlight-group events return true even for stale ids; `ReaderViewModel.openHighlight` resolves only live highlights/notes, leaving unknown ids alone. Cached `assets/readium/scripts/readium-reflowable.js` calls `onDecorationActivated(...) || onTap(...)`: true prevents chrome dispatch without time-based tap suppression.

The editor is now `ReaderNoteEditor` in the reader’s existing ModalBottomSheet / SettingsSection / SettingsActionRow / ToolbarCircleButton components. It uses reader theme tokens, full passage text, a focused note field, six existing annotation swatches (Underline drawn as a rule), and iOS’s labels. Colour saves immediately; Cancel discards only the note draft, just as iOS. Done trims the note. Delete closes the editor and uses the existing confirmation and `deleteAnnotation` tombstone path. Contents navigates, hides its sheet, then opens this same editor for plain highlights and stored note marks; bookmarks still only navigate.

`AnnotationRepository.addOrRecolorHighlight(id, color)` is an identity-based overload of the existing recolour entry point. The selection overload has no annotation id and can match a different duplicate passage or create a record; it is unsuitable for an existing-mark editor. The overload loads by id and calls the existing `saveAnnotation` (timestamp/sync path), preserving the latest note and other fields, and ignoring missing, pending-delete or bookmark records. Note updates still use `updateNote`; deletion still uses `deleteAnnotation`. No schema or backup changes.

The iOS picker includes Underline. Android’s old decoration builder rendered it as yellow, so the builder now uses the cached toolkit’s actual `Decoration.Style.Underline(Int, Boolean)` for that existing colour. Other decoration colours retain their existing mapping. iOS code wins over the older Android fallback editor’s Edit note / Save / Delete words and note-only Contents gate. No conflict with this brief was found in the requested iOS behaviour.


The ViewModel serializes recolour, note and confirmed-delete writes with a coroutine mutex. Room reads suspend, so two otherwise independent read/copy/save calls could lose a colour when Done follows it immediately. Serialization preserves both edits and prevents the reader’s queued writes from racing its own delete. The editor resolves `editingAnnotationId` against the live annotation flow; removal clears the editor id, and recolouring does not replace the note draft with an old snapshot.

## Tests written, not run

`ReaderFanMenuTest` now expects only Contents, Bookmarks & Highlights, Find in Work, Comments (with AO3 identity), and Themes & Settings. `ReaderFanMenuUiTest.commentsDispatchAndDisabledActionsCannotBeTapped` keeps Comments dispatch and disabled Find/Kudos assertions. No selection-pill entries, callbacks or assertions remain in these files. Native selection tests remain untouched.

Added six tests in `ReaderHighlightEditorTest`:

1. A real Readium `OnActivatedEvent` for a known annotation opens `editingAnnotationId` for that id and returns consumed, so the recording ordinary-tap fallback does not toggle chrome.
2. Unknown ids leave editor state alone and consume the highlight-group event without a chrome toggle; another group is unhandled.
3. Contents’ shared `openHighlight` entry opens plain highlights and stored note marks; bookmarks do not open the editor.
4. The actual `ReaderNoteEditor` controls route Blue, trimmed Done and confirmed Delete to the real ViewModel/repository, each once for the same id. Recording DAO reads/writes/deletes assert the repository operations; deletion also verifies the real signed `readingAnnotation` tombstone. Cancel writes nothing and discards the draft. The test renders with Sepia reader tokens, but it does not assert visual correctness.
5. A deliberately suspended colour read followed immediately by note save verifies that the note waits, then both fields survive. Each repository operation reads/saves the same id once.
6. Recolour targets the selected id even beside an identical passage, and never inserts a missing/deleted id.

The recording boundary is the DAO under the real `AnnotationRepository`, not a mocked repository: colour/note each produce exactly one id lookup and one save, confirmed deletion one id lookup/delete and one signed tombstone. No WebView or navigator Fragment is constructed in these tests. The tap fallback models the inspected toolkit script’s short-circuit dispatch; it cannot prove real DOM hit-testing or lifecycle registration.

## Checks and handoff

`git diff --check` passed. New source/test/report files also passed explicit trailing-whitespace and final-newline checks. Verified new toolkit signatures from the cached 3.3.0 artifact, including the underline constructor, and the existing Compose/Room/repository symbols from code. These are static checks, **not Kotlin compilation or passing tests**.

Claude should run the Android compile/test gate, specifically `ReaderHighlightEditorTest`, `ReaderFanMenuTest`, `ReaderFanMenuUiTest`, unchanged `ReaderSelectionActionModeCallbackTest`, and existing `AnnotationTombstoneTest`. No Gradle or Xcode command was run here.

On an emulator/device with a local EPUB: create a highlight from the native selection menu; tap a drawn highlight with chrome hidden and visible; verify Add Note / Edit Note opens for that mark while chrome stays put. Tap elsewhere to verify the existing chrome toggle. Exercise Colour (including Underline), Done with an added/edited/cleared note, Cancel after a colour change, and Delete Highlight with confirm/cancel and the existing confirmation preference. Reopen the book to verify persistence. Select a plain highlight and a note from Contents, and a bookmark; check that only marks open the shared editor. Verify full passage text, keyboard/focus, sheet scrolling and all four reader themes, plus listener behaviour after leaving/reopening the reader and changing preferences. **Only this device run can prove the real page delivers the highlight tap.**

Scope: Android reader implementation and tests plus this result file only. The iOS worktree, native selection wrapper/IDs, locator storage envelope, Room entities/schema, backup format and TASKS.md are unchanged. No commits, pushes, branch switches, sign-in or network/AO3 requests. Temporary artifact-inspection jars were removed; no helper scripts, stub source files or `.orig` files remain. Item 5 of 3ap’s historical removal list (updating DECISIONS/3ao’s landing status) was outside the requested items 1–4; those historical notes can be updated by Claude when this pass lands.
