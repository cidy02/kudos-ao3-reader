# R4: iOS's Edit multiple works and own-works list, read in full (for a brief)

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/R4-result.md`. No helper scripts or scratch files left behind.

iOS is at `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` (read-only). Android is in this
worktree under `android/app/src/main/java/io/github/cidy02/kudos/`.

R2 (`docs/android-port/audits/R2-result.md`) read these in a few lines each. This is the same
reading **in full** for two of them, because a brief will be written from it. For **each**,
write one section in the result with exactly these parts, read from the code and quoted,
never from memory. "What is on screen" must list **every** section header, row label, value
wording, placeholder, picker option, footnote, button, alert and empty, loading and failure
state, word for word and in order, each with its `path:line` and the condition under which
it appears. "What it reads and writes" must quote the Swift that builds each request (the
address, every field name and value, the order, what is sent for a value left as it is) and
the Swift that decides whether AO3 accepted it.

- **Edit multiple works** (`Features/Writing/EditMultipleWorksView.swift`, all of it;
  `Features/Authors/OwnWorksBulkBar.swift`; `loadBulkEditForm` and `bulkEditWorks` in
  `Services/AO3WorkActions.swift`; the models they use in `Models/AO3WritingModels.swift`).
  Say exactly which works are sent, how many requests one Save makes for N works, in what
  order, and what happens when the third of five fails.
- **A writer's own works list and its entrances to the work form**
  (`Features/Authors/AuthorProfileContentSections.swift`, `AuthorProfileView.swift`,
  `Features/Account/AccountView.swift`): the select mode, the bulk bar and each of its
  buttons, the swipe actions on an own work's row (Edit, and any other), the "New Work" and
  "New series" entrances, and what each opens. Then say what Android's
  `author/AuthorProfileScreen.kt` and `account/AccountWorksListScreen.kt` have of each,
  with `path:line`.

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
