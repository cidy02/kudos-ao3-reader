# 3ee: "Read author's notes" for Read Aloud (Android)

Done 2026-10-14 by Claude, alone. Gate 2,659 (one new test). Picture: `shots/3ee/`.

3ak (2026-10-05) left iOS's "Read author's notes" out of Settings › Listening: Android had no
engine behind it. With the device's voice (3dm) and the paragraph filter (3ea) there is now.

- **Setting** (`ReaderSpeechPreferences.readAuthorNotes`, key `readerSpeechReadAuthorNotes`):
  on unless turned off, kept on the device outside backups like the rest of speech, and not
  touched by Reset Read Aloud (iOS's reset leaves it too).
- **Row** in Settings › Listening, after Voice as on iOS, with iOS's hint for TalkBack
  ("Author's notes often carry content warnings. Turn this off to hear only the story.").
  The reader's Display & Themes sheet does not have it yet: the reader's controls wait on
  owner question 12.
- **Rule** (`ReaderContentText.speakableParagraphs`, iOS's `KokoroSemanticDocument`): with
  the setting off, a note runs from its label ("Notes", "Chapter Notes", "End Notes"…) to
  the end of the quotation after it; anything not a quote ends it, so a label followed by
  plain text leaves that text spoken. Read Aloud now takes Readium's elements (a blockquote
  is a quote) instead of one string; read when Read Aloud starts.

`ReaderContentTextTest` has both settings. Seen on the emulator: the row, and it turns off.
Not heard: an emulator has no ears, and no demo work has an author's note.
