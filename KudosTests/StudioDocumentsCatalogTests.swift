import Foundation
import Testing
@testable import Kudos

private func makeAO3Work(
    id: Int,
    title: String,
    words: Int? = 2000,
    chapters: String = "1/1",
    isComplete: Bool? = true,
    dateUpdated: String = "2026-10-20",
    fandoms: [String] = ["Original Work"],
    summary: String = "",
    giftRecipients: [String] = []
) -> AO3WorkSummary {
    AO3WorkSummary(
        id: id,
        title: title,
        authors: ["saltwindow"],
        fandoms: fandoms,
        rating: "General Audiences",
        warnings: ["No Archive Warnings Apply"],
        categories: ["Gen"],
        isComplete: isComplete,
        dateUpdated: dateUpdated,
        tags: [],
        summary: summary,
        language: "English",
        words: words,
        chapters: chapters,
        comments: nil,
        kudos: nil,
        hits: nil,
        seriesTitle: nil,
        seriesURL: nil,
        seriesPosition: nil,
        giftRecipients: giftRecipients
    )
}

private func makeLocalWork(
    id: UUID = UUID(),
    title: String,
    ao3WorkID: Int? = nil,
    updatedAt: Date = Date(timeIntervalSince1970: 1_760_000_000),
    chapters: [WritingChapter] = [],
    storyNotes: [WritingStoryNote] = [],
    excerpts: [UUID: String] = [:]
) -> StudioLocalWorkSnapshot {
    let work = WritingWork(
        id: id,
        title: title,
        ao3WorkID: ao3WorkID,
        createdAt: updatedAt,
        updatedAt: updatedAt,
        updatedBy: "test-device",
        chapterOrder: chapters.map(\.id)
    )
    return StudioLocalWorkSnapshot(
        work: work,
        chapters: chapters,
        storyNotes: storyNotes,
        chapterExcerpts: excerpts
    )
}

private func makeChapter(
    id: UUID = UUID(),
    title: String,
    status: WritingChapterStatus = .local,
    wordCount: Int = 500,
    ao3ChapterID: Int? = nil,
    updatedAt: Date = Date(timeIntervalSince1970: 1_760_000_000)
) -> WritingChapter {
    WritingChapter(
        id: id,
        title: title,
        summary: "",
        notesBefore: "",
        notesAfter: "",
        ao3ChapterID: ao3ChapterID,
        status: status,
        wordCount: wordCount,
        bodySavedAt: updatedAt,
        updatedAt: updatedAt,
        updatedBy: "test-device"
    )
}

