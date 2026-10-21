# Brief 3gd result — Settings › Listening: voice pack, Engine, Pitch (A66 #15, #16)

Branch: `android/agent-opus-3gd` (not committed, per brief).

Status: complete.

## What the earlier model had done (and what was fixed/finished)

The earlier model stopped at its quota after touching 10 tracked files and creating `VoicePackState.kt` and `ListeningSpeechSettings.kt` without wiring `SettingsListeningPage.kt` or writing tests:

1. **Kept from the earlier model:**
   - `android/app/src/main/java/io/github/cidy02/kudos/reader/speech/VoicePackState.kt:11-60` — sealed `VoicePackState` (`NotDownloaded`, `Downloading(progress)`, `Extracting`, `Cancelling`, `Downloaded`, `Failed(message)`) and `VoicePackState.from(WorkInfo?, installed, cancelling)`.
   - `android/app/src/main/java/io/github/cidy02/kudos/reader/speech/TTSDownloadWorker.kt:67-68` and `ReaderSpeechController.kt:150-152` — shared `TTSDownloadWorker.cancel(context)`.
   - `android/app/src/main/java/io/github/cidy02/kudos/reader/settings/ReaderSpeechPreferences.kt:5-79`, `ReaderPreferences.kt:45-46`, `SettingsRepository.kt:145-189`, `:678-679` — `pitch` (`0.75f..1.25f`, step `0.05`, default `1.0f`) and `engine` (`""`, `"system"`, `"kokoro"`), DataStore keys `readerSpeechPitch` and `readerSpeechEngine`, `updateSpeechPitch`, `updateSpeechEngine`, and reset in `resetSpeechPreferences()`.
   - `android/app/src/main/java/io/github/cidy02/kudos/reader/ReaderViewModel.kt:118-123`, `:482-490` and `ReaderScreen.kt:1115-1124` — persisted reader Pitch slider using `ReaderSpeechPreferences.PITCH_RANGE`, `PITCH_STEPS`, and `speechPitchLabel`.
2. **Fixed in the earlier model's code:**
   - `android/app/src/main/java/io/github/cidy02/kudos/settings/ListeningSpeechSettings.kt:10-12` — removed invalid `import androidx.compose.foundation.layout.weight` (in Compose `Modifier.weight` is a `RowScope` member extension; the top-level import does not exist and would fail compilation).
   - `android/app/src/main/java/io/github/cidy02/kudos/reader/speech/TTSService.kt:24-27`, `KokoroTTSController.kt:107`, `:221`, `AutomaticTTSService.kt:30-35`, `:102`, `:229` — added `ensureReady()` and `shutdown()` to `TTSService` and widened `AutomaticTTSService`'s `kokoro` and `device` constructor parameters to `TTSService` (keeping the same defaults) so unit tests can verify engine routing with both engines ready in JVM tests.
   - `android/app/src/main/java/io/github/cidy02/kudos/reader/settings/ReaderSpeechPreferences.kt:59-62` — accepted `"device"` as a synonym for `ReaderTTSEngineKind.SYSTEM` (`"system"`) in `ReaderTTSEngineKind.from`.
3. **Finished:**
   - Wired `SettingsListeningPage.kt` to `rememberVoicePackUi`, `ListeningVoicePackSection`, `ListeningEngineRow`, `ListeningPitchRow`, `service.setEngine(speech.engine)`, and `ReaderTTSEngineKind.effective`, keeping `Voice` and its separator untouched so the concurrent Pronunciations change merges cleanly.
   - Added unit and Compose UI tests in `SettingsListeningPageTest.kt`, `SettingsRepositoryTest.kt`, and `SystemTTSServiceTest.kt`.

---

## 1. #15 — Voice pack on the Listening page

