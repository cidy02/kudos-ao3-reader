import Foundation
import SwiftData
import Testing
@testable import Kudos

/// Tests the library-wide availability sweep.
///
/// These are mostly *politeness* tests. The sweep's whole justification is that it sends
/// no more traffic than it has to, so what needs pinning is which works it skips, how
/// many it will contact, and that it stops when told — not that it can make a request.
@MainActor
struct WorkAvailabilitySweepTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, SyncTombstone.self, ReadingAnnotation.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [configuration]))
    }

    @discardableResult
    private func ao3Work(_ context: ModelContext, id: Int, checked: Date? = nil) -> SavedWork {
        let work = SavedWork(
            title: "Work \(id)",
            author: "A",
            sourceURL: "https://archiveofourown.org/works/\(id)"
        )
        work.ao3WorkID = id
        work.lastAvailabilityCheck = checked
        context.insert(work)
        return work
    }

    /// No pacing, so tests do not spend real seconds sleeping.
    private func run(
        _ context: ModelContext,
        limit: Int = WorkAvailabilitySweep.defaultLimit,
        verify: @escaping (SavedWork) async -> Void
    ) async -> WorkAvailabilitySweep.Summary {
        await WorkAvailabilitySweep.run(
            in: context,
            limit: limit,
            spacing: .zero,
            verify: verify
        )
    }

    // MARK: - What it will and won't contact

    @Test func onlyAO3WorksAreEverContacted() async throws {
        // A fanfiction.net work cannot be checked at all, so it must not cost a request.
        let context = try makeContext()
        ao3Work(context, id: 1)
        let ffn = SavedWork(title: "FFN", author: "A", sourceURL: "https://www.fanfiction.net/s/9/1/")
        context.insert(ffn)
        let imported = SavedWork(title: "Imported", author: "A")
        context.insert(imported)

        var contacted: [String] = []
        let summary = await run(context) { work in
            contacted.append(work.title)
            work.lastAvailabilityCheck = Date()
        }

        #expect(contacted == ["Work 1"])
        #expect(summary.checked == 1)
        // Reported rather than hidden, so the count not matching the library is explained.
        #expect(summary.unverifiable == 2)
    }

    @Test func recentlyCheckedWorksAreSkipped() async throws {
        // Running twice in an afternoon should send no traffic the second time.
        let context = try makeContext()
        ao3Work(context, id: 1, checked: Date())
        ao3Work(context, id: 2, checked: Date().addingTimeInterval(-8 * 24 * 3600))

        var contacted: [String] = []
        let summary = await run(context) { work in
            contacted.append(work.title)
            work.lastAvailabilityCheck = Date()
        }

        #expect(contacted == ["Work 2"], "a work checked today must not be re-asked")
        #expect(summary.skippedRecent == 1)
    }

    @Test func worksInRecentlyDeletedAreLeftAlone() async throws {
        let context = try makeContext()
        let work = ao3Work(context, id: 1)
        work.isPendingDeletion = true

        var contacted = 0
        let summary = await run(context) { _ in contacted += 1 }
        #expect(contacted == 0)
        #expect(summary.checked == 0)
    }

    @Test func neverCheckedWorksGoFirst() async throws {
        // Oldest-first ordering is what makes repeated runs cover a large library
        // instead of re-walking the same prefix.
        let context = try makeContext()
        ao3Work(context, id: 1, checked: Date().addingTimeInterval(-10 * 24 * 3600))
        ao3Work(context, id: 2, checked: nil)
        ao3Work(context, id: 3, checked: Date().addingTimeInterval(-30 * 24 * 3600))

        let order = WorkAvailabilitySweep.pending(in: context).map(\.title)
        #expect(order == ["Work 2", "Work 3", "Work 1"])
    }

    // MARK: - Bounds and reporting

    @Test func theRunIsCappedAndSaysWhatItDidNotReach() async throws {
        let context = try makeContext()
        for id in 1...5 { ao3Work(context, id: id) }

        var contacted = 0
        let summary = await run(context, limit: 2) { work in
            contacted += 1
            work.lastAvailabilityCheck = Date()
        }

        #expect(contacted == 2)
        #expect(summary.checked == 2)
        // A silent cap would read as "your library is fine".
        #expect(summary.remaining == 3)
    }

    @Test func cancellationStopsAndKeepsWhatItFound() async throws {
        let context = try makeContext()
        for id in 1...20 { ao3Work(context, id: id) }

        let task = Task { @MainActor in
            await WorkAvailabilitySweep.run(
                in: context,
                spacing: .milliseconds(50),
                verify: { work in work.lastAvailabilityCheck = Date() }
            )
        }
        // Let a couple through, then stop it.
        try await Task.sleep(for: .milliseconds(120))
        task.cancel()
        let summary = await task.value

        #expect(summary.cancelled)
        #expect(summary.checked > 0, "work done before cancelling must be kept")
        #expect(summary.checked < 20)
        #expect(summary.remaining > 0)
    }

    // MARK: - Outcomes

    @Test func deletedWorksAreCountedAndBadged() async throws {
        let context = try makeContext()
        let gone = ao3Work(context, id: 1)
        gone.hasEPUB = true
        ao3Work(context, id: 2)

        let summary = await run(context) { work in
            // Work 1 is gone from AO3; work 2 is fine.
            WorkAvailability.record(work.ao3WorkID == 1 ? .deleted : .present, on: work, in: context)
        }

        #expect(summary.nowUnavailable == 1)
        #expect(summary.stillAvailable == 1)
        #expect(gone.preservationState == .preservedLastCopy)
    }

    @Test func anInconclusiveCheckCountsAsNeitherOutcome() async throws {
        // A timeout records nothing, so it must not be reported as "still available" —
        // that would be a clean bill of health the sweep did not earn.
        let context = try makeContext()
        ao3Work(context, id: 1)

        let summary = await run(context) { _ in }
        #expect(summary.checked == 1)
        #expect(summary.stillAvailable == 0)
        #expect(summary.nowUnavailable == 0)
    }
}
