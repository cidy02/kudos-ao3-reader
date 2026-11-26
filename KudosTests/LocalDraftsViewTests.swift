import Foundation
import Testing
@testable import Kudos

/// Account-free drafts (T-576): the list's row detail, and a work written through the store shows up in it.
@MainActor
struct LocalDraftsViewTests {
    @Test func rowDetailCountsChaptersAndSaysWhenItWasEdited() {
        let work = WritingWork(
            id: UUID(), title: "Slack Water", ao3WorkID: nil, createdAt: .now, updatedAt: .now,
            updatedBy: "this-device", chapterOrder: [UUID(), UUID()]
        )
        #expect(LocalDraftsView.detail(for: work).hasPrefix("2 chapters · edited "))
        let one = WritingWork(
            id: UUID(), title: "", ao3WorkID: nil, createdAt: .now, updatedAt: .now,
            updatedBy: "this-device", chapterOrder: [UUID()]
        )
        #expect(LocalDraftsView.detail(for: one).hasPrefix("1 chapter · "))
    }

    @Test func aWorkCreatedInTheStoreIsListed() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("local-drafts-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WritingDocumentStore(root: root)
        let created = try await store.createWork(title: "No account needed")
        let listed = try await store.listWorks()
        #expect(listed.map(\.id).contains(created.id))
    }
}
