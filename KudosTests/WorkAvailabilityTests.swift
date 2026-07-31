import Foundation
import SwiftData
import Testing
@testable import Kudos

/// Tests the import-time "does this still exist?" check.
///
/// The network is stubbed through `verify`'s injectable fetch, so these exercise the
/// state transitions rather than AO3.
@MainActor
struct WorkAvailabilityTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, SyncTombstone.self, ReadingAnnotation.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [configuration]))
    }

    /// A work that already has everything the tag refresh would fetch — which is
    /// precisely the case that used to skip the check entirely.
    private func fullyPopulatedWork(id: Int = 555) -> SavedWork {
        let work = SavedWork(
            title: "Complete Metadata",
            author: "Someone",
            sourceURL: "https://archiveofourown.org/works/\(id)"
        )
        work.ao3WorkID = id
        work.hasEPUB = true
        work.workTags = ["Fluff"]
        work.workFandoms = ["A Fandom"]
        work.workWarnings = ["No Archive Warnings Apply"]
        work.workCategories = ["Gen"]
        work.language = "English"
        work.wordCount = 1000
        work.chapters = "1/1"
        work.workTagsFetched = true
        work.authorIdentitiesJSON = "[]"
        return work
    }

    /// `nonisolated static` because the stub closure is `@Sendable` and does not run
    /// on the main actor.
    private nonisolated static func metadata(id: Int = 555) -> AO3WorkMetadata {
        AO3WorkMetadata(id: id, title: "Complete Metadata")
    }

    @Test func a404MarksTheLocalCopyAsTheLastOne() async throws {
        let context = try makeContext()
        let work = fullyPopulatedWork()
        context.insert(work)

        await WorkAvailability.verify(work, in: context) { _ in throw AO3Error.notFound }

        #expect(work.ao3Unavailable)
        #expect(work.lastAvailabilityCheck != nil)
        // The badge the owner asked for reads this.
        #expect(work.preservationState == .preservedLastCopy)
    }

    @Test func aWorkStillOnAO3IsRecordedAsChecked() async throws {
        let context = try makeContext()
        let work = fullyPopulatedWork()
        context.insert(work)

        await WorkAvailability.verify(work, in: context) { _ in Self.metadata() }

        #expect(!work.ao3Unavailable)
        #expect(work.lastAvailabilityCheck != nil)
        #expect(work.preservationState == .available)
    }

    @Test func aWorkThatReappearsLosesTheFlag() async throws {
        // The one-way trap this fixes: `needsAO3Refresh` returns false while
        // `ao3Unavailable` is true, so nothing else would ever clear it and a work an
        // author un-hid stayed labelled as deleted forever.
        let context = try makeContext()
        let work = fullyPopulatedWork()
        work.ao3Unavailable = true
        context.insert(work)

        await WorkAvailability.verify(work, in: context) { _ in Self.metadata() }

        #expect(!work.ao3Unavailable)
        #expect(work.preservationState == .available)
    }

    @Test func anInconclusiveFailureRecordsNothingAtAll() async throws {
        // A timeout says nothing about existence. Crucially the *timestamp* is not
        // stamped either, so a later pass still sees this work as unchecked rather
        // than as verified-present.
        let context = try makeContext()
        let work = fullyPopulatedWork()
        context.insert(work)

        await WorkAvailability.verify(work, in: context) { _ in
            throw URLError(.timedOut)
        }

        #expect(!work.ao3Unavailable)
        #expect(work.lastAvailabilityCheck == nil)
    }

    @Test func aFailureDoesNotClearAnExistingFlag() async throws {
        let context = try makeContext()
        let work = fullyPopulatedWork()
        work.ao3Unavailable = true
        context.insert(work)

        await WorkAvailability.verify(work, in: context) { _ in throw URLError(.notConnectedToInternet) }

        // Still flagged: being offline is not evidence the work came back.
        #expect(work.ao3Unavailable)
    }

    @Test func aWorkWithNoAO3IdentityIsLeftUnknown() async throws {
        // A community copy from fanfiction.net cannot be checked — there is no native
        // path to that site — so nothing is recorded rather than implying it is fine.
        let context = try makeContext()
        let work = SavedWork(
            title: "Rescued",
            author: "Lost",
            sourceURL: "https://www.fanfiction.net/s/999/1/"
        )
        context.insert(work)

        var fetched = false
        await WorkAvailability.verify(work, in: context) { _ in
            fetched = true
            return Self.metadata()
        }

        #expect(!fetched, "a non-AO3 work must not trigger an AO3 request")
        #expect(!work.ao3Unavailable)
        #expect(work.lastAvailabilityCheck == nil)
        #expect(work.origin == .fanfictionNet)
    }

    @Test func theWorkIDIsRecoveredFromTheSourceURL() async throws {
        // A converted AO3 HTML download keeps its work URL but has no id yet; the check
        // has to find it, which is also what lets tags refresh later.
        let context = try makeContext()
        let work = SavedWork(
            title: "Converted",
            author: "A",
            sourceURL: "https://archiveofourown.org/works/424242"
        )
        work.workTags = ["Fluff"]
        work.workFandoms = ["F"]
        work.workWarnings = ["W"]
        work.workCategories = ["Gen"]
        work.language = "English"
        work.wordCount = 10
        work.chapters = "1/1"
        work.workTagsFetched = true
        work.authorIdentitiesJSON = "[]"
        context.insert(work)

        var requestedID: Int?
        await WorkAvailability.verify(work, in: context) { id in
            requestedID = id
            return Self.metadata(id: id)
        }

        #expect(requestedID == 424_242)
        #expect(work.ao3WorkID == 424_242)
    }
}
