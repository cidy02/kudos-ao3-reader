# A67: a second review of what landed on 2026-10-16 (Android), hunting bugs

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/A67-result.md`. Leave no other file behind. Do not edit `TASKS.md`.

Each commit below landed with a single reviewer (Claude). Read each one's diff with
`git show <sha>` (read-only) in this worktree (lane HEAD `28bcd3c5`), then the code around it.
iOS, where a change copies it, is `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`
(read-only). Binding rules: `docs/AO3_NETWORKING_POLICY.md` (authenticated reads only of the
reader's own lists or a page they opened; no background or bulk reading; a write only when the
reader asks, sent once, never retried; pacing never weakened) and
`docs/DATA_AND_PERSISTENCE_INVARIANTS.md`.

In this order (most risk first); stop where you run out of time and say where:

1. `bab161fd` and `28bcd3c5`: a work is read again after an AO3 read before it is written.
   Is there any writer of a `WorkEntity` (or other entity a reader edits) left that holds a
   copy across a suspend (network, file, `delay`, `withContext`) and writes it back? Search
   the whole tree, not only the files these commits touched; list each with `path:line`.
2. `dda69793` (3fr, the Library's foreground tag backfill) and `ae18bdc2`, `d2581fca`: can any
   AO3 read now happen outside a screen the reader opened, or more than once per work per
   24 hours, or survive leaving the Library, or run in the demo? Is the pacing the shared one?
3. `2f00aa6a`: Sync Folder's Auto Sync and Disconnect; "a paused sync stays paused"; Replace
   without an undo copy. Can a paused sync be resumed by anything but the reader? Can Replace
   lose data iOS would keep?
4. `72158be6` (3fq part 2): web view EPUB import (download trust boundary: only HTTPS AO3
   `/downloads/…/*.epub`), address field, Load More append, exact page entry, author dashboard
   About, popular tags (one read per opening of a picker, never per keystroke or tag cycle),
   Collection Items' Submit (still guarded against a double submit).
5. `b5a21a66` (3fq part 1), `a503499f`, `e9583487`: bulk Download, remote menus acting on the
   right work, Home bulk Delete always asking, Inbox delete always asking, the Inbox pager.

Find what is **wrong**: data a reader loses, a write sent twice or without the reader asking, a
read the policy forbids, the wrong work acted on, a crash (including regex or API features
the JVM accepts but Android's runtime rejects), a coroutine that outlives its screen, a wrong
screen state. Every finding quotes the Kotlin with `path:line`, says what happens to a reader,
and how sure you are (sure / likely / possible); without a quote, leave it out. Say plainly when
a change looked right. Put a priority list of findings at the top and keep it current.
