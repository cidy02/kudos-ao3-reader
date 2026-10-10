# R9: the Library, section by section: what Android still lacks

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/R9-result.md`. No helper scripts left behind.

iOS is at `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` (read-only): `Features/Library/`
and whatever it uses from `UIComponents/`. Android is in this worktree under
`android/app/src/main/java/io/github/cidy02/kudos/` (start from `library/` and `app/AppNavHost.kt`).

The Library is the one large area of the Android port still marked unfinished, and nobody has
listed what is left. List it. For **every** screen, sheet, menu and section under iOS's
`Features/Library/` (the dashboard and each of its sections; Reading History and its
grouping; Favorites and its scopes; Downloads; Collections; Recently Deleted; every "see all"
list; every sort and filter menu; every context menu on a card; every empty state):

1. the Swift `struct` and file, with `path:line`;
2. what it shows, in order: each heading, row, control and menu item, word for word, with the
   condition under which it appears;
3. the Kotlin composable and file that draws the same thing on Android, with `path:line`, **or**
   "not found", naming the files you searched and the words you searched for;
4. each difference you can quote: a string that differs, a menu item one side lacks, a sort
   or filter one side lacks, an empty state one side lacks. **Both quotes or leave it out.**

Do not judge appearance: you cannot see either app. Words, items, order and what a tap does.

End with a table sorted by size of the gap: the iOS screen or control, `path:line`, Android's
`path:line` or "not found", one line. If you run short of time, finish the dashboard and its
sections first and say where you stopped.
