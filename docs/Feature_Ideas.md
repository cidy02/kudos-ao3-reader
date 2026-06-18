# Feature Ideas Tracker

This document tracks feature ideas and improvements for the app. Ideas are added here so they can be prioritized later without losing them during active development (especially during the UI refresh and Readium migration).

---

## Ideas

### Search & Filters

- **Long-press to clear filters**  
  When long-pressing the Filters button in Search, show a confirmation dialog to quickly clear all active filters. This would be a quality-of-life improvement for users who frequently change filter sets.

- **Advanced Rating filtering**  
  When filtering by rating, allow users to choose:
  - Exact match (e.g., only Mature)
  - Rating+ (Mature + higher ratings like Explicit)
  - Rating- (Mature + lower ratings like Teen/General)
  Add a separate toggle to include or exclude "Not Rated" works.

- **Cycling Include/Exclude for tags**  
  For tag-based filters (Fandom, Characters, Relationships, Additional Tags), use a single selection flow instead of separate Include/Exclude fields:
  - Tap once = Include
  - Tap again = Exclude
  - Tap a third time = Clear
  This reduces UI clutter while still supporting AO3’s powerful include/exclude functionality.

- **Expandable search result cards**  
  Add an expand/collapse button on search result cards that shows the full summary and tags (like on AO3) without opening the work detail page. This allows users to preview more information directly in the results list.

### Browse / Web View

- **Sync browser theme with app theme**  
  When the user changes the app theme (Light / Sepia / Dark), automatically adjust the in-app browser (Browse tab) to use a matching theme on archiveofourown.org if possible. This improves visual consistency when switching themes.

### Theming & Customization

- **AO3 Red as default accent + color picker**  
  Change the default accent color from system blue to AO3's signature red. Add a dedicated section in Settings with a color picker so users can customize the app's accent color.

### Library

- **Hide privacy button when no hidden works exist**  
  When there are no works in the Library that can be hidden by the mature content privacy setting, the privacy button (eye icon) should not be shown in the Library toolbar.

- **Tap tag to filter Library**  
  Tapping a tag (Work Tag or My Tag) on a saved work should filter the Library to show only works that contain that tag.

---

## Status Legend

- **Idea**: Captured but not yet planned.
- **Planned**: Agreed to implement at some point.
- **In Progress**: Currently being worked on.
- **Done**: Implemented and merged.
- **Parked**: Good idea but deprioritized for now.

---

*Last updated: 2026-06-17*