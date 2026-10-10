# A40: every Android text field, and where its text comes from

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/A40-result.md`. **Leave no other file behind**: no dumps, no helper
scripts, nothing at the root of the worktree.

Android only: `android/app/src/main/java/io/github/cidy02/kudos/`.

Background. A Compose text field whose `value` is read from a `StateFlow` (through
`collectAsState`) and whose `onValueChange` writes back to that flow can drop or reorder
characters typed fast, because the field is told its old text for a frame. This was seen on the
emulator in the comment composer: `comments/CommentComposerSheet.kt` takes `draft: String` and
`onDraftChange`, and `comments/CommentsScreen.kt` passes `viewModel.draft.collectAsState()` and
`viewModel::updateDraft`. A field whose text lives in `remember { mutableStateOf(...) }` in the
same composable (or in a plain state holder that uses `mutableStateOf`) does not have the fault.
This job finds every field of the first kind. Claude will check every row, so what helps is an
**index of where to look**: every row quotes the Kotlin with `path:line`. A row without a quote
is worth nothing: leave it out.

Do this:

1. List **every** call of `BasicTextField(`, `TextField(`, `OutlinedTextField(` and of any
   wrapper composable in this codebase that ends up calling one (find the wrappers first:
   search for composables whose body contains one of those three calls and that take a
   `value: String` or `TextFieldValue` parameter; name each wrapper with `path:line`).
2. For each call: `path:line`; the expression passed as `value`; the expression passed as
   `onValueChange`.
3. Trace the `value` back to where the text is stored, through every composable parameter on
   the way, and quote the line that stores it. Say which it is:
   - **LOCAL**: `remember { mutableStateOf(...) }` / `rememberSaveable` / `TextFieldValue` kept
     in the composable or a parent composable;
   - **SNAPSHOT**: a `mutableStateOf` field of a state-holder class (quote the field);
   - **FLOW**: a `StateFlow` / `MutableStateFlow` read with `collectAsState` (quote both the
     flow and the `collectAsState` line);
   - **OTHER**: say what.
4. For each FLOW row, say what the write-back does besides setting the flow (a save to disk, a
   network call, a validation), with the quote.

End with a table sorted FLOW first: number, the field (`path:line`), the screen it is on in one
or two words, LOCAL / SNAPSHOT / FLOW / OTHER, where the text is stored (`path:line`).
Start the file with four numbers: fields found, FLOW, SNAPSHOT, LOCAL.
