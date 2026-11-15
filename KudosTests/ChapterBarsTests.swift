import Foundation
import Testing
@testable import Kudos

/// T-477: bar widths (I-15), read / current / posted / unposted, and the
/// chapter-length cache dropping a record when the file changes.
struct ChapterBarsTests {
    @Test func oneSevenAndFortyBarsKeepTheirWidthUntilTheLineIsFull() {
        let one = ChapterBarGeometry.metrics(count: 1, availableWidth: 400, nominalWidth: 6, gap: 2)
        #expect(one.width == 6)
        #expect(one.radius == 3)

        let seven = ChapterBarGeometry.metrics(count: 7, availableWidth: 400, nominalWidth: 6, gap: 2)
        #expect(seven.width == 6)
        #expect(seven.gap == 2)
        #expect(seven.radius == 3)

        // 40 × 6 + 39 × 2 = 318, which still fits in 400.
        let forty = ChapterBarGeometry.metrics(count: 40, availableWidth: 400, nominalWidth: 6, gap: 2)
        #expect(forty.width == 6)
        #expect(forty.gap == 2)
        #expect(forty.radius == min(3, forty.width / 2))

        let cramped = ChapterBarGeometry.metrics(count: 40, availableWidth: 120, nominalWidth: 6, gap: 2)
        #expect(cramped.width < 6)
        #expect(cramped.gap == 2)
        #expect(cramped.radius == min(3, cramped.width / 2))

        let card = ChapterBarGeometry.metrics(count: 7, availableWidth: 800, nominalWidth: 14, gap: 4)
        #expect(card.width == 14)
        #expect(card.gap == 4)
        #expect(card.radius == 3)
    }

