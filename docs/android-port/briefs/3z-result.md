# 3z result

Written by Claude. Codex wrote the code and was cut off by its usage limit before its own compile
check and before writing this file. Claude checked the code against iOS, ran the gate, fixed the
one failing test, and checked it on the emulator.

## What changed

- **A fandom's works** (`browse/FandomWorksScreen.kt`). The floating chrome holds the filter button
  and a "…" menu (Select, Expand All), and the page starts below the status bar and the back row.
  The shell's "Works" title bar above the header is gone: `Routes.hasSubjectHeader` now includes
  `BrowseWorks` and `SeriesWorks` (`NavigationRoutesTest` updated to match).
- **A series** (`app/SeriesWorksScreen.kt`), as iOS's `AO3SeriesDetailView`: the "Series" kicker and
  title, the shared `SensitiveWorkRow`, paging above and below, a "…" menu (Select, Expand All,
  Open on AO3, Share Series), and the remote selection bar (Save for Later, Save).
- **Tag taps**, as iOS's `AppRouter.searchAO3(field, value)`: a tapped tag switches to Search and
  runs an AO3 search in that tag's own field. `search/SearchTagRequest.kt` hands the request to
  the Search screen; `MainScaffold` provides it; `tagSearchFilters` maps the field
  (`SearchLocalMatchesTest`). It is wired where iOS has it: a work row's fandom line and, when the
  row is expanded, its tag chips; and Work detail's tag chips. **Work detail used to open
  archiveofourown.org in the phone's browser for a tag tap**; it now stays in the app.
- **The shared work row** (`ui/components/SensitiveWorkRow.kt`), when expanded, groups its tags as
  iOS does (Archive Warnings, Relationships, Characters, Additional Tags) and lists each fandom on
  its own line.

## User-visible strings

- Fandom works. Before: icon buttons named "Expand all" / "Collapse all" and "Select works" /
  "Exit selection". After: "More actions"; menu items "Select" / "Exit selection" and
  "Expand All" / "Collapse All". Everything else is unchanged.
- Series. Before: "Series", "Works in this AO3 series.", "Loading series…", "Couldn't load
  series", "Retry", "No works found", "This series has no works on this page.". After (iOS's):
  "Series", "Works", "Loading series…", "Couldn't load series", "Try Again", "No visible works",
  "No works in this series are visible to you on AO3.", "More actions", "Select" /
  "Exit selection", "Expand All" / "Collapse All", "Open on AO3", "Share Series", "Selection".
- Expanded work rows: group labels "Archive Warnings", "Relationships", "Characters",
  "Additional Tags", and "Tags" when a work's tags are not categorised.

## Callbacks

- `SeriesWorksScreen` gained `workImporter`, `readingQueueRepository` and `onOpenAo3`, all with
  defaults; `AppNavHost` passes them. `onOpenWork` is unchanged.
- `SearchViewModel.searchTag(tag)` became `searchTag(field, tag, isFreshTabJump)`. A jump from
  another tab starts a fresh filter history, as on iOS; a tap inside Search pushes onto it.
- `SensitiveWorkRow` gained `onTagSearch`; an `onTagClick` a caller already passes still wins.

## Unused screens, left in place

`browse/TagWorksScreen.kt` and `author/AuthorWorksScreen.kt`. Nothing navigates to them: a tag
opens Search (above), and an author's works are the Works tab of the author profile, as on iOS.

## Left out

- iOS's series page has owner actions (Edit series, Reorder) and a "Showing cached AO3 data"
  line. Android has neither a series editor nor a series cache.

## What was and wasn't seen on the emulator (Dark)

Seen: a fandom's works with the floating chrome and no title bar; its menu; selection mode; the
series page's header, its error state and its menu; a fandom tag tapped on Work detail opening
Search with one active filter; an expanded row in the Library with grouped tags.
Not seen: a series with works (the demo has no fixture for `/series/<id>`), and the share sheet.
