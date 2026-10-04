# Brief 3af: the Library's filter panel, as iOS's

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; don't change Room schemas or backup formats; don't edit `TASKS.md`. Your sandbox can't run
Gradle; Claude builds and tests afterwards, so make it compile by reading the real symbols you use.
**When this brief and iOS's code disagree, iOS's code wins: say so in the result.**

Android's `android/app/src/main/java/io/github/cidy02/kudos/library/LibraryFilterPanel.kt` is still
the old Material panel: "Filter and Sort", an outlined search field, chip rows (Sort by, Status,
Download, Completion, My Tags), and Close and Apply buttons. It is opened from the Library
(`library/LibraryScreen.kt`) and from Home's section lists (`home/HomeSectionListScreen.kt`).

iOS's is `kudos-ao3-reader/Features/Library/LibraryFilterPanel.swift`, with its model
`LibraryFilters.swift` and `LibraryFilterEmptyState.swift` (the iOS lane is
`/Users/cidy02/kudos-ios-polish`): the title "Filters", Reset and Done, then Sort by, Rating,
Warnings, Categories, Completion, Language, Word count, and Tags to include and to exclude, each
chosen from an option picker.

## Do this, in order

1. **Compare first.** Read both panels and both filter models. Put a table at the top of the
   result: every control on each side, the field it filters on, how it matches, and whether the
   other side has it.
2. **Redraw the panel** the way the redesigned sheets are drawn. `account/AO3CollectionsFilterPanel.kt`
   (landed today) is the model: a plain sheet, a header with the title and its two actions,
   panels of rows from `ui/subject/` (`SubjectFormRow`, `SubjectToggle`, `SubjectSegmentedControl`,
   `SubjectRowSeparator`, `subjectPanel`), notes at the footnote size with a line height. No
   Material chips, outlined text fields or filled buttons. iOS's sections in iOS's order, iOS's
   strings verbatim. A whole row opens its choices, not only its value.
3. **Port the facets iOS has and Android lacks** into Android's filter state and matching, exactly
   as `LibraryFilters.swift` matches them, with tests named for iOS's (`KudosTests`, search for
   `LibraryFilters`). Where a rule is the same as one in `search/AO3SummaryFilter.kt` (landed
   today), reuse it; don't write a second matcher for the same rule.
4. **Keep every Android control that works today** and that iOS's panel does not have (Status,
   Download, My Tags, collections, the search field). For each, say in the result where iOS
   offers the same thing instead, if it does. Removing any of them is the owner's call, not
   yours.
5. Both callers keep working. If `LibraryFilterState` is stored or backed up anywhere, its
   stored form must still load: add fields with defaults and say what you checked.

## Result

`docs/android-port/briefs/3af-result.md`: the comparison table; every user-visible string before
and after; what was kept Android-only and why; each new matching rule with the iOS lines it
follows; the tests; what has to be seen on the emulator.
