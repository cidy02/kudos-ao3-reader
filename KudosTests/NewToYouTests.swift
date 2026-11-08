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

    @MainActor
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
        // No rating in the notification: blank, so the gate's undetermined rule conceals
        // the card in either mode (it is never shown in the clear).
        let gate = PrivacyGate()
        #expect(authorCard.map { gate.isBlurred($0.summary, enabled: true, mode: .obscure) } == true)
        #expect(authorCard.map { gate.isBlurred($0.summary, enabled: true, mode: .hide) } == true)
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
        var recorded: [UInt64] = []
        let summary = AO3WorkSummary.subscription(id: 51, title: "Claimed", authors: ["Writer"])
        let card = NewToYouCard(preview: summary, source: .author("marrowlight"))
        do {
            _ = try await NewToYouLibrary.save(card, in: context, downloadEPUB: { _ in
                throw AO3Error.maintenance
            }) { recorded.append($0) }
            Issue.record("maintenance must throw")
        } catch AO3Error.maintenance {
            // The card stays. Nothing was written.
        }
        #expect(recorded.isEmpty)
        #expect(try context.fetch(FetchDescriptor<SavedWork>()).isEmpty)
    }

    @Test("Save stores the EPUB's metadata, not the card's claims")
    func saveUsesEPUBMetadataNotTheClaim() async throws {
        let context = try makeContext()
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("NewToYou-\(UUID().uuidString).epub")
        try FileManager.default.copyItem(at: try EPUBTests.sampleEPUB, to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }

        var summary = AO3WorkSummary.subscription(
            id: 77, title: "Claimed Title", authors: ["Claimed Author"]
        )
        summary.summary = "Claimed blurb"
        summary.fandoms = ["Claimed Fandom"]
        summary.rating = "Explicit"
        summary.chapters = "99/?"
        let card = NewToYouCard(preview: summary, source: .author("marrowlight"))

        let work = try await NewToYouLibrary.save(card, in: context, downloadEPUB: { _ in temp }) { _ in }
        defer { try? FileManager.default.removeItem(at: work.fileURL) }

        #expect(work.title == "A Test Work")
        #expect(work.author == "Test Author")
        #expect(work.summary != "Claimed blurb")
        #expect(work.rating == "Teen And Up Audiences")
        #expect(!work.workFandoms.contains("Claimed Fandom"))
        #expect(work.chapters != "99/?")
        #expect(work.ao3WorkID == 77)
        #expect(work.isInSavedForLaterQueue)
    }

    @Test("A failed EPUB install leaves no library row and no saved decision")
    func failedInstallDoesNotSaveOrDecide() async throws {
        let card = NewToYouCard(
            preview: AO3WorkSummary.subscription(id: 51, title: "Claimed", authors: ["Writer"]),
            source: .author("marrowlight")
        )
        let invalid = FileManager.default.temporaryDirectory
            .appendingPathComponent("NewToYou-bad-\(UUID().uuidString).epub")
        try Data("not an epub".utf8).write(to: invalid)
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("NewToYou-missing-\(UUID().uuidString).epub")
        defer { try? FileManager.default.removeItem(at: invalid) }

        for file in [invalid, missing] {
            let context = try makeContext()
            var recorded: [UInt64] = []
            do {
                _ = try await NewToYouLibrary.save(card, in: context, downloadEPUB: { _ in file }) {
                    recorded.append($0)
                }
                Issue.record("install failure must throw")
            } catch {
                // The card stays. `.saved` is not recorded.
            }
            #expect(recorded.isEmpty)
            #expect(try context.fetch(FetchDescriptor<SavedWork>()).isEmpty)
        }
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
