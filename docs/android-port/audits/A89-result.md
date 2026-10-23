# A89 result: Codex's Android batch 3gx against the iPhone (read only)

*Done, 2026-10-23.*
- Read `git -C /Users/cidy02/kudos-agent-codex diff` against `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader` and the lane's `DECISIONS.md`.
- No builds, no Gradle, no git command that changes anything, no sign-in, no AO3. No file changed except this one.
- Android paths are under `android/app/src/main/java/io/github/cidy02/kudos/` (tests under `…/src/test/…`), iOS paths under `kudos-ao3-reader/`. Line numbers are the 3gx working tree's.

## Findings

### P2 — Opening Display & Themes now starts a second speech engine, and loads Kokoro on the main thread

**What changed**
- Display now hosts the shared Listening form: `reader/ReaderScreen.kt:1065` → `SettingsListeningContent(settingsRepository, frame)`.
- That form makes its own engine in composition: `settings/SettingsListeningPage.kt:52`, `remember(context) { AutomaticTTSService(context) }`.
- `AutomaticTTSService` builds both engines at once:
  - `KokoroTTSController`, whose `init` calls `initEngine()` (`reader/speech/KokoroTTSController.kt:75-77`). That synchronously creates `OfflineTts` (`:123`) whenever the voice pack is installed.
  - `SystemTTSService`, which binds a `TextToSpeech` in its `init` (`:133-134`).
- Before 3gx, Display only drew the reader's existing controller's state (the removed `speechController.availableVoices` / `viewModel::setSpeechRate` arguments) and made no engine.

**Failing case**
- Voice pack installed, a work open. Tap Display to change the theme.
- Every opening loads the Kokoro model on the UI thread, and binds a device TTS engine for a sheet the reader opened for its theme.
- If Read Aloud is playing, a second Kokoro model sits in memory beside the reader's own (`reader/speech/ReaderSpeechController.kt:46`).
- The cost is not measured (no device here); the code path is certain.
- The reader's Read Aloud sheet already pays this (`reader/ReaderSpeechSettingsSheet.kt:40`), but Display is the sheet people open often.

**iOS:** the sheet Codex matched shows these controls; Android's problem is only when the engine is made.

**Fix:** make the service only when Audition is first tapped, or hand Display the reader's controller through the existing service seam (`SettingsListeningPage.kt:74`, the overload that takes a `TTSService`).

### P3 — Library's Add to Queue reads a series page twice

- **Android:** with Include series on, the new preview reads page 1 (`library/WorkMembershipDialogs.kt:191-199`, `seriesRepository.seriesPage(...)`). Add then calls `repository.preserveSeries(url, …)` (`:242`), which reads every page again from page 1 (`network/ao3/series/AO3SeriesRepository.kt:33-49`).
- **iOS:** preserves from the preview's works when the preview covers the whole series (`Features/Library/ReadingQueues.swift:642-650`, `canUsePreviewForPreservation`).
- Android's Work Detail already does the same (`works/WorkDetailScreen.kt:553-554`). Library's path doesn't.
- **Failing case:** a three-work, one-page series → two GETs of `/series/<id>` where iOS makes one. I found no HTTP cache in `network/ao3/AO3Client.kt` that would absorb the second.
- **Fix:** Work Detail's branch: `if (prompt.canUsePreviewForPreservation) preserveSeries(prompt.preview!!.works, …)`.

### P3 — Tag rename: the right change, but it reverses a recorded decision, and its case rule is narrower than iOS's

