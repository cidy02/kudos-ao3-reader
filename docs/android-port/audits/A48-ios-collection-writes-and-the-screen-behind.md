# A48: iOS collection and challenge writes, and whether the screen behind each is told

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/A48-result.md`. **Leave no other file behind.** Trace every write to the end before writing the table.

iOS only, and **not the copy in this worktree**: read `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`
(read-only; it is the current iOS code, and has uncommitted work on fault 2 below in it).

Background. Two faults of one kind were found by hand. (1) After a saved Edit multiple works,
the writer's works list showed the old rating until pulled (fixed: `EditMultipleWorksView`
now takes `onSaved`). (2) After a saved series edit, the series page kept its old title and
order (being fixed). The cause each time: a pushed form writes to AO3 and returns, and the
screen behind it neither reads its page again nor is told; and `AO3AuthorPageCache`
(`Services/AO3Client+Authors.swift`) answers the same address for five minutes. This job finds
every other case. Claude will check every row, so what helps is an **index of where to look**:
every row quotes the Swift with `path:line`. A row without a quote is worth nothing: leave it
out. Never write "none" without naming the files and the words you searched for.

Do this, in order, and stop where you run out of time (say where):

1. **The writes: only these two files.** `Services/AO3CollectionActions.swift` and
   `Services/AO3ChallengeActions.swift`: every `func` that sends a POST (it reaches
   `submitWrite`), its name and `path:line`. An earlier run (A41) covered
   `Services/AO3WorkActions.swift` and found five real faults; they are fixed (the work form,
   the drafts list, a withdrawn sign-up, leaving a collection). Do not repeat those. **If the two
   files hold more than sixteen such functions, trace the first sixteen and name the rest.**
2. **The callers.** For each write: every view or model that calls it (`path:line`), and **the
   exact lines that run after it succeeds** in that caller. Say which is true, with the quote:
   (a) the caller reloads its own data from AO3; (b) the caller calls a closure handed to it
   (`onSaved`, `onChanged`, `onFinish`: name it) and say whether each presenter of that view
   passes one (`path:line` of each presenter, and what the closure does); (c) the caller
   changes its own state by hand; (d) the caller only dismisses or shows a message.
3. **The screen behind.** For every (d), and every (b) where a presenter passes no closure: the
   view that pushed or presented the caller (`path:line` of the `navigationDestination`,
   `sheet` or `NavigationLink`), what that view shows that the write changed (a title, a count,
   a row, an order), and where that data came from (a `let` handed in, an `@State` loaded once
   in `.task`, a model): quote the line. Does anything make it read again when the pushed view
   goes away (`onChange`, `task(id:)` whose id changes, `onAppear`)? Quote it or say none.
4. **The cache.** Every call that removes entries from `AO3AuthorPageCache` (`removeValue`,
   `removePages`, `removeAuthorDashboards`, `removeSeries`, and the `invalidate...` helpers in
   `Services/AO3AuthorProfileService.swift`): `path:line` and which write triggers it. Then,
   for each write in step 1 that changes something an author page, a series page or the Inbox
   shows, say whether any removal follows it.

Note: `Features/Account/AO3CollectionDetailView.swift` now reads every segment again when it
receives `.ao3CollectionChanged` (posted after a sign-up, a withdrawal and leaving), and the
collections list refreshes on `.ao3CollectionDeleted`. A write that changes what either shows and
posts neither is what this job is looking for.

End with a table sorted by how sure you are: number, the write (`path:line`), the caller
(`path:line`), the screen behind and what it goes on showing (`path:line`), (a) to (d), one line.
