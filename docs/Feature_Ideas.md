# Feature Ideas Tracker

This document tracks feature ideas and improvements for the app. Ideas are added
here so they can be prioritized later without losing them during active
development (especially during the UI refresh and Readium migration).

Each item has a stable ID (`FI-N`) and a status. When an item is being worked on,
its `Board` link points at the matching task in [`../TASKS.md`](../TASKS.md). Keep
the status here in sync with the board.

**Status:** `Idea` (captured) · `Planned` (agreed for the backlog) · `In Progress`
· `Done` · `Parked`.

---

## Ideas

### Search & Filters

- **[FI-1] Long-press to clear filters** — *Status: Done (2026-06-18) · Board: T-12*  
  Long-pressing the Filters button in Search shows a context menu with a
  destructive **Clear All Filters** action (resets filters, keeps the query, and
  refreshes). Implemented via `.contextMenu` (the reliable long-press affordance
  for toolbar buttons).

- **[FI-2] Advanced Rating filtering** — *Status: Done (2026-06-18) · Board: T-09*
  Search now offers Exact, Rating+, and Rating− matching plus a separate
  **Include Not Rated** toggle. Multi-rating searches use AO3's field-qualified
  `rating_ids` query syntax (verified against live AO3 results).

- **[FI-3] Cycling Include/Exclude for tags** — *Status: Done (2026-06-18) · Board: T-09*
  Search's Fandom, Character, Relationship, and Additional Tag pickers now cycle
  each result through Include → Exclude → Clear, with distinct chips and labels.
  The separate generic Exclude Tags field is no longer needed.

- **[FI-4] Expandable search result cards** — *Status: Done (2026-06-18) · Board: T-10*
  Search result cards now keep summaries to three lines by default and provide a
  **Show more / Show less** control that reveals the full summary and wrapped tag
  chips without opening the work detail page.

### Browse / Web View

- **[FI-5] Sync browser theme with app theme** — *Status: Idea · Board: T-15*  
  When the user changes the app theme (Light / Sepia / Dark), adjust the in-app
  browser (Browse tab) to use a matching theme on archiveofourown.org if possible.

### Theming & Customization

- **[FI-6] AO3 Red as default accent + color picker** — *Status: Idea · Board: T-16*  
  Change the default accent color from system blue to AO3's signature red. Add a
  Settings section with a color picker so users can customize the app's accent.

### Library

- **[FI-7] Hide privacy button when no hidden works exist** — *Status: Done (already implemented) · Board: T-13*  
  Verified already satisfied: both `LibraryView` and `BookmarksView` gate the eye
  toggle on `hideMature && <list has adult works>`, so it's hidden when nothing
  could be hidden.

- **[FI-8] Tap tag to filter Library** — *Status: Done (2026-06-18) · Board: T-11*  
  Tapping a Work Tag (fandom / character / relationship / additional) or a My Tag
  on a saved work switches to the Library and filters it to works with that tag
  (via `AppRouter.filterLibrary` → `LibraryView`). Verified in the simulator.

---

*Last updated: 2026-06-18*
