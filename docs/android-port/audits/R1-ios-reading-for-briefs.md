# R1: what iOS has, for eight features Android lacks (a reading, for briefs)

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/R1-result.md`. No helper scripts or scratch files left behind.

iOS is at `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` (read-only). Android is in this
worktree under `android/app/src/main/java/io/github/cidy02/kudos/`.

`docs/android-port/audits/A14-result.md`, section "2. M — missing on Android", lists what iOS
has and Android does not. For **each row of that section** (all of them, in its order), write
one section in the result with exactly these parts, read from the code and quoted, never
from memory:

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

If a row of that section turns out to exist on Android after all, say where, with
`path:line`, and stop there for that row.

Exact files and lines only. Quote strings as they are written, with their punctuation.
