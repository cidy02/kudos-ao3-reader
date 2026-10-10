# R10: the reader, control by control: what Android still lacks

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/R10-result.md`. No helper scripts left behind.

iOS is at `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` (read-only):
`Features/ReaderReadium/` and whatever it uses from `UIComponents/` and `Features/Reader/ReaderStyle.swift`.
Android is in this worktree under `android/app/src/main/java/io/github/cidy02/kudos/` (start
from `reader/`, `reader/readium/`, `reader/settings/` and `reader/speech/`).

The reader is one of the areas of the Android port still marked unfinished, and nobody has
listed what is left. List it. **Leave out the speech engine itself** (every file whose name
starts with `Kokoro`, `CoreMLKokoro`, `SherpaKokoro`, `TTS`, `SystemTTS`, `TextChunker`,
`SpeechSpectrum`): Android has no engine yet and that is known. Everything a reader can see
or tap is in scope, including the read-aloud **controls and settings screens** (what they
show and say), which are.

For **every** screen, sheet, menu, bar and gesture of iOS's reader (the top bar; the fan menu
and each pill and round button, with the condition under which each appears; the position
card and its scrubber; the Contents sheet's three tabs and their rows, swipe actions and
empty states; Find in Work; the note editor; the text selection menu; Display & Themes and
"Customize Theme"; the read-aloud controls, the speech settings sheet, the pronunciation
settings; the end-of-work actions; the dismiss gesture; what a tap, a double tap, a long
press and a swipe on the page do; what is saved when the reader closes; every error and
loading state):

1. the Swift `struct` or function and file, with `path:line`;
2. what it shows or does, in order: each heading, row, control and menu item, word for word,
   with the condition under which it appears;
3. the Kotlin composable or function and file that does the same on Android, with
   `path:line`, **or** "not found", naming the files you searched and the words you searched
   for;
4. each difference you can quote: a string that differs, a control one side lacks, a
   condition that differs, a gesture one side lacks. **Both quotes or leave it out.**

Do not judge appearance: you cannot see either app. Words, items, order, conditions and what
a tap does.

End with a table sorted by size of the gap: the iOS control, `path:line`, Android's
`path:line` or "not found", one line. If you run short of time, finish the fan menu, the
Contents sheet and Display & Themes first and say where you stopped.