    @Test func barsMarkReadCurrentUnreadAndUnposted() {
        let oneRead = ChapterBarGeometry.items(planned: nil, posted: 1, progress: 1, weights: nil)
        #expect(oneRead == [ChapterBarItem(role: .read, weight: 1)])

        let oneCurrent = ChapterBarGeometry.items(planned: nil, posted: 1, progress: 0.4, weights: nil)
        #expect(oneCurrent == [ChapterBarItem(role: .current(fill: 0.4), weight: 1)])

        let oneUnread = ChapterBarGeometry.items(planned: nil, posted: 1, progress: nil, weights: nil)
        #expect(oneUnread == [ChapterBarItem(role: .postedUnread, weight: 1)])

        let seven = ChapterBarGeometry.items(planned: 7, posted: 5, progress: 0.5, weights: nil)
        #expect(seven.map(\.role) == [
            .read, .read, .current(fill: 0.5), .postedUnread, .postedUnread, .notPosted, .notPosted
        ])

        let forty = ChapterBarGeometry.items(planned: 40, posted: 10, progress: nil, weights: nil)
        #expect(forty.count == 40)
        #expect(forty.prefix(10).allSatisfy { $0.role == .postedUnread })
        #expect(forty.dropFirst(10).allSatisfy { $0.role == .notPosted })
    }

    @Test func newChaptersAreMarkedAndLengthsSetTheHeights() {
        let fresh = ChapterBarGeometry.items(
            planned: 7, posted: 5, progress: 0.5, weights: nil, newChapterCount: 2
        )
        #expect(fresh[3].role == .newChapter)
        #expect(fresh[4].role == .newChapter)
        #expect(fresh[0].role == .read)
        #expect(fresh[5].role == .notPosted)

        let sized = ChapterBarGeometry.items(
            planned: 3, posted: 2, progress: nil, weights: [1, 3]
        )
        #expect(sized.map(\.weight) == [1, 3, 2])
        #expect(sized.map(\.role) == [.postedUnread, .postedUnread, .notPosted])
    }

    @Test func progressLabelNamesTheChapterAndThePercent() {
        #expect(ChapterBarGeometry.progressLabel(chapters: "12/20", progress: 0.58, isFinished: false) == "Ch 7 · 58%")
        #expect(ChapterBarGeometry.progressLabel(chapters: "12/20", progress: 0, isFinished: false) == nil)
        #expect(ChapterBarGeometry.progressLabel(chapters: "12/20", progress: nil, isFinished: true) == "Ch 12 · 100%")
    }

    @Test func aChangedFileDropsTheCachedChapterLengths() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("chapter-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("work.epub")
        try Data("not an epub".utf8).write(to: file)
        let id = UUID()
        ChapterLengthCache.store(workID: id, fileURL: file, weights: [4, 9], directory: directory)
        #expect(ChapterLengthCache.weights(workID: id, fileURL: file, directory: directory) == [4, 9])

        try Data("not an epub anymore".utf8).write(to: file)
        #expect(ChapterLengthCache.weights(workID: id, fileURL: file, directory: directory) == nil)
    }

    @Test func measuredChaptersFollowTheEPUBAndANewFileMeasuresAgain() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("chapter-measure-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("book.epub")
        let short = "<p>Hi.</p>"
        let long = "<p>\(String(repeating: "word ", count: 800))</p>"
        try EPUBBuilder.archive(
            metadata: .init(title: "Measured", author: "A", identifier: "measured"),
            chapters: [
                .init(title: "Chapter 1", bodyXHTML: short),
                .init(title: "Chapter 2", bodyXHTML: long)
            ]
        ).write(to: file)

        let id = UUID()
        let weights = try #require(ChapterLengthCache.weights(workID: id, fileURL: file, directory: directory))
        #expect(weights.count == 2)
        #expect(weights[1] > weights[0])

        let again = ChapterLengthCache.weights(workID: id, fileURL: file, directory: directory)
        #expect(again == weights)

        try Data("replaced".utf8).write(to: file)
        #expect(ChapterLengthCache.weights(workID: id, fileURL: file, directory: directory) == nil)
    }

    /// Word counts draw the bars; positions (what reading progress is measured in) still
    /// decide which bar is read, current or unread.
    @Test func wordCountsSetBarHeightsWhilePositionsPlaceTheReader() {
        let items = ChapterBarGeometry.items(
            planned: 4, posted: 3, progress: 0.5, weights: [1, 1, 2], heights: [100, 300, 50]
        )
        #expect(items.map(\.weight) == [100, 300, 50, 150])
        #expect(items.map(\.role) == [.read, .read, .postedUnread, .notPosted])

        let noWords = ChapterBarGeometry.items(planned: 2, posted: 2, progress: nil, weights: [2, 6])
        #expect(noWords.map(\.weight) == [2, 6])
    }

    /// The "Ch N" label counts the same measured chapters as the bars, not equal ones.
    @Test func progressLabelUsesTheMeasuredChapters() {
        #expect(ChapterBarGeometry.progressLabel(chapters: "3/3", progress: 0.5, isFinished: false) == "Ch 2 · 50%")
        #expect(
            ChapterBarGeometry.progressLabel(chapters: "3/3", progress: 0.5, isFinished: false, weights: [1, 1, 2])
                == "Ch 3 · 50%"
        )
        #expect(WorkCoverMetadata.reading(chapters: "3/3", progress: 0.5, weights: [1, 1, 2]) == "Ch 3 of 3 · 50%")
    }

    @Test func wordCountSkipsTheHeadAndTags() {
        let xhtml = "<html><head><title>Ch 1: A Long Title</title></head>"
            + "<body><h2>One</h2><p>two <em>three</em></p></body></html>"
        #expect(EPUBDocument.wordCount(ofXHTML: xhtml) == 3)
    }

    @Test func measuredChaptersCarryWordCountsAndOldRecordsMeasureAgain() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("chapter-words-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("book.epub")
        try EPUBBuilder.archive(
            metadata: .init(title: "Words", author: "A", identifier: "words"),
            chapters: [
                .init(title: "Chapter 1", bodyXHTML: "<p>Hi.</p>"),
                .init(title: "Chapter 2", bodyXHTML: "<p>\(String(repeating: "word ", count: 800))</p>")
            ]
        ).write(to: file)

        // A record from before word counts (positions only) measures again for lengths.
        let id = UUID()
        ChapterLengthCache.store(workID: id, fileURL: file, weights: [1, 1], directory: directory)
        #expect(ChapterLengthCache.weights(workID: id, fileURL: file, directory: directory) == [1, 1])
        let lengths = try #require(ChapterLengthCache.lengths(workID: id, fileURL: file, directory: directory))
        #expect(lengths.words.count == 2)
        #expect(lengths.words[1] - lengths.words[0] == 799)
        #expect(ChapterLengthCache.lengths(workID: id, fileURL: file, directory: directory) == lengths)
    }

    @Test func defaultTwelveOfTwentyCardIsUnchanged() {
        let layout = ChapterBarGeometry.layout(
            planned: 20,
            posted: 12,
            read: 6,
            chapterProgress: 0.22,
            scale: .card,
            availableWidth: 326
        )
        #expect(layout.bars.count == 20)
        #expect(layout.bars.prefix(6).allSatisfy { $0.role == .read })
        #expect(layout.bars[6].role == .current(fill: 0.22))
        #expect(layout.bars[7 ..< 12].allSatisfy { $0.role == .postedUnread })
        #expect(layout.bars.dropFirst(12).allSatisfy { $0.role == .notPosted })
        #expect(layout.trackFill == nil)
        #expect(!layout.showsOpenTotalDots)
        #expect(layout.chaptersPerBar == 1)
        #expect(layout.groupNote == nil)
        #expect(layout.metrics.width == CGFloat(326 - 19 * 4) / 20) // 12.5: unrounded, as before T-514

        let model = ResumeCardModel(
            title: "The Cartographer's Daughter",
            authors: ["inkwell_moth"],
            authorIdentities: [],
            fandoms: ["Original Work"],
            rating: "T",
            categories: ["F/M"],
            warnings: [],
            completion: .inProgress,
            words: 84_210,
            kudos: 3_104,
            chapters: "12/20",
            progress: 0.58,
            chapterProgress: 0.22,
            chapterName: "Ch 7, The Salt Road",
            published: "Mar 3",
            updated: "Oct 21",
            newChapterCount: 0
        )
        let cardLayout = model.chapterBarLayout(lengths: nil)
        #expect(cardLayout.bars.count == 20)
        #expect(cardLayout.bars.prefix(6).allSatisfy { $0.role == .read })
        #expect(cardLayout.bars.dropFirst(12).allSatisfy { $0.role == .notPosted })
        #expect(!cardLayout.showsOpenTotalDots)
        #expect(cardLayout.trackFill == nil)
        #expect(model.postedLabel == "12 of 20 posted")
        #expect(model.postedShortLabel == "12 of 20")
        #expect(model.detailPrimaryTitle(fallback: "Read") == "Resume Chapter 7")
    }

    @Test func unknownTotalDrawsPostedBarsAndThreeFadingDotsWithoutDashedBars() {
        let layout = ChapterBarModel.layout(
            chapters: "12/?",
            read: 6,
            chapterProgress: 0.22,
            progress: nil,
            weights: nil,
            scale: .card
        )
        #expect(layout.bars.count == 12)
        #expect(!layout.bars.contains { $0.role == .notPosted })
        #expect(layout.bars.prefix(6).allSatisfy { $0.role == .read })
        #expect(layout.bars[6].role == .current(fill: 0.22))
        #expect(layout.bars.dropFirst(7).allSatisfy { $0.role == .postedUnread })
        #expect(layout.showsOpenTotalDots)
        #expect(layout.trackFill == nil)
        #expect(layout.accessibilityLabel == "Chapters: 6 read, 12 posted, total not set by the author")
    }

    @Test func oneChapterWorkDrawsATrackWithNoBarsAndButtonReadsResume() {
        let card = ChapterBarModel.layout(
            chapters: "1/1",
            progress: 0.38,
            weights: nil,
            scale: .card
        )
        #expect(card.bars.isEmpty)
        #expect(card.trackFill == 0.38)
        #expect(!card.showsOpenTotalDots)
        #expect(card.accessibilityLabel == "One chapter, 38 percent read")

        let row = ChapterBarModel.layout(
            chapters: "1/1",
            progress: nil,
            weights: nil,
            newChapterCount: 1,
            scale: .row
        )
        #expect(row.bars.isEmpty)
        #expect(row.trackFill == 1)
        #expect(row.accessibilityLabel == "New work, one chapter")

        let model = ResumeCardModel(
            title: "One-shot",
            authors: ["wren"],
            authorIdentities: [],
            fandoms: ["Original Work"],
            rating: "G",
            categories: ["Gen"],
            warnings: [],
            completion: .complete,
            words: 4_200,
            kudos: 120,
            chapters: "1/1",
            progress: 0.38,
            chapterProgress: 0.38,
            chapterName: "Chapter 1",
            published: "Mar 3",
            updated: "Mar 3",
            newChapterCount: 0
        )
        #expect(model.detailPrimaryTitle(fallback: "Read") == "Resume")
        #expect(model.postedLabel == "One chapter")
    }

    @Test func moreChaptersThanFitGroupIntoEqualBarsWithANote() {
        let longCard = ChapterBarGeometry.layout(
            planned: 200,
            posted: 143,
            read: 61,
            chapterProgress: 0.40,
            scale: .card,
            fit: 37
        )
        #expect(longCard.chaptersPerBar == 6)
        #expect(longCard.bars.count == 34)
        #expect(longCard.groupNote == "Each bar is 6 chapters")
        #expect(!longCard.showsOpenTotalDots)
        #expect(longCard.bars.prefix(10).allSatisfy { $0.role == .read })
        #expect(longCard.bars[10].role == .current(fill: 1.4 / 6.0))
        // Group 23 covers chapters 138..<144 (5 posted, 1 unposted) and counts as posted.
        #expect(longCard.bars[23].role == .postedUnread)
        #expect(longCard.bars.dropFirst(24).allSatisfy { $0.role == .notPosted })

        let longOpen = ChapterBarGeometry.layout(
            planned: nil,
            posted: 312,
            read: 100,
            scale: .card
        )
        #expect(longOpen.chaptersPerBar == 7)
        #expect(longOpen.bars.count == 45)
        #expect(longOpen.showsOpenTotalDots)
        #expect(!longOpen.bars.contains { $0.role == .notPosted })
        #expect(longOpen.groupNote == "Each bar is 7 chapters")

        let longRow = ChapterBarGeometry.layout(
            planned: nil,
            posted: 214,
            newChapterCount: 2,
            scale: .row,
            availableWidth: 204
        )
        #expect(longRow.chaptersPerBar == 6)
        #expect(longRow.bars.count == 36)
        #expect(longRow.showsOpenTotalDots)
        #expect(longRow.bars.last?.role == .current(fill: 0.5))
    }

    @Test func fewChaptersCapBarWidthAtTwentySevenPoints() {
        let layout = ChapterBarGeometry.layout(
            planned: 4,
            posted: 3,
            read: 1,
            chapterProgress: 0.60,
            scale: .card,
            availableWidth: 326
        )
        #expect(layout.bars.count == 4)
        #expect(layout.bars.map(\.role) == [.read, .current(fill: 0.60), .postedUnread, .notPosted])
        #expect(layout.metrics.width == 27)
    }

    @Test func unknownLengthsGiveEveryBarOneHeight() {
        let layout = ChapterBarGeometry.layout(
            planned: 20,
            posted: 12,
            read: 0,
            weights: nil,
            heights: nil,
            scale: .card
        )
        #expect(layout.bars.count == 20)
        #expect(layout.bars.allSatisfy { $0.weight == 1 })
    }

    @Test func readCountIsCappedAtPostedChapters() {
        let layout = ChapterBarGeometry.layout(
            planned: 20,
            posted: 12,
            read: 16,
            chapterProgress: 0.5,
            scale: .card
        )
        #expect(layout.bars.count == 20)
        #expect(layout.bars.prefix(12).allSatisfy { $0.role == .read })
        #expect(layout.bars.dropFirst(12).allSatisfy { $0.role == .notPosted })
        #expect(layout.accessibilityLabel == "Chapters: 12 read, 12 posted, 8 not posted yet")
    }

    @Test func voiceOverSummaryDescribesTheWholeImage() {
        let usual = ChapterBarGeometry.layout(planned: 20, posted: 12, read: 6, scale: .card)
        #expect(usual.accessibilityLabel == "Chapters: 6 read, 12 posted, 8 not posted yet")

        let openTotal = ChapterBarGeometry.layout(planned: nil, posted: 12, read: 6, scale: .card)
        #expect(openTotal.accessibilityLabel == "Chapters: 6 read, 12 posted, total not set by the author")

        let grouped = ChapterBarGeometry.layout(planned: 200, posted: 143, read: 61, scale: .card, fit: 37)
        #expect(grouped.accessibilityLabel == "Chapters: 61 read, 143 posted, 57 not posted yet. Each bar is 6 chapters")

        let rowFresh = ChapterBarGeometry.layout(planned: 30, posted: 15, newChapterCount: 3, scale: .row)
        #expect(rowFresh.accessibilityLabel == "3 new chapters, 15 posted, 15 not posted yet")

        let rowOpenFresh = ChapterBarGeometry.layout(planned: nil, posted: 5, newChapterCount: 1, scale: .row)
        #expect(rowOpenFresh.accessibilityLabel == "1 new chapter, 5 posted, total not set by the author")
    }
}
