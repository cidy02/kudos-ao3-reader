# Brief 3ah: the Library when a filter leaves nothing

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; don't change Room schemas or backup formats; don't edit `TASKS.md`. Your sandbox can't run
Gradle; Claude builds and tests afterwards, so make it compile by reading the real symbols you use.
**When this brief and iOS's code disagree, iOS's code wins: say so in the result.**

Since brief 3af the Library's filter panel is iOS's
(`android/app/src/main/java/io/github/cidy02/kudos/library/LibraryFilterPanel.kt`). What the
Library shows when a filter leaves a section, or the whole Library, empty is not. With a rating
filter on, an empty Saved for Later section still says "You haven't saved any works for later.
Add a work to Saved for Later to see it here.", which is not true.

iOS: `kudos-ao3-reader/Features/Library/LibraryFilterEmptyState.swift` (the collision card: which
filter to drop and how many works that would bring back, Edit, and Clear all filters), and where
`Features/Library/` and `Features/Home/HomeSectionListView.swift` use it. The iOS lane is
`/Users/cidy02/kudos-ios-polish`.

1. Find every empty state the Library screen (`library/LibraryScreen.kt`) and Home's section
   lists (`home/HomeSectionListScreen.kt`) can show, and for each say what iOS shows in the same
   case, filtered and unfiltered. Put that table at the top of the result.
2. Port iOS's filtered empty states, with its counts (computed as iOS computes them: read the
   Swift, don't guess), its strings verbatim and its two actions. Draw them as the Library's
   other cards are drawn; no Material cards or buttons.
3. The unfiltered empty states stay as they are unless iOS's differ; if they do, list the
   difference and follow iOS.
4. Tests for the counts, named for iOS's tests if iOS has them.

## Result

`docs/android-port/briefs/3ah-result.md`: the table; every user-visible string before and after;
how each count is computed, with the iOS lines; the tests; what has to be seen on the emulator.