struct StudioDocumentsCatalogTests {
    @Test func mergesLocalAndAO3WorksIntoManuscriptsAndLooseDrafts() {
        let baseDate = Date(timeIntervalSince1970: 1_761_000_000)

        let linkedLocal = makeLocalWork(
            title: "What the Tide Keeps",
            ao3WorkID: 101,
            updatedAt: baseDate,
            chapters: [
                makeChapter(title: "Low Water", status: .posted, wordCount: 2980, ao3ChapterID: 1),
                makeChapter(title: "Slack Water", status: .ao3Draft, wordCount: 1240, ao3ChapterID: 4)
            ],
            storyNotes: [
                WritingStoryNote(
                    id: UUID(),
                    kind: .character,
                    name: "Ines",
                    detail: "Boatbuilder",
                    pinned: true,
                    updatedAt: baseDate,
                    updatedBy: "test-device"
                )
            ]
        )

        let localMultiChapter = makeLocalWork(
            title: "Harbour Notes",
            ao3WorkID: nil,
            updatedAt: baseDate.addingTimeInterval(-100),
            chapters: [
                makeChapter(title: "Part One", status: .local, wordCount: 800),
                makeChapter(title: "Part Two", status: .local, wordCount: 900)
            ]
        )

        let localSingleWithNote = makeLocalWork(
            title: "Sea Glass",
            ao3WorkID: nil,
            updatedAt: baseDate.addingTimeInterval(-200),
            chapters: [makeChapter(title: "Opening", status: .local, wordCount: 400)],
            storyNotes: [
                WritingStoryNote(
                    id: UUID(),
                    kind: .place,
                    name: "Pier",
                    detail: "North side",
                    pinned: false,
                    updatedAt: baseDate,
                    updatedBy: "test-device"
                )
            ]
        )

        let looseLocal = makeLocalWork(
            title: "Untitled lighthouse piece",
            ao3WorkID: nil,
            updatedAt: baseDate.addingTimeInterval(-300),
            chapters: [makeChapter(title: "", status: .local, wordCount: 640)]
        )

        let postedMatched = makeAO3Work(
            id: 101,
            title: "What the Tide Keeps",
            words: 9800,
            chapters: "3/8",
            isComplete: false,
            dateUpdated: "2026-10-20"
        )
        let postedRemoteOnly = makeAO3Work(
            id: 202,
            title: "Keeper of the Northern Light",
            words: 22_410,
            chapters: "7/7",
            isComplete: true,
            dateUpdated: "2026-10-15",
            giftRecipients: ["quietharbor"]
        )
        let ao3DraftOnly = makeAO3Work(
            id: 303,
            title: "Small Weathers II",
            words: 3980,
            chapters: "1/1",
            isComplete: false,
            dateUpdated: "2026-10-02"
        )

        let snapshot = StudioDocumentsCatalog.build(
            localWorks: [linkedLocal, localMultiChapter, localSingleWithNote, looseLocal],
            ao3PostedWorks: [postedMatched, postedRemoteOnly],
            ao3DraftWorks: [ao3DraftOnly],
            ao3DraftDaysLeft: [303: 12],
            deviceName: "iPhone"
        )

        // Linked work 101 appears once, not twice.
        #expect(snapshot.allWorks.count == 6)
        #expect(snapshot.manuscripts.count == 5)
        #expect(snapshot.looseDrafts.count == 1)
        #expect(snapshot.looseDrafts.first?.title == "Untitled lighthouse piece")

        let tide = snapshot.manuscripts.first { $0.ao3WorkID == 101 }
        #expect(tide != nil)
        let tideState = tide?.manuscriptStateLine(deviceName: "iPhone")
        #expect(tideState == "In progress · 3 of 8 posted · 9,800 words on AO3")

        let keeper = snapshot.manuscripts.first { $0.ao3WorkID == 202 }
        let keeperState = keeper?.manuscriptStateLine(deviceName: "iPhone")
        #expect(keeperState == "Complete · 7 chapters · 22,410 words")

        let draft = snapshot.manuscripts.first { $0.ao3WorkID == 303 }
        let draftState = draft?.manuscriptStateLine(deviceName: "iPhone")
        #expect(draftState == "AO3 draft · 12 days left · 3,980 words")

        #expect(snapshot.recent.count == StudioDocumentsCatalog.maxRecentCount)
        #expect(snapshot.chipCounts[.all] == 6)
        #expect(snapshot.chipCounts[.posted] == 2)
        #expect(snapshot.chipCounts[.gifts] == 1)
        #expect(snapshot.chipCounts[.drafts] == 5)
    }

    @Test func filterChipsAndSearchMatchExpectedWorks() {
        let giftWork = makeAO3Work(
            id: 10,
            title: "Austen Exchange Gift",
            fandoms: ["Persuasion"],
            giftRecipients: ["quietharbor"]
        )
        let localOnly = makeLocalWork(
            title: "Ferry Timetable",
            chapters: [makeChapter(title: "Dawn", status: .local, wordCount: 300)]
        )
        let snapshot = StudioDocumentsCatalog.build(
            localWorks: [localOnly],
            ao3PostedWorks: [giftWork],
            ao3DraftWorks: []
        )

        let gifts = StudioDocumentsCatalog.filter(snapshot.allWorks, chip: .gifts, query: "")
        #expect(gifts.map(\.title) == ["Austen Exchange Gift"])

        let posted = StudioDocumentsCatalog.filter(snapshot.allWorks, chip: .posted, query: "")
        #expect(posted.map(\.title) == ["Austen Exchange Gift"])

        let drafts = StudioDocumentsCatalog.filter(snapshot.allWorks, chip: .drafts, query: "")
        #expect(drafts.map(\.title) == ["Ferry Timetable"])

        let searchedByChapter = StudioDocumentsCatalog.filter(snapshot.allWorks, chip: .all, query: "dawn")
        #expect(searchedByChapter.map(\.title) == ["Ferry Timetable"])

        let searchedByRecipient = StudioDocumentsCatalog.filter(snapshot.allWorks, chip: .all, query: "quietharbor")
        #expect(searchedByRecipient.map(\.title) == ["Austen Exchange Gift"])
    }

