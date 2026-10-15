# A53: review what Claude landed on 2026-10-15 between 06:30 and 08:45 (Android and iOS)

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/A53-result.md`. **Leave no other file behind.** Do not edit `TASKS.md`.

Android: `~/kudos-android-lane` at `03ea8d0d` (read-only). iOS: `/Users/cidy02/kudos-ios-polish/`
at `13132ed9` (read-only). Each change has a commit message and a `DECISIONS.md` entry
(Android) or a `TASKS.md` row (iOS). The networking policy and the data rules are binding:
`docs/AO3_NETWORKING_POLICY.md`, `docs/DATA_AND_PERSISTENCE_INVARIANTS.md`.

Every finding quotes the code with `path:line`, says what happens to a reader, and how sure you
are; without a quote, leave it out. Say plainly when a change looked right.

In this order; stop where you run out of time (say where):

1. **3ey** (`4870ad9c`): Save Search now opens over the filter sheet, which stays open
   (`search/SearchScreen.kt`). Two Material bottom sheets at once: back, focus, the keyboard,
   dismissing either, saving twice; does the filter sheet's discard still run when it closes?
2. **3ez** (`f7ea565e`): the blank-locator guard (`reader/ReaderProgressMapper.kt`); the
   stored AO3 ID in `WorkIdentitySnapshot.index` (can two works now collide on one ID and one
   be merged into the other wrongly; what does iOS do then?); the exporter's limits
   (`backup/BackupExporter.kt`: is `output.size()` after `closeEntry` the right measure; can a
   library that imported fine now fail to export, and is that worse than before?); the failed
   Replace message.
3. **3fb** (`e66684a8`): the account lists open on Compact; Marked for Later's "synced" clause
   (`account/AccountWorksListScreen.kt`: is `remember(current.page)` a fetch, or does it
   change on other recompositions; the minute ticker's lifetime) and its "Everything else"
   heading.
4. **iOS T-411 to T-415**: `TextSizeSlider` and `CustomizeThemeView` at the largest sizes;
   `SearchView`'s save sheet moved onto the filter panel (does it still open on iPad and Mac,
   where the panel is an inspector; and from anywhere else that calls `presentSaveDialog`);
   `AO3CollectionItemsView`'s rows stacking (`row(spacing:)`); the three footers made rows
   (`SearchView`, `AccountView`, `BulkTagStatePicker`): a deleted saved search, VoiceOver
   order; `MediaBrowserView.appThemedScroll()` in Light and Dark.

End with a short list: the findings worth fixing first, one line each.
