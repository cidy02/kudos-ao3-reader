# Bug Tracker

This document tracks bugs and issues found during development and testing. It helps keep track of problems that need fixing without losing them in chat history.

Each bug has a stable ID (`BUG-N`); link active bugs to a task in [`../TASKS.md`](../TASKS.md)
when work starts. **Status:** `Open` · `In Progress` · `Fixed & Verified` · `Won't fix`.

---

## Active Bugs

*(None currently tracked.)*

---

## Fixed / Verified

### Search

- **[BUG-2] T-09 tag cycling UI / search placement regression** — ✅ Fixed &
  verified (2026-06-18, `main` + `readium-migration`; Board: T-22).
  Selected chips now continue the Include → Exclude → Clear cycle independently
  of their surrounding Form row, and the tag picker search field is restored to
  the top navigation drawer on iOS. Verified interactively in the iPhone 17
  simulator: blue included chip → red excluded chip → cleared.

### Theming

- **[BUG-1] Sepia theme not applying consistently** — ✅ Fixed & verified (2026-06-18, `main` + `readium-migration`; Board: T-08).  
  Sepia now applies app-wide via the `.appThemedScroll()` / `.appThemedRows()`
  surface modifiers (`UIComponents/AppThemeSurface.swift`). The screens that
  previously fell back to white were fixed and verified in the simulator:
  - **Settings** (`ReaderOptionsForm`) — warm cells, warm segmented controls, brown text.
  - **Browse-by-fandom footer** — was a white box; now plain text on the warm backdrop.
  - **Bookmarks empty states** — warm backdrop instead of white.
  - **Customize Theme sheet** — themed form + preview header.
  - **Work cards** — warm card surfaces + accent icons.

---

## Notes

- Try to include enough detail (which screen, what exactly looks wrong, theme, etc.) when adding new bugs.
- Once a bug is fixed and verified on `main`, move it to the "Fixed / Verified" section or remove it.
- Critical bugs that block daily use should be prioritized over polish items.

---

*Last updated: 2026-06-18*
