# Audit A15: a string check, Challenges and Writing (the screens Android has)

**Read-only.** Work only in this worktree. Change no source file. Do not build, commit, push,
switch branches, sign in or contact archiveofourown.org. Write exactly one file:
`docs/android-port/audits/A15-result.md`.

This is a mechanical check, and its value is exactness. Report only what you found by
searching; never infer, never describe a file you did not open, never invent a line number.

## The check

For every user-visible string literal in these iOS folders (in this worktree):

- `kudos-ao3-reader/Features/Challenges/`: only `ChallengeSettingsView.swift`, `TagSetView.swift`, `PromptMemeView.swift`, `CollectionModerationView.swift`, `CollectionMaintainersView.swift`
- `kudos-ao3-reader/Features/Writing/`: only `WritingDraftsView.swift`, `WorkEditView.swift`, `WritingFormFields.swift`, `WritingTextEditor.swift`, `WritingTagsEditor.swift`, `WritingTagConvenience.swift`, `WorkAssociationPickers.swift`, `WritingChaptersView.swift`; and `kudos-ao3-reader/Features/Account/AO3Collection*.swift`

that is, the text of a `Text("…")`, `Button("…")`, `Label("…", …)`, `Toggle("…")`,
`Picker("…")`, `.navigationTitle("…")`, an alert's or dialog's title, message and buttons, a
menu item, a placeholder, an accessibility label, or a string returned by a function whose
result is shown: search the Android tree for it

- `android/app/src/main/java/io/github/cidy02/kudos/account/` and `…/kudos/writing/`, then the
  whole of `android/app/src/main/` if not found there (Kotlin files and `res/values/strings.xml`)

with an exact, case-sensitive search of the whole string (for a string with interpolation,
search its longest fixed part).

## The result file

1. Counts: iOS files read, strings checked, found, not found.
2. **Not found on Android**: a table, one row per string: the string exactly as written; the
   iOS `path:line` (open the file and copy the real line number); what kind of thing it is
   (button, row label, alert message…); the exact search you ran. Group by iOS file.
3. **Found, but worded differently on Android** only when you saw it by reading the Android
   counterpart: the iOS string, the Android string, both `path:line`.
4. What you did not read.

Do not list strings that are only in comments, in `#Preview` blocks, in debug-only code
(`#if DEBUG`), or log messages.

## Learned from A7

- A string that exists on Android only inside a test (`android/app/src/test/`) is **not
  found**: search `android/app/src/main/` only.
- For each "not found" row, add one more column: the nearest Android file you opened that
  should hold it (or "none"), so the triage can start there.
- A setting, toggle or menu item with no Android counterpart matters most. Put those rows
  first within each file.
- **Leave no helper files behind.** A13's run left nineteen scripts and text files in this
  worktree. Work in memory or under `/tmp`, and delete anything you create except the result.
- In these two areas a string that is a Save, Post, Delete, Preview or Withdraw control is
  expected to be missing (those writes are not built yet): list those rows last, under
  "Expected: write not built".
