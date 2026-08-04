# Phase 5: Comments / Discussion

This phase focuses on rebuilding the comment system to support nested threading, chapter-aware scoping, and full management (edit/delete) with reliability features like duplicate guards and draft persistence.

## User Review Required

- **Nested Threading Design**: The UI will transition from a flat list to a nested tree. This may affect performance on very deep threads; I will implement collapse/expand to mitigate this.

## Proposed Changes

### Comment Tree Infrastructure (Prerequisite)

#### [AO3CommentModels.kt](file:///Users/cidy02/Documents/AO3_App_OpenSource/android/app/src/main/java/io/github/cidy02/kudos/network/ao3/comments/AO3CommentModels.kt)
- Update `AO3Comment` to include `replies: List<AO3Comment>`, `parentCommentID`, and `threadPath`.
- Add `isThreadCutoff`, `cutoffCount`, and `cutoffThreadPath` for AO3's deep-thread disclosures.

#### [AO3CommentParser.kt](file:///Users/cidy02/Documents/AO3_App_OpenSource/android/app/src/main/java/io/github/cidy02/kudos/network/ao3/comments/AO3CommentParser.kt)
- Rebuild `parseComments` to recursively build a tree instead of a flat list.
- Capture `chapterID` and `chapterLabel` for each comment.

---

### Nested Rendering & Interaction (Items 1, 2, 3, 15, 16, 17, 18)

#### [CommentsScreen.kt](file:///Users/cidy02/Documents/AO3_App_OpenSource/android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsScreen.kt)
- Implement recursive `CommentThreadRow` that renders nested replies.
- Add collapse/expand state management per comment.
- Add "Read more" clamp (5 lines) for long comment bodies.
- Render chapter badges and cutoff nodes ("N more comments...").
- Add "Thread", "Parent Thread", and "Copy Link" actions to each comment.

---

### Comment Management & Reliability (Items 5, 6, 8, 9, 11, 19)

#### [AO3CommentRepository.kt](file:///Users/cidy02/Documents/AO3_App_OpenSource/android/app/src/main/java/io/github/cidy02/kudos/network/ao3/comments/AO3CommentRepository.kt)
- Add `editComment(path, content)` and `deleteComment(path)` (PUT/DELETE).
- Implement ambiguous-submission verification (re-fetch after timeout to check if post landed).
- Add comment-page caching with a 300s TTL.

#### [CommentDraftStore.kt](file:///Users/cidy02/Documents/AO3_App_OpenSource/android/app/src/main/java/io/github/cidy02/kudos/network/ao3/comments/CommentDraftStore.kt) [NEW]
- Persist drafts keyed by (work, chapter, parent-comment, identity).

---

### Scoping & Navigation (Items 10, 12, 13, 14)

#### [CommentsViewModel.kt](file:///Users/cidy02/Documents/AO3_App_OpenSource/android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsViewModel.kt)
- Support `AO3CommentTarget.Chapter` and implement chapter-picker UI.
- Add newest-first/oldest-first sorting toggle.
- Add `loadFocusedThread(commentId)` for inbox notification deep-links.

#### [WorkDetailScreen.kt](file:///Users/cidy02/Documents/AO3_App_OpenSource/android/app/src/main/java/io/github/cidy02/kudos/works/WorkDetailScreen.kt)
- Update Discussion tab rows to correctly pass chapter scoping.
- Hide "Chapter Comments" for single-chapter works.

## Verification Plan

### Automated Tests
- Create `AO3CommentTreeTest` to verify recursive parsing and tree structure.
- Run `AO3CommentRepositoryTest` for management actions.

### Manual Verification
- Expand/collapse deep threads in a busy work.
- Post a comment, edit it, and delete it; verify AO3 reflects changes.
- Verify "Read more" clamping on long comments.
- Test "By Chapter" filter and verify it only shows comments for that chapter.
- Trigger a network timeout mid-post and verify the duplicate guard prevents double-posting.
