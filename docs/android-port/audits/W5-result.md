# W5: The Words on Android's Comments Screens Beside iOS's

- **Android strings found**: 63
- **DIFFERS**: 3
- **NO IOS STRING**: 2
- **SAME**: 58

This audit compares every string literal a reader can see or a screen reader speaks across the three pairs of comments files:
1. `comments/CommentsScreen.kt` beside `Features/Comments/CommentsView.swift` (and other files in `Features/Comments/`)
2. `comments/CommentComposerSheet.kt` beside `Features/Comments/CommentsView.swift:1159` (`CommentComposerSheet`, the component that draws the composer on iOS)
3. `comments/CommentsViewModel.kt` (every string assigned to `_message` or returned by `commentsReadErrorMessage`) beside `Features/Comments/CommentsModel.swift`, `Features/Comments/CommentsErrorMessages.swift`, and `Services/CommentSubmission.swift`

Reference paths:
- Android: `/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/`
- iOS: `kudos-ao3-reader/`

---

## Table 1: Differing and Missing Strings (DIFFERS and NO IOS STRING)

| Android String (`path:line`) | iOS String (`path:line`) | Status | Notes / Words Searched |
|---|---|---|---|
| `"Comments"` (`comments/CommentsScreen.kt:189`) | — | **NO IOS STRING** | Fallback work title in `SubjectHeaderBlock` when `thread.workTitle` is null. Searched `Features/Comments/CommentsView.swift` for `"workTitle"`, `"fallback"`, `"Comments"`. iOS passes `model.workContext.title` directly to `SubjectHeaderBlock` (`CommentsView.swift:439`) with no fallback string literal. |
| `"Log in to AO3"` (`comments/CommentsScreen.kt:571`) | `"Try Again"` (`Features/Comments/CommentsView.swift:669`) | **DIFFERS** | Retry/action button on the comments error state when authentication is required (`CommentsUiState.AuthRequired`). Android displays `"Log in to AO3"`; iOS displays `"Try Again"`. |
| `"· ${replyTarget.chapterLabel}"` (`comments/CommentComposerSheet.kt:212`) | `" · \(chapter)"` (`Features/Comments/CommentsView.swift:1451`) | **DIFFERS** | Quoted parent reply banner chapter label. Android has no leading space before the interpunct (`"· ${replyTarget.chapterLabel}"`); iOS has a leading space before the interpunct (`" · \(chapter)"`). |
| `"You just posted this. Reload to see if it appeared."` (`comments/CommentsViewModel.kt:659`) | — | **NO IOS STRING** | Message assigned to `_message.value` when attempting to submit content matching `lastSubmittedContentHash`. Searched `Features/Comments/CommentsModel.swift`, `Features/Comments/CommentsErrorMessages.swift`, and `Services/CommentSubmission.swift` for `"posted"`, `"Reload"`, `"appeared"`. No corresponding string exists on iOS (iOS guards duplicate submissions via `CommentSubmissionGuard` without this message). |
| `"Couldn't confirm this posted — reloading to check."` (`comments/CommentsViewModel.kt:712`) | `"AO3 answered but didn't confirm the comment posted. Checking whether it went through…"` (`Features/Comments/CommentsErrorMessages.swift:32-33`) / `"The connection dropped while posting. Checking whether the comment went through…"` (`Features/Comments/CommentsErrorMessages.swift:35`) | **DIFFERS** | Feedback message on unconfirmed comment submission. Android assigns `"Couldn't confirm this posted — reloading to check."` to `_message.value` and triggers a background page reload. iOS displays ambiguous status banner text from `CommentsErrorMessages.swift:32-35` in `CommentComposerSheet` with a `"Check Again"` button. (Searched `Features/Comments/CommentsModel.swift`, `Features/Comments/CommentsErrorMessages.swift`, `Services/CommentSubmission.swift` for `"confirm"`, `"posted"`, `"reloading"`: the exact Android phrasing does not exist on iOS). |

---

## Table 2: Identical Strings (SAME)

