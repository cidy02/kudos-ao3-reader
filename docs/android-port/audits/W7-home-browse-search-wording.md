# W7: the words on Android's Home, Browse and Search beside iOS's

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/W7-result.md`. **Leave no other file behind.**

Android: `/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/`
(read-only). iOS, the reference, and **not the copy in this worktree**:
`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` (read-only).

For each pair below, list **every string literal a reader can see or a screen reader speaks**
in the Android file (button labels, headings, captions, notices, error messages, dialog titles
and bodies, content descriptions), and beside it iOS's string for the same place.

| Android | iOS |
| --- | --- |
| `home/HomeScreen.kt`, `home/HomeSectionsUi.kt`, `home/HomeQueueCard.kt` | `Features/Home/HomeView.swift` and the other files in `Features/Home/` |
| `browse/BrowseScreen.kt`, `browse/BrowseCategoryPanels.kt` | `Features/Browse/BrowseView.swift`, `Features/Browse/MediaBrowser*.swift` |
| `search/SearchScreen.kt` (not the filter sheet) | `Features/Search/SearchView.swift` |

Rules, and they are strict because a row without both quotes cannot be used:

- One row per Android string: the Android string exactly as written, its `path:line`; the iOS
  string exactly as written, its `path:line`; and one of SAME, DIFFERS, or NO IOS STRING.
- Write NO IOS STRING only after searching the iOS files named above for three distinctive
  words of the Android string, and name the words you searched for.
- A string built from parts is compared as built: quote the template on each side.
- Do not judge which side is right. Do not suggest changes.
- List the SAME rows too, in a second table at the end, so the count can be checked.
- Then a third table the other way round, **only** for Home's section headings, its empty-state
  messages and its menus: every iOS string there that has no Android string, with its
  `path:line` and the three words you searched Android's `home/` for.

Start the file with four numbers: Android strings found, DIFFERS, NO IOS STRING, and iOS
strings with no Android string.