### What changed
- `android/app/src/main/java/io/github/cidy02/kudos/reader/speech/VoicePackState.kt:11-60` — maps `TTSDownloadWorker` `WorkInfo` state, `KEY_PHASE` (`"downloading"` / `"extracting"`), `KEY_PROGRESS`, `KEY_ERROR`, `installed`, and `cancelling` into `VoicePackState` (`NotDownloaded`, `Downloading(progress)`, `Extracting`, `Cancelling`, `Downloaded`, `Failed(message)`).
- `android/app/src/main/java/io/github/cidy02/kudos/reader/speech/TTSDownloadWorker.kt:67-68` and `ReaderSpeechController.kt:150-152` — extracted `TTSDownloadWorker.cancel(context)` (`WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)`) so the reader and Settings › Listening share both `enqueue` and `cancel`.
- `android/app/src/main/java/io/github/cidy02/kudos/settings/ListeningSpeechSettings.kt:54-217` — added `VoicePackUi`, `rememberVoicePackUi(context)` (observing `WorkManager.getInstance(context).getWorkInfosForUniqueWorkFlow(TTSDownloadWorker.WORK_NAME)` and recomputing `TTSDownloadWorker.isModelDownloaded(context)` on state changes), and `ListeningVoicePackSection`:
  - `NotDownloaded`: `"Download Voice Pack"` action row, which opens a confirmation `AlertDialog` titled `"Download Efficient (Int8) Voice Pack?"` with message `"Kudos downloads this public Voice Pack from GitHub. Nothing about your reading or library is sent, but the provider or its delivery service can receive your IP address and basic connection details."` and buttons `"Download 103 MB"` / `"Cancel"`.
  - `Downloading(progress)`: `LinearProgressIndicator`, `"Downloading... N%"`, and `"Cancel"` button.
  - `Extracting`: spinner row `"Extracting..."` with `"Cancel"` button.
  - `Cancelling`: spinner row `"Cancelling…"`.
  - `Failed(message)`: error text and `"Retry Download"` action row (which opens the confirmation dialog).
  - `Downloaded`: `"Voice Pack Downloaded"` row with green checkmark.
  - Section footer: iOS's `VOICE_PACK_DISCLOSURE` (preserving Android's `"The installed voice pack could not be opened."` prefix when `packFailedToOpen` is true).
- `android/app/src/main/java/io/github/cidy02/kudos/settings/SettingsListeningPage.kt:41-59`, `:154-159` — wired `rememberVoicePackUi(context)` and replaced the static `"Kokoro Pack"` section with `ListeningVoicePackSection`.

### iOS code followed
- `Features/ReaderReadium/ReaderSpeechSettingsSection.swift:305-429`, `:530-555` (`sherpaDownloadSection`, `packStatusViews`, `busyRow`, `downloadOrRetryButton`, `selectedPackSizeLabel`, `selectedPackHostName`, `downloadDisclosure`).
- `Features/ReaderReadium/KokoroModelConfiguration.swift:7-18` (`KokoroModelPack.int8V019.displayName = "Efficient (Int8)"`).
- `Features/ReaderReadium/TTSDownloadManager.swift:13-22` (`TTSDownloadManager.Status`).

---

## 2. #16 — Engine and Pitch

### What changed
- `android/app/src/main/java/io/github/cidy02/kudos/reader/settings/ReaderSpeechPreferences.kt:5-79` and `ReaderPreferences.kt:45-46` — added `pitch: Float = DEFAULT_PITCH` (`0.75f..1.25f`, step `0.05`, `PITCH_STEPS = 9`, `clampPitch`) and `engine: String = AUTOMATIC_ENGINE` (`""` for Automatic, `normalizeEngine`), plus `ReaderTTSEngineKind` (`SYSTEM("system", "Device voice")`, `KOKORO("kokoro", "Kokoro")`, `preferred`, `effective`). `ReaderSpeechPreferences.applyTo` copies both `speechPitch` and `speechEngine` onto `ReaderPreferences`.
- `android/app/src/main/java/io/github/cidy02/kudos/data/preferences/SettingsRepository.kt:145-189`, `:678-679` — persisted `readerSpeechPitch` (`Keys.SpeechPitch`) and `readerSpeechEngine` (`Keys.SpeechEngine`), added `updateSpeechPitch` and `updateSpeechEngine`, and cleared both in `resetSpeechPreferences()`.
  - **Backup check:** iOS `Services/KudosBackup.swift:1724-1820` (`KudosBackupSettings`) does not back up any `readerSpeech*` keys (`readerSpeechEngine` and `readerSpeechPitch` live only in `UserDefaults`, `Features/ReaderReadium/ReaderSpeechPreferences.swift:15-21`). Android matches iOS by keeping `readerSpeechPitch` and `readerSpeechEngine` as device-local DataStore keys outside `KudosSettings` / `BackupSettings` (manifest stays v8 with no changes).
