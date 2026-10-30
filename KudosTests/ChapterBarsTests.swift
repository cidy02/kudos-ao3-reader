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
        let oneRead = ChapterBarGeometry.items(planned: 1, posted: 1, progress: 1, weights: nil)
        #expect(oneRead == [ChapterBarItem(role: .read, weight: 1)])

        let oneCurrent = ChapterBarGeometry.items(planned: 1, posted: 1, progress: 0.4, weights: nil)
        #expect(oneCurrent == [ChapterBarItem(role: .current(fill: 0.4), weight: 1)])

        let oneUnread = ChapterBarGeometry.items(planned: 1, posted: 1, progress: nil, weights: nil)
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
}
