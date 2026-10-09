# R3: what iOS has in Challenges that Android lacks (a reading, for briefs)

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/R3-result.md`. No helper scripts or scratch files left behind.

iOS is in this worktree under `kudos-ao3-reader/`. Android is at
`/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/` (read-only;
not in this worktree).

iOS has these Challenges screens and actions that Android does not have yet. For **each**,
write one section in the result with exactly these parts, read from the code and quoted,
never from memory:

- **Assignments** (`Features/Challenges/` : the assignments list and what a row does;
  fulfilling, defaulting).
- **Challenge settings, editing** (`ChallengeSettingsEditView.swift`,
  `ChallengeSettingsEditSections.swift`; Android has the read-only screen,
  `account/AO3ChallengeSettingsScreen.kt`).
- **The sign-ups list** for a challenge (a moderator's view and a participant's), and
  **withdrawing or deleting a sign-up** (`ChallengeSignUpView.swift` and what it calls;
  Android has the sign-up form, `account/AO3ChallengeSignUpScreen.kt`).
- **The prompt tags editor** (`PromptTagsEditorView.swift`).
- Anything else under `Features/Challenges/` and `Services/AO3ChallengeActions.swift` that
  writes to AO3 and has no counterpart under Android's `account/AO3Challenge*`,
  `AO3PromptMeme*`, `AO3TagSet*` or `network/ao3/writes/AO3WriteRepository.kt`: list each
  function with its `path:line`.

1. **Where on iOS**: the files and the lines of the view, its model and any service call.
2. **How a reader gets there**: every entry point (the row, button or menu item, in which
   screen, with its label and its `path:line`).
3. **What is on screen**: every section, row, button, menu item, placeholder, footnote, empty
   state, loading state, error and alert, **word for word**, in order, with the condition
   under which each appears.
4. **What it reads and writes**: every network request (method, address, when, how often,
   what stops a repeat), every stored value (the key or the model field, and whether it is in
   the backup), and anything it does to the reader's library.
5. **Where it would go on Android**: the nearest existing screen and file, the components
   already there that draw the same kind of thing (name them with `path:line`), and anything
   Android already has that covers part of it.
6. **Size**: small (a row or a menu item on an existing screen), medium (a sheet or a
   sub-screen), large (a screen with its own data).

If a screen turns out to exist on Android after all, say where, with `path:line`, and stop
there for that screen.

Exact files and lines only. Quote strings as they are written, with their punctuation. For
every request, quote the Swift that builds it (the field names, the values, the order, what
is sent for an empty value, the headers) and the Swift that decides whether AO3 accepted it
(the selectors and status codes), because a brief for a screen that writes to AO3 is built
on exactly those lines.
