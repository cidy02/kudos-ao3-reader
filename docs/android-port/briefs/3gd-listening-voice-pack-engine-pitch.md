# Brief 3gd: Settings › Listening — the voice pack, Engine and Pitch, as iOS (A66 #15, #16)

**Write code; do not commit, push, switch branches, sign in, run Gradle or contact
archiveofourown.org.** Create `docs/android-port/briefs/3gd-result.md` FIRST (an earlier agent on
this plan read for an hour and wrote nothing), then write each item into it as you finish it:
what changed (`path:line`), the iOS code followed, the test added. Do not edit `TASKS.md`.

Hard rules: iOS (`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`, read-only) is the source of
truth; nothing Android has may be lost; Room migrations additive only (none expected; settings
are DataStore preferences); the backup manifest stays v8 with additive keys — check whether iOS
backs up its speech engine and pitch settings and do exactly what iOS does. Android's ICU regex
rejects some JVM-accepted flags (`RegexPortabilityTest`).

Another agent is changing `settings/SettingsListeningPage.kt` at the same time (adding a
"Pronunciations" row after Voice). Keep your additions in their own composables and change as
few existing lines of that file as you can, so the two merge cleanly.

The verified findings, with quotes, are in `docs/android-port/audits/A66-verified.json` (ids 15
and 16).

1. **#15, the voice pack in Settings › Listening.** iOS lets the reader download, cancel or retry
   the Kokoro voice pack there, with a confirmation that discloses the download
   (`Features/ReaderReadium/ReaderSpeechSettingsSection.swift:225`–`:417`). Android has the
   download only in the reader (`reader/speech/TTSDownloadWorker.kt`, `ReaderSpeechController.kt`
   watches its WorkManager state). Put the same flow on the Listening page: Download (with iOS's
   words and size), progress with Cancel, Retry after a failure, and the installed state.
2. **#16, Engine and Pitch.** iOS has an Engine picker (Automatic, Kokoro, Apple) and a Pitch
   slider (`ReaderSpeechSettingsSection.swift:68`, `:147`). Android: Engine (Automatic, Kokoro,
   Device voice) honoured by `reader/speech/AutomaticTTSService.kt`, and Pitch applied to both
   engines where the engine supports it (say where it cannot). Developer Settings: leave out
   (recorded decision; say so in the result).
3. Tests: the preference round trip and reset, the engine choice reaching `AutomaticTTSService`,
   and the download states the page shows.
