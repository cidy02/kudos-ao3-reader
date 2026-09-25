import Foundation
import Testing
@testable import Kudos

/// 1o's pure pieces: which pill a row survives, which group it falls in,
/// the sync line, the download footnote, and the watermark key that keeps
/// this list's "last looked" off the subscriptions clock. Nothing here
/// signs in or posts.
struct AO3MarkedForLaterScreenTests {
    private struct Row: Equatable {
        var name: String
        var updated: Bool
        var downloaded: Bool
    }

    private let rows = [
        Row(name: "updated-downloaded", updated: true, downloaded: true),
        Row(name: "downloaded", updated: false, downloaded: true),
        Row(name: "plain", updated: false, downloaded: false),
        Row(name: "updated", updated: true, downloaded: false)
    ]

    private func sections(
        _ rows: [Row],
        filter: AO3MarkedForLaterFilter
    ) -> [AO3MarkedForLaterSection<Row>] {
        AO3MarkedForLaterGrouping.sections(
            rows,
            filter: filter,
            isUpdated: \.updated,
            isDownloaded: \.downloaded
        )
    }

    private func summary(id: Int, chapters: String) -> AO3WorkSummary {
        AO3WorkSummary(
            id: id,
            title: "Work \(id)",
            authors: ["someone"],
            fandoms: [],
            rating: "",
            warnings: [],
            categories: [],
            dateUpdated: "",
            tags: [],
            summary: "",
            language: "",
            chapters: chapters
        )
    }

    /// All is the artboard's two runs: updated rows first, in page order,
    /// then everyone else. An empty run is omitted rather than drawn as 0.
    @Test func allSplitsUpdatedAheadOfEverythingElse() {
        let split = sections(rows, filter: .all)

        #expect(split.map(\.group) == [.updatedSinceYouLooked, .everythingElse])
        #expect(split.map(\.showsHeader) == [true, true])
        #expect(split.map(\.layout) == [.covers, .ledger])
        #expect(split[0].items.map(\.name) == ["updated-downloaded", "updated"])
        #expect(split[1].items.map(\.name) == ["downloaded", "plain"])
    }

    @Test func allDropsAnEmptyRun() {
        let onlyUpdated = rows.filter(\.updated)
        let split = sections(onlyUpdated, filter: .all)

        #expect(split.map(\.group) == [.updatedSinceYouLooked])
        #expect(split[0].layout == .covers)
    }

    /// A narrowed pill is one list. Updated stays covers. Downloaded is
    /// ledger, in page order, including a row that is also updated — that
    /// row would have been a cover on All, and the size line needs a ledger.
    @Test func narrowedPillsAreOneList() {
        let updated = sections(rows, filter: .updated)
        #expect(updated.count == 1)
        #expect(updated[0].showsHeader == false)
        #expect(updated[0].layout == .covers)
        #expect(updated[0].items.map(\.name) == ["updated-downloaded", "updated"])

        let downloaded = sections(rows, filter: .downloaded)
        #expect(downloaded.count == 1)
        #expect(downloaded[0].showsHeader == false)
        #expect(downloaded[0].layout == .ledger)
        #expect(downloaded[0].items.map(\.name) == ["updated-downloaded", "downloaded"])
    }

