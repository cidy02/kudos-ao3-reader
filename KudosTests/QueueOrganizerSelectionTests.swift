import Foundation
import SwiftData
import Testing
@testable import Kudos

/// Artboard 1i's select mode (bulk Pin / Delete) and its always-live drag,
/// which a filter switches off.
@MainActor
struct QueueOrganizerSelectionTests {
    /// Pin pins the whole selection unless every queue already is — then the
    /// same button unpins them all.
    @Test func bulkPinPinsTheRestThenUnpinsAll() throws {
        let context = try makeContext()
        let pinned = ReadingQueueService.createQueue(named: "Pinned", in: context)
        pinned.isPinned = true
        let loose = ReadingQueueService.createQueue(named: "Loose", in: context)
        loose.syncStatus = .synced
        pinned.syncStatus = .synced
        let selection = [pinned, loose]

        #expect(QueueOrganizerSelection.pinTarget(selection))
        QueueOrganizerSelection.setPinned(selection, QueueOrganizerSelection.pinTarget(selection), in: context)
        #expect(pinned.isPinned && loose.isPinned)
        // The pin is a real change to sync; a queue already pinned is not stamped.
        #expect(loose.syncStatus == .pending)
        #expect(pinned.syncStatus == .synced)

        #expect(!QueueOrganizerSelection.pinTarget(selection))
        QueueOrganizerSelection.setPinned(selection, QueueOrganizerSelection.pinTarget(selection), in: context)
        #expect(!pinned.isPinned && !loose.isPinned)
    }

    /// Bulk Delete is the single-queue delete per queue: Recently Deleted, works
    /// intact. Saved for Later is never deleted, and an unselected queue is left.
    @Test func bulkDeleteSoftDeletesTheSelectedCustomQueuesOnly() throws {
        let context = try makeContext()
        let savedForLater = ReadingQueueService.ensureSavedForLaterQueue(in: context)
        let chosen = ReadingQueueService.createQueue(named: "Chosen", in: context)
        let kept = ReadingQueueService.createQueue(named: "Kept", in: context)
        let work = SavedWork(title: "Queued", author: "Writer")
        context.insert(work)
        ReadingQueueService.add(work, to: chosen, in: context)

        let selection = [savedForLater, chosen]
        #expect(QueueOrganizerSelection.deletable(selection).map(\.id) == [chosen.id])
        QueueOrganizerSelection.delete(selection, in: context)

        #expect(chosen.isPendingDeletion)
        #expect(chosen.permanentDeletionScheduledAt != nil)
        #expect(chosen.memberships.count == 1)
        #expect(!savedForLater.isPendingDeletion)
        #expect(!kept.isPendingDeletion)
        #expect(QueueOrganizerSelection.deleteTitle([chosen]) == "Delete “Chosen”?")
        #expect(QueueOrganizerSelection.deleteTitle([chosen, kept]) == "Delete 2 queues?")
        #expect(QueueOrganizerSelection.deleteMessage(count: 1).hasPrefix("The queue moves"))
        #expect(QueueOrganizerSelection.deleteMessage(count: 2).hasPrefix("The 2 queues move"))
    }

    /// A filtered list can't write its order back, so the drag is off under a
    /// tag filter or a search, and the header line says which to clear.
    @Test func dragIsOffUnderAFilterAndTheHeaderSaysSo() {
        #expect(QueueOrganizerSelection.canReorder(tagFilterActive: false, searchActive: false))
        #expect(!QueueOrganizerSelection.canReorder(tagFilterActive: true, searchActive: false))
        #expect(!QueueOrganizerSelection.canReorder(tagFilterActive: false, searchActive: true))
        #expect(QueueOrganizerSelection.reorderNote(tagFilterActive: false, searchActive: false) == "Drag to reorder")
        #expect(QueueOrganizerSelection.reorderNote(tagFilterActive: true, searchActive: true)
            == "Clear the tag filter to reorder")
        #expect(QueueOrganizerSelection.reorderNote(tagFilterActive: false, searchActive: true)
            == "Clear the search to reorder")
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, SyncTombstone.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }
}
