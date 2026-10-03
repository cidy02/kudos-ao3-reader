# Brief 3u-fix2: Library section filter chips as iOS draws them

Work only in this worktree. **Do not commit**, push, switch branches, stash or reset. Leave changes
uncommitted. If your sandbox can't run Gradle, write carefully (declare before use; check that every
symbol and signature exists) and say so. iOS lane, for reading:
`/Users/cidy02/Documents/AO3_App_OpenSource/.claude/worktrees/handoff-documentation-2151af/.claude/worktrees/polish`.

iOS's Library section lists (`Features/Library/LibrarySectionListView.swift`) show a strip of filter
chips under the subtitle. Reading Now has "All 3" and "WIP 2" (see
`docs/android-port/shots/3u/reading-now-ios-vs-android.png`, iOS left). Android
(`library/LibraryScreen.kt`, `LibrarySectionContent`) has none.

1. Read which chips each `LibrarySectionKind` offers on iOS, what each one filters (e.g. WIP means
   not complete), how the counts are computed (before or after other filters), the default
   selection, and whether the choice persists. Look for the chip strip, `applyFavoriteChips`, and
   the related state.
2. Implement the same per-section chips on Android, with the same labels, counts and filtering,
   using the lane's subject components: the selected chip filled with the accent, the others glass
   (see the fandom chips on the Library dashboard, `LibraryScreen.kt`, or `SubjectChip` in
   `ui/subject`).
3. Put the filtering rule in a pure function, and add a JUnit test per section's chips.

Don't touch `backup/`, `data/local`, migrations, `account/`, `settings/` or `app/MainScaffold.kt`.
Write `docs/android-port/briefs/3u-fix2-result.md`.
