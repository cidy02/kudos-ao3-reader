# Brief 3ak result: Settings › Listening

**Landing note (Claude, 2026-10-05).** Landed as written, with the tests' waits made patient
enough for a first composition under Robolectric and given a tall window (the page is a lazy
list, and a section below the fold is not there to be found). Gate green (1,421 tests). Seen on
the emulator in Light, Dark and at the largest text size: the three sections in iOS's order,
the rows opening their menus' values, the sliders, and the footnotes. **Not heard:** the
emulator has no voice pack and no network, so Play Sample is greyed out there and nothing was
spoken; the changes to the speech engine's start, stop and shutdown were read, not run.
Two things a reader will notice: the reader's own speed control now stops at 1.5x, as iOS's
does (it went to 2.0x), and a chosen voice and speed are now remembered between sessions.

| iOS order / control label | iOS footnote or hint | Values and default | Android engine / store before this change |
| --- | --- | --- | --- |
| Audition Voice › Sample Text | “Play a sample to hear your current Read Aloud settings without opening a work.” (section footer) | Dialogue-heavy, Numbers & Names, Plain Narration; default Plain Narration; view-local | Existing `TTSService.speak(text)` can audition without a reader; no stored sample selection needed. |
| Audition Voice › Speed | Same audition footer | 0.5–1.5, steps 0.05; default 1.0 (“Default (1.0x)”) | Engine supports 0.5–2.0; reader's value is session-only, not persisted. |
| Audition Voice › 0.9x / 1.0x (default) / 1.1x | Same audition footer | Three shortcuts to the **same** Speed value | Engine supports all three; same session-only rate. |
| Play Sample / Playing Sample / Stop (with Engine and Voice while playing) | Same audition footer | Play when idle; Stop when playing | Existing Kokoro service can speak and stop local sample text; no preview UI yet. |
| Kokoro Pack (iOS 26) / Kokoro Neural Engine (iOS 27+) › install / retry / cancel / status | Int8: “The Int8 Voice Pack downloads its public files from GitHub.” Disclosure continues: Kudos sends no book text, audio, AO3 login details, library, reading history, usage data, or account identifiers; host sees IP/basic connection details. FP32: 345 MB, up to 900 MB free, Hugging Face fixed revision. Core ML: uses fastest device processor; GitHub Releases download; no book text/audio/library sent, IP/basic connection details visible to GitHub. | Int8 default; FP32 on 26; Core ML pack on 27+; actions: Download Voice Pack / Download Official FP32 Model / Download Kokoro (Neural Engine), Retry Download, Cancel; confirmation: Download 103 MB (Int8) / Download 345 MB (FP32) / Download (Core ML), Cancel; states reflect disk/download | Android only has the Int8 pack and `TTSDownloadWorker.isModelDownloaded`; existing reader can enqueue downloads. This brief forbids any new network request, so Listening shows local status only, no download action. |
| Read Aloud › Engine | 27+ footer: “Automatic starts with an Apple voice, then uses Kokoro on the Neural Engine after you install its optional voice pack. Kudos doesn't send your reading, your library or any usage data.” 26 footer: “Automatic starts with an Apple voice, then uses Kokoro after you download its optional Int8 Voice Pack. Full precision (FP32) is a separate download from Hugging Face. Kudos doesn't send your reading, your library or any usage data.” | Automatic (empty ID), Apple, Kokoro (Neural Engine); default Automatic | Kokoro only; no engine preference or system fallback. |
| Kokoro model (26 only) | FP32 unavailable: official Hugging Face voice data, reuses Int8 voices/speech files; until finished hears Int8 or Apple | Efficient (Int8), Full precision (FP32); default Int8 | Fixed Int8 engine; no model preference. |
| Kokoro compute (26 only) | Core ML: “Choosing Core ML asks your device to use it, but the Neural Engine may not be used.” | CPU, Core ML (Experimental); default CPU | Fixed CPU; no provider preference; Core ML is Apple-only. |
| Read author's notes | Accessibility hint: “Author's notes often carry content warnings. Turn this off to hear only the story.” | On/off; default **on** | No note-filtering preference or speech extraction classification. |
| Voice | Automatic: “Chooses the best installed voice for this work’s language” / “Currently …”; Installed Voices show quality and language | Automatic (best available), installed engine voices; default Automatic (empty ID) | Nullable session-only ID; engine reports exactly `numSpeakers()` entries named `Voice N`; only installed pack voices, no quality/language metadata. Null previously did not clear a live explicit voice. |
| Pronunciations | No row footnote | None / count; opens overrides, default None | No Android speech override engine/store/UI. Backup passthrough is outside this brief. |
| Developer Settings | No row footnote | Default / Modified; opens tuning settings, default Default | No Android equivalent tuning store or processing pipeline. |
| Read Aloud › Speed | Read Aloud section footer above | 0.5–1.5, steps 0.05; default 1.0 (“Default”, otherwise percent) | Supported engine; session-only rate. |
| Pitch | Read Aloud section footer above | 0.75–1.25, steps 0.05; default 1.0 (“Default”, otherwise 2-decimal multiplier) | Reader has session-only pitch, but `KokoroTTSController.setPitch` is explicitly a **no-op**. Omit this control. |
| Reset Read Aloud | Read Aloud section footer above | Resets engine, voice, speed, pitch, model, compute; **does not reset author's notes** | Can reset supported Voice/Speed; unsupported settings omitted. |

