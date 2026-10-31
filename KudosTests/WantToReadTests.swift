import Foundation
import SwiftData
import Testing
@testable import Kudos

@MainActor
struct WantToReadTests {
    @Test func librarySectionKindSavedForLaterDisplaysWantToRead() {
        #expect(LibrarySectionKind.savedForLater.title == "Want to Read")
        #expect(LibrarySectionKind.savedForLater.emptyMessage.contains("Want to Read"))
        #expect(!LibrarySectionKind.savedForLater.emptyMessage.contains("Saved for Later"))
    }

    @Test func readingQueueSavedForLaterDisplaysWantToReadWhilePreservingStoredName() {
        let queue = ReadingQueue(name: "Saved for Later", kind: .savedForLater)
        #expect(queue.displayName == "Want to Read")
        #expect(queue.name == "Saved for Later")
        #expect(queue.displayHue == CoverArt.hue(for: "Saved for Later"))
        #expect(ReadingQueueService.savedForLaterName == "Saved for Later")

        let custom = ReadingQueue(name: "Favorites", kind: .custom)
        #expect(custom.displayName == "Favorites")
    }

    @Test func newQueueSeedSavedForLaterDisplaysWantToRead() {
        #expect(NewQueueSeed.savedForLater.title == "Want to Read")
        #expect(NewQueueSeed.empty.title == "Empty")
    }

    @Test func workActionLabelsSavedForLaterDisplayWantToRead() {
        let unqueued = WorkActionLabels.savedForLater(isQueued: false)
        #expect(unqueued.title == "Want to Read")
        #expect(unqueued.systemImage == "clock")

        let queued = WorkActionLabels.savedForLater(isQueued: true)
        #expect(queued.title == "Remove from Want to Read")
        #expect(queued.systemImage == "clock.badge.xmark")
    }

    @Test func workDetailPresentationLaterActionDisplayWantToRead() {
        let unqueued = WorkDetailPresentation.laterAction(isQueued: false)
        #expect(unqueued.title == "Want to Read")

        let queued = WorkDetailPresentation.laterAction(isQueued: true)
        #expect(queued.title == "Remove from Want to Read")
    }
}
