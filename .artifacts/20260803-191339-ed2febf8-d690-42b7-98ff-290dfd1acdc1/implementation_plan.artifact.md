# Phase 6: Browse / Search

This phase focuses on making the Browse and Search areas "local-first" by integrating the search index and canonical work merging, while also enhancing AO3 query features with better filtering and navigation.

## Proposed Changes

### Local Search Infrastructure (Prerequisite)

#### [SavedWork.kt](file:///Users/cidy02/Documents/AO3_App_OpenSource/android/app/src/main/java/io/github/cidy02/kudos/core/model/SavedWork.kt)
- Add `searchText` field for normalized full-text search.
- Add `searchIndexVersion` for rebuild tracking.

#### [WorkSearchIndex.kt](file:///Users/cidy02/Documents/AO3_App_OpenSource/android/app/src/main/java/io/github/cidy02/kudos/works/WorkSearchIndex.kt)
- Implement `reindex(work, userTags)` to populate `searchText`.
- Implement `matches(work, terms, userTags, extraTerms)` for local filtering.

---

### Local-First Search (Items 1, 2)

#### [SearchScreen.kt](file:///Users/cidy02/Documents/AO3_App_OpenSource/android/app/src/main/java/io/github/cidy02/kudos/search/SearchScreen.kt)
- Implement "Global Search": show matching local works, fandoms, and tags live as the user types.
- Add "Search AO3 for..." button as a fallback.

---

### Remote List Enhancements (Items 3-9, 14)

#### [AO3WorkCard.kt](file:///Users/cidy02/Documents/AO3_App_OpenSource/android/app/src/main/java/io/github/cidy02/kudos/ui/components/AO3WorkCard.kt)
- Make tag/fandom chips tappable to trigger a new search.
- Add long-press context menu for quick actions (Save, Download, Queue).

#### [FandomWorksScreen.kt](file:///Users/cidy02/Documents/AO3_App_OpenSource/android/app/src/main/java/io/github/cidy02/kudos/browse/FandomWorksScreen.kt)
- Add query-time `SearchFilterSheet` integration.
- Implement expand/collapse-all for remote results.
- Replace simple pager with a full pagination bar (First/Prev/Next/Last + numbers).

#### [TagWorksScreen.kt](file:///Users/cidy02/Documents/AO3_App_OpenSource/android/app/src/main/java/io/github/cidy02/kudos/browse/TagWorksScreen.kt) [NEW]
- New screen for browsing works for a specific tag, with client-side "refine" filtering.

---

### Background Self-Healing (Items 11, 12, 13)

#### [WorkTagsRepository.kt](file:///Users/cidy02/Documents/AO3_App_OpenSource/android/app/src/main/java/io/github/cidy02/kudos/network/ao3/work/WorkTagsRepository.kt) [NEW]
- Implement background AO3 tag refresh and availability tracking (404 detection).

#### [FandomCatalogCache.kt](file:///Users/cidy02/Documents/AO3_App_OpenSource/android/app/src/main/java/io/github/cidy02/kudos/network/ao3/browse/FandomCatalogCache.kt)
- Persist fandom catalog to disk with a 7-day TTL.

#### [SearchFilterSheet.kt](file:///Users/cidy02/Documents/AO3_App_OpenSource/android/app/src/main/java/io/github/cidy02/kudos/search/SearchFilterSheet.kt)
- Wire live AO3 tag autocomplete for the include/exclude fields.

## Verification Plan

### Automated Tests
- Create `WorkSearchIndexTest` for matching logic.
- Run `FandomCatalogCacheTest`.

### Manual Verification
- Type a query in Search and see local results appear instantly.
- Tap a fandom chip on a search result and verify it navigates to that fandom's works.
- Filter a fandom's works using the new filter panel.
- Verify pagination bar allows jumping to specific pages.
- Check that long-pressing a result card shows the action menu.