| Android String (`path:line`) | iOS String (`path:line`) | Status |
|---|---|---|
| `"Expand to full screen"` (`comments/CommentsScreen.kt:244`) | `"Expand to full screen"` (`Features/Comments/CommentsView.swift:330`) | **SAME** |
| `"Close"` (`comments/CommentsScreen.kt:252`) | `"Close"` (`Features/Comments/CommentsView.swift:321`) | **SAME** |
| `"Delete this comment?"` (`comments/CommentsScreen.kt:264`) | `"Delete this comment?"` (`Features/Comments/CommentsView.swift:299`) | **SAME** |
| `"This removes the comment on AO3. It cannot be undone."` (`comments/CommentsScreen.kt:265`) | `"This removes the comment on AO3. It cannot be undone."` (`Features/Comments/CommentsView.swift:303`) | **SAME** |
| `"Delete"` (`comments/CommentsScreen.kt:274`) | `"Delete"` (`Features/Comments/CommentsView.swift:300`) | **SAME** |
| `"Cancel"` (`comments/CommentsScreen.kt:279`) | `"Cancel"` (`Features/Comments/CommentsView.swift:301`) | **SAME** |
| `"AO3"` (`comments/CommentsScreen.kt:289`) | `"AO3"` (`Features/Comments/CommentsView.swift:305`) | **SAME** |
| `"OK"` (`comments/CommentsScreen.kt:293`) | `"OK"` (`Features/Comments/CommentsView.swift:306`) | **SAME** |
| `"Chapter ${selectedChapter?.position}"` (`comments/CommentsScreen.kt:377`) | `"Chapter \(chapter.position)"` (`Features/Comments/CommentsView.swift:463`) | **SAME** |
| `"Comments"` (`comments/CommentsScreen.kt:379`) | `"Comments"` (`Features/Comments/CommentsView.swift:465`) | **SAME** |
| `"Comments"` (`comments/CommentsScreen.kt:422`) | `"Comments"` (`Features/Comments/CommentsView.swift:520`) | **SAME** |
| `"Threads"` (`comments/CommentsScreen.kt:429`) | `"Threads"` (`Features/Comments/CommentsView.swift:527`) | **SAME** |
| `"Yours"` (`comments/CommentsScreen.kt:436`) | `"Yours"` (`Features/Comments/CommentsView.swift:538`) | **SAME** |
| `"Latest"` (`comments/CommentsScreen.kt:445`) | `"Latest"` (`Features/Comments/CommentsView.swift:547`) | **SAME** |
| `"Threads, Yours and Latest count only this page. The comment total covers the whole work."` (`comments/CommentsScreen.kt:460`) | `"Threads, Yours and Latest count only this page. The comment total covers the whole work."` (`Features/Comments/CommentsView.swift:559`) | **SAME** |
| `"Chapter ${it.position}"` (`comments/CommentsScreen.kt:473`) | `"Chapter \(chapter.position)"` (`Features/Comments/CommentsView.swift:638`) | **SAME** |
| `"By chapter"` (`comments/CommentsScreen.kt:473`) | `"By chapter"` (`Features/Comments/CommentsView.swift:637`) | **SAME** |
| `"All comments"` (`comments/CommentsScreen.kt:475`) | `"All comments"` (`Features/Comments/CommentsView.swift:636`) | **SAME** |
| `"Browse comments by chapter"` (`comments/CommentsScreen.kt:490`) | `"Browse comments by chapter"` (`Features/Comments/CommentsView.swift:585`) | **SAME** |
| `"Newest"` (`comments/CommentsScreen.kt:505`) | `"Newest"` (`Features/Comments/CommentsView.swift:618`) | **SAME** |
| `"Oldest"` (`comments/CommentsScreen.kt:505`) | `"Oldest"` (`Features/Comments/CommentsView.swift:618`) | **SAME** |
| `"Sort comments"` (`comments/CommentsScreen.kt:508`) | `"Sort comments"` (`Features/Comments/CommentsView.swift:629`) | **SAME** |
| `"Oldest First"` (`comments/CommentsScreen.kt:522`) | `"Oldest First"` (`Features/Comments/CommentsView.swift:602, 604`) | **SAME** |
| `"Newest First"` (`comments/CommentsScreen.kt:532`) | `"Newest First"` (`Features/Comments/CommentsView.swift:611, 613`) | **SAME** |
| `"Couldn't Load Comments"` (`comments/CommentsScreen.kt:556`) | `"Couldn't Load Comments"` (`Features/Comments/CommentsView.swift:665`) | **SAME** |
| `"Try Again"` (`comments/CommentsScreen.kt:559`) | `"Try Again"` (`Features/Comments/CommentsView.swift:669`) | **SAME** |
| `"Couldn't Load Comments"` (`comments/CommentsScreen.kt:568`) | `"Couldn't Load Comments"` (`Features/Comments/CommentsView.swift:665`) | **SAME** |
| `"No Comments Yet"` (`comments/CommentsScreen.kt:582`) | `"No Comments Yet"` (`Features/Comments/CommentsView.swift:687`) | **SAME** |
| `"You can be the first to comment on this work."` (`comments/CommentsScreen.kt:583`) | `"You can be the first to comment on this work."` (`Features/Comments/CommentsView.swift:689`) | **SAME** |
| `"Comments"` (`comments/CommentsScreen.kt:592`) | `"Comments"` (`Features/Comments/CommentsView.swift:699`) | **SAME** |
| `"Previous"` (`comments/CommentsScreen.kt:632`) | `"Previous"` (`Features/Comments/CommentsView.swift:776`) | **SAME** |
| `"Page ${thread.currentPage} of ${thread.totalPages}"` (`comments/CommentsScreen.kt:636`) | `"Page \(model.currentPageNumber) of \(page.totalPages)"` (`Features/Comments/CommentsView.swift:784`) | **SAME** |
| `"Next"` (`comments/CommentsScreen.kt:647`) | `"Next"` (`Features/Comments/CommentsView.swift:793`) | **SAME** |
| `"Write a comment"` (`comments/CommentsScreen.kt:665`) | `"Write a comment"` (`Features/Comments/CommentsView.swift:823, 835`) | **SAME** |
| `"Log in to comment"` (`comments/CommentsScreen.kt:665`) | `"Log in to comment"` (`Features/Comments/CommentsView.swift:823, 835`) | **SAME** |
| `"Browse Comments by Chapter"` (`comments/CommentsScreen.kt:742`) | `"Browse Comments by Chapter"` (`Features/Comments/CommentsView.swift:978`) | **SAME** |
| `"All Comments"` (`comments/CommentsScreen.kt:772`) | `"All Comments"` (`Features/Comments/CommentsView.swift:904`) | **SAME** |
| `"AO3 doesn't show comment totals for each chapter. Choose a chapter to see its comments."` (`comments/CommentsScreen.kt:836`) | `"AO3 doesn't show comment totals for each chapter. Choose a chapter to see its comments."` (`Features/Comments/CommentsView.swift:951`) | **SAME** |
| `"Edit comment"` (`comments/CommentComposerSheet.kt:103`) | `"Edit comment"` (`Features/Comments/CommentsView.swift:1220`) | **SAME** |
| `"Reply to ${replyTarget.author.name}"` (`comments/CommentComposerSheet.kt:104`) | `"Reply to \(parent.author)"` (`Features/Comments/CommentsView.swift:1222`) | **SAME** |
| `"New comment"` (`comments/CommentComposerSheet.kt:105`) | `"New comment"` (`Features/Comments/CommentsView.swift:1221`) | **SAME** |
| `"Save"` (`comments/CommentComposerSheet.kt:108`) | `"Save"` (`Features/Comments/CommentsView.swift:1207`) | **SAME** |
| `"Post"` (`comments/CommentComposerSheet.kt:108`) | `"Post"` (`Features/Comments/CommentsView.swift:1208, 1209`) | **SAME** |
| `"Cancel"` (`comments/CommentComposerSheet.kt:133`) | `"Cancel"` (`Features/Comments/CommentsView.swift:1298`) | **SAME** |
| `"View ${replyTarget.author.name}'s profile"` (`comments/CommentComposerSheet.kt:208`) | `"View \(parent.author)'s profile"` (`Features/Comments/CommentsView.swift:1465`) | **SAME** |
| `"Write your reply…"` (`comments/CommentComposerSheet.kt:238`) | `"Write your reply…"` (`Features/Comments/CommentsView.swift:1373`) | **SAME** |
| `"Share your thoughts…"` (`comments/CommentComposerSheet.kt:238`) | `"Share your thoughts…"` (`Features/Comments/CommentsView.swift:1373`) | **SAME** |
| `"New comments post to the whole work. AO3 shows them on its latest chapter."` (`comments/CommentComposerSheet.kt:267`) | `"New comments post to the whole work. AO3 shows them on its latest chapter."` (`Features/Comments/CommentsView.swift:1255`) | **SAME** |
| `"as $it"` (`comments/CommentComposerSheet.kt:279`) | `"as \($0)"` (`Features/Comments/CommentsView.swift:1389`) | **SAME** |
| `"Not signed in"` (`comments/CommentComposerSheet.kt:279`) | `"Not signed in"` (`Features/Comments/CommentsView.swift:1389`) | **SAME** |
| `"$remainingCharacters left"` (`comments/CommentComposerSheet.kt:284`) | `"\(remainingCharacters.formatted()) left"` (`Features/Comments/CommentsView.swift:1395`) | **SAME** |
| `"Drag the sheet taller"` (`comments/CommentComposerSheet.kt:292`) | `"Drag the sheet taller"` (`Features/Comments/CommentsView.swift:1202, 1264`) | **SAME** |
| `"Log in to AO3 to do that."` (`comments/CommentsViewModel.kt:46`) | `"Log in to AO3 to do that."` (`Features/Comments/CommentsErrorMessages.swift:43`) | **SAME** |
| `"AO3 declined the request. The work may be restricted to logged-in users."` (`comments/CommentsViewModel.kt:47`) | `"AO3 declined the request. The work may be restricted to logged-in users."` (`Features/Comments/CommentsErrorMessages.swift:49`) | **SAME** |
| `"AO3 couldn't find these comments — the work may be hidden or deleted."` (`comments/CommentsViewModel.kt:48`) | `"AO3 couldn't find these comments — the work may be hidden or deleted."` (`Features/Comments/CommentsErrorMessages.swift:47`) | **SAME** |
| `"AO3 is asking for a pause. Please try again in a moment."` (`comments/CommentsViewModel.kt:49`) | `"AO3 is asking for a pause. Please try again in a moment."` (`Features/Comments/CommentsErrorMessages.swift:41`) | **SAME** |
| `"You're offline. Comments will load when you're back online."` (`comments/CommentsViewModel.kt:51`) | `"You're offline. Comments will load when you're back online."` (`Features/Comments/CommentsErrorMessages.swift:51`) | **SAME** |
| `"Comment deleted."` (`comments/CommentsViewModel.kt:635`) | `"Comment deleted."` (`Services/AO3CommentActions.swift:73` / `Features/Comments/CommentsView.swift:1009`) | **SAME** |

## Triage (Claude, 2026-10-10)

63 strings, 58 the same. Of the five that are not:

- **"Couldn't confirm this posted — reloading to check."** against iOS's two sentences, one for
  an answer that confirmed nothing and one for a dropped connection: **real, P3, fixed.** Android
  now says iOS's sentence for whichever happened (`comments/CommentsViewModel.kt`).
- "Log in to AO3" where iOS says "Try Again" on a comments page that needs a sign-in: Android's
  button opens the sign-in, which is the thing to do. Left.
- "You just posted this. Reload to see if it appeared.": Android's own guard against a second
  tap; iOS guards in `CommentSubmissionGuard` without words. Left.
- The header's fallback title "Comments", and a space before "·" in the reply banner: nothing
  a reader sees differently. Left.