    @Test func folderBadgesReflectPostedAO3DraftAndOnDeviceStates() {
        let postedOnly = makeAO3Work(id: 1, title: "Posted Only")
        let draftOnly = makeAO3Work(id: 2, title: "Draft Only")
        let localOnly = makeLocalWork(
            title: "Local Only",
            chapters: [makeChapter(title: "Ch 1", status: .local, wordCount: 250)]
        )
        let postedPlusDraftLocal = makeLocalWork(
            title: "Posted Plus Draft",
            ao3WorkID: 3,
            chapters: [
                makeChapter(title: "Ch 1", status: .posted, wordCount: 1000, ao3ChapterID: 11),
                makeChapter(title: "Ch 2", status: .ao3Draft, wordCount: 800, ao3ChapterID: 12)
            ]
        )
        let postedPlusLocalChapter = makeLocalWork(
            title: "Posted Plus Local",
            ao3WorkID: 4,
            chapters: [
                makeChapter(title: "Ch 1", status: .posted, wordCount: 1000, ao3ChapterID: 21),
                makeChapter(title: "Ch 2", status: .local, wordCount: 600)
            ]
        )
        let postedMirroredOnly = makeLocalWork(
            title: "Posted Mirror",
            ao3WorkID: 5,
            chapters: [
                makeChapter(title: "Ch 1", status: .posted, wordCount: 1000, ao3ChapterID: 31)
            ]
        )

        let snapshot = StudioDocumentsCatalog.build(
            localWorks: [localOnly, postedPlusDraftLocal, postedPlusLocalChapter, postedMirroredOnly],
            ao3PostedWorks: [
                postedOnly,
                makeAO3Work(id: 3, title: "Posted Plus Draft"),
                makeAO3Work(id: 4, title: "Posted Plus Local"),
                makeAO3Work(id: 5, title: "Posted Mirror")
            ],
            ao3DraftWorks: [draftOnly]
        )

        func badges(named title: String) -> [StudioFolderBadge] {
            snapshot.allWorks.first { $0.title == title }?.folderBadges ?? []
        }

        #expect(badges(named: "Posted Only") == [.posted])
        #expect(badges(named: "Draft Only") == [.ao3Draft])
        #expect(badges(named: "Local Only") == [.onDevice])
        #expect(badges(named: "Posted Plus Draft") == [.posted, .ao3Draft])
        #expect(badges(named: "Posted Plus Local") == [.posted, .onDevice])
        #expect(badges(named: "Posted Mirror") == [.posted])
    }

    @Test func sortFoldersOrdersByEditedTitleAndWords() {
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = Date(timeIntervalSince1970: 1_760_000_000)

        let zeta = makeLocalWork(
            title: "Zeta",
            updatedAt: newer,
            chapters: [makeChapter(title: "One", status: .local, wordCount: 100, updatedAt: newer)]
        )
        let alpha = makeLocalWork(
            title: "Alpha",
            updatedAt: older,
            chapters: [makeChapter(title: "One", status: .local, wordCount: 5000, updatedAt: older)]
        )

        let snapshot = StudioDocumentsCatalog.build(
            localWorks: [alpha, zeta],
            ao3PostedWorks: [],
            ao3DraftWorks: []
        )

        let byEdited = StudioDocumentsCatalog.sortFolders(snapshot.allWorks, by: .edited).map(\.title)
        let byTitle = StudioDocumentsCatalog.sortFolders(snapshot.allWorks, by: .title).map(\.title)
        let byWords = StudioDocumentsCatalog.sortFolders(snapshot.allWorks, by: .words).map(\.title)

        #expect(byEdited == ["Zeta", "Alpha"])
        #expect(byTitle == ["Alpha", "Zeta"])
        #expect(byWords == ["Alpha", "Zeta"])
    }

    @Test func renamedLinkedWorkStaysOneRowUnderTheLocalTitle() {
        let localID = UUID()
        let local = makeLocalWork(
            id: localID,
            title: "Harbour Name",
            ao3WorkID: 101,
            chapters: [makeChapter(title: "One")]
        )
        let snapshot = StudioDocumentsCatalog.build(
            localWorks: [local],
            ao3PostedWorks: [makeAO3Work(id: 101, title: "AO3 Name")],
            ao3DraftWorks: []
        )
        #expect(snapshot.allWorks.count == 1)
        let row = snapshot.allWorks[0]
        #expect(row.title == "Harbour Name")
        #expect(row.id == "local:\(localID.uuidString)")
        #expect(row.ao3PostedWork?.id == 101)
    }

