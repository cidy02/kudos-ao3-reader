# 3f result — Work detail redesigned (Artboard 1a)

Rebuilt `WorkDetailScreen.kt` and extracted components under `works/detail/` to achieve visual and behavioral parity with iOS Artboard 1a and `docs/android-port/specs/work-detail.md`.

## Features & Implementation

- **Identity Header (`works/detail/WorkDetailIdentity.kt`)**: Displays primary fandom kicker with excess count badge via `SubjectHeaderBlock`, 32sp title, and an individually tappable author byline row (`AuthorBylineRow`) navigating to author search.
- **Figure Strip**: Four-cell stat strip covering Rating (G/T/M/E/NR with theme-aware tints), Archive Warnings (mutually exclusive None / Undisclosed / Present logic with green/orange/red badges), Category (with "+N" badge), and Chapters / Completion status (`WorkCompletionStatus`).
- **Resume Card**: 20dp glass panel (`glassFill(0.10)`, `glassStroke(0.14)` border) hosting `WorkReadingOrDownloadRing`, locator position title, relative read time, and a 42dp solid accent circle play button.
- **Page Sections (`works/detail/WorkDetailSections.kt`)**: Rendered over a 620dp wash (`subjectScreenWash`):
  - **Summary**: 16sp serif typography (line-height 25.6sp) with smooth 8-line collapse.
  - **ON AO3 Chips**: Pill cluster for Kudos (with compact count), Subscribe/Unsubscribe, Bookmark, and Mark for Later.
  - **Tag Clusters**: Warnings, Fandoms, Relationships (tinted), Characters, and Additional Tags linking to AO3 search.
  - **Facts Card**: Outlined unfilled panel with Series (part/title), language, compact word count, updated date, and publication date.
  - **Archive Stats Strip & Comments**: Kudos, accented Comments button, Bookmarks, and Hits; accompanied by comments panel ("All comments", "Chapter comments", "Write a comment").
  - **Page Actions & Series**: Outlined "Mark as Finished" and "Open on AO3" buttons; Series section with "Download Whole Series" and AO3 series link.
  - **My Copy Row**: Gateway row displaying device state summary and disclosure chevron.
- **"My Copy" Native Sheet (`works/detail/WorkDetailMyCopySheet.kt`)**: Full bottom sheet managing local device state:
  - Three-cell summary strip: Progress %, On device file size, and Preserved status.
  - Status toggles (Download / Downloaded / Kept Offline, Saved for Later, Finished).
  - Queues & Collections membership and management.
  - Storage & Activity diagnostics with exact iOS strings ("Not downloaded", "Removed to save space. Kudos gets it again when you read it").
  - Origin & Conversion info with "Rebuild from Original" action.
  - Private user tags with creation, removal, and suggested tag chips.
- **Chrome & Legacy Preservation**: Configured `ProvidePushedShellChrome` with favorite star button and overflow "…" menu preserving every existing operation (kudos, bookmarking dialog, series preservation prompt, queue/collection pickers, redownload, metadata refresh). Unit tests added in `WorkDetailLogicTest.kt`.