    @Test func updatedMeansChaptersGrewSinceTheWatermark() {
        let grown = summary(id: 4, chapters: "14/20")
        let seen = [4: SubscriptionWatermark(postedChapterCount: 12, seenAt: Date())]

        #expect(AO3MarkedForLaterClassification.isUpdated(work: grown, watermarks: seen))
        // First sight is not "updated". Otherwise the cover group is the whole page.
        #expect(!AO3MarkedForLaterClassification.isUpdated(work: grown, watermarks: [:]))
        #expect(!AO3MarkedForLaterClassification.isUpdated(
            work: summary(id: 4, chapters: "10/20"),
            watermarks: seen
        ))
        #expect(!AO3MarkedForLaterClassification.isUpdated(work: grown, watermarks: [
            4: SubscriptionWatermark(postedChapterCount: 14, seenAt: Date())
        ]))
    }

    @Test func downloadedIsTheLocalEPUBFlag() {
        #expect(AO3MarkedForLaterClassification.isDownloaded(hasEPUB: true))
        #expect(!AO3MarkedForLaterClassification.isDownloaded(hasEPUB: false))
        #expect(!AO3MarkedForLaterClassification.isDownloaded(hasEPUB: nil))
    }

    @Test func syncLineIsCountThenRelativeStamp() {
        let now = Date(timeIntervalSince1970: 1_000_000)

        #expect(AO3MarkedForLaterCopy.subtitle(workCount: 12, syncedAt: nil, now: now) == "12 works")
        #expect(
            AO3MarkedForLaterCopy.subtitle(
                workCount: 1,
                syncedAt: now.addingTimeInterval(-120),
                now: now
            ) == "1 work · synced 2 min ago"
        )
        #expect(
            AO3MarkedForLaterCopy.subtitle(
                workCount: 12,
                syncedAt: now.addingTimeInterval(-120),
                now: now
            ) == "12 works · synced 2 min ago"
        )
        #expect(
            AO3MarkedForLaterCopy.relativeSyncPhrase(
                from: now.addingTimeInterval(-30), to: now
            ) == "just now"
        )
        #expect(
            AO3MarkedForLaterCopy.relativeSyncPhrase(
                from: now.addingTimeInterval(-60), to: now
            ) == "1 min ago"
        )
        #expect(
            AO3MarkedForLaterCopy.relativeSyncPhrase(
                from: now.addingTimeInterval(-3_600), to: now
            ) == "1 hr ago"
        )
        #expect(
            AO3MarkedForLaterCopy.relativeSyncPhrase(
                from: now.addingTimeInterval(-7_200), to: now
            ) == "2 hr ago"
        )
        #expect(
            AO3MarkedForLaterCopy.relativeSyncPhrase(
                from: now.addingTimeInterval(-86_400), to: now
            ) == "1 day ago"
        )
        #expect(
            AO3MarkedForLaterCopy.relativeSyncPhrase(
                from: now.addingTimeInterval(-172_800), to: now
            ) == "2 days ago"
        )
        // A clock skew into the future does not read as a negative sync.
        #expect(
            AO3MarkedForLaterCopy.relativeSyncPhrase(
                from: now.addingTimeInterval(30), to: now
            ) == "just now"
        )
    }

    @Test func footerUsesTheRealPageNumbers() {
        #expect(
            AO3MarkedForLaterCopy.footer(currentPage: 2, totalPages: 4)
                == "Marked for Later lives on AO3. "
                + "Pagination follows the ledger: 2 of 4 pages."
        )
        #expect(
            AO3MarkedForLaterCopy.footer(currentPage: 1, totalPages: 1)
                == "Marked for Later lives on AO3. "
                + "Pagination follows the ledger: 1 of 1 page."
        )
    }

    /// The screen has no unmark and the app has no unmark write, so the footer
    /// must not promise one (1o.3).
    @Test func footerPromisesNoUnmark() {
        for (page, pages) in [(1, 1), (2, 4)] {
            #expect(!AO3MarkedForLaterCopy.footer(currentPage: page, totalPages: pages)
                .lowercased().contains("unmark"))
        }
    }

    /// Page 1 of 9 is not the whole list; the tally says which page it counts.
    @Test func subtitleNamesThePageWhenThereAreSeveral() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(
            AO3MarkedForLaterCopy.subtitle(
                workCount: 20, syncedAt: now.addingTimeInterval(-120), now: now,
                currentPage: 1, totalPages: 9
            ) == "20 works · synced 2 min ago · page 1 of 9"
        )
        #expect(
            AO3MarkedForLaterCopy.subtitle(
                workCount: 20, syncedAt: nil, now: now, currentPage: 1, totalPages: 1
            ) == "20 works"
        )
    }

    @Test func downloadLineRequiresARealSize() {
        #expect(
            AO3MarkedForLaterDownloadLine.text(hasEPUB: true, byteLabel: "1.4 MB")
                == "Downloaded · 1.4 MB"
        )
        #expect(AO3MarkedForLaterDownloadLine.text(hasEPUB: false, byteLabel: "1.4 MB") == nil)
        #expect(AO3MarkedForLaterDownloadLine.text(hasEPUB: true, byteLabel: nil) == nil)
        #expect(AO3MarkedForLaterDownloadLine.text(hasEPUB: true, byteLabel: "") == nil)
    }

    /// The footnote does not format bytes itself. It repeats the label the
    /// work-detail screen and the storage screen already share.
    @Test func downloadLineUsesTheSharedFileSizeLabel() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AO3MarkedForLaterScreenTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("sample.epub")
        let payload = Data(count: 1_400_000)
        try payload.write(to: file)

        let label = try #require(WorkDetailPresentation.fileSizeLabel(forFileAt: file))
        #expect(label == LocalStorageFootprint.formatted(bytes: 1_400_000))
        #expect(AO3MarkedForLaterDownloadLine.text(hasEPUB: true, byteLabel: label) == "Downloaded · \(label)")
    }

    /// Looking at Marked for Later must not write the subscriptions key, and
    /// the other way around. Same work id, two clocks.
    @Test func watermarkNamespacesDoNotShareAKey() throws {
        let suite = "AO3MarkedForLaterScreenTests-\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: suite))
        defer { store.removePersistentDomain(forName: suite) }

        let later = [
            7: SubscriptionWatermark(postedChapterCount: 3, seenAt: Date(timeIntervalSince1970: 10))
        ]
        let subscriptions = [
            7: SubscriptionWatermark(postedChapterCount: 9, seenAt: Date(timeIntervalSince1970: 20))
        ]
        SubscriptionWatermarks.save(later, to: store, namespace: .markedForLater)
        SubscriptionWatermarks.save(subscriptions, to: store, namespace: .subscriptions)

        #expect(SubscriptionWatermarks.load(from: store, namespace: .markedForLater)[7]?.postedChapterCount == 3)
        #expect(SubscriptionWatermarks.load(from: store, namespace: .subscriptions)[7]?.postedChapterCount == 9)

        let work = summary(id: 7, chapters: "5/8")
        #expect(AO3MarkedForLaterClassification.isUpdated(
            work: work,
            watermarks: SubscriptionWatermarks.load(from: store, namespace: .markedForLater)
        ))
        #expect(!AO3MarkedForLaterClassification.isUpdated(
            work: work,
            watermarks: SubscriptionWatermarks.load(from: store, namespace: .subscriptions)
        ))
    }
}