    @Test func linkedLocalMissingFromAO3ListsStaysOneRow() {
        let local = makeLocalWork(
            title: "Kept",
            ao3WorkID: 55,
            chapters: [makeChapter(title: "One", status: .posted)]
        )
        let snapshot = StudioDocumentsCatalog.build(
            localWorks: [local],
            ao3PostedWorks: [],
            ao3DraftWorks: []
        )
        #expect(snapshot.allWorks.count == 1)
        let row = snapshot.allWorks[0]
        #expect(row.localWork?.id == local.work.id)
        #expect(row.ao3PostedWork == nil)
        #expect(row.ao3DraftWork == nil)
    }

    @Test func twoLocalsSharingAnAO3IDStayDistinctRows() {
        let first = makeLocalWork(
            title: "First Copy",
            ao3WorkID: 7,
            chapters: [makeChapter(title: "A")]
        )
        let second = makeLocalWork(
            title: "Second Copy",
            ao3WorkID: 7,
            chapters: [makeChapter(title: "B")]
        )
        let snapshot = StudioDocumentsCatalog.build(
            localWorks: [first, second],
            ao3PostedWorks: [makeAO3Work(id: 7, title: "On AO3")],
            ao3DraftWorks: []
        )
        let ids = Set(snapshot.allWorks.map(\.id))
        let postedIDs = snapshot.allWorks.compactMap { $0.ao3PostedWork?.id }
        #expect(snapshot.allWorks.count == 2)
        #expect(ids.count == 2)
        #expect(postedIDs == [7, 7])
    }
}

struct StudioAO3FreshnessTests {
    @Test func windowMatchesTheWritingTabRule() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let fresh = StudioAO3Freshness.isStale(now.addingTimeInterval(-14 * 60), now: now)
        let stale = StudioAO3Freshness.isStale(now.addingTimeInterval(-15 * 60), now: now)
        let backwards = StudioAO3Freshness.isStale(now.addingTimeInterval(60), now: now)
        #expect(StudioAO3Freshness.freshFor == 15 * 60)
        #expect(StudioAO3Freshness.isStale(nil, now: now))
        #expect(!fresh)
        #expect(stale)
        #expect(backwards)
    }
}

@MainActor
struct StudioAO3LoadCacheTests {
    @Test func anotherSessionIsHiddenAndAFailedStoreKeepsWorks() {
        let cache = StudioAO3LoadCache()
        let work = makeAO3Work(id: 9, title: "Kept")
        let loadedAt = Date(timeIntervalSince1970: 1_700_000_000)
        cache.storeDocuments(
            session: 1,
            username: "ada",
            posted: [work],
            drafts: nil,
            draftsLoaded: true,
            error: nil,
            loadedAt: loadedAt
        )
        let otherSession = cache.documents(session: 2, username: "ada")
        let otherUser = cache.documents(session: 1, username: "bea")
        #expect(otherSession == nil)
        #expect(otherUser == nil)
        let readable = cache.documents(session: 1, username: "ADA")
        let ids = readable?.posted.map(\.id)
        #expect(ids == [9])
        let stillStale = StudioAO3Freshness.isStale(readable?.loadedAt, now: loadedAt.addingTimeInterval(16 * 60))
        #expect(stillStale)

        cache.storeDocuments(
            session: 1,
            username: "ada",
            posted: nil,
            drafts: nil,
            draftsLoaded: false,
            error: "offline",
            loadedAt: loadedAt.addingTimeInterval(20 * 60)
        )
        let afterFailure = cache.documents(session: 1, username: "ada")
        let keptIDs = afterFailure?.posted.map(\.id)
        #expect(keptIDs == [9])
        #expect(afterFailure?.error == "offline")

        let chapter = AO3ChapterRef(id: 3, position: 1, title: "One", dateText: "2026-01-01")
        cache.storeChapters(workID: 9, session: 1, chapters: [chapter], error: nil, loadedAt: loadedAt)
        cache.storeChapters(workID: 9, session: 1, chapters: nil, error: nil, loadedAt: loadedAt)
        let keptChapters = cache.chapters(workID: 9, session: 1)?.chapters.map(\.id)
        let otherSessionChapters = cache.chapters(workID: 9, session: 2)
        #expect(keptChapters == [3])
        #expect(otherSessionChapters == nil)
    }
}
