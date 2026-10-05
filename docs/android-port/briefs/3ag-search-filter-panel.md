# Brief 3ag: the search filter panel, as iOS's

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; don't change Room schemas or backup formats; don't edit `TASKS.md`. Your sandbox can't run
Gradle; Claude builds and tests afterwards, so make it compile by reading the real symbols you use.
**When this brief and iOS's code disagree, iOS's code wins: say so in the result.**

Android's `android/app/src/main/java/io/github/cidy02/kudos/search/SearchFilterSheet.kt` is still
the old Material sheet: chip rows, a round filled Done button, outlined fields. It has four
callers: Search (`search/SearchScreen.kt`), a tag's works and a fandom's works
(`browse/TagWorksScreen.kt`, `browse/FandomWorksScreen.kt`), and, in its Refine mode, the four
account lists (`account/AccountWorksListScreen.kt`; that mode was added today and narrows the
loaded page without running a search).

iOS's is `kudos-ao3-reader/Features/Search/AO3FilterPanel.swift`, with `FilterLanguagePicker.swift`,
`FilterRangeSlider.swift`, `TagSelectField.swift` and the model in `Models/AO3Models.swift` (the
iOS lane is `/Users/cidy02/kudos-ios-polish`). Find how iOS's panel is used for a search and how
for refining a list that is already loaded, and follow each.

## Do this, in order

1. **Compare first.** A table at the top of the result: every control on each side, the filter
   field it sets, and whether the other side has it. Include the chapter-count facet and the
   word sliders that brief 3w's result says Android lacks.
2. **Redraw the sheet** the way the redesigned sheets are drawn. `library/LibraryFilterPanel.kt`
   and `account/AO3CollectionsFilterPanel.kt` (both landed today) are the models: a plain sheet,
   a header with the title and its two icon actions, panels of rows from `ui/subject/`, whole
   rows that open their choices, notes at 12 sp with a 17 sp line height. No Material chips,
   outlined fields or filled buttons. iOS's sections in iOS's order, iOS's strings verbatim.
   The three-state tag controls (include, exclude, clear) keep their three states; draw them as
   iOS does.
3. **Port the facets iOS has and Android lacks** into `AO3SearchFilters`, into the query the
   search sends (read how each existing facet reaches AO3's search URL and follow iOS's
   parameter names exactly; the tests must assert the built URL, not call AO3), and into
   `search/AO3SummaryFilter.kt` for Refine. Tests named for iOS's.
4. **Every caller keeps working**, and Refine mode keeps what it does today: it narrows the
   loaded page, runs no search, and shows its live count line.
5. Keep any Android control that works today and that iOS's panel does not have; list each in
   the result.

## Result

`docs/android-port/briefs/3ag-result.md`: the comparison table; every user-visible string before
and after; each new facet with the iOS lines it follows and the URL parameter it sets; the
tests; what has to be seen on the emulator (Search, a fandom's works, Refine on Bookmarks; Dark;
the largest text).