- `android/app/src/main/java/io/github/cidy02/kudos/reader/speech/TTSService.kt:24-34` and `AutomaticTTSService.kt:38-100` — added `setEngine(engine: String)` to `TTSService` (called by `applySpeechPreferences`) and implemented it in `AutomaticTTSService`:
  - `Automatic` (`""`) uses `kokoro` when the pack is installed and ready, otherwise `device`.
  - `Kokoro` (`"kokoro"`) uses `kokoro` when the pack is installed and ready, and falls back to `device` when the pack is not installed or fails to open (matching iOS `ReaderTTSEngineKind.effective`).
  - `Device voice` (`"system"`) forces `device` even when the Kokoro pack is installed, and reports `emptyList()` for `availableVoices` (since the device voice uses the system TTS engine's on-device voice).
  - **Where Pitch applies vs cannot:** `AutomaticTTSService.setPitch(pitch)` (`AutomaticTTSService.kt:93-96`) forwards pitch to both engines. `SystemTTSService.setPitch` (`AutomaticTTSService.kt:225-227`) applies it to `android.speech.tts.TextToSpeech.setPitch`. `KokoroTTSController.setPitch` (`KokoroTTSController.kt:245-248`) is a documented no-op because `sherpa-onnx`'s `OfflineTts` has no pitch control (matching iOS `SherpaKokoroTTSService.setPitch`).
- `android/app/src/main/java/io/github/cidy02/kudos/settings/ListeningSpeechSettings.kt:220-276` and `SettingsListeningPage.kt:71-73`, `:138`, `:166-168`, `:199-201`, `:212` — added `ListeningEngineRow` (with the iOS `isKokoroAwaitingVoicePack` note when Kokoro is selected without the voice pack installed) and `ListeningPitchRow` (`0.75–1.25`, step `0.05`, formatted as `"Default"` at `1.0` or `"%.2f×"`), updated `service.setEngine(speech.engine)` when preferences change, and updated the Audition active Engine row to `ReaderTTSEngineKind.effective(speech.engine, installed).displayName`.
- `android/app/src/main/java/io/github/cidy02/kudos/reader/ReaderViewModel.kt:118-123`, `:482-490` and `ReaderScreen.kt:1115-1124` — aligned the in-reader Display & Themes Pitch slider with the persisted `ReaderSpeechPreferences` range (`0.75f..1.25f`), steps (`9`), and label (`speechPitchLabel`).
- **Developer Settings:** left out per recorded decision (`DECISIONS.md` 2026-10-05 / brief 3ak), because Android has no speech pause/chunk/boundary tuning pipeline behind `ReaderSpeechDeveloperSettingsView`.

### iOS code followed
- `Features/ReaderReadium/ReaderSpeechSettingsSection.swift:68-73` (`Picker("Engine")`), `:120-131` (`isKokoroAwaitingVoicePack`), `:171-192` (`Pitch` slider and `Reset Read Aloud`), `:503-512` (`effectiveEngineKind`), `:637-640` (`pitchLabel`).
- `Features/ReaderReadium/ReaderSpeechPreferences.swift:15-30`, `:52-57`, `:88-94`.
- `Features/ReaderReadium/TTSService.swift:10-42` (`ReaderTTSEngineKind`).

---

## 3. Tests

- `android/app/src/test/java/io/github/cidy02/kudos/data/preferences/SettingsRepositoryTest.kt:300-342` (`speechEngineAndPitchRoundTripClampNormalizeResetAndStayOutOfBackupSettings`) — verifies `updateSpeechPitch` and `updateSpeechEngine` persistence round-trip, pitch clamping (`0.75f..1.25f`, `NaN` → `1.0f`), engine normalization (`"device"` → `"system"`, unknown → `""`), `applyTo(ReaderPreferences())`, exclusion from `BackupSettings` / `replaceAll`, and reset via `resetSpeechPreferences()`.
- `android/app/src/test/java/io/github/cidy02/kudos/reader/speech/SystemTTSServiceTest.kt:123-171` (`automaticHonoursEngineChoiceFallsBackWhenKokoroPackMissingAndForwardsPitch`) — verifies `AutomaticTTSService` routes `speak()` and `availableVoices` according to the chosen engine (`""` Automatic, `"system"` Device voice, `"kokoro"` Kokoro with pack installed and fallback to Device voice when pack is missing) and forwards `pitch` to the underlying engines.
- `android/app/src/test/java/io/github/cidy02/kudos/settings/SettingsListeningPageTest.kt:124-273`:
  - `resetReadAloudClearsExplicitVoiceRatePitchAndEngineWithoutChangingBackupSettings` (`:124-152`) — verifies `"Reset Read Aloud"` resets voice, rate, pitch, and engine to defaults without altering `KudosSettings`.
  - `engineChangedOnListeningPersistsReachesServiceAndWarnsWhenKokoroPackIsMissing` (`:155-176`) — verifies selecting `"Kokoro"` and `"Device voice"` in the Engine row persists to `SettingsRepository`, reaches `TTSService.setEngine`, and shows/hides the missing-pack info message.
  - `voicePackSectionShowsConfirmationProgressCancelRetryAndInstalledStates` (`:179-266`) — verifies `VoicePackState.from` mapping and `SettingsListeningPage` UI states: `"Download Voice Pack"` + confirmation dialog (`"Download Efficient (Int8) Voice Pack?"`, disclosure text, `"Download 103 MB"`, `"Cancel"`), `"Downloading... 42%"` + `"Cancel"`, `"Extracting..."` + `"Cancel"`, `"Cancelling…"`, `"Retry Download"` on failure, and `"Voice Pack Downloaded"`.
