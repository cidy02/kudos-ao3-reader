# 3gf — Reader parity handoff

Owner: Codex · Branch: `android/agent-codex2-3gf` · Base: `8becf4c2`.

Status: implementation and regressions written; ready for Claude verification. Scope: F22 chapter transport and standalone mini-player,
A61 #29 compact section pills, F21 reader font import/delete.

No commits, pushes, branch changes, sign-in, Gradle runs or AO3 traffic are authorized.
Claude owns builds, test execution, visual verification and landing.

Android paths below are relative to `android/app/src/main/java/io/github/cidy02/kudos/`
unless a full path is given. Test paths are under `android/app/src/test/java/io/github/cidy02/kudos/`.

## Implementation

### 1. F22 — chapter transport

- `android/app/src/main/java/io/github/cidy02/kudos/reader/speech/ReaderSpeechSkip.kt:6`
  selects the first position of the next spine item; Previous restarts the current
  item after page 2, otherwise selects the previous item. First item/page 1 and
  last-item Next are no-ops; missing positions do not fall back to paragraphs.
- `reader/ReaderScreen.kt:398` wires the latest reader position and publication
  into the controller's chapter callbacks. Accepted navigation reanchors speech
  through the existing seek lifecycle, retaining paused versus playing state
  and the author's-notes preference.
- `reader/speech/ReaderSpeechController.kt:196` dispatches both mini-player and
  MediaSession skips through those same callbacks. Removed the superseded
  paragraph-skip restart path. Hold-seek's position mapping/session is retained.
- iOS followed (paths under `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`):
  `Features/ReaderReadium/ReaderSpeechSkip.swift:9`,
  `ReadiumReaderView.swift:1664`–`:1707`,
  `ReaderSpeechController.swift:878` / `:902`.
- Tests added: `ReaderSpeechSkipTest` (restart/near-start/bounds/spine items),
  `ReaderSpeechControllerTest.playerAndMediaSessionDispatchTheSameChapterActions`,
  `chapterTapDuringAPullReplacesTheOldSourceAndCannotSpeakItsLateParagraph`.
  The old paragraph-skip tests were replaced because taps now leave the chapter;
  existing paused/playing reanchor tests remain. Added
  `chapterTapWhilePausedWaitsForPlayAtTheNewChapter` and
  `lateOldChapterPullCannotClearTheNewPullsPauseGuard`: `ReaderSpeechController.kt:227`
  now prevents late completion of cancelled old-chapter IO from clearing a new
  chapter's in-flight pull guard. Stop resets the guard. Not executed.

### 2. F22 — standalone mini-player

- `reader/ReaderScreen.kt:753` keeps the bottom transport visible during playing
  and paused speech when chrome is hidden. `reader/ReaderPositionCard.kt:92`
  decouples its player from progress/slider/separator; caption/background taps
  reveal full chrome. Stop ends speech without hiding visible reader chrome.
  Existing model-download controls remain available.
- Transport accessibility labels now say Previous chapter / Next chapter;
  Material icons, hold-to-seek callbacks, and shared controls remain in use.
- iOS followed: `Features/ReaderReadium/ReadiumReaderView.swift:1059`–`:1114`
  (`bottomChromeLayer`, `standaloneMiniPlayer`, `speechMiniPlayer`).
- Tests added: `ReaderPositionCardTest.standaloneTransportSurvivesHiddenChromeAndPausedPlayback`
  and `holdingTransportSeeksPositionsWithoutDispatchingAChapterTap`. Not executed.

### 3. A61 #29 — compact section labels and the iPhone contract

- `reader/ReaderSection.kt:37` implements iOS `pillLabel`: P / S / A for
  Preface/Summary/Afterword, `N/M` (numeric chapter / posted-or-derived total)
  for story chapters, empty for Other. `reader/ReaderProgressDisplay.kt:33`
  resolves the compact label from progress and posted chapter totals; missing,
  Other and out-of-range sections return null for percent-only fallback.
