# Adversarial Self-Review: Phase 5 (Comments / Discussion)

## 1. Recursion & Performance
- **Finding**: `CommentThreadRow` is a recursive Composable. For extremely deep threads (rare but possible on AO3), this might cause a `StackOverflowError` during composition or simply UI stutter.
- **Mitigation**: Added `expanded` state per node and `depth` clamping in padding. Collapse/expand is the primary mitigation.
- **Fix**: Consider a flat list of flattened tree nodes if performance becomes a real-world issue. For parity with iOS, the current recursive structure is faithful.

## 2. Navigation & Deep-linking
- **Finding**: "View Thread" in the dropdown menu calls `viewModel.load(focusedCommentId = commentId)`, which resets the whole view to a single thread. There's no "Back to all comments" affordance other than reloading the whole page.
- **Fix**: The ViewModel should keep track of whether it's in a "focused" mode and provide a "Clear focus" action in the UI.

## 3. Data Integrity & Drafting
- **Finding**: `CommentDraftStore` uses `PreferencesDataStore` with a string key. It's safe but the keying format (`draft:workId:chapterId:...`) is hand-rolled.
- **Mitigation**: Consistent with other stores in the project.

## 4. UI Consistency
- **Finding**: `CommentsScreen` is now managed by a ViewModel, but `target` is still passed via the Composable parameter and used as a `remember(target)` key.
- **Impact**: If navigation passes a new target, the ViewModel is re-initialized correctly, but internal `mutableStateOf` (if any left) might need careful sync.
- **Fix**: Most state was moved to the ViewModel, which is good.

## 5. Potential Regressions
- **Finding**: `AO3CommentRepository.loadThread` now supports `focusedCommentId`. The previous single-chapter/work URL logic was modified.
- **Verification**: Ensure that when `focusedCommentId` is null, it still correctly uses `target.pageUrl(safePage)`. (Confirmed in code).

---

# Action Plan for Self-Review Findings:
1. Add a "Focused Thread" header with a "Clear" button when viewing a single thread.
2. Implement `AO3CommentRepository.editComment` and `deleteComment` UI (Delete confirmation dialog).
3. Wire the "Read more" clamping logic more robustly (already implemented but can be refined).
