# Bug Tracker

This document tracks bugs and issues found during development and testing. It helps keep track of problems that need fixing without losing them in chat history.

---

## Active Bugs

*(None currently tracked.)*

---

## Fixed / Verified

### Theming

- **Sepia theme not applying consistently** — ✅ Fixed & verified (2026-06-18, `main` + `readium-migration`).  
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