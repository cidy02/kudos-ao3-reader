# Adversarial Self-Review: Phase 6 (Browse / Search)

## 1. State Management Complexity
- **Finding**: `SearchScreen` is holding too much state (filters, results, generation, saved searches).
- **Fix**: Move search state to a `SearchViewModel`. This will also fix the "stubbed" tag-tapping logic more cleanly.

## 2. Tag Tapping Gaps
- **Finding**: `onTagClick` in `SearchScreen` and `AO3WorkCard` is currently a no-op or stub.
- **Fix**: Wire `onTagClick` to trigger a new AO3 search with that tag as the primary filter.

## 3. Search Index Integrity
- **Finding**: `WorkRepository` correctly calls `reindex` on `upsert`, but does it handle user tag changes?
- **Verification**: `reindexSearchForWork` exists but needs to be called when user tags are added/removed. (Confirmed: `addUserTag` and `removeUserTag` in `WorkRepository.kt` should trigger a reindex).

## 4. UI Consistency
- **Finding**: `TagWorksScreen` and `FandomWorksScreen` have slightly different pagination and header logic.
- **Fix**: Consolidate into shared components where possible. Added `TagWorksScreen` to `AppNavHost` but didn't verify navigation from fandom chips.

## 5. Metadata Accuracy
- **Finding**: `toRemoteSummary()` in `SearchScreen` hand-rolls the conversion from `SavedWork` to `AO3WorkSummary`.
- **Mitigation**: Standardize this conversion in a model extension.

---

# Action Plan for Self-Review Findings:
1. Create `SearchViewModel` to manage `SearchScreen` state and tag-tapping.
2. Wire `addUserTag` / `removeUserTag` to `reindexSearchForWork` in `WorkRepository`.
3. Fix the `onTagClick` stubs to navigate/refresh search.
4. Add a "Search by Tag" button to result cards or context menus.
