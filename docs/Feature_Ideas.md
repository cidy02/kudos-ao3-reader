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

- **[FI-3] Cycling Include/Exclude for multi-select filters** — *Status: Done (2026-06-18) · Board: T-09, T-23*
  Search's Warnings, Categories, Fandom, Character, Relationship, and Additional
  Tag controls now cycle each option through Include → Exclude → Clear, with
  distinct labels and colors. The separate generic Exclude Tags field is no
  longer needed.

- **[FI-4] Expandable search result cards** — *Status: Done (2026-06-18) · Board: T-10*
  Search result cards now keep summaries to three lines by default and provide a
  **Show more / Show less** control that reveals the full summary and wrapped tag
  chips without opening the work detail page.

### Browse / Web View

- **[FI-5] Sync browser theme with app theme** — *Status: Done (2026-06-19) · Board: T-15*
  The Browse tab now keeps AO3's native Light skin and applies matching Sepia or
  Dark palettes on official AO3 hosts. Changes apply live and persist across page
  navigation without affecting external sites.

- **[FI-10] AO3 authentication foundation** — *Status: Done (2026-06-20) · Board: T-30*
  Settings now provides native account entry backed by AO3's real login form in
  a hidden WebView. Mechanism failures automatically reveal a themed WebView
  fallback; captured sessions persist device-only in Keychain and support
  restoration, expiration, logout, and reusable authenticated requests.

- **[FI-11] Marked for Later reading list** — *Status: Done (2026-06-20) · Board: T-33*
  First login-gated read feature (native-AO3 roadmap Phase 2). A new **"Later"**
  segment in the Bookmarks tab fetches the user's AO3 Marked-for-Later list
  (`/users/<name>/readings?show=to-read`) with their session, reusing the search
  card, pagination, and work-page navigation. Shows a sign-in prompt when logged
  out and re-prompts on session expiry.

- **[FI-12] AO3 Bookmarks list** — *Status: Done (2026-06-20) · Board: T-34*
  Second Phase-2 read feature. A new **"AO3 Bookmarks"** segment shows the works
  the user has bookmarked on AO3 (`/users/<name>/bookmarks`). The Marked-for-Later
  view was generalized into a reusable `AO3AccountWorksList(kind:)`; bookmark
  blurbs are parsed by `parseBookmarksPage` (work id read from the `/works/` link
  since the `<li>` id is the bookmark id; series and external-work bookmarks are
  skipped). Same sign-in / pagination / expiry handling.

- **[FI-9] Enrich Browse-by-fandom category cards** — *Status: Done (2026-06-19) · Board: T-24*  
  Cards now show real **fandom count** + **work count** (from each category's
  fandom index, session-cached in `FandomCatalog`), the user's **saved-work count**
  in that category, and **recently-read fandom chips** (tap → fandom search), with
  a regular-weight name (icon stays emphasized) and thin section dividers. Matching
  dividers added to the Search and Library result cards. Verified in the simulator.

### Theming & Customization

- **[FI-6] AO3 Red as default accent + color picker** — *Status: Done (2026-06-19) · Board: T-16*  
  Default accent is now AO3 red (`#990000`); Settings ▸ Theme has an Accent Color
  `ColorPicker` + "Reset to AO3 Red" (`ThemeManager.accentColor`). The accent
  applies in Light/Dark; Sepia keeps its warm tint. Verified in the simulator.

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

*Last updated: 2026-06-20*
