# Brief 3k: Comments Redesign Result

## Summary
Rebuilt the Android comments screens under `comments/` to match iOS `CommentsView.swift`, `CommentThreadScreen.swift`, `CommentThreadRow.swift`, `CommentMarkup.swift`, and `CommentsModel.swift`. The implementation preserves all actions, connects to offline demo fixtures, and adheres to `SubjectPalette` and `KudosTokens` styling.

## Key Changes
- **Thread Geometry (`CommentThreadGeometry.kt`)**: DFS tree flattening with stepped avatar sizes (30/26/22dp), depth-based indentation (clamped at 5 levels), auto-collapse (>8 replies), and chunked expansion (20 replies).
- **Thread Components (`CommentThreadComponents.kt`)**: Custom canvas vertical rails and rounded elbows (`elbowRadius` 21/18dp), `CommentSwipeTracker` rail sync, 5-line clamped body ("Read more"/"Show less"), 44dp hit-target action strip with overflow menu ("Reply", "Edit Comment", "Copy Link", "Thread", "Parent Thread", "Delete Comment"), `ContentUnavailableView`, and `CommentSkeletonRow`.
- **Formatting & Composer (`CommentMarkup.kt`, `CommentComposerSheet.kt`)**: All 14 AO3 HTML formatting tags with quick format bar and modal tray. Bottom sheet includes quoted parent comment rail, character countdown (`10000 left`), and draft persistence.
- **Isolated Thread Screen (`CommentThreadScreen.kt`)**: Subtree view for deep thread focus with pushed chrome.
- **Top-Level Screen & VM (`CommentsScreen.kt`, `CommentsViewModel.kt`)**: Added `SubjectHeaderBlock`, `SubjectStatStrip` (Comments, Threads, Latest), `signalScopeNote`, filter rail (chapter pill & sort menu), chapter picker sheet, and floating 44dp CTA pill. Wired `/navigate` in `DemoNetwork.kt` and parsed `workTitle`.

## String and Callback Audit
- **Callbacks**:
  - `onLogin`: Preserved on floating CTA and overflow menu ("Log in to Reply").
  - `onOpenAuthor`: Preserved on avatar and byline taps.
  - `onReply`, `onEdit`, `onDelete`: Preserved in action strip, overflow menu, and swipe actions.
  - `onCopyLink`: Preserved in overflow menu and swipe actions.
  - `onViewThread`: Mapped to `handlers.onFocusThread(id)` pushing `CommentThreadScreen` (iOS `CommentThreadRow.swift:1422`).
  - `onBack`, `onRequestExpand`: Preserved in `ProvidePushedShellChrome`.
  - `onLoadPage`: Replaced with iOS pull-to-refresh (`.refreshable`) and chapter scope filtering (`CommentsView.swift:190`).
- **Strings**: All iOS spec strings preserved verbatim, including "Comments", "Threads, Yours and Latest count only this page. The comment total covers the whole work.", "All comments", "Oldest", "Newest", "Delete this comment?", "This removes the comment on AO3. It cannot be undone.", "Reply to %s", "Show %d replies", "Show %d more", and "Continue thread".

## Screenshots
Captured on `emulator-5554` (Dark mode, Airplane mode):
- `docs/android-port/shots/3k/comments-dark.png`: Thread list, stat strip, filter rail, curved connector rails, author badges, and floating CTA.
- `docs/android-port/shots/3k/comments-chapter-picker-dark.png`: Chapter picker bottom sheet.
- `docs/android-port/shots/3k/comments-composer-dark.png`: Reply composer with parent quote rail, character countdown, and formatting toolbar.

## Claude's review (2026-10-03)
- Checked: pagination (Previous / "Page X of Y" / Next) kept. The `DemoNetwork` change still
  answers only the AO3 host while the demo is active (a `navigate` fixture route, plus
  `show_comments` handling).
- Fixed: the header sat under the floating back circle. It now uses the status-bar inset plus
  56dp, as the other pushed screens do.
- **Fixed a pre-existing auth bug:** the AO3 session was restored only when the Account tab was
  first opened, so a signed-in reader who went straight to Comments or Work detail saw "Log in to
  comment" and signed-out actions. `KudosApp` now restores at launch, as iOS `ContentView` does.
- Compared rows with iOS's comments demo: rails, avatars, the Author badge, chapter chips, Hide
  and ⋯ all match. iOS shows the reply action as an icon only; Android shows "Reply" with the icon.
  Left as a minor looks difference.
