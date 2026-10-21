# Brief 3fz results

Status: implementation complete; ready for Claude to build, test, visually verify, review, and land. No Gradle, commits, pushes, branch changes, sign-in, or AO3 traffic.

## #61 Converter stamp
done — Android version 1 and atomic sidecar writes; imports/rebuilds refresh the stamp, missing/unreadable records are stale, My copy immediately rebuilds stale works and only confirms current copies using iOS wording. Reader fan gains the stale-only rebuild pill and reloads after rebuilding.
- `android/app/src/main/java/io/github/cidy02/kudos/works/WorkConversionRecord.kt:10`: bump `CURRENT_VERSION` when Android converter output changes. Swift's numeric Date (seconds since 2001) is preserved. Additive `converterPlatform` identifies Android's scale; an unmarked/foreign record is conservatively stale even if its iOS version is larger. No schema or manifest version change.
- `android/app/src/main/java/io/github/cidy02/kudos/works/WorkImporter.kt:340`, `works/RebuildOriginalDialog.kt:50`, `works/detail/WorkDetailMyCopySheet.kt:601`, `reader/ReaderFanMenu.kt:119`: implementation paths (paths relative to Android source root where abbreviated).
- iOS rule: read-only `Services/WorkConversionRecord.swift:14`, `Services/WorkReconversion.swift:39`, `Features/WorkDetail/WorkProvenanceSections.swift:120`, `Features/ReaderReadium/ReadiumReaderView.swift:1933`. The named `Services/TTS/AutomaticTTSService.swift` is absent in this iOS checkout; actual speech references are under `Features/ReaderReadium/`.
- Transport was already real on both apps: iOS `Services/KudosBackupExport.swift:157` and `Services/FolderSyncService.swift:981`; Android `backup/BackupRepository.kt:191`, `backup/SyncRepository.kt:334` carry originals plus sidecars under `Originals/` with iOS UUID filenames. Android local storage retains existing lowercase `originals/`. Existing `OriginalsRoundTripTest` protects foreign-byte preservation and identity remapping.
- Tests added: `ReaderFanMenuTest.aStaleImportsRebuildPillUsesTheExistingFanAndDispatchesItsAction`, `WorkConversionRecordTest` (stale rules, independent scales, Swift Date shape, file round trip), `WorkReadingCopyTest` (import/rebuild stamping and local-state preservation). Tests not run: Gradle prohibited. UI not visually verified.

## #116 Hold-seek
done — Previous/Next preserve tap behavior and now repeat one paragraph per 180 ms hold tick. A hold pauses/cancels current playback, previews the queued paragraph, pulls the next paragraph on demand when needed, stops at bounds, and only resumes on release if it began playing. A hold begun paused remains paused until Play.
- `android/app/src/main/java/io/github/cidy02/kudos/reader/ReaderPositionCard.kt:466` (gesture and accessible tap), `reader/speech/ReaderSpeechController.kt:202` (paused seek and release), `reader/speech/ReaderSpeechSeek.kt:5` (pure stepping rule).
- iOS rule: read-only `Features/ReaderReadium/ReaderSpeechSkip.swift:62` (`seekIndex` returns nil at bounds), `ReadiumReaderView.swift:1738` (step) / `:1749` (resume only if previously playing). Android positions remain paragraph/chunk queue indices, rather than Readium pages.
- Tests: `ReaderSpeechSeekTest.eachHoldTickMovesOneParagraphAndBoundsNeverWrap`. Not run (Gradle prohibited); touch/accessibility/playing-versus-paused release still needs device verification.

## #85 Incremental speech loading
done — Replaced whole-publication `content.elements()` extraction with a pull source over Readium's content iterator, anchored to the live locator. Only the next speakable paragraph/chunk is extracted before its utterance; subsequent resources are pulled as playback reaches them, through EOF. The existing author's-notes filter retains its state between pulls. The mini-player's empty-content title/contents fallback is retained.
- `android/app/src/main/java/io/github/cidy02/kudos/reader/ReaderContentText.kt:24` (lazy iterator and stateful notes filter), `reader/ReaderSpeechSource.kt:4` (pull contract), `reader/speech/ReaderSpeechController.kt:245` (pull/speak loop), `reader/ReaderScreen.kt:614` / `:727` (both entry points).
- iOS rule: read-only `Features/ReaderReadium/ReaderSpeechController.swift:412` (`chapterUnits`, first href only), `:450` (`startSpeech`, current resource). The brief's line in `ReadiumReaderView.swift` now belongs to hold-seek in this checkout. Android is finer-grained: it starts after the first paragraph rather than after extracting the current chapter.
- Tests: `ReaderContentTextTest.firstSpeechComesFromTheCurrentResourceWithoutReadingOtherResources` (real Publication/ContentService seam, locator forwarded, counter proves next resource untouched at first utterance); `incrementalSpeechKeepsTheNotesSwitchAndReadsThroughTheLastResource` covers notes on/off and EOF; `ReaderSpeechSourceTest` covers fallback only for empty prose. Not run (Gradle prohibited).

## #88 Voice availability
not real — `android/app/src/main/java/io/github/cidy02/kudos/reader/speech/AutomaticTTSService.kt:65` already calls `packInstalled()` and `kokoro.ensureReady()` inside **every** `speak`, replacing the owner only at that boundary. Pause/resume remain with the engine speaking the current utterance (A49 F3). No production change needed.
- iOS rule: the brief's `Services/TTS/AutomaticTTSService.swift:45` is absent in this read-only checkout. Actual `Features/ReaderReadium/TTSService.swift:8` requires reevaluation for new playback; `ReaderSpeechController.swift:261` and `:473` select the available engine.
- Added `SystemTTSServiceTest.automaticChecksPackAvailabilityAgainBeforeEveryUtterance`: same service, pack absent → installed but unusable → removed, with device fallback and a per-utterance availability assertion. Not run (Gradle prohibited).

## Handoff checks
- `git diff --check` passes. Static scan of Android main sources found neither `(?U)` nor `UNICODE_CHARACTER_CLASS`; no new regex patterns introduced.
- Updated two superseded conversion-stamp statements in `docs/android-port/DECISIONS.md`.
- Left: Claude's Android build/JVM suites (including `RegexPortabilityTest`, `OriginalsRoundTripTest`, the changed/new suites), emulator review of stale/current rebuild and hold release while playing/paused, and a long-work smoke with notes on/off through chapter boundaries. No build/test success or visual correctness claimed.
- No `TASKS.md`, Room schema, manifest version, iOS tree, or git history edits. No AO3 traffic. Branch remains `android/agent-codex2-3fz`; changes intentionally uncommitted as dispatched.
