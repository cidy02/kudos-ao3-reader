# Brief 3fa-2: the Replace rollback without hard links, recovered after a crash; the export's words

Same rules as brief 3fa (`docs/android-port/briefs/3fa-replace-rollback-and-export-gaps.md`).
Revise your 3fa work **in place** in this worktree (`android/agent-codex-3fa`, uncommitted).
Update `docs/android-port/briefs/3fa-result.md` to say what changed.

Claude reviewed 3fa. The design is right (one transaction for a Replace; files undone on
failure; Merge and Reconcile unchanged; the export receipt). Three changes before it lands:

## 1. No hard links: Android refuses them

`BackupFileUndo.beforeWrite` keeps the old file with `Files.createLink`. On the emulator
(API 36), in the app's own files directory, as the app's user, `ln` fails: "cannot create hard
link … Permission denied" (SELinux). Every Replace that overwrites a file would fail. Move the
old file aside instead: `Files.move(destination, aside, ATOMIC_MOVE)` to a **deterministic**
sibling name (for example `<file name>.kudos-replace-undo`), then let the writer create the new
file. Rollback: delete whatever is at the destination, move the aside back. Commit: delete the
asides. Keep the order: every check that reads the destination (`hasFile`, `mayRestoreEpub`,
the font comparison) runs before the move.

## 2. A crash in the middle leaves no book without its file

Moving aside opens a window in which the destination does not exist. If the process dies
there (or after the rows commit but before the asides are deleted), the next start must
repair it: a sweep of the works, fonts and originals directories that, for each aside, moves
it back when its destination is missing and deletes it when the destination exists. Run it
where the app's other start-up repairs run (find where `TombstoneLocalMigration` runs at
launch) and at the start of every Replace, inside the persistence gate. Tests: an aside with
no destination comes back; an aside beside a destination is deleted.

## 3. The export's words

"Left out 1 book(s)' EPUB files: …" reads badly. Write it as the app writes counts elsewhere:
"1 book was left out because its file is missing: Title." / "3 books were left out because
their files are missing: A, B and C." / "… A, B, C and 2 more." Fonts the same ("font",
"fonts"). Update the test that pins the wording.