- **Matches iOS:** `renameUserTag` now refuses a colliding name instead of merging (`library/ReadingQueueRepository.kt:507-517`). The editor blocks Save (`library/QueueTags.kt:548-560`). iOS now blocks the same way (`Features/Library/QueueTagManagerView.swift:346-358`, `:587-593`).
- **Unrecorded reversal:** `DECISIONS.md:2019` (3fi, 2026-10-14) still says "colliding tag renames merge everywhere". 3gx changes that and records nothing. It needs a DECISIONS entry naming the reversal.
- **Case rule:**
  - Android's lookup is SQLite `COLLATE NOCASE LIMIT 1` (`data/local/dao/TagDao.kt:24`, used by `ReadingQueueRepository.kt:499-503`). NOCASE folds ASCII only; iOS uses `localizedCaseInsensitiveCompare`.
  - **Failing case:** with a tag "Émotions", renaming another tag to "émotions" is allowed on Android and blocked on iOS.
  - And when case variants already coexist (backup restore keeps exact case, per iOS's own comment), `LIMIT 1` can return the tag being renamed itself and miss the other one. iOS excludes the tag itself before searching.
  - **Fix:** query `WHERE id != :tagId`, and compare with a Unicode case fold in Kotlin over the (small) tag list.

### P3 — Work Detail's queue toggle now removes, reversing a recorded brief constraint without a note

- **Android:** a checked queue now unchecks (`works/WorkDetailScreen.kt:962-968`, `removeWork`, which doesn't delete).
- **iOS:** the same toggle removes (`Features/WorkDetail/WorkDetailView.swift:212` → `Features/Library/ReadingQueues.swift:670-676`), so this is parity.
- **What it reverses:** Work Detail was additive-only under brief 3bn's data-safety rule ("nothing here may remove … a queue membership"), recorded as kept in `docs/android-port/audits/A62-result.md:402` and `briefs/3fp-result.md:121`.
- Record the change in DECISIONS, so the next audit doesn't flag it as a regression.

### P3 — The restored Group variants setting can leave the fandom list empty

- **Android:** the stored setting is applied with `LaunchedEffect(storedGrouping) { groupsVariants = storedGrouping }` (`browse/FandomListScreen.kt:72-75`). The chip also clears the multi-name filter (`:207-208` → `browse/FandomFamily.kt:268-269`). The restore doesn't.
- **Failing case:**
  1. In category A, with grouping on, turn on the "more than one name" filter.
  2. Open category B and turn grouping off (now stored).
  3. Go back to A. A's entry state keeps `multiTagOnly = true` but is now ungrouped, so every single-name family is filtered out (`FandomFamily.kt:326`) and the list is empty.
- Also, `collectAsState(initial = true)` draws one grouped frame before a stored `false` arrives.
- **Fix:** `options = options.groupsVariantsChanged(storedGrouping)` in the same effect.
- Read, not run.

### P3 — `GIT_BRANCH` shows in every build type, including release

- **Android:** `android/app/build.gradle.kts:37-44` reads `git branch --show-current` at configuration. `:58` puts it in `defaultConfig`, so debug and release both get it. About appends it when it isn't "main" (`account/AboutScreen.kt:70`, `:194-195`).
- **iOS:** shows a branch only on builds made by `Scripts/build-unsigned-ipa.sh`, which writes `KudosBuildBranch` (script `:94`; `Settings/AboutView.swift:112-135`). An Xcode build shows none.
- **What leaks:** for a distributed branch build, the two match. Android, though, also shows it on any release APK built from a local branch, e.g. an unpushed `security-fixes`, which would name that branch to everyone who installs it.
- **What doesn't:** tag/CI checkouts are detached and give "". Escaping is safe (git refnames can't hold `\` or `"`). No signing, ID or dependency change.
- **Side effect on shots:** debug shot builds from agent worktrees will read "… · android/agent-codex-3gx" while the iPhone's Xcode-built shots read none, so aboutkudos gains a new difference in every side-by-side.
- **Suggestion:** set the field only in the debug build type (release gets ""), or only when a release property such as `-Pkudos.branchBuild` is passed, as iOS's script opts in.

### P3 — Tests that would still pass with their change reverted

Each of these tests a helper or a repository, but not the line that wires it into the app:
1. **`app/Brief3gxParityTest.kt:207` `aboutShowsOnlyAKnownNonMainBranch`** tests only `aboutBranchSuffix`. Reverting `AboutScreen.kt:70` (`+ aboutBranchSuffix(BuildConfig.GIT_BRANCH)`) or the Gradle field keeps it green. Codex says so too.
2. **`reader/ReaderLocatorStorageTest.kt:23` `aSearchResultGetsTheNearestPositionInItsOwnResource`** calls `ReadiumProgressAdapter.resolvedPositionLocator` directly. Reverting the call site in `ReaderScreen.kt` (search result → `hit.locator`) keeps it green, and Find in Work bookmarks would lose their position again.
3. **`data/preferences/SettingsRepositoryTest.kt:35` `fandomGroupingSurvivesRepositoryRecreation…`** tests the repository only. Reverting `FandomListScreen.kt:72-75` (read) or `:207` (write) keeps it green.
4. **`network/ao3/browse/AO3BrowseRepositoryTest.kt:64` `explicitRefreshBypassesAFreshCatalog…`** tests the parameter only. Reverting `FandomListScreen.kt:171` (`loadNow(bypassCache = true)`) keeps it green.
   - `browse/FandomResultsParityTest.kt:92` doesn't catch it either: its `AO3BrowseRepository(client = client)` (`:52`) has no disk cache, so every load reaches the client with or without the bypass. It does catch the keep-rows half.

The rest I read look sensitive to their change, as Codex describes. Specifically:
- the two `FilterTagPickerPopularTest` cases: either gate left at 2 fails the first; a plain Text fails the second;
- `TagSheetParityTest.aConflictingRename…` and `ReadingQueueRepositoryTest.aCollidingRename…`;
- `AnnotationTombstoneTest:104`;
- `FandomFilterSheetParityTest.dismissCancelsTheDraft`.

None was run here.

### Unconfirmed — Codex's "shared authenticated AO3SeriesRepository"

- The container's repository is built with `client = ao3Client` and `authenticatedClient` (`app/KudosAppContainer.kt:254-256`). But `seriesPage`/`seriesWorks` read through `client.get` (`AO3SeriesRepository.kt:57`), and `ao3Client` is a plain `OkHttpAO3Client()` (`KudosAppContainer.kt:116`).
- Only `detailPage` uses the session (`:64-70`).
- So, unless the plain client shares the session cookie (not verified), signed-in series previews and preservation read as a guest. A series with members-only works would be under-counted and under-preserved, where iOS's shared session sees them.
- This predates 3gx (Work Detail uses the same path); 3gx only reuses it. Not counted above.

## Checked and fine

- **47fbc6ec:**
  - 3gx doesn't touch four of its files: `KudosPaginationBar`, `CustomizeThemeSheet`, `ReaderContentsSheetTest` and `PaginationHintTest`.
  - It does touch five: `CollectionEditorSheet`, `ReaderContentsSheet`, `FilterTagPicker`, `PronunciationSettings` and `FilterTagPickerPopularTest`. Its patch for each applies to the 47fbc6ec copy with no conflict, offset or fuzz (`patch --dry-run` on copies in my scratchpad). No hunk undoes 47fbc6ec.
  - The meanings are compatible:
    - `FilterTagPicker`: 3gx changes the remote gate (`:118`, `:122`) and the placeholder (`:170`); 47fbc6ec guards the local candidates (`:134`). A86's trailing-comma test passes a null repository.
    - `PronunciationSettings`: 3gx's hunks end before 47fbc6ec's separator change.
- **Bookmark de-duplication:** matches on Readium position (`reader/AnnotationRepository.kt:74-78`) as iOS `addBookmark(at:)` does. Position 8 still makes a new bookmark.
- **Group variants storage:** stored under iOS's own key (`SettingsRepository.kt:76`; iOS `Features/Search/FandomListView.swift:47`, `@AppStorage`), outside `KudosSettings` and the backup, as on iOS.
- **Fandom index refresh:** only pull-to-refresh bypasses the fresh catalog (`AO3BrowseRepository.kt:51-59`). That is one GET per pull, as iOS's `.refreshable` invalidates its cache and reads (`FandomListView.swift:243-246`). A failure keeps the rows, as iOS (`:440-456`).
- **Fandom family fallback:** an unresolved sibling falls back to the names join, as iOS (`Features/Browse/NativeBrowseView.swift:160-168`, `:352-361`). It returns before `exactFamilyCounts.store`. It adds one search GET where Android used to show an error, the same as iOS.
- **One-character tag search:** iOS also searches from one character after 300 ms (`Services/AO3TagAutocomplete.swift:92-93`; `Features/Search/TagSelectField.swift:356-363`). Parity, not a new read.
- **Backup import:** the removed paragraph's content survives. "It removes nothing" is on the sheet (`backup/BackupScreen.kt:539-540`, iOS's words, `Settings/BackupImportSheet.swift:89`), and the Backup page keeps "Unsigned deletion claims…" (`BackupScreen.kt:267`). Owner question 9's technical notes are intact.
- **Room:** no schema, entity or backup-format change. The only repository-level writes that changed are `renameUserTag` and the Group variants key.

## The eleven owner questions

The owner's rule (A89 brief) is parity with no lost features or information. That rule settles ten of the eleven. Only Q2 is a real choice, and even that leans to iOS.

| # | Verdict | Where |
|---|---|---|
| 1 | **Settled:** the heading takes iOS's loaded count. "Page X of Y" isn't lost, because the Load More row under the list already shows it. | `app/SeriesWorksScreen.kt:261` duplicates `author/AuthorProfileScreen.kt:1162` (via `SeriesWorksScreen.kt:280-282`) |
| 2 | **The one real choice, leaning parity.** Nothing in DECISIONS records Android's create-or-match, and iOS makes a second record (`Services/ReadingQueueService.swift:166-180`). Either way, Android's current match silently drops the draft (colour, offline, tags, seed) and the sheet closes as if it had made the queue (`library/ReadingQueueRepository.kt:271-275`). That predates 3gx and isn't counted. | |
| 3 | **Settled: keep.** Removing local substitution loses progress and reader routing, which the rule forbids. | `ui/components/SensitiveWorkRow.kt:767` |
| 4 | **Settled: keep** multi-work series support. Per-queue concurrency is an implementation choice, not the owner's. | `library/WorkMembershipDialogs.kt:168` |
| 5 | **Settled: keep** typed and library suggestions. Already recorded in code as Android extras. | `search/FilterTagPicker.kt:131` comment |
| 6 | **Settled by parity: enable AO3 suggestions in Refine.** iOS's Refine uses the same `TagSelectField`, which always asks AO3 (`Features/Search/AO3FilterPanel.swift:514-527`; `TagSelectField.swift:363`). Android passes `null` in Refine. The traffic is iOS's own (debounced). | `search/SearchFilterSheet.kt:254` |
| 7 | **Settled: keep** the reading-order fallback and nesting. `DECISIONS.md:2057` already keeps a nested TOC's outer title. | |
| 8 | **Not an owner question:** a backlog item that needs real engine capability. The playback exclusion is already decided. | |
| 9 | **Not an owner question:** voice metadata needs engine data. The width-based spread loses nothing; keep it. | |
| 10 | **Settled: keep** all four. Removing any of them loses entry or information. | |
| 11 | **Settled: keep** the 403/session-loss guard. It's write safety, and removing it loses behaviour. | `account/AO3ChallengeSettingsEditState.kt:41` |

**P1 0 / P2 1 / P3 6 / unconfirmed 1**

---

## Triage (Claude, 2026-10-23)

Every finding was checked in the code before acting; all are real. Fixed before 3gx landed:
- **P2 Display's second engine:** the shared Listening form now makes its `AutomaticTTSService` off
  the UI thread (`produceState`, `Dispatchers.Default`, shut down when the form leaves) and shows a
  spinner until it is ready. Handing it the reader's controller was not taken: the form calls
  `stop()` when it closes and `setEngine` on every change, which would cut Read Aloud short.
- **P3 Library's series read twice:** preserved from the preview when it covers the series.
- **P3 tag rename:** recorded in DECISIONS (2026-10-23); the collision is matched with a Unicode
  case-insensitive compare over the user's tags, leaving the tag itself out.
- **P3 Work Detail's uncheck:** recorded in DECISIONS (parity with iOS).
- **P3 Group variants restore:** clears the "more than one name" filter, as the chip does.
- **P3 `GIT_BRANCH`:** opt-in with `-Pkudos.branchBuild`, as iOS's branch build script.
- **P3 tests that pass with their wiring reverted:** noted, not changed. Each covers the rule it
  names; the wiring is in screens with no test seam (About's `BuildConfig`, the reader's search
  result call site, the fandom list's stored setting and pull-to-refresh).
- **Unconfirmed (series pages read as a guest):** predates 3gx; left as a lead.
- **Owner questions:** A89's verdicts taken. Q1 and Q6 applied (the Works heading counts the works
  shown; Refine asks AO3 for tags); the kept Android extras are in DECISIONS; Q2 is owner question 34.
