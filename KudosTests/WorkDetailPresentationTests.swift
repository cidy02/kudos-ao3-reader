import Foundation
import Testing
@testable import Kudos

/// The Work Details redesign moved the old view's inline label/state logic into
/// `WorkDetailPresentation`; these tests lock in that moved behavior.
struct WorkDetailPresentationTests {
    @Test func readActionReflectsDownloadState() {
        #expect(WorkDetailPresentation.readAction(hasEPUB: true, working: false).title == "Read")
        #expect(WorkDetailPresentation.readAction(hasEPUB: false, working: false).title == "Download & Read")
        // A download in flight wins regardless of the EPUB flag.
        #expect(WorkDetailPresentation.readAction(hasEPUB: false, working: true).title == "Downloading…")
        #expect(WorkDetailPresentation.readAction(hasEPUB: true, working: true).title == "Downloading…")
    }

    @Test func savedAndLaterActionsAreStateAware() {
        #expect(WorkDetailPresentation.savedAction(isSaved: false).title == "Save to Keep")
        #expect(WorkDetailPresentation.savedAction(isSaved: true).title == "Saved")
        #expect(WorkDetailPresentation.savedAction(isSaved: true).systemImage == "bookmark.fill")

        #expect(WorkDetailPresentation.laterAction(isQueued: false).title == "Save for Later")
        #expect(WorkDetailPresentation.laterAction(isQueued: true).title == "Remove from Later")
    }

    @Test func queueAndCollectionLabelsPluralize() {
        #expect(WorkDetailPresentation.queueLabel(count: 0) == "Add to Queue")
        #expect(WorkDetailPresentation.queueLabel(count: 1) == "In 1 Queue")
        #expect(WorkDetailPresentation.queueLabel(count: 3) == "In 3 Queues")

        #expect(WorkDetailPresentation.collectionLabel(count: 0) == "Add to Collection")
        #expect(WorkDetailPresentation.collectionLabel(count: 1) == "In 1 Collection")
        #expect(WorkDetailPresentation.collectionLabel(count: 2) == "In 2 Collections")
    }

    @Test func totalChapterCountParsesAO3ChapterStat() {
        #expect(WorkDetailPresentation.totalChapterCount(from: "5/10") == 10)
        #expect(WorkDetailPresentation.totalChapterCount(from: "1/1") == 1)
        // Unknown totals and malformed values stay nil.
        #expect(WorkDetailPresentation.totalChapterCount(from: "5/?") == nil)
        #expect(WorkDetailPresentation.totalChapterCount(from: "") == nil)
        #expect(WorkDetailPresentation.totalChapterCount(from: "12") == nil)
    }

    @Test func summaryCollapsesOnlyWhenLong() {
        #expect(!WorkDetailPresentation.summaryCollapses("Short summary."))
        #expect(!WorkDetailPresentation.summaryCollapses(String(repeating: "a", count: 600)))
        #expect(WorkDetailPresentation.summaryCollapses(String(repeating: "a", count: 601)))
    }

    @Test func preservationStatusLabelCoversEveryState() {
        #expect(WorkDetailPresentation.preservationStatusLabel(.preserved) == "Preserved offline")
        #expect(WorkDetailPresentation.preservationStatusLabel(.preserving) == "Preserving…")
        #expect(WorkDetailPresentation.preservationStatusLabel(.queued) == "Preservation queued")
        #expect(WorkDetailPresentation.preservationStatusLabel(.failed) == "Needs restore")
        #expect(WorkDetailPresentation.preservationStatusLabel(.missingFile) == "Needs restore")
        #expect(WorkDetailPresentation.preservationStatusLabel(.notPreserved) == "Not preserved")
    }

    @Test func fileSizeLabelFormatsExistingFileAndNilsMissing() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkDetailPresentationTests", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("sample.epub")
        try Data(count: 4096).write(to: file)
        let label = WorkDetailPresentation.fileSizeLabel(forFileAt: file)
        #expect(label != nil)
        #expect(label?.isEmpty == false)

        let missing = directory.appendingPathComponent("missing.epub")
        #expect(WorkDetailPresentation.fileSizeLabel(forFileAt: missing) == nil)
    }
}