## Reference and findings

Read-only reference: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Settings/SettingsRoute.swift` → `SettingsHubView.swift` → `SettingsReadingPages.swift::SettingsListeningPage` → `ReaderSpeechSettingsSection.swift`, including `ReaderSpeechAuditionHarness.swift`, `ReaderSpeechPreferences.swift`, `TTSService.swift`, `KokoroModelConfiguration.swift`.

**iOS code wins:** the audition harness is actually present before the pack and Read Aloud sections; it is not debug-only. The two Speed controls and three shortcuts write one rate. Android's old reader range is 0.5–2.0; this page and reader use iOS's 0.5–1.5 / 0.05. Android's voice names are reported generic names, not invented Apple/Kokoro names. Automatic falls back to Android's speaker 0; Android cannot yet select the best voice by language/quality.

`ReaderViewModel.setSpeechRate` / `setSpeechVoiceIdentifier` originally only copied `ReaderPreferences` in session memory. `SettingsRepository` had no speech keys. Implementation puts supported speech values in the existing settings DataStore, outside `KudosSettings` / backup DTOs, and both screens write those keys. No Room or archive change.

`ReaderScreen` configures the speech controller when its preferences change; `configure` sets the engine rate/voice. Kokoro reads these at `generate` for the next chunk; audio already generated is not regenerated mid-chunk. Both entry points retain this behavior in the source; runtime confirmation is pending. iOS's audition harness additionally restarts a playing sample on sample/rate/voice changes; Android's audition does the same.

## Missing, needs engine work

- Engine choice / Automatic system fallback: implement Android system TTS, engine dispatch and language/quality-based automatic selection. A one-choice Engine menu would do nothing.
- FP32 / compute choice / Neural Engine pack: install and validate additional models, configure compatible Android providers and retain safe fallback. Core ML is Apple-specific. Int8 pack download already exists in the reader but is intentionally excluded here by the no-new-network rule.
- Read author's notes: classify extracted content and filter note bodies according to a persisted preference, retaining warnings by default.
- Pronunciations: add local override storage and apply overrides in the synthesis text/phoneme path, then build its editor.
- Developer Settings: port actual supported synthesis tuning and persist it; do not expose cosmetic settings without engine effects.
- Pitch: implement pitch processing or use an engine that supports it; current Kokoro method does nothing.
- Voice metadata: engine only supplies speaker indices; need a real installed-pack catalog for human names, language and quality. Listening must show the engine's existing names and on-device availability.

## Implementation

- `SettingsListeningPage.kt`: replaces the placeholder with Audition Voice → local Kokoro Pack status → Read Aloud, preserving supported iOS labels and order. Sample selection and Voice are whole-row Material dropdowns. Sample strings, order and default are copied from iOS. Three comparison actions use settings action rows, as required by Android chrome, rather than SwiftUI bordered buttons. The unsupported Apple/fallback sentences of the iOS footer are omitted; its final privacy sentence is retained. No network action is wired.
- `SettingsRepository.speechPreferences`: one existing DataStore, two device-local keys (`readerSpeechRate`, `readerSpeechVoiceID`). No fields added to `KudosSettings`, backup DTOs or Room. `replaceAll` does not touch these keys; general Reset settings clears them along with other local settings.
- `ReaderViewModel`: loads the saved speech snapshot on open, observes it for an open reader, and sends reader Voice/Speed changes through the same repository setters. `ReaderSpeechPreferences.applyTo` overlays only speech fields, retaining display preferences.
- `TTSService.applySpeechPreferences`: the actual path used by `ReaderSpeechController.configure` and sample playback. Automatic always applies speaker 0, clearing a previous explicit voice; unavailable/invalid speaker IDs also fall back to 0 in the Kokoro engine. Best-by-language selection remains missing engine work.
- `SubjectSliderRow`: the existing settings slider was found in `SettingsPages.kt`, reused and moved beside the chrome rows in `SettingsChrome.kt`. It now has token colours, explicit line heights and accessibility label/value. Both Listening sliders and the reader use 0.5–1.5 / 0.05; persistence happens when the slider interaction finishes, matching the existing reader control's timing.
- Shared settings action/group/form/header text receives explicit line heights. No literal colours, glass/capsule controls, Material buttons or outlined fields were added to Listening.
- `KokoroTTSController`: sample restart waits for cancelled native synthesis to finish before reusing its model; the synthesis job alone releases its AudioTrack, with stop/pause/release guarded against stale-track access. Disposal stops playback, joins synthesis, releases `OfflineTts`, then cancels its scope. The bundled `sherpa-onnx-1.13.6.aar` was inspected with `javap`: `numSpeakers`, `generate`, and `release` are actual APIs. Temporary inspection output was removed.

## Verification and handoff

No Gradle or Xcode invocation; no sign-in, AO3 contact, network request, branch switch, commit, push or `TASKS.md` edit. Build, JVM/Compose tests, installed-pack audio and four-theme visual checks remain for Claude.

Added `SettingsListeningPageTest` (five tests):

1. Change Speed on the real Listening page, re-read the persisted store, overlay reader preferences, and use the reader's actual engine-application function to assert the received rate.
2. Change Voice on the page and assert the persisted reader preference and received engine speaker.
3. Assert the Voice menu lists exactly the engine-reported catalog, including an observed catalog replacement; Automatic is an extra option, not an invented voice.
4. Play the exact default iOS sample without a reader, change shared speed during playback, assert a restarted sample, and Stop.
5. Reset Read Aloud clears Voice/Speed and applies speaker 0 / speed 1.0 while backup-compatible settings remain unchanged.

These tests use a recording implementation of the existing `TTSService` seam; they do not load native Sherpa or make network requests. They exercise actual page actions, persistence and the same projection/application functions used by the reader. They do **not** instantiate the full reader ViewModel or prove native audio timing.

Static verification: `git diff --check` clean; production symbols traced through reader/store/service; Android-only changes; no task-board, backup/schema, iOS-reference, branch or history edits. **No build or tests run**, per the brief. No claim of visual or audio correctness.

Claude still needs to run `:app:assembleDebug` and `:app:testDebugUnitTest` (including `SettingsListeningPageTest` and existing reader/preferences suites). Device checks: choose each installed speaker from Settings, reopen the reader and listen; change Voice/Speed in the reader and verify Settings; confirm a live reader picks up stored changes at the next synthesis chunk; play/restart/stop samples repeatedly and leave the page while synthesizing; verify no leaked audio, native crash or model retention; verify missing/corrupt pack disables Play Sample honestly. Inspect Light/Dark/Sepia/OLED and large fonts (menus, sliders and shared text rows). All runtime, test and screenshot claims remain pending those runs.
