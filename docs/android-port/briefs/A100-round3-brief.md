# A100 — round 3: filter sheets' tint, and Load More's ink

**Agent:** Codex. **Worktree:** `~/kudos-agent-codex`, branch `android/agent-codex-a100` (from the lane's
`edf3d2fd`). iOS is read only, in `~/kudos-ios-polish/kudos-ao3-reader/`.

## 1. What tint do the library filter sheets take? (A98 item 4 may have read it wrong)

Tile `~/kudos-tools/pairs/tiles-r2/libraryfilters.png` (iPhone row above Android; Dark, Light, Sepia, OLED,
largest): Reading Now's Filters sheet. Behind the iPhone's sheet the section page's wash is **pink-red**,
but the sheet's ✓ and its menu values (Default, Any rating) are **purple**, the app's own accent. Android's
✓ and values are red (the section's palette) after A98, which made `LibraryFilterPanel` take a palette
and had the queue and collection pages pass theirs.

Find from iOS's code what a filter sheet's tint is: `UIComponents/FilterPanelPresentation.swift`, how
`LibrarySectionListView.swift` (`:251`), the queue page and the collection page present
`LibraryFilterPanel`, `UIComponents/AccentInk.swift` (`accentTint`, `accentFill`), and whatever sets the
app-wide tint. The owner's rule (2026-10-11): the tab bar and chrome buttons follow the current screen's
wash; check whether presented sheets follow it on iOS or keep the app's accent. Then make every Android
caller of `LibraryFilterPanel` (`library/LibraryScreen.kt:571`, `home/HomeSectionListScreen.kt:524`,
`library/QueuePageScreen.kt:468`, `library/CollectionDetailScreen.kt:581`) give the sheet the tint iOS
gives it in the same place. If iOS's queue or collection sheets do take their page's palette, keep that.

## 2. The author Bookmarks page's "Load More"

Tile `~/kudos-tools/pairs/tiles-a97b/authorbookmarks.png`: Android's "Load More" is the accent in Light
and Sepia, primary ink on the iPhone (`Features/Authors/AuthorProfileContentSections.swift:66-95`).
Android: `author/AuthorProfileScreen.kt:1166`. Match iOS, in every tab that uses the row.

## Rules

- §1 of `~/kudos-android-lane/docs/android-port/LIVING-PROMPT.md`. Work only in this worktree. Do not
  commit, push, switch branches, run Gradle (Claude builds and tests), sign in, contact
  archiveofourown.org, or edit `TASKS.md`.
- Tests: wait for idle after changing the theme before reading `tokens` (A98's two tests read a stale
  theme); don't use `hasVisualOverflow` to mean "cut" (use `isLineEllipsized`).

## Output

Write `docs/android-port/briefs/A100-result.md` **first**, then keep it current: per item, the iOS evidence
(`path:line`), your verdict, and what you changed (`path:line`); per test, what it checks and how it fails
with its change reverted. Tests go in `android/app/src/test/java/io/github/cidy02/kudos/app/BriefA100ContentTest.kt`;
update `BriefA98ContentTest.kt`'s library test if item 1 changes what it asserts, and say so.
