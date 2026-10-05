# Brief 5h: which files an import may write, decided when it writes

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; **don't edit `TASKS.md`**. **Don't change the backup format** (manifest version, key
names, file and folder names) **or a Room schema.** Your sandbox can't run Gradle or Xcode. Claude
builds, tests and commits afterwards, so make what you write compile by reading the real symbols
you use, and say which claims need a test run.

**Android only.** iOS is the reference: read it at `/Users/cidy02/kudos-ios-polish/`, change
nothing there. **When this brief and iOS's code disagree, iOS's code wins.** Write
`docs/android-port/briefs/5h-result.md` as you go.

## Read first

`docs/android-port/briefs/5c-landing.md`, all of it; its last section ("Brief 5g") ends with the
risk this brief is about, which you noted yourself in `5g-result.md`. The rules that bind every
sync and backup change are in that file: a sync always writes its manifest and deletes nothing
without a full view of the folder, and it never stops because a file is missing.

## The fault

Since 5g an import's **rows** are checked again, inside the database write, against what the
import captured. Its **files** are not. Which EPUBs it may write
(`BackupMergeResult.epubFilesToWriteByWorkId`), and which originals and fonts, is decided at
merge time from the captured state: whether the work holds a file, whether it is marked to keep
(the preservation status that protects a local copy, iOS `KudosBackupService.mayReplaceEPUB`),
whether the reader removed the download. If any of that changes while the import runs, the
import still writes what it planned:

- a work the reader marked to keep while the import ran has its file replaced;
- a download the reader removed while the import ran comes back;
- a work the reader deleted while the import ran gets a file with no row (check what 5g's
  `installedWorkIds` guard already covers, and what it does not);
- `WorkRepository.deleteLocalEpub` and the importer's own writes can change the file outside
  the import's gate (`PersistenceGate`): say which callers hold the gate and which do not.

## Build

Decide each file write when it is made, from the row as it is then: after 5g's database write
has committed, for each planned EPUB re-read the work and apply the same rule the merge applied
(reuse that function; do not write a second copy of the rule). Skip a write the rule no longer
allows, and leave the row saying what is true (`hasEpub`, `remoteEpubPending`). Do the same for
originals and their conversion records, and say whether fonts can meet the fault at all.

- A skipped write must not lose the file for good: for a sync, the next run fetches it again if
  the row still wants it (check that `remoteEpubPending` is set so the manifest keeps promising
  it); for a one-off backup file, add it to the count the import already reports as held back
  ("N item(s) you changed during the import kept your version; import again to take the
  backup's").
- Close the gap between the check and the write as far as the existing gate allows: say what
  window is left, if any.
- iOS: its restore runs in one go on the main actor. Confirm in a line that it cannot meet this.

Tests (`BackupTrustPhase2Test` or `SyncRepositoryTest`, in the style of the 5g tests): a work
marked to keep between merge and apply keeps its bytes; a download removed between merge and
apply stays removed and the work still says a copy is owed; a work deleted meanwhile gets no
file; an untouched work still gets the incoming file exactly as today; a sync run after a
skipped write fetches the file when the row wants it.

## Not in this brief

Anything on iOS; findings F19, F25, F26 and F27 and the queued flag (they wait for the owner);
settings changed during an import; any screen.