- **Source discrepancy, resolved in favor of the owner's “match iPhone”:**
  the supplied iOS `Reading/ReaderSection.swift:32` defines the compact labels,
  but its production caller is the legacy reader's `Features/Reader/ReaderView.swift:275`
  (`currentSectionLabel`, used by paged `positionLabel` at `:256`). The iPhone's
  current `Features/ReaderReadium/ReadiumReaderView.swift:1768` instead constructs
  `ReaderPositionSummary`, whose `ReaderTimeEstimate.swift:136` place resolution
  and work line use full section names and “Chapter N of M”. There are no
  literal N or M section kinds. Android's current position card matches that
  iPhone behavior, so its visible full-word labels are retained. The compact
  formatter is available with regression tests; it is deliberately not wired into the full card
  or used to introduce a new pill absent from the iPhone.
- An optional clarification was sent during work; absent a response, the explicit
  iPhone instruction and source above determine the implementation.
- Tests added: `ReaderProgressDisplayTest.compactPillsMatchTheIosReferenceWithoutChangingTheIphoneCardWords`
  (101 story chapters, P/S/A, posted totals, unknown totals, out-of-range/missing),
  `compactPillsKeepOtherSectionsEmptyAndSingleChapterIsOneOfOne` (Other,
  malformed-index parity, 1/1). Follows
  `/Users/cidy02/kudos-ios-polish/KudosTests/ReaderSectionTests.swift:64`–`:108`.
  Not executed.

### 4. F21 — reader fonts reuse Settings import/delete

- `settings/SettingsPages2.kt:464` extracts the existing font list/picker/status
  code as shared `ReaderFontSection`. Settings › Font delegates to it at `:455`;
  `reader/ReaderScreen.kt:1213` uses it in Display & Themes. Both list built-ins
  then imported fonts, select with a checkmark, offer Add Font…, and allow
  deletion only for imported fonts with a Material delete button.
- Import and deletion still call `files/CustomFontRepository.kt:42` / `:107`.
  No repository, Room, file-store, settings schema or backup changes. Its 3ga
  refusals remain in force. Mixed success/refusal batches now keep the refusal
  reasons visible instead of replacing them with only a success count.
- `reader/readium/ReadiumNavigatorHost.kt:154` rebuilds font declarations at the
  controller's live locator instead of the original opening locator. Its mount
  and disposal at `:189` / `:197` complete the fragment transactions synchronously;
  a font-triggered replacement can no longer reuse a fragment pending removal
  and then lose it when that removal commits. The replacement lifecycle needs
  device verification; the Compose font tests cover list/picker/repository wiring.
- iOS followed: `Settings/SettingsView.swift:154`–`:211`
  (`ReaderFontSection`, `deleteCustomFonts`, shared importer). Selected-font
  deletion resets to System through Android's existing repository behavior.
- Tests added: `ReaderFontSectionTest.readerListsSelectsImportsAndDeletesFontsThroughTheSettingsRepository`
  drives the reader sheet and its document-picker callback with a real local
  font; `readerImportKeepsExistingFontsAndExplainsRejectedFilesIncludingPartialSuccess`
  covers malformed/unsupported file refusals and a mixed batch. Existing
  `CustomFontRepositoryTest` covers byte limits, metadata/file deletion, and
  fallback. Not executed.

## Verification / remaining work

- Initial tree clean; dispatched branch confirmed.
- Local `READIUM_MIGRATION_NOTES.md` absent; using the explicitly supplied iOS
  source tree read-only for this Android-only brief.
- `git diff --check`: passed. Read-only source/caller review completed. No new
  regex or regex flags; no dependency, Room, backup, signing or project changes.
- No Gradle, builds, tests, AO3 requests, sign-in, commits, pushes or branch changes
  were performed. All implementation and added tests remain uncommitted as requested.
