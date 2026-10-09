# W3: the words on six more Android screens, checked against iOS

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/W3-result.md`. No helper scripts or scratch files left behind.

iOS is in this worktree under `kudos-ao3-reader/`. Android is at
`/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/` (read-only;
not in this worktree).

These Android screens were written or changed on 2026-10-09 (the first two) or have never had their words checked (the rest), each from an iOS screen.
For each pair, compare **every string a reader can see or hear**: titles, kickers, subtitles,
section headers, row labels, values, placeholders, footnotes, buttons, menu items, alerts
(title, message, each button), empty, loading and failure states, and accessibility labels,
hints and action names.

| Android | iOS |
|---|---|
| The Post, Preview and Delete parts of `writing/WritingWorkFormScreen.kt`; `writing/WritingAO3PreviewScreen.kt`; `workPostConfirmation` and the messages in `writing/WritingWorkFormState.kt` | `Features/Writing/WorkEditView.swift` (Post, Delete, the confirmations), `Features/Writing/WritingPreviewView.swift` |
| `settings/PrivacyDataScreen.kt`, `settings/LocalDataFootprint.kt`; the notices in `auth/AO3AuthRepository.kt` | `Features/Account/PrivacyDataView.swift`, `Services/LocalDataFootprint.swift`, `Services/LocalDataClearing.swift`, the `noticeMessage` strings in `Services/AO3AuthService.swift`, `UIComponents/DeleteConfirmation.swift` |
| `comments/CommentsScreen.kt`, `CommentThreadComponents.kt`, `CommentComposerSheet.kt`, the messages in `comments/CommentsViewModel.kt` | `Features/Comments/CommentsView.swift`, `CommentsModel.swift`, `CommentComposerView.swift` and the other files under `Features/Comments/` |
| `account/AccountInboxPane.kt` (rows, menus, bulk bar, filters, empty and failure states) | the Inbox in `Features/Account/AccountView.swift` and the files under `Features/Account/` whose names begin `AccountInbox` or `AO3Inbox` |
| `ui/components/KudosPaginationBar.kt` (the bar and its page sheet) | `UIComponents/` pagination bar and page picker (find them: "Nearby", "First page", "Last") |
| `account/AO3CollectionFormScreen.kt` and the messages in `AO3CollectionFormState.kt` | `Features/Collections/AO3CollectionFormView.swift` |

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
