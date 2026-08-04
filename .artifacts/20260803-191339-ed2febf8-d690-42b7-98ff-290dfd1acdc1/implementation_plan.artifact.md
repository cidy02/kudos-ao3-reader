# Phase 4: Library / Reading Queues / Collections

This phase focuses on enhancing reading queues and collections with management features, bulk actions, and better filtering.

## Proposed Changes

### Reading Queues (Items 1-7)

#### [QueueDetailScreen.kt](file:///Users/cidy02/Documents/AO3_App_OpenSource/android/app/src/main/java/io/github/cidy02/kudos/library/QueueDetailScreen.kt)
- Add drag-to-reorder support for works in the queue.
- Add Rename and Delete actions to the overflow menu.
- Integrate `LibraryFilterPanel` for filtering and sorting within the queue.

#### [ReadingQueueRepository.kt](file:///Users/cidy02/Documents/AO3_App_OpenSource/android/app/src/main/java/io/github/cidy02/kudos/library/ReadingQueueRepository.kt)
- Add `updateSortOrder(queueId, workIds)` to persist reordering.
- Add `renameQueue(queueId, newName)` and `deleteQueue(queueId)` (soft-delete).

#### [WorkDetailScreen.kt](file:///Users/cidy02/Documents/AO3_App_OpenSource/android/app/src/main/java/io/github/cidy02/kudos/works/WorkDetailScreen.kt)
- Add "Create New Queue" button to the `queuePickerOpen` dialog.
- Add series preservation logic (Download series works when adding one to a queue).

#### [ReadingQueueStorageScreen.kt](file:///Users/cidy02/Documents/AO3_App_OpenSource/android/app/src/main/java/io/github/cidy02/kudos/library/ReadingQueueStorageScreen.kt) [NEW]
- New screen to manage EPUB storage for queues.

---

### Collections (Item 8)

#### [CollectionDetailScreen.kt](file:///Users/cidy02/Documents/AO3_App_OpenSource/android/app/src/main/java/io/github/cidy02/kudos/library/CollectionDetailScreen.kt)
- Add "Add Works" action with a multi-select searchable work picker.

---

### Bulk Actions (Items 9, 10)

#### [LibraryViewModel.kt](file:///Users/cidy02/Documents/AO3_App_OpenSource/android/app/src/main/java/io/github/cidy02/kudos/library/LibraryViewModel.kt)
- Add bulk actions: Save toggle, Mark for Later toggle, Add to Queue, Add to Collection.

#### [AO3WorkCard.kt](file:///Users/cidy02/Documents/AO3_App_OpenSource/android/app/src/main/java/io/github/cidy02/kudos/ui/components/AO3WorkCard.kt)
- Wrap card with a selection mode affordance for remote lists (Search/Browse/Author).

---

### Account List Refinement (Item 12)

#### [AccountScreen.kt](file:///Users/cidy02/Documents/AO3_App_OpenSource/android/app/src/main/java/io/github/cidy02/kudos/account/AccountScreen.kt)
- Add filters, display-mode toggle, and expand-all to account list screens.
- Use `CanonicalWorkMerge` to render local cards in remote lists.

## Verification Plan

### Automated Tests
- Run `ReadingQueueRepositoryTest`.
- Command: `./gradlew test`

### Manual Verification
- Reorder works in a queue via drag-and-drop.
- Rename and soft-delete a queue; verify it shows in Recently Deleted.
- Add a work to a queue and verify all series works are downloaded.
- Perform bulk actions on multiple works in Library and Search results.
- Filter works in an AO3 Bookmark list.
