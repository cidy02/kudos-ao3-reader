# Brief 3ft: Read Aloud's pronunciation corrections, as iOS (a parity gap found 2026-10-20)

**Write code; do not commit, push, switch branches, sign in, run Gradle or contact
archiveofourown.org.** Claude builds, tests and lands it. Do not edit `TASKS.md`. Leave a result
file, `docs/android-port/briefs/3ft-result.md`, written as you go: what you changed
(`path:line`), each iOS rule ported with its iOS `path:line`, tests added, what you could not do.

Hard rules: Room migrations additive only, in a straight line from the current schema (v10 in
this lane, `MIGRATION_10_11` onward, each with a `KudosDatabaseMigrationTest` case, and bump
`RoomDaoTest.databaseCreatesAtCurrentSchemaVersion`) — but prefer a plain file, as iOS does,
and then no migration is needed. The backup manifest stays v8 with **additive** keys only. iOS is
the source of truth. Nothing Android has today may be lost. Read
`docs/DATA_AND_PERSISTENCE_INVARIANTS.md` before touching backup or sync. Android's ICU regex
engine rejects some flags the JVM accepts (`RegexPortabilityTest`).

## What iOS has (read-only: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`)

- `Features/ReaderReadium/KokoroPronunciationStore.swift`: a JSON file
  (`kokoro-pronunciations.json` in Application Support; `version`, `global`, `fandoms`, `works`:
  word → IPA), tier 1 of the phonemizer's order. Also `KokoroInlinePronunciation.swift`,
  `KokoroRespelling.swift` (how an entry is applied and what a reader may type).
- `Features/ReaderReadium/ReaderPronunciationSettingsView.swift` (the list and editor, opened
  from Settings › Listening and from the reader's speech settings: `ReaderSpeechSettingsSheet.swift`,
  `ReaderSpeechSettingsSection.swift`).
- `ReadiumBook.swift:79` and `ReadiumReaderView.swift` `beginPronunciationCorrection()`: the
  selection menu's **Fix Pronunciation** takes the first word of the selection, trimmed of
  punctuation but `'` and `-`, and opens the editor with any existing entry.
- `Services/KudosBackup.swift:618`–`:780` (`KudosBackupPronunciations`, `capture`, and how a
  restore applies it: find the restore path and copy its rule exactly, merge or replace), and
  `Services/KudosBackupExport.swift`. Check the sync folder service for the same key.

## What Android has

- No store, no editor, no menu item. `backup/SyncRepository.kt:380` carries unknown manifest
  keys (iOS's `pronunciations` among them) through untouched; the backup restore path likely
  does the same — find it. Read Aloud: `reader/speech/` (`KokoroTTSController.kt` on
  sherpa-onnx, `AutomaticTTSService.kt` for the device voice, `TextChunker.kt`). Settings ›
  Listening: `settings/SettingsListeningPage.kt`. The selection menu:
  `reader/readium/ReaderSelectionContainer.kt` (brief 3fs is changing Highlight/Add Note there
  in another worktree: add Fix Pronunciation as a third item and touch nothing else in that file).

## Do

1. A Kotlin store reading and writing the same JSON shape, in the app's files dir, never in the
   TTS model directory.
2. Backup and sync: write `pronunciations` from the store and apply it on restore by iOS's rule,
   so an iOS backup's corrections land in Android's store and an Android backup's land in
   iOS's. Unknown keys still pass through. Add a cross-platform test: an iOS-shaped manifest with
   corrections restores into the store; an export carries them back field for field.
3. The list and editor in Settings › Listening, drawn with `ui/subject/` parts as that page is,
   with iOS's wording and order; and **Fix Pronunciation** in the selection menu.
4. Apply corrections to speech. sherpa-onnx's Kokoro config takes `lexicon` files (word →
   phonemes): check what the bundled model and the AAR in `app/libs/` accept, and generate a
   lexicon from the store (global, then the work's fandom, then the work: the most specific
   wins, as iOS). If a correction cannot reach the engine in some case (the device voice,
   for one), say so in the result file and in a code comment; do not fake it.
5. Tests: the store round-trip, the scope order, the selection word trimming, the backup
   round-trip both ways.
