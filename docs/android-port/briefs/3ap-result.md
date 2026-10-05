# Brief 3ap result: reader selection menu

**Landing note (Claude, 2026-10-05).** Landed with one change that only a device could show.
As written, the wrapper added Highlight and Add Note only when it found the system's Copy item
by `android.R.id.copy`; the WebView's Copy has Chromium's own id, so on the emulator the real
menu never got them. The rule is now "the native menu holds something". Gate green (1,501
tests). Seen on the emulator: selecting a word shows Copy, Share, Select all, Read aloud, and
under the menu's overflow Highlight and Add Note; Highlight opens the existing dialog with the
selected word and stores the highlight. Not tapped: Add Note (the same call with one flag).
**The two pills are still in the reader's menu**; "Exact pill removal list" below is the next
step. Where this file says the owner authorized the wrapper, it was Claude's answer (it is in
`DECISIONS.md`).

Checking this found an older fault, fixed in the same landing: **a highlight made from a
selection was saved and never shown.** It was stored with a bare Readium locator, and the page
draws (and goes to) only a locator in this reader's envelope. It is now stored in the
envelope, as bookmarks are, and is drawn at once. Highlights stored bare by earlier builds
stay undrawn: they cannot be told from an iPhone's.

Status: native callback wrapper implemented following the owner's clarification. **Both selection pills remain pending emulator review**, as requested. This work stays on `android/agent-codex-3ap`, uncommitted. Compilation and runtime behavior still need Claude's build/test run.

## What was built

- `reader/readium/ReaderSelectionContainer.kt`: a small `FrameLayout` around the existing `FragmentContainerView`. Its typed `startActionModeForChild` wraps only `TYPE_FLOATING` modes whose originating view is a `WebView` in this navigator container. Other types/origins and the legacy untyped (`TYPE_PRIMARY`) overload pass through unchanged. Android's cached SDK `ViewGroup` implementation confirms that the original descendant view is forwarded up the parent chain.
- `ReaderSelectionActionModeCallback` delegates native create/prepare/click/destroy and preserves the original create/click results. After successful creation, and after every preparation, it uses `findItem` to add **Highlight**, then **Add Note**, with unique resource IDs in `res/values/ids.xml`. The Android SDK's menu category ordering places `CATEGORY_SYSTEM` last; these items use its final two ordering slots, after the native items. No Fix Pronunciation action is added.
- A native Copy item must exist before annotations are offered: a floating WebView caret/insertion menu has no range to annotate. A rejected native creation adds nothing. Preparation re-adds the two actions after a native menu rebuild, without duplicating them; loss of the native Copy item removes any stale annotation entries.
- Native clicks go straight to the original callback, including Copy, Share and installed text-processing actions. `onGetContentRect` delegates to the original `Callback2`; when the original is a plain `Callback`, Android's default view-bounds behavior is used.
- Optional menu-addition/dispatch failures disable the additions, remove partial custom items where possible and leave native callback handling available. The container also retries startup with the original callback if starting the wrapped mode throws a `RuntimeException`.
- `ReadiumNavigatorHost` now constructs that outer container and retains the **same** inner `FragmentContainerView` ID and fragment transaction/lifecycle. Both callbacks use `rememberUpdatedState`, like the existing host callbacks. **Readium's `selectionActionModeCallback` is not set.** No fragment configuration, preference, restoration or decoration changes.
- `ReaderScreen.ReaderReading.annotateSelection(asNote, onComplete)` was moved outside the chrome's `AnimatedVisibility` so native actions work with chrome hidden. Both native actions and both retained pills call it. The selection locator/text/progression/spine snapshot and existing `AnnotateDialog` → `ReaderViewModel.addHighlight` recording path are unchanged. The native callback supplies completion so the mode finishes **after** Readium's asynchronous current-selection read and `clearSelection()`, not before the range can be captured. Repeated custom clicks while that read is pending do not dispatch twice; completion does not finish a mode already destroyed.
- `ReaderFanMenu.kt` and `ReaderFanMenuTest.kt` only change their obsolete comments. Pill contents, appearance and existing assertions are retained for this pass.

## Reference and existing recording path

