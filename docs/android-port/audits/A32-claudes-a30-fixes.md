# A32: Claude's fixes for your audit A30, reviewed before they are trusted

**Read-only.** Change no source file anywhere. Do not build, commit, push, switch branches, sign
in or contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/A32-result.md`. No helper scripts left behind.

You wrote `docs/android-port/audits/A30-result.md` (it is in the repository at
`android/redesign-parity`; read it with `git show android/redesign-parity:docs/android-port/audits/A30-result.md`).
Claude has answered it. Nobody has reviewed the answers. For each item say **fixed**, **not
fixed**, or **fixed but broke something**, with the code quoted (`path:line`), the failing
inputs or taps, and the smallest fix. Say plainly where Claude is wrong. Do not repeat a
finding from A30 that is unchanged; say "unchanged" in one line.

## Android: commit `fe873221` (`git show fe873221 -- android/app/src`)

1. **A30-1** `comments/CommentsViewModel.kt`: one `composerGeneration` fences every draft
   lookup. Is there any path that changes what the composer is for and does not move the
   count (a target or scope change with the sheet open, a session change, `load`, a submit
   that fails)? Any path where the count moves and a draft the reader should see is dropped?
2. **A30-5** `setScope` and `setTarget` no longer return early while Chapter Comments is
   pending. Can that now start two loads, or lose `retry()`'s pending request?
3. **A30-6, A30-7** `firstNamingChapter` and the number from the byline; the index replacing a
   placeholder in `loadChaptersIfNeeded`. Can the replacement move the screen to another
   chapter or trigger a load?
4. **A30-10** `present`: the page's copy of the root gives way to the thread's. Is anything
   on the page lost that the thread does not hold (replies AO3 folded on one and not the
   other)? Still two rows with one key anywhere? And `demoCommentThreadPage`.
5. **A30-11** `chaptersViewer`. Is `currentUsername()` the right identity (two sessions with
   one name; a session without a name)? Does the reader effect in `CommentsScreen.kt`
   (`chapterForPosition`) still act on a guest's index?
6. **A30-12** `labelSpokenByControl` in `ui/subject/SubjectForm.kt` and
   `settings/SettingsChrome.kt`. List every caller whose spoken label changed.
7. **A30-9** `app/DemoLibrary.kt`: the seeded catalog is dated 0. Does anything treat a
   stale entry as usable (a fallback when a read fails, the Privacy screen's figure)?
8. Commit `c4e093db` (three strengthened tests) and the tests in `fe873221`: does each fail
   for the fault it names? Name any that cannot.

## iOS: **uncommitted** changes in `/Users/cidy02/kudos-ios-polish` (`git -C /Users/cidy02/kudos-ios-polish diff`)

9. **A30-3** `Services/KudosBackup.swift` `restoreAnnotations`: in Replace, marks this device
   has that the snapshot does not list are left out of the same-passage dedupe. Is that set
   exactly the set Replace then hides? Does leaving them out lose a note the dedupe used to
   park or fill?
10. **A30-4** same function: Merge now takes an incoming mark with the same id when the copy
    here is one the tombstone removes. Check each resolution the incoming one can have
    (`reviveNewerData`, `preserveAmbiguous`, `noTombstone`) and that a live local mark nobody
    deleted is still never overwritten by Merge. Is the displaced note still parked?
11. **A30-2** `Services/CommentSubmission.swift`: `CommentDraftIdentity.unnamedSession` now
    carries a token made once per launch. Claude chose this over a token stored with the
    session: it gives up carrying an unnamed session's drafts to the next launch (they stay on
    disk, unread). Is any reader of the old integer-only keys left? Does the per-launch token
    break the two hand-overs in `Services/AO3AuthService.swift` or the one in
    `Features/Comments/CommentsModel.swift` within a launch? Is the trade wrong?
12. **A30-8** `Features/Search/SearchView.swift`: `requestedFilters`. Can closing the panel
    now undo an Apply, or restore the filters of a request that was superseded?
13. The three new tests in `KudosTests/TombstoneSweepsExistingRecordsTests.swift` and the
    changed one in `KudosTests/CommentSubmissionTests.swift`: does each fail without its fix?

If you run short of time, do the iOS items (9 to 13) first, then 1, then the rest, and write
the file with what you have verified: a partial file with true verdicts is worth more than none.
