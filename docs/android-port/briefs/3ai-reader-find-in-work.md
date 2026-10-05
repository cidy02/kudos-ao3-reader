# Brief 3ai: the reader's Find in Work, as iOS's

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; don't change Room schemas or backup formats; don't edit `TASKS.md`. Your sandbox can't run
Gradle; Claude builds and tests afterwards, so make it compile by reading the real symbols you use.
**When this brief and iOS's code disagree, iOS's code wins: say so in the result.**

In Android's reader, Find in Work (`ReaderSearchSheet`, private in
`android/app/src/main/java/io/github/cidy02/kudos/reader/ReaderScreen.kt`, opened from the fan
menu's "Find in Work" pill) is a title and a field. iOS's is
`kudos-ao3-reader/Features/ReaderReadium/ReaderSearchView.swift` with `ReaderSearchGrouping.swift`
and the tests in `KudosTests/ReaderSearchGroupingTests.swift` (the iOS lane is
`/Users/cidy02/kudos-ios-polish`): scopes, "This Chapter", results grouped by chapter, the
match shown in its sentence, a tap that goes to the place in the text, and bookmarking a result.

1. **Compare first.** Read both, and how each reader runs a search (which engine, what a result
   holds, how it jumps to one). Put a table at the top of the result: each thing iOS's sheet
   does, whether Android's reader can do it with what it has, and what is missing if not.
2. **Build what Android's reader can support**, as iOS draws it and with iOS's strings verbatim:
   the sheet drawn like the reader's other sheets (it takes the reader's theme, not the app's),
   the scopes, the grouping (port `ReaderSearchGrouping.swift` as plain Kotlin with tests named
   for iOS's), the result rows, the jump. Move the sheet into its own file.
3. **Bookmarking a result** only if Android's reader already has the annotation call it needs
   (`reader/` and the annotation repository); the bookmark must be the same kind of record the
   reader's own bookmark action makes. If it does not, leave it out and say what is missing.
4. Searching must not block the reader: cancel a search when the query changes or the sheet
   closes, and never search an empty or one-character query if iOS does not.
5. Anything iOS does that needs reader engine work Android lacks: don't fake it. List it.

## Result

`docs/android-port/briefs/3ai-result.md`: the table; every user-visible string before and after;
the grouping rules with the iOS lines they follow; the tests; what has to be seen on the
emulator (a search with matches in several chapters, in the reader's Light, Sepia and Dark
themes; "This Chapter"; a jump; a bookmark made from a result, if built).
