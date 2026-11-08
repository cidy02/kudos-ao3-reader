import Foundation
import SwiftData
import Testing
@testable import Kudos

@MainActor
struct NewToYouTests {
    private let when = Date(timeIntervalSince1970: 1_762_000_000)

    @Test("Only new works from an author or a series become cards")
    func onlyAuthorAndSeriesNewWorks() {
        let updates = [
            update(workID: 1, source: .author("marrowlight"), isNewWork: true),
            update(workID: 2, source: .series("Series #4021"), isNewWork: true),
            update(workID: 3, source: .work, isNewWork: true, anchored: true),
            update(workID: 4, source: .author("marrowlight"), isNewWork: false),
            update(workID: 5, source: .unknown, isNewWork: true),
            update(workID: 6, source: .author("marrowlight"), isNewWork: true, contested: true)
        ]
        let cards = NewToYouDeck.cards(from: updates, library: WorkIdentityIndex([]), decidedWorkIDs: [])
        #expect(cards.map(\.workID).sorted() == [1, 2])
    }

    @Test("One card per work, skipping library works and decisions")
    func oneCardPerWorkExcludingLibraryAndDecisions() {
        let saved = SavedWork(
            title: "Already here",
            author: "Writer",
            sourceURL: "https://archiveofourown.org/works/42"
        )
        let library = WorkIdentityIndex([saved])
        let older = update(
            uid: 1, workID: 7, source: .author("marrowlight"), isNewWork: true,
            title: "Older claim", at: when
        )
        let newer = update(
            uid: 2, workID: 7, source: .author("marrowlight"), isNewWork: true,
            title: "Newer claim", at: when.addingTimeInterval(60)
        )
        let updates = [
            update(workID: 42, source: .author("marrowlight"), isNewWork: true),
            update(workID: 8, source: .series("Series #9"), isNewWork: true),
            older,
            newer
        ]
        let cards = NewToYouDeck.cards(
            from: updates,
            library: library,
            decidedWorkIDs: [8]
        )
        #expect(cards.map(\.workID) == [7])
        #expect(cards.first?.claimedTitle == "Newer claim")
        #expect(cards.first?.summary.title == "Newer claim")
    }

    @Test("The card headline is the subscription, and the title is only a claim")
    func headlineDoesNotStateTheTitle() {
        let author = update(
            workID: 11,
            source: .author("marrowlight"),
            isNewWork: true,
            title: "Honest Work",
            rating: nil,
            fandoms: ["Original Work"],
            words: 480,
            chaptersPosted: 3,
            summary: "A lighthouse."
        )
        let series = update(
            workID: 12,
            source: .series("Series #4021"),
            isNewWork: true,
            title: "Paper Boats",
            rating: "Not Rated"
        )
        let cards = NewToYouDeck.cards(
            from: [author, series],
            library: WorkIdentityIndex([]),
            decidedWorkIDs: []
        )
        let authorCard = cards.first { $0.workID == 11 }
        let seriesCard = cards.first { $0.workID == 12 }

        #expect(authorCard?.headline == "New from marrowlight")
        #expect(authorCard?.headline != "Honest Work")
        #expect(authorCard?.headline.contains("Honest Work") == false)
        #expect(authorCard?.attribution == "AO3's notification names \u{201C}Honest Work\u{201D}")
        #expect(seriesCard?.headline == "New in Series #4021")
        #expect(seriesCard?.headline.contains("Paper Boats") == false)
        for text in [authorCard?.headline, authorCard?.attribution, seriesCard?.headline, seriesCard?.attribution] {
            #expect(text?.localizedCaseInsensitiveContains("email") != true)
        }
        #expect(authorCard?.summary.isAdult == true)
        #expect(seriesCard?.summary.isAdult == true)
        #expect(authorCard?.summary.fandoms == ["Original Work"])
        #expect(authorCard?.summary.words == 480)
        #expect(authorCard?.summary.chapters == "3/?")
        #expect(authorCard?.summary.summary == "A lighthouse.")
        #expect(authorCard?.summary.rating.isEmpty == true)
    }

    @Test("A recognized teen rating stays visible to the gate")
    func teenRatingIsNotAdult() {
        let card = NewToYouDeck.cards(
            from: [update(
                workID: 13,
                source: .author("saltwindow"),
                isNewWork: true,
                rating: "Teen And Up Audiences"
            )],
            library: WorkIdentityIndex([]),
            decidedWorkIDs: []
        ).first
        #expect(card?.summary.isAdult == false)
        #expect(card?.summary.rating == "Teen And Up Audiences")
    }

    @Test("Maintenance does not save the work or record the decision")
    func maintenanceKeepsTheWorkUndecided() async throws {
        let context = try makeContext()
        var recorded = false
        let summary = AO3WorkSummary.subscription(id: 51, title: "Claimed", authors: ["Writer"])
        do {
            _ = try await NewToYouLibrary.save(summary, in: context, downloadEPUB: { _ in
                throw AO3Error.maintenance
            })
            recorded = true
            Issue.record("maintenance must throw")
        } catch AO3Error.maintenance {
            // The card stays. Nothing was written.
        }
        #expect(!recorded)
        #expect(try context.fetch(FetchDescriptor<SavedWork>()).isEmpty)
    }

    private func update(
        uid: UInt32? = nil,
        workID: UInt64,
        source: SubscriptionUpdate.Source,
        isNewWork: Bool,
        anchored: Bool = false,
        contested: Bool = false,
        title: String = "Honest Work",
        at: Date? = nil,
        rating: String? = nil,
        fandoms: [String] = [],
        words: UInt64? = nil,
        chaptersPosted: UInt32? = nil,
        summary: String? = nil
    ) -> SubscriptionUpdate {
        SubscriptionUpdate(
            uid: uid ?? UInt32(workID),
            workID: workID,
            chapterID: nil,
            chapterNumber: nil,
            isNewWork: isNewWork,
            isContested: contested,
            isAnchoredToWork: anchored,
            workTitle: title,
            author: "marrowlight",
            at: at ?? when,
            source: source,
            rating: rating,
            fandoms: fandoms,
            words: words,
            chaptersPosted: chaptersPosted,
            summary: summary
        )
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self, SyncTombstone.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }
}
