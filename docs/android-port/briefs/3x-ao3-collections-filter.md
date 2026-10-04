# Brief 3x: the AO3 Collections sort-and-filter panel

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; don't change Room schemas or backup formats; don't edit `TASKS.md`. Your sandbox can't run
Gradle; Claude builds and tests afterwards, so make it compile by reading the real symbols you use.

On Android's AO3 Collections list (`android/app/src/main/java/io/github/cidy02/kudos/account/AO3CollectionsScreen.kt`)
the Filter button does nothing (`/* TODO: Filter */`). Build what iOS has behind it. The iOS lane
is `/Users/cidy02/kudos-ios-polish`; read these first:

- `kudos-ao3-reader/Features/Account/AO3CollectionsFilter.swift`: the filter itself (sort, order,
  the four "show only" switches, `apply`, `summaryLabels`, `hasActiveFilters`, `needsWholeIndex`)
  and `AO3CollectionsWholeIndex`;
- `kudos-ao3-reader/Features/Account/AO3CollectionsFilterPanel.swift`: the sheet (artboard 1bm);
- `kudos-ao3-reader/Features/Account/AO3CollectionsList.swift`: how the list uses them;
- `KudosTests/AO3CollectionsFilterTests.swift`: the rules, as tests.

iOS wins: same behaviour, iOS's strings verbatim.

## Do this, and only this

1. **The filter, as plain Kotlin.** `account/AO3CollectionsFilter.kt`, a port of the Swift struct
   and of `AO3CollectionsWholeIndex` over Android's `network/ao3/account/AO3Collection`. No Compose
   in it. Port iOS's tests to
   `android/app/src/test/java/io/github/cidy02/kudos/account/AO3CollectionsFilterTest.kt`: the same
   cases and the same expected values.
2. **The panel.** `account/AO3CollectionsFilterPanel.kt`. Present it the way
   `library/LibraryFilterPanel.kt` presents its sheet, and draw its groups with the subject
   components the redesigned screens use (`ui/subject`: `SubjectFieldLabel`, `SubjectFormRow`,
   `SubjectSegmentedControl`, `SubjectToggle`, subject panels, theme tokens). Everything iOS's
   panel has: the sort group, the "show only" group, the note about roles, and Reset.
3. **The list.** In `AO3CollectionsScreen.kt` and `AO3CollectionsViewModel`
   (`account/AccountViewModel.kt`, state in `account/AccountUiState.kt`), as iOS's list does it:
   - the Filter button appears and shows its active state under iOS's conditions, and its
     long-press clears the filters;
   - the filter rail of `summaryLabels` under the scope chips while filters are active;
   - the rows are `filter.apply(…)` of what is loaded;
   - the "No collections match" state with Clear Filters, and the line saying how many are hidden;
   - when the filter needs the whole list, fetch the remaining pages through the repository call
     the screen already uses: one page at a time, never in parallel, with iOS's page cap, its
     reuse of page one, and its note when the list is partial. Hide paging while the whole list is
     in use, and make pull to refresh behave as iOS's does in that state.
4. Leave the "+" (New Collection) button and the "Your items" chip as they are; they are separate
   briefs. Don't touch any other screen. Keep every string and callback the list has today.

Read `docs/AO3_NETWORKING_POLICY.md` before changing how pages are fetched. The demo serves these
pages from fixtures (`network/ao3/DemoNetwork.kt`); don't add a request iOS doesn't make.

## Result

Write `docs/android-port/briefs/3x-result.md`: what you added; every new user-visible string;
every signature change; each iOS test and the Kotlin test that mirrors it; anything iOS has that
you left out, and why.
