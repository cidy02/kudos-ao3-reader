# Brief 3el: a comments page with no list of comments is an error, not "No Comments Yet" (A50 F7)

Rules (binding): work only in this worktree (`~/kudos-agent-codex`, branch
`android/agent-codex-3el`, at the lane's `acce50d8`); don't commit, push, or switch branches;
never sign in and never contact archiveofourown.org; no stub files; no helper scripts or
`.orig` files left behind; **don't edit `TASKS.md`**. Don't change the backup format or a Room
schema. Your sandbox can't run Gradle: Claude builds, tests and commits afterwards, so make
what you write compile by reading the code around it. End with a short note,
`docs/android-port/briefs/3el-result.md`: what you changed, file by file, and what you could
not check.

## The fault (your own A50 F7)

`network/ao3/comments/AO3CommentParser.kt` `parseComments` falls back to `emptyList()` when the
page has no `ol.thread`, so an unrecognised 200 page (an adult-content interstitial, a changed
page) reads as "No Comments Yet", and newest-page discovery accepts it. iOS fails closed:
`kudos-ao3-reader/Services/AO3Client+Comments.swift` `parseCommentsPage` (in
`/Users/cidy02/kudos-ios-polish/`, read-only) requires `#comments_placeholder` and its direct
child `ol.thread`, which otwarchive always prints, even empty; and a `/comments/<id>` page's
top-level `ol.thread` (its own parser there).

## What to do

1. Make Android's comments parsing fail closed as iOS's does, for a work's or chapter's
   comments page and for a `/comments/<id>` thread page (look at how each reaches
   `parseComments` and which selector each needs). The failure must reach the screen as
   `AO3Error.Parse` (the repository already maps a thrown exception to it), so the screen
   shows its error state with Retry, not "No Comments Yet".
2. Claude tried exactly that rule and other comments tests failed: their made-up HTML lacks
   the list (`CommentsViewModelDraftTest.theThreadPutFirstNeverRepeatsACommentTheChapterPageShows`
   got an Error state, and one test then spun at full CPU, which points to a loop that waits
   for a Loaded state; find it and say whether the screen code, not only the test, can spin
   like that on an Error). Bring every such test page, and
   `app/src/test/resources/ao3/comments/comments_empty.html`, in line with AO3's real markup
   (`app/src/debug/assets/fixtures/ao3_comments_empty.html` is a real empty page). Change a
   test's expectations only where it asserted the old wrong behaviour; say which.
3. Add one test: a 200 page without the list gives an error, not an empty page.
