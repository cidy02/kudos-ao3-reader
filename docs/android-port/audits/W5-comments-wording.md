# W5: the words on Android's comments screens beside iOS's

**Read-only.** Change no source file. Do not build, commit, push, switch branches, sign in or
contact archiveofourown.org. Write exactly one file, in this worktree:
`docs/android-port/audits/W5-result.md`. **Leave no other file behind.**

Android: `/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/`
(read-only). iOS, the reference: `kudos-ao3-reader/` in this worktree.

For each pair below, list **every string literal a reader can see or a screen reader speaks**
in the Android file (button labels, headings, captions, notices, error messages, dialog titles
and bodies, content descriptions), and beside it iOS's string for the same place.

| Android | iOS |
| --- | --- |
| `comments/CommentsScreen.kt` | `Features/Comments/CommentsView.swift` and the other files in `Features/Comments/` |
| `comments/CommentComposerSheet.kt` | `Features/Comments/CommentComposerView.swift` (or the file in `Features/Comments/` that draws the composer: name it) |
| `comments/CommentsViewModel.kt` (its messages: every string assigned to `_message` or returned by `commentsReadErrorMessage`) | `Features/Comments/CommentsModel.swift`, `Features/Comments/CommentsErrorMessages.swift`, `Services/CommentSubmission.swift` |

Rules, and they are strict because a row without both quotes cannot be used:

- One row per Android string: the Android string exactly as written, its `path:line`; the iOS
  string exactly as written, its `path:line`; and one of SAME, DIFFERS, or NO IOS STRING.
- Write NO IOS STRING only after searching the iOS files named above for three distinctive
  words of the Android string, and name the words you searched for.
- A string built from parts (`"Reply to $name"`, `"Reply to \(name)"`) is compared as built:
  quote the template on each side.
- Do not judge which side is right. Do not suggest changes.
- List the SAME rows too, in a second table at the end, so the count can be checked.

Start the file with three numbers: Android strings found, DIFFERS, NO IOS STRING.
