# Brief 5g: what an import writes over, and a deletion record for a row that was kept

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; **don't edit `TASKS.md`**. **Don't change the backup format** (manifest version, key
names, file and folder names) **or a Room schema.** Your sandbox can't run Gradle or Xcode. Claude
builds, tests and commits afterwards, so make what you write compile by reading the real symbols
you use, and say which claims need a test run.

**Android only.** iOS is the reference: read it at `/Users/cidy02/kudos-ios-polish/`, change
nothing there. If iOS looks wrong, say so at the top of the result and leave it.

Write `docs/android-port/briefs/5g-result.md` as you go. Do the parts in order.

## Read first

- `docs/android-port/briefs/5c-landing.md`, all of it, and above all its last section
  ("Brief 5f"): the two risks at the end of it are yours, from `5f-result.md`, and they are this
  brief. The rules that bind every sync and backup change are in it too:
  - **A sync always writes its manifest and deletes nothing without a full view of the folder.**
  - **When a brief and iOS's code disagree, iOS's code wins.** Say so in the result.
- `docs/android-port/DECISIONS.md`, the entries dated 2026-10-04 and 2026-10-05.

## Part 1: an import must not write over what the reader did while it ran

An import (`BackupRepository`, any mode) captures the library, merges it with the archive
outside any transaction, then `applyMergeResult` writes the merged rows. Rows **created**
meanwhile are safe since 5c, 5e and 5f. A row that was captured and is **kept** by the merge is
still upserted as the merge computed it, whatever happened to it since: the reader's edit made
during the import (a renamed collection, a new reading position, a note's text, a work moved in
a queue, a saved search's filters) is written over with the older captured value merged with the
archive.

Decide, per kind of row, what "the reader changed it meanwhile" means using what the row
already carries (`lastModifiedAt` where there is one, whole-row equality with the captured row
where there is not), and make the apply skip, or re-merge, a row whose stored value no longer
equals what was captured. State the rule you chose for each of the kinds `applyMergeResult`
writes, and why. Rules:

- Never lose the archive's data silently either: if a row is skipped because the reader changed
  it, the archive's newer value for it is lost until the next import or sync. Say for each kind
  whether that is acceptable (a sync runs again; a one-off import of a backup file does not),
  and prefer re-merging the fresh row with the archive's record through the existing merge
  function for that kind where that is a small change.
- Do it inside the transaction the apply already uses for that kind, so the check and the write
  cannot be separated.
- Reading progress is the common case (the reader is reading while a sync runs). Make sure a
  position saved during the import is not moved back.
- iOS: its restore runs in one go on the main actor, so it cannot interleave. Confirm, and say
  so in a line.

Tests (`BackupTrustPhase2Test`, in the style of the 5f tests there): for a work's reading
position, a collection's name, an annotation's note, a saved search's filters and a queue
membership's order, a change made between capture and apply survives; the same row left alone
still takes the archive's newer value; nothing is duplicated.

## Part 2: Replace Library's deletion record for a row it then keeps

Replace Library records a deletion (`mintImmediateTombstone`) at merge time for a saved link or
a saved search the archive omits. Since 5f the apply keeps such a row if the reader changed it
after capture. The deletion record stays in `merge.snapshot.tombstones`, and a later sync that
honours it removes the row the reader edited (saved searches are swept by deletion records).

When the apply keeps a row for that reason, its omission record must not be stored. Find every
kind of row for which Replace mints a deletion record and the apply can now keep the row, and
handle them the same way. A deletion record that came from the archive, or from another device,
is not yours to drop. Tests: a saved link and a saved search edited during a Replace survive it
and survive the next reconcile; an unedited one is still deleted and its record is still
stored; a deletion record from the archive is untouched.

## Not in this brief

Anything on iOS; findings F19, F25, F26 and F27 and the queued flag (they wait for the owner);
any screen. If you see another data-loss bug on the way, write it at the top of the result and
go on.
