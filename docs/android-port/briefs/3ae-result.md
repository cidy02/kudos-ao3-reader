# 3ae result

Done by Claude: Codex's weekly limit ran out before it could start.

## What changed

- `library/WorkMembershipDialogs.kt` (new) holds the Library's two dialogs, moved out of
  `LibraryScreen` with their strings, buttons and repository calls unchanged:
  - `AddToQueueDialog(queues, onAdd, onManageQueues, onDismiss)`
  - `AddToCollectionDialog(workId, collections, workRepository, scope, onSetMembership, onDismiss)`
  - `ReadingQueueRepository.queuePreviews()`: every queue with its work count. `LibraryViewModel`
    had this listing written out twice; both now call it.
- `LibraryScreen` calls the two composables with the same view-model calls as before
  (`addToQueue`, `setCollectionMembership`) and the same "Manage queues" navigation.
- `HomeSectionListScreen` opens the same two dialogs from a row's menu. Add to Queue calls
  `ReadingQueueRepository.addWork(queueId, workId)`; the collection checklist calls
  `WorkRepository.addWorkToCollection` / `removeFromCollection`, and its "Add" field calls
  `WorkRepository.addToCollection(workId, name)`, exactly as the Library's do.
- New parameter: `HomeSectionListScreen(onOpenReadingQueues = {})`, passed from `AppNavHost` for
  the "Manage queues" button.

## Strings (all unchanged from the Library's)

"Add to Queue", "No queues yet. Create one from Reading Queues.", "Close", "Manage queues",
"Add to Collection", "New collection", "Add", "No collections yet. Create one above to start
grouping works.", "Collections", "Done".

## Checked on the emulator (Dark)

From Recently Opened on Home: the row menu, the queue dialog listing the four queues, adding the
work to "Case fic pile" (the database gained one `reading_queue_memberships` row), the collection
checklist, and toggling "To recommend" (one `collection_work_cross_refs` row removed, then added
back). From the Library's Reading Now list: both dialogs still open with the same contents. The
demo data was put back afterwards.
