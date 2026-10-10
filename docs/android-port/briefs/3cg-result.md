# Result of brief 3cg: the comments model, one captured context

Written and landed by Claude on 2026-10-10 (Codex, for whom the brief was written, is out until
10-14). **Not reviewed by anyone else yet: a review by Codex is owed.** Gate: 2,538 tests.
Never run against AO3.

## What changed

`comments/CommentsViewModel.kt`

- **A composer context** (`Composer`: target, viewer, reply id, edit), captured when a composer
  opens. `saveDraft`, `submitComment` and its completion, and both draft lookups use it and never
  "what is on screen now". A lookup or a send that comes back and finds another composer (or
  none) is over. This replaces the count kept since A28.
- **The viewer is a session** (`Viewer`: the published name and the session's count, from a new
  `sessionGeneration` lambda). `syncViewer()` is iOS's `syncAuthenticationContext`: what was
  typed is saved as the reader who typed it, the composer closes, the chapter list and the
  chosen chapter go, and the screen is read again. Called by the screen when either value
  changes, and by every entry point that acts for a viewer.
- **The comment put first** on Chapter Comments: chosen against every id the page draws, at any
  depth, not only its top level; and `present` prepends nothing whose own id the page draws.
- A chapter or scope the reader chose stands against the chapter the reader's button asked for
  when that button's index answers late.
- **Found while there:** a saved **edit** cleared the new comment waiting in the work's draft
  slot (an edit has no slot; iOS clears only `if editTarget == nil`). Fixed, with a test.

`comments/CommentsScreen.kt`: takes `sessionGeneration`; calls `syncViewer()` when the name or
the count changes; the reader's-button effect is keyed by both, so an index asked for as a guest
does not open a chapter after sign-in; the sheet's note is about the composer's own target.
`app/AppNavHost.kt`: hands over `authRepository.generation`.

## What iOS does, and where Android differs

| Case | iOS (`Features/Comments/CommentsModel.swift`) | Android now |
| --- | --- | --- |
| Target changes while a composer is open | `composerContext` is captured at `startComposer` (`:970`) and `resetForContextChange` (`:295`) does not touch it: the composer keeps its target. | The same. |
| Target changes while a new comment's draft is still being read | Cannot happen: `startComposer` is not suspended. | **The composer does not open.** The reader tapped Write and then chose another chapter; opening a sheet bound to the page they left would post there. They tap Write again. |
| The reader changes | `syncAuthenticationContext` (`:232`): saves the draft under the old identity, closes the composer, clears everything, scope `.all`, drops the pending focus. | The same, except that **Android asks again for what the route named** (the Inbox's thread or chapter) instead of the work's first page: a session restored a moment after the screen opened would otherwise lose it. |
| A send answers after the reader changed | `guard isCurrent(expected, auth)` (`:1092`) returns before the draft is cleared: the posted text stays as a draft. | The screen is left alone, but **the draft of a comment AO3 confirmed is cleared** from its own slot. |
| A send answers after its sheet was dismissed and another opened | `finishIfSucceeded` (`:1179`) closes whatever composer is open. | Clears its own slot; the composer opened since keeps its target and text. Looked at on iOS (2026-10-10): not reachable there, because the sheet cannot be closed while a send is out (Cancel is `.disabled(model.submissionGuard.phase.isBusy)`, `CommentsView.swift:1302`, and `.interactiveDismissDisabled` at `:1353`). Android's sheet can be, so Android needs the rule. |
| A saved edit | Clears no draft (`:1094`). | The same (was a fault). |

## Tests

New `comments/CommentsViewModelContextTest.kt`, 11 tests. Every lookup that must answer late is
held by an explicit gate (the draft store's read, a GET, the POST). Waiting for a page still
polls in real time: the repository parses on its own dispatcher and the brief forbids changing
it. Each fix was taken out in turn and the test named for it failed:

| Fix taken out | Test that failed |
| --- | --- |
| a target change cancels a composer still reading its draft | `aComposerStillReadingItsDraftDoesNotOpenOnTheChapterTheReaderMovedTo` |
| the lookup's own check of the viewer | `aDraftReadForOneSessionDoesNotOpenForTheNext` |
| the draft is saved to the composer's own target | `anOpenComposerKeepsWhatItWasOpenedForWhenTheScreenMovesToAChapter` |
| a send closes only its own composer | `aSendThatAnswersAfterAnotherComposerOpenedClearsItsOwnDraftOnly` |
| an edit clears no draft | `aSavedEditLeavesTheNewCommentDraftAlone` |
| the whole tree of ids | `theCommentAskedForIsDrawnOnceWhereverThePageHoldsPartOfItsThread` |
| the session's count in the viewer | `aChapterListIsReadAgainForANewSessionOfTheSameNameAndALateOneIsNotShown` (and the lookup test) |
| the reader's choice stands | `aChapterTheReaderChoseIsNotReplacedByTheOneTheReadersButtonAskedFor` |
| a reply on the last reader's page opens nothing | `aNewReaderGetsACleanScreenAndTheLastOnesTextStaysTheirs` |

Two more are guardrails that pass with or without a fix here, as A32-8 asked for them:
`theChapterIsTheOneTheThreadsRootNamesNotTheReplys` (root 77 against reply 88) and
`allCommentsChosenWhileEitherChapterCommentsReadIsHeldStands` (each read held by a gate).

One run of the sixth mutation also failed two unrelated tests; six repeats did not. The likely
cause was a failed test leaving its model's reads to answer during the next test, so every test
now ends by cancelling its models. Five runs of the class without a mutation, and the full gate,
were clean. **If this class is ever intermittent, look there first.**

Changed in the older `CommentsViewModelDraftTest`: one fake was given a second page, because a
reader signing in now has the thread read again.

## Seen on the emulator (airplane mode, the demo's local answers, Light)

A Test Work's comments: a draft typed on All comments, on Chapter 3, and in a reply to a comment,
each came back in its own composer and in no other; the chapter's sheet shows its note about
posting to the whole work. **Not seen:** a send; a change of reader while the screen is open;
the reader's chapter button; Dark, OLED, Sepia; twice the text size.

## Found and not fixed here

**Typed fast, the composer's field loses and reorders characters.** `adb shell input text
"for the chapter"` left "fohe chapterr" in the field; typed a word at a time it was right. The
field's text comes from the model's `StateFlow` and goes back through it on every key, which is
the known way for a Compose text field to drop input. It was like this before this change. A
comment is sent to AO3 as typed, so this matters.

**Fixed the same night, in its own commit.** The sheet already kept its own text; the fault was
its `LaunchedEffect(draft)`, which took each late echo of the field's own text for a change from
outside and put it back over what had been typed since. `DraftEchoes` in
`comments/CommentComposerSheet.kt` now tells the two apart. Seen on the emulator: two fast
bursts ("… and the quick brown fox jumps over the lazy dog") arrived whole, in a new comment
and in a reply, and each was there when its composer was reopened. Gemini's index A40 listed
seventeen other fields whose text comes from a flow; two were given the same fast input on the
emulator and kept every character (`audits/A40-result.md`). iOS binds its editor straight to the
model (`TextEditor(text: $model.composerText)`, `CommentsView.swift:1362`), so it has no echo to
mistake.

## Left alone

- Android's draft store keys by name only, with one "guest" slot for no name; iOS files an
  unnamed session's drafts under the session. Out of this brief's scope.
- `deleteComment` sets `submitting` for the whole screen; a delete and a send can overlap.
- The demo's page for an absent comment id still has mismatched action addresses (A32-4, last
  paragraph).