- Claude: compile Android, run `ReaderSpeechSkipTest`, `ReaderSpeechControllerTest`,
  `ReaderSpeechSeekTest`, `ReaderSpeechSeekSessionTest`, `ReaderPositionCardTest`,
  `ReaderProgressDisplayTest`, `ReaderFontSectionTest`, `CustomFontRepositoryTest`,
  `ReaderSettingsMapperTest`, `ReaderFragmentRestoreTest`, `RegexPortabilityTest`,
  and the normal regression suite. No test success is claimed.
- Manual: with a local multi-spine EPUB, test chapter skips from mid-chapter,
  pages 1/2, first/last item, and MediaSession (playing and paused); hold both
  controls with chrome hidden; reveal chrome by caption tap; Stop with chrome
  up/down. Import/select/delete a font mid-work and confirm actual glyph changes,
  no blank navigator, and the current location survives; selected-font deletion
  returns to System. Check Light/Sepia/Dark/OLED and large text. No UI rendering
  or visual correctness is claimed.
- No separate port/cherry-pick needed: work is on the dispatched Android branch.
  No iOS files were edited. Source discrepancy for #29 is documented above; if
  the owner instead chooses compact visible card labels, that is a UI decision
  for Claude to apply before landing.

## 2026-10-21 — follow-up on lane verification failures

- Removed only the local 3gf row from `TASKS.md`, as dispatched. No replacement
  task row or other task-board edits. Preserved Claude's `ReaderScreen.skipChapter`
  compile fix: `endSeeking(ReaderContentText.source(... readsAuthorNotes()))`
  remains inside `scope.launch`; this follow-up does not edit `ReaderScreen.kt`.
- **Font rejection test:** `ReaderFontSectionTest.readerImportKeepsExistingFontsAndExplainsRejectedFilesIncludingPartialSuccess`
  now compares the expected `CustomFont.dateAdded` at millisecond precision.
  `KudosTypeConverters.instantToEpochMillis` / `epochMillisToInstant` persist that
  precision; all other font fields remain part of the equality assertion. Storage
  and import behavior are unchanged.
- **Standalone player test:** `ReaderPositionCardTest.standaloneTransportSurvivesHiddenChromeAndPausedPlayback`
  now finds the caption with `useUnmergedTree = true` before `performClick`.
  The clickable strip merges the caption's semantics, so the previous lookup
  targeted the whole strip; Android Compose's `performClick` injects a touch at
  the selected node's center, over the transport controls. The new lookup taps
  the caption bounds and exercises the existing background callback. Production
  UI is unchanged. This follows iOS `ReadiumReaderView.speechMiniPlayer` and
  `ReaderSpeechMiniPlayer.body`: non-control caption/background taps reveal
  chrome, while transport buttons handle their own actions.
- **Real stale-pull bug:** `ReaderSpeechController.speakCurrent` now calls
  `ensureActive()` immediately after `nextParagraph()`, before changing the shared
  queue, source, or playback state. The existing job-identity guard in
  `nextParagraph` protected the new pull's pause guard, but did not stop cancelled
  old-chapter IO returning from `NonCancellable` and adding its text to the new
  queue. Late null results could also clear the new source and mark it stopped.
  Cancellation now discards both results. This preserves iOS chapter reanchoring
  (`ReaderSpeechController.reanchor` / `startSpeech`, which cancels the prior
  extraction task) and the paused-versus-playing contract.
- Kept `lateOldChapterPullCannotClearTheNewPullsPauseGuard` and its expected
  **New chapter.** assertion unchanged. Added
  `ReaderSpeechControllerTest.lateOldChapterEndCannotStopTheNewChapterPull` for
  the late-null case while a new chapter pull is pending.
- Verification: source/caller review and `git diff --check` only. No Gradle,
  build, test execution, UI verification, commit, push, or branch change in this
  follow-up. Claude should rerun the three reported tests, the new late-null
  regression, and the reader speech/seek suites before landing. The earlier
  lane report (three failures, 3,159 passes) is dispatch evidence, not a rerun here.
