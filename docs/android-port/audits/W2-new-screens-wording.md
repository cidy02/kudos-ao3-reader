# W2: the words on the screens Android gained this week, checked against iOS

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/W2-result.md`. No helper scripts or scratch files left behind.

iOS is in this worktree under `kudos-ao3-reader/`. Android is at
`/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/` (read-only;
not in this worktree).

These Android screens were written on 2026-10-08 and 2026-10-09, each from an iOS screen.
For each pair, compare **every string a reader can see or hear**: titles, kickers, subtitles,
section headers, row labels, values, placeholders, footnotes, buttons, menu items, alerts
(title, message, each button), empty, loading and failure states, and accessibility labels,
hints and action names.

| Android | iOS |
|---|---|
| `writing/WritingWorkFormScreen.kt` (and its state's messages) | `Features/Writing/WorkEditView.swift`, `WritingFormFields.swift` |
| `writing/WritingEditTagsScreen.kt` | `Features/Writing/EditTagsView.swift` |
| `writing/WritingChapterFormScreen.kt`, `WritingChaptersScreen.kt` | `Features/Writing/AddChapterView.swift`, `WritingChaptersView.swift` |
| `writing/WritingSeriesScreen.kt` | `Features/Writing/SeriesEditView.swift`, `SeriesReorderDestination.swift` |
| `account/AO3ChallengeSignUpScreen.kt` | `Features/Challenges/ChallengeSignUpView.swift` |
| `account/AccountShortcuts*.kt` | `Features/Account/AccountShortcuts.swift` |
| `author/AuthorWorksSortFields.kt` and the sort sheet in `author/AuthorProfileScreen.kt` | `Features/Search/AO3FilterPanel.swift` (the works sort), `Models/AO3WorksSort.swift` |
| `library/LibraryHistoryGrouping.kt`, the History parts of `library/LibraryScreen.kt` | `Features/Library/LibraryHistoryGrouping.swift`, `LibrarySectionListView.swift` |
| `library/FavoriteAffinityRow.kt`, `library/ReadingAffinities.kt` | `Features/Library/FavoriteAffinityRow.swift`, `ReadingAffinities.swift` |
| `account/AccountMoreOnAO3Screen.kt` | `Features/Account/AccountMoreOnAO3View.swift` |
| `works/detail/WorkDetailForms.kt` | the bookmark, queue and series sheets under `Features/WorkDetail/` |

For each pair write a table: the iOS string with its `path:line` and where it appears; the
Android string with its `path:line`; and **same**, **differs** (quote both), **missing on
Android**, or **Android only**. A string built from a pattern (a count, a name) is compared
by its pattern, for one, two and zero where the wording changes. Where iOS's string is an
accessibility label, hint, value or action name, say which, and compare it with the matching
Android semantics property, not with visible text.

Leave out of "differs": words that name a platform thing Android does not have (Face ID,
iCloud, the Files app, "swipe" where Android draws a menu), and anything
`/Users/cidy02/kudos-android-lane/docs/android-port/DECISIONS.md` records (quote the entry's
heading).

End with the list of every **differs** and **missing on Android**, most visible first.
Exact files and lines only. Quote strings as written, with their punctuation.
