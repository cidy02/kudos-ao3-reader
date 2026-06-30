# UI Polish To-Do

This document tracks small visual and interaction polish items that don't rise to
the level of full feature ideas but still need attention for overall design
quality and consistency.

Each item has a stable ID (`UI-N`) and a status; the `Board` link points at the
matching task in [`../TASKS.md`](../TASKS.md). **Status:** `Idea` · `Planned` ·
`In Progress` · `Done` · `Parked`.

---

## Items

### Search Results

- **[UI-1] Refine pagination pill** — *Status: Done (2026-06-19) · Board: T-14, T-25*
  Pagination uses the same elevated card treatment and width as Search results.
  A T-25 follow-up calmed it to one row of tightly grouped page pills between
  single previous/next arrows; long-pressing the arrows jumps to the first/last
  page. The active page remains highlighted, and narrow cards use a nearby-page
  fallback instead of overflowing.

### Browse

- **[UI-2] Theme-respecting category icons** — *Status: Done (2026-06-30) · Board: (see TASKS.md)*
  The main icons in `MediaBrowserView.categoryCard` (for Browse categories like "TV Shows", "Books & Literature", etc.) now use `.foregroundStyle(.tint)` (was `.primary`). This ensures they respect the app theme accent (AO3 red on Light/Dark; warm brown on Sepia), consistent with stat icons and other elements.

---

## Notes

- Items here are generally lower priority than active development (Readium work,
  major features).
- Many can be grouped into a single "UI Polish Pass" when bigger structural changes
  are more stable.
- Add new items as they come up during testing and daily use.

---

*Last updated: 2026-06-30*
