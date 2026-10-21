# Brief 3gf: the reader's last parity items (A62 F21/F22, A61 #29; owner 2026-10-20: "match iPhone")

**Write code; do not commit, push, switch branches, sign in, run Gradle or contact
archiveofourown.org.** Claude builds, tests and lands it. Create `docs/android-port/briefs/3gf-result.md`
first and write each item into it as you finish it: what changed (`path:line`), the iOS code
followed (`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`, read-only), the test added.

Hard rules: iOS is the source of truth; nothing Android has may be lost; Android's navigation and
chrome stay Material 3 (Material icon buttons), the behaviour follows iOS; no Room or backup change
expected; Android's ICU regex rejects some JVM-accepted flags (`RegexPortabilityTest`). The owner
answered on 2026-10-20 that Android's reader is to do what the iPhone's does (questions 29/30;
owner question 12's spirit). Findings, with quotes, in `docs/android-port/audits/A62-result.md`
(F21, F22) and `A61-result.md` (#29).

1. **F22, Read Aloud's Previous/Next.** iOS moves by chapter ("Previous chapter"/"Next chapter",
   `Features/ReaderReadium/ReaderSpeechController.swift:878`, `:902`); Android moves by paragraph
   (`reader/ReaderPositionCard.kt` "Previous paragraph", `reader/speech/ReaderSpeechController.kt`).
   Match iOS, including the MediaSession skip buttons; keep 3gc's hold-seek (a hold steps through
   positions) as iOS keeps it.
2. **F22, the mini-player with the chrome hidden.** iOS shows a standalone mini-player when the
   chrome is hidden (`ReadiumReaderView.swift:1069` `standaloneMiniPlayer`); Android hides the only
   player with the chrome. Show iOS's standalone player (Material controls).
3. **A61 #29, compact section pill labels** P/S/N/M/A where iOS's contract uses them
   (`reader/ReaderProgressDisplay.kt:63`; find iOS's labels and when it uses them).
4. **F21 remainder, fonts in the reader.** The Customize Theme sheet (3fs) lists fonts; iOS's
   reader font list also offers imported fonts, "Add Font…" and deleting an imported font
   (`Settings/SettingsView.swift:154`–`:185`, `ReaderFontSection`). Reuse Android's existing font
   import and delete (`files/CustomFontRepository.kt`, Settings › Font, including 3ga's import
   refusals) rather than writing new ones.
