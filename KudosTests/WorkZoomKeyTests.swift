import Foundation
import SwiftData
import Testing
@testable import Kudos

/// Pins the identity the zoom transition matches a work card against its pushed
/// destination on.
///
/// This is worth testing directly because its failure mode is silent: a remote
/// card's advertised source id and its destination's id are two different model
/// types (`AO3WorkSummary.id: Int` vs `SavedWork.id: UUID`) with no natural
/// relationship, so a mismatch produces no error — `matchedTransitionSource` and
/// `navigationTransition(.zoom(sourceID:))` simply never pair, and the screen falls
/// back to an ordinary push. Found by re-reading `WorkCardZoomTransition.swift`
/// after wiring the Account tab, not by any test failing.
@MainActor
struct WorkZoomKeyTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([SavedWork.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [configuration]))
    }

    private func summary(_ id: Int) -> AO3WorkSummary {
        AO3WorkSummary(
            id: id,
            title: "Summary Work \(id)",
            authors: ["Writer"],
            fandoms: ["Fandom"],
            rating: "Teen And Up Audiences",
            warnings: ["No Archive Warnings Apply"],
            categories: [],
            isComplete: true,
            dateUpdated: "2026-06-30",
            tags: ["Freeform"],
            summary: "Summary \(id)",
            language: "English",
            words: 1_000,
            chapters: "1/1",
            comments: nil,
            kudos: nil,
            hits: nil,
            seriesTitle: nil,
            seriesURL: nil,
            seriesPosition: nil
        )
    }

    // MARK: - The pairing the whole transition depends on

    /// This is the actual regression case: once a remote card's work resolves to a
    /// local one (`ReadingQueueService.applyRemoteMetadata` sets `ao3WorkID`), the
    /// two must produce the *same* key or the zoom silently never fires.
    @Test func aRemoteSummaryAndItsResolvedLocalWorkShareOneZoomKey() throws {
        let context = try makeContext()
        let remote = summary(9001)
        let local = SavedWork(title: remote.title, author: "Writer")
        context.insert(local)

        // What ReadingQueueService.applyRemoteMetadata does to the identity field —
        // exercised directly here rather than through the network-backed import path.
        local.ao3WorkID = remote.id

        #expect(local.zoomKey == remote.zoomKey)
    }

    @Test func anAO3BackedLocalWorkKeysOnTheAO3ID() throws {
        let context = try makeContext()
        let work = SavedWork(title: "Backed by AO3", author: "Writer")
        work.ao3WorkID = 4242
        context.insert(work)

        #expect(work.zoomKey == .ao3(4242))
    }

    @Test func anImportedWorkWithNoAO3OriginKeysOnItsOwnID() throws {
        // A converted PDF/HTML/text import: no AO3 identity exists, and no remote
        // card ever needs to match this one, so its own UUID is the whole story.
        let context = try makeContext()
        let work = SavedWork(title: "Imported From a File", author: "Writer")
        context.insert(work)

        #expect(work.ao3WorkID == nil)
        #expect(work.zoomKey == .local(work.id))
    }

    @Test func twoDifferentAO3WorksNeverShareAKey() {
        #expect(summary(1).zoomKey != summary(2).zoomKey)
    }

    @Test func aRemoteSummaryAlwaysKeysOnItsAO3ID() {
        #expect(summary(5555).zoomKey == .ao3(5555))
    }
}
