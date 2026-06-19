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

- **[FI-1] Long-press to clear filters** — *Status: Planned · Board: T-12*  
  When long-pressing the Filters button in Search, show a confirmation dialog to
  quickly clear all active filters. A quality-of-life win for users who frequently
  change filter sets.

- **[FI-2] Advanced Rating filtering** — *Status: Planned · Board: T-09*  
  When filtering by rating, allow users to choose:
  - Exact match (e.g., only Mature)
  - Rating+ (Mature + higher ratings like Explicit)
  - Rating- (Mature + lower ratings like Teen/General)
  Add a separate toggle to include or exclude "Not Rated" works.

- **[FI-3] Cycling Include/Exclude for tags** — *Status: Planned · Board: T-09*  
  For tag-based filters (Fandom, Characters, Relationships, Additional Tags), use a
  single selection flow instead of separate Include/Exclude fields:
  - Tap once = Include
  - Tap again = Exclude
  - Tap a third time = Clear
  Reduces UI clutter while still supporting AO3's include/exclude functionality.

- **[FI-4] Expandable search result cards** — *Status: Planned · Board: T-10*  
  Add an expand/collapse button on search result cards that shows the full summary
  and tags (like on AO3) without opening the work detail page.

### Browse / Web View

- **[FI-5] Sync browser theme with app theme** — *Status: Idea · Board: T-15*  
  When the user changes the app theme (Light / Sepia / Dark), adjust the in-app
  browser (Browse tab) to use a matching theme on archiveofourown.org if possible.

### Theming & Customization

- **[FI-6] AO3 Red as default accent + color picker** — *Status: Idea · Board: T-16*  
  Change the default accent color from system blue to AO3's signature red. Add a
  Settings section with a color picker so users can customize the app's accent.

### Library

- **[FI-7] Hide privacy button when no hidden works exist** — *Status: Planned · Board: T-13*  
  When there are no works in the Library that can be hidden by the mature-content
  privacy setting, the privacy (eye) button should not be shown in the toolbar.

- **[FI-8] Tap tag to filter Library** — *Status: Planned · Board: T-11*  
  Tapping a tag (Work Tag or My Tag) on a saved work should filter the Library to
  show only works that contain that tag.

---

*Last updated: 2026-06-18*
