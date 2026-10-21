# Brief 3gc result

Branch: `android/agent-codex2-3gc`; starting HEAD: `7e38381d`.

Status: implementation and regression tests written; ready for Claude's build,
test, device review, and landing. No build/test success or visual correctness claimed.

Scope: fix the four review findings on 3fz. No commits, pushes, branch changes,
Gradle runs, sign-ins, AO3 traffic, or TASKS.md edits; Claude verifies and lands.

## Review fixes

### 1. Read Aloud preparation off Main — implemented

- `android/app/src/main/java/io/github/cidy02/kudos/reader/speech/ReaderSpeechController.kt:284`:
  `tts.speak` runs inside `withContext(Dispatchers.Default)`, including Automatic's
  per-utterance pack check and `kokoro.ensureReady()`. Queue mutations, navigator
  callbacks, and MediaSession publishing remain on Main.
- Regression: `ReaderSpeechControllerTest.enginePreparationRunsOffMain` injects
  a suspended engine and checks its actual coroutine dispatcher; without the fix
  it observes Main. Tests not run (Gradle prohibited).

### 2. Next/Previous during a pull — implemented

- `android/app/src/main/java/io/github/cidy02/kudos/reader/speech/ReaderSpeechController.kt:204`:
  skips park the active pull and join it before restarting. The loop queues its
  result before parking, so advancing the IO iterator cannot drop the paragraph.
  Repeated taps share one pending restart; Stop cancels that restart. EOF during
  a parked pull still permits Previous to return to an already queued paragraph.
- Regressions: `ReaderSpeechControllerTest.nextDuringAnIoPullRetainsTheTakenParagraphAndItsQueueIndex`,
  `previousDuringAnIoPullRetainsTheTakenParagraph`, and
  `repeatedSkipsDuringOnePullRetainEveryParagraph` suspend an IO pull after taking
  P1, skip, then check P1/P2/P3 remain at their original queue indices. The old
  cancellation loses P1 and fails these assertions. Tests not run.

### 3. Converter records — implemented

- `android/app/src/main/java/io/github/cidy02/kudos/works/WorkConversionRecord.kt:20`:
  only an explicitly Android record below Android's current version is stale.
  Missing/unreadable, unmarked (iOS/legacy), and foreign-platform stamps do not
  auto-rebuild or show the stale reader pill. Android writing remains tagged
  `converterPlatform = "android"`; no transport or schema changes.
- Regression: `WorkConversionRecordTest.onlyOlderAndroidStampsAreStale` fails
  without this fix for both low/high unmarked versions, explicit foreign stamps,
  and missing/unreadable records; it also protects old/current/future Android
  versions. Existing sidecar round-trip test protects the additive platform key.
- Tests not run (Gradle prohibited). iOS's matching rule is Claude's T-421 work.
- `WorkReadingCopyTest.foreignConverterRecordsNeverOfferAnAutomaticRebuild`
  (`android/app/src/test/java/io/github/cidy02/kudos/works/WorkReadingCopyTest.kt:203`)
  covers the importer predicate shared by My copy and the reader pill, at
  versions 0/9/999 with unmarked/iOS/other stamps. The existing rebuild test now
  supplies an explicitly old Android stamp and checks the replacement's platform.
  Updated the superseded rebuild rule in `docs/android-port/DECISIONS.md:2272`.

### 4. Hold-seek follows the reader — implemented

- `android/app/src/main/java/io/github/cidy02/kudos/reader/speech/ReaderSpeechSeek.kt:15`:
  resolve the chapter by href and step its Readium positions, preferring global
  position, then progression, then scaled visual-page metrics, as iOS does.
  Bounds never cross chapters. The seek session retains accepted targets while
  navigator callbacks lag, so repeated backward ticks can pass the speech start.
- `android/app/src/main/java/io/github/cidy02/kudos/reader/ReaderScreen.kt:361`:
  hold ticks call navigator `go` without animation and haptic on success; release
  builds a fresh `ReaderContentText` source at the final accepted locator,
  preserving the author's-notes preference.
- `android/app/src/main/java/io/github/cidy02/kudos/reader/speech/ReaderSpeechController.kt:231`:
  release replaces the old queue/source and resumes only if playing before the
  hold. A paused release waits for Play at the new locator.
- Regressions: `ReaderSpeechSeekSessionTest` checks page movement before the
  initial speech anchor, delayed navigator updates, chapter bounds, global vs
  visual position mapping, release re-anchoring, and rejected navigation.
  `ReaderSpeechControllerTest.holdReleaseReanchorsPlayingSpeechAtTheNewSource`
  and `holdReleaseKeepsPausedSpeechPausedUntilPlayAtTheNewSource` check playback
  and source replacement. The former queue-only implementation cannot satisfy
  these page/release assertions. Tests not run; touch/page/audio QA remains Claude's.
- iOS references read: `Features/ReaderReadium/ReaderSpeechSkip.swift:62`,
  `ReadiumReaderView.swift:1714–1755`, `ReaderPageMetrics.swift:45` in the
  read-only `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` tree.

## Handoff checks

- `git diff --check` passes. Static scan of Android main sources found neither
  `(?U)` nor `UNICODE_CHARACTER_CLASS`; no regex patterns changed.
- New suites: `ReaderSpeechControllerTest` and `ReaderSpeechSeekSessionTest`.
  Existing suites updated: `WorkConversionRecordTest`, `WorkReadingCopyTest`,
  and the position-step test name in `ReaderSpeechSeekTest`.
- Claude should run those suites plus `ReaderContentTextTest`,
  `ReaderSpeechSourceTest`, `SystemTTSServiceTest`, `OriginalsRoundTripTest`,
  `ReaderFanMenuTest`, and `RegexPortabilityTest` with the normal Android gate.
- Manual: download a voice pack then start speech while interacting with the
  reader; tap Next/Previous rapidly across a resource boundary; hold backward
  past the speech start and forward to the chapter bound; release playing and
  paused, and confirm page movement and the first spoken words at the new page.
- No local `READIUM_MIGRATION_NOTES.md` was present in this worktree or found in
  the lane/iOS checkout; the live read-only iOS hold-seek code was used directly.
- Branch and HEAD remain `android/agent-codex2-3gc` / `7e38381d`. Changes are
  intentionally uncommitted. TASKS.md, iOS sources, signing/project settings,
  Room schema, manifest versions, backup/sync transport, and AO3 networking are
  untouched. No Gradle or network commands were run.