Read-only iOS reference: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Features/ReaderReadium/`.

- `ReadiumBook.selectionEditingActions` is `EditingAction.defaultActions` followed by **Highlight**, **Add Note**, then **Fix Pronunciation**. The cached Swift toolkit's `Sources/Navigator/EditingAction.swift` defines the defaults as Copy, Share, Look Up, Translate (Look Up can surface Search Web too). Thus the custom additions follow the defaults, with Highlight before Add Note. Fix Pronunciation is an additional iOS action outside this brief.
- `ReaderHighlightHostController` forwards the custom selectors to `ReadiumReaderView.createAnnotationFromSelection(withNote:)`. That method reads the current selection's locator and `locator.text.highlight`, then clears the selection. New iOS marks are highlights even when Add Note opens their editor. Highlight creates immediately and offers a colour bar; repeating the same colour on an existing exact-locator mark deletes it, a different colour recolours it, and Add Note opens its editor.
- Android `ReaderScreen`'s local `annotateSelection(asNote)` reads `ReadiumNavigatorController.currentSelection()`, snapshots `selection.locator.toJSON()` and `locator.text.highlight`, progression and the live spine index into `AnnotateDialogState`, then calls `clearSelection()`. Dialog confirmation calls `ReaderViewModel.addHighlight`, which calls the existing `AnnotationRepository.addOrRecolorHighlight`. Android currently asks for confirmation/colour and stores Add Note with kind `note`. This brief expressly requires reusing that recording path without changing storage; those pre-existing creation differences have not been ported.
- `READIUM_MIGRATION_NOTES.md` is absent in both worktrees. The concrete iOS reader code and cached toolkit APIs were read instead; no iOS files were changed.

## Exact Readium 3.3.0 limitation

`android/gradle/libs.versions.toml` pins `readium = "3.3.0"`. Inspected the locally cached navigator AAR and its extracted `classes.jar`, using `jar` and `javap -c -p`; no downloads or network access:

`~/.gradle/caches/modules-2/files-2.1/org.readium.kotlin-toolkit/readium-navigator/3.3.0/162dd7fdee9e61a10441e5262792ec0d76b6011e/readium-navigator-3.3.0.aar`

The supported configuration property really exists:

```kotlin
EpubNavigatorFragment.Configuration.selectionActionModeCallback: ActionMode.Callback?
```

It **can carry custom actions**, but it is a replacement callback, not an additive hook that preserves the system actions:

1. `ReadiumNavigatorHost` creates `EpubNavigatorFragment.Configuration` and currently only configures fonts. `EpubNavigatorFragment.WebViewListener.getSelectionActionModeCallback()` returns that configuration's callback directly.
2. In `R2BasicWebView.startActionMode(callback)`, a non-null configured callback bypasses the WebView callback and is passed directly to `parent.startActionModeForChild`.
3. In `R2BasicWebView.startActionMode(callback, type)`, the configured callback is wrapped in `Callback2Wrapper`. Its `onCreateActionMode`, `onPrepareActionMode`, `onActionItemClicked` and `onDestroyActionMode` delegate exclusively to the configured callback. Only `onGetContentRect` delegates to the original WebView `Callback2`.
4. `BaseActionModeCallback` supplies no default menu: prepare/click return false and destroy is empty; applications must implement creation. There is no factory receiving the original WebView callback in `Configuration`.

Consequently, simply setting this property and adding Highlight/Add Note would replace the native menu creation and dispatch, losing the existing system actions. Returning false for an unhandled Copy item does not restore the original callback. Rebuilding Copy/Share/etc. ourselves would not preserve the system's own actions, including installed text-processing actions. A native Android parent callback wrapper could delegate to the original WebView callback and append items, but that would depart from the brief's requirement to use the toolkit's own customization mechanism.

This is narrower than saying “Readium cannot carry a custom action”: it can, but its supported hook cannot satisfy **append to the system's own menu while retaining Copy and the rest**. The owner subsequently authorized the native parent callback wrapper, explicitly prohibited setting this property, and instructed that the pills remain until emulator review. That clarification supersedes the initial brief's toolkit-only mechanism and pill-removal timing; the iOS code still determines the two labels and their ordering.

## Tapping an existing highlight: differences, not implemented

| Action | iOS reference | Android today |
|---|---|---|
| Tap a mark on the page | `ReadiumBook.observeHighlightTaps` registers decoration interactions; `ReadiumReaderView.openHighlight` opens `ReaderNoteEditor`. | `ReadiumNavigatorController.applyHighlightDecorations` draws the highlights, but neither it nor `ReadiumNavigatorHost` registers a decoration interaction listener. There is no annotation editor dispatch on a highlight tap. Ordinary unhandled content taps toggle the chrome through `InputListener.onTap`; exact event consumption needs a device check. |
| Edit/add note | `ReaderNoteEditor` opens for any tapped highlight, titled Add Note or Edit Note. | Contents' `onSelectAnnotation` opens the existing note editor only for kind `note` or nonblank note text. A plain highlight without a note only navigates to its locator. |
| Change colour | `ReaderNoteEditor` has a Colour picker, and newly created highlights also offer the floating colour bar. | The existing note editor has no colour control. Colour is chosen in the creation dialog; reselecting a passage can reach the existing repository's recolour path. |
| Delete | `ReaderNoteEditor` offers Delete Highlight. | No deletion action from a page tap. The note editor offers Delete and the Contents list has an annotation-delete callback, both using the existing confirmation/delete path. |

No changes to annotation matching, storage, rendering, sync, backup format, Room schema, fan-menu appearance or highlight-tap behavior were made.

## Verification and handoff

Read and traced the real host configuration, selection/controller APIs, reader dialog, view-model recording method, repository, fan-menu tests and iOS reference. Inspected the cached Android SDK's actual `ActionMode.Callback2`, both `ViewGroup.startActionModeForChild` overloads and native `MenuBuilder` category order. No Gradle/Xcode builds or tests run, as instructed; no sign-in, network/AO3 access, commits, pushes, branch switches or `TASKS.md` edits. No helper scripts, stub files or `.orig` files were created.

`ReaderSelectionActionModeCallbackTest` adds eleven local Robolectric unit tests with a recording original callback, recording action mode and fake `Menu`/`MenuItem` proxies. **No WebView is constructed.** Tests cover labels/order, prepare-time rebuilding, no duplicates, both annotation entry points and finish order, asynchronous completion and duplicate taps, native clicks/return values, destroy, content-rectangle delegation and plain-callback fallback, type/origin filtering, no-range insertion menus, rejected creation, completion after destroy, partial insertion failure and custom dispatch failure. These tests are written but **have not been compiled or run**. The existing `ReaderFanMenuTest` and `ReaderFanMenuUiTest` continue to require the retained pills.

Claude should run the offline Android compilation/test gate, including the new suite and the retained fan-menu suites. Checks run here: `git diff --check` passed; whitespace checks on all four new files passed; `ids.xml` parsed successfully with Python's standard XML parser. The app's actual Gradle namespace and cached SDK resource IDs (`copy`, `paste`, `shareText`) were confirmed against the references used. These checks do not prove Kotlin compilation.

Only a device/emulator can prove the **real WebView's menu** and event/lifecycle behavior: use a local EPUB, long-press and adjust the selected range, verify native items remain and the two custom labels/order appear on creation and preparation, exercise Copy, Highlight and Add Note with chrome hidden, cancel/save the existing annotation dialog, and reopen the book to verify its record/decoration. Confirm the toolbar stays anchored, selection clears after capture, and font/preference changes or navigation do not leave stale toolbar actions. The unit filter uses a boolean origin rather than a WebView; it cannot prove the originating WebView reaches this container on the real navigator's parent chain. The native Copy-item gate likewise needs confirmation against the actual WebView menu. Startup retry with the original callback needs an emulator check; unit tests cover callback-level failures only. No visual or runtime success is claimed.

## Exact pill removal list after emulator approval

Keep the new wrapper/host callbacks, resource IDs and shared `annotateSelection` function. Remove **only** the fallback fan entries and their plumbing/assertions:

1. `reader/ReaderFanMenu.kt`: remove the fallback comment and the two `add(ReaderFanMenuPill(...))` blocks with IDs `highlightSelection` and `noteSelection` (currently lines 121–131). Remove `onHighlightSelection` and `onNoteSelection` from the **`readerFanPills` builder's** parameters (lines 95–96), and remove its unused `BorderColor` and `Edit` icon imports. Do not change the glass composables or other pills.
2. `reader/ReaderScreen.kt`: remove those two named arguments from the **`readerFanPills(...)` call** (currently lines 474–475). Keep `ReadiumNavigatorHost`'s `onHighlightSelection` / `onAddNoteSelection` arguments (lines 369–370) and `annotateSelection` (line 330).
3. `reader/ReaderFanMenuTest.kt`: remove those two builder callback arguments in the `pills` helper (lines 53–54). In `iosPillsKeepTheirOrderAndDispatchTheExistingDestinations`, remove the IDs `highlightSelection` / `noteSelection`, titles `Highlight selection` / `Add note to selection`, obsolete fallback comment, and `highlight` / `note` dispatch expectations (lines 61–72). In `anImportWithoutAo3IdentityOmitsCommentsAndKudosButKeepsLocalActions`, remove the two IDs from the expected import list (line 79). Retain the other destination assertions.
4. `reader/ReaderFanMenuUiTest.kt`: in `commentsAndRetainedSelectionPillsDispatchAndDisabledActionsCannotBeTapped`, remove the two builder callback arguments (lines 46–47), the two selection-pill `performClick` calls (lines 56–57), and their `close:false` plus `highlight` / `note` expectations (lines 59–60). Rename the test to describe Comments and disabled actions. Keep its Find/Kudos disabled assertions and Comments dispatch assertion.
5. Update the menu description in `docs/android-port/DECISIONS.md` and the selection-pill status in `briefs/3ao-result.md` when removal lands, so the retained-pills explanation no longer describes the current menu. Do not remove the new `ReaderSelectionActionModeCallbackTest` coverage.

Line numbers are from this uncommitted pass; the named functions/IDs identify the exact deletion sites if they move.
