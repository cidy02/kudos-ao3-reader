# Brief 3t: close the Settings and sort gaps with iOS

Work only in this worktree. **Do not commit**, push, switch branches, stash or reset. Leave changes
uncommitted. If your sandbox can't run Gradle, write carefully (declare before use; check that every
symbol and signature exists) and say so in the result. Claude gates and commits.
iOS lane, for reading: `/Users/cidy02/Documents/AO3_App_OpenSource/.claude/worktrees/handoff-documentation-2151af/.claude/worktrees/polish`.
Owner rules: iOS wins, and behaviour must be identical across platforms.

## 1. Settings > Import uses the T-353 confirmation
Open/Share with Kudos already confirms the download date (`works/DocumentImportPreparation.kt`,
`works/DownloadDateImportConfirmation.kt`, wired in `app/KudosApp.kt`). The Settings Import page
(`settings/SettingsPages2.kt`, its file-import launcher) still imports straight away. Route it through
the same `prepareDocumentImports` and confirmation (single file and batch), as iOS's
`Settings/SettingsImportPage.swift` does.

## 2. Library sort options as iOS offers them
iOS `Features/Library/LibraryFilters.swift` `LibrarySort` offers exactly: Default (`natural`), Date
Added, Date Downloaded, Title, Author, Word Count, with those labels and orders. Android's
`library/LibrarySort.kt` differs (it has "Last read" and is missing "Default" and possibly others).
- Make Android's options, labels and orderings identical, including what `natural` means on iOS
  (read it).
- Map any stored Android value that no longer exists to Default, so nobody's saved preference
  breaks.
- Update `LibraryQuery` and its tests.

## 3. Settings iOS has and Android lacks
- **Keep screen awake** (Reader page): iOS `Reading/KeepScreenAwake.swift` and its use in
  `ReadiumReaderView.swift`. On Android, set `FLAG_KEEP_SCREEN_ON` (or `Modifier.keepScreenOn()`)
  while the reader is open and the setting is on. Use the same default as iOS. Store it in
  `SettingsRepository`/DataStore.
- **Show zero counts** (Library page): iOS `UIComponents/WorkStatLabel.swift` (around line 691, the
  `showsZeroStats` rule) and `Settings/SettingsStoragePages.swift:71`. Apply the same rule to
  Android's work-card stat rows, with the same default.
- **Download on subscribe** (Downloads page): read iOS's rule. If it needs network or subscription
  work Android doesn't have, add **only** the stored toggle and the row, wired to nothing, with a
  `ponytail:` comment, and list it in the result.

Match iOS's strings and footnotes verbatim. Add a unit test per behaviour (the sort orders, the
stored-value mapping, the zero-count rule). Don't touch `backup/` or migrations (DataStore keys are
fine), `reader/` beyond the keep-awake hook, `comments/`, or `app/MainScaffold.kt`.
Write `docs/android-port/briefs/3t-result.md`.
