# Adversarial Self-Review: Phase 4 (Library/Queues/Collections)

## 1. Data Integrity & Persistence
- **Finding**: `ReadingQueueRepository.updateSortOrder` iterates through IDs and updates each one. If the process is killed midway, the queue will be partially reordered.
- **Mitigation**: DB operations for reordering should ideally be in a single transaction. Room `@Transaction` can be used.
- **Finding**: `CanonicalWorkMerge.remoteLed` only pairs IDs. It doesn't update the local record if it was already deleted.
- **Mitigation**: `WorkIdentityIndexInstance` already associates by source URL, which includes deleted works if `WorkRepository` observes them. `AccountListViewModel` uses `workRepository.observeSavedWorks()` which filters `isSaved`. This might miss works that are in history but not explicitly "Saved".
- **Fix**: Update `AccountListViewModel` to use `observeLibraryWorks()` (all local works) instead of `observeSavedWorks()`.

## 2. UI/UX Consistency
- **Finding**: `LibraryFilterPanel` uses `emptyList()` for `userTags` and `collections` in `QueueDetailScreen`.
- **Impact**: The filter panel inside a queue detail won't show user tags or collections to filter by, unlike the main Library screen.
- **Fix**: Thread `userTags` and `collections` from a ViewModel or repository into `QueueDetailScreen`.

## 3. Performance
- **Finding**: `AccountListViewModel` re-calculates `CanonicalWorkMerge.remoteLed` every time `local` works change (e.g. on every scroll or update).
- **Mitigation**: This is an in-memory map lookup, so it's relatively cheap, but for very large libraries it might cause stutter.
- **Fix**: Ensure `WorkIdentityIndexInstance` is optimized (which it is, using Maps).

## 4. Feature Parity
- **Finding**: `ReadingQueueStorageScreen` was in the brief but not implemented.
- **Impact**: Users can't manage disk usage specifically for reading queues.
- **Resolution**: Move to Phase 4b or Phase 11 polish.

## 5. Potential Regressions
- **Finding**: Making `LibraryCarouselCard` and `LibraryCardActions` public for reuse in `AccountScreen` might lead to unintended usages elsewhere.
- **Mitigation**: These are now explicitly shared components.

---

# Action Plan for Self-Review Findings:
1. Wrap `updateSortOrder` in a transaction.
2. Fix `AccountListViewModel` to observe all library works for better merging.
3. Pass real tags/collections to `QueueDetailScreen`'s filter panel.
