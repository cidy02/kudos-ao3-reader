# W6: the words on Android's reader beside iOS's

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/W6-result.md`. **Leave no other file behind.**

Android: `/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/`
(read-only). iOS, the reference, and **not the copy in this worktree**:
`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` (read-only).

For each pair below, list **every string literal a reader can see or a screen reader speaks**
in the Android file (button labels, headings, captions, notices, error messages, dialog titles
and bodies, content descriptions), and beside it iOS's string for the same place.

| Android | iOS |
| --- | --- |
| `reader/ReaderChromeTopBar.kt`, and the fan menu and its pills in `reader/ReaderScreen.kt` | `Features/ReaderReadium/ReaderChromeTopBar.swift`, `Features/ReaderReadium/ReadiumReaderView.swift` |
| `reader/ReaderContentsSheet.kt` | `Features/ReaderReadium/ReaderContentsSheet.swift` |
| `reader/ReaderSearchSheet.kt` | `Features/ReaderReadium/ReaderSearchView.swift` |
| the note editor and the selection actions in `reader/` (find them: "Highlight", "Note", "Delete Highlight") | `Features/ReaderReadium/ReaderNoteEditor.swift`, `Features/ReaderReadium/ReadiumBook.swift` |
| the reader's settings sheet in `reader/` (find it: "Themes & Settings") | `Features/ReaderReadium/` (the files whose names contain `Settings` or `Theme`) |

Rules, and they are strict because a row without both quotes cannot be used:

- One row per Android string: the Android string exactly as written, its `path:line`; the iOS
  string exactly as written, its `path:line`; and one of SAME, DIFFERS, or NO IOS STRING.
- Write NO IOS STRING only after searching the iOS files named above for three distinctive
  words of the Android string, and name the words you searched for.
- A string built from parts is compared as built: quote the template on each side.
- Do not judge which side is right. Do not suggest changes.
- List the SAME rows too, in a second table at the end, so the count can be checked.
- Then a third table the other way round, **only** for the fan menu and the contents sheet:
  every iOS string in those two that has no Android string, with its `path:line` and the three
  words you searched Android's `reader/` for.

Start the file with four numbers: Android strings found, DIFFERS, NO IOS STRING, and iOS
strings with no Android string.
