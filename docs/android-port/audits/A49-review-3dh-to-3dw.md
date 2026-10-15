# A49: review what Claude landed alone on Android, 3dh to 3dw (2026-10-12 to 10-14)

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/A49-result.md`. **Leave no other file behind.** Do not edit `TASKS.md`.

Read the Android code as it stands on `android/redesign-parity` at `cce20bf1` (in
`~/kudos-android-lane`, read-only; your own worktree may be behind it). Each change has a note
in `docs/android-port/briefs/` named after it (3dh … 3dw). iOS, where a change copies it, is
`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` (read-only).

Every change below was written, built and looked at by one agent with no second reader. Find
what is **wrong**: a fault a reader would meet, a broken rule, a test that proves less than it
says. Style and naming are not wanted. Every finding quotes the Kotlin with `path:line`, says
what happens to a reader (or to their data), and how sure you are. A finding without a quote is
worth nothing: leave it out. Say plainly when a change looked right.

Take them in this order and stop where you run out of time (say where):

1. **3dm, Read Aloud with the device's voice** (`reader/speech/AutomaticTTSService.kt`,
   `ReaderSpeechController.kt`). The privacy rule is that no network voice is ever used, so the
   work's text never leaves the phone: can any path speak with a voice that needs the network
   (the engine's default after `onInit`, a later voice change by the system, `setVoice`)? The
   pause, resume, skip and stop sequencing with `readings`, `utterance` and `handover`: a race
   that leaves the player saying PLAYING with nothing playing, or reading two things at once?
   The controller now maps UNAVAILABLE to MODEL_NOT_DOWNLOADED only when the pack is missing:
   is there a state the reader can no longer leave?
2. **3dj, an author's page** (`network/ao3/author/AO3AuthorIdentities.kt` `byline`,
   `AO3AuthorParser.routeFromPath`, `ui/components/AO3RichText.kt`). The bio is a stranger's
   HTML: can anything in `AO3RichTextHtml.clean` let through a link that is not http or https,
   or an image or script? Does a tapped link outside AO3 open anything without the reader
   choosing to? Does the decoded pseud ever produce a doubly encoded or wrong address?
3. **3do, author links** (`works/WorkDetailScreen.kt` `hasAccount`, `accountByline`). A name
   is a link only with an AO3 account. Is there a case where the wrong account opens (two
   co-authors with the same display name, a pseud equal to another account's name)?
4. **3dq, Browse and counts** (`browse/BrowseScreen.kt` `currentLibrary`,
   `ui/subject/SubjectComponents.kt` `compactCount`). `compactCount` is used in about twenty
   places: any caller that relied on the old decimals (a value that now reads wrong, such as
   "1M" for 999,950 where a count must be exact)?
5. **3dl, the Contents sheet** (`reader/ReaderContentsSheet.kt`,
   `readium/ReadiumTocAdapter.startPercents`). Can `publication.positions()` be slow or fail
   on a large work in a way that blocks the reader?
6. **3ds, removed code** (`account/AccountScreen.kt`). 476 lines were deleted as unused.
   Anything still reached by reflection, a navigation string or a test?
7. **3dw, Settings' header** (`settings/SettingsScreen.kt`). `hasSubjectHeader = true` for
   every page in Settings: is there a page there with no header of its own, which would now
   lose its back button or title?
8. If time is left: 3dr (`settings/SettingsScreen.kt` font name; `author/AuthorProfileScreen.kt`
   `isOwnProfile`), 3dt (`AO3AuthorAvatar`), 3dv (`browse/FandomWorksScreen.kt`).

End with a short list: the findings worth fixing first, one line each.
