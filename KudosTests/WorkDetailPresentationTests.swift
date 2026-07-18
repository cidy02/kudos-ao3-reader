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

    @Test func readActionShowsContinueForStartedUnfinishedDownloads() {
        #expect(WorkDetailPresentation.readAction(
            hasEPUB: true, working: false, continueReading: true
        ).title == "Continue Reading")
        // Continue never overrides a missing file or an in-flight download.
        #expect(WorkDetailPresentation.readAction(
            hasEPUB: false, working: false, continueReading: true
        ).title == "Download & Read")
        #expect(WorkDetailPresentation.readAction(
            hasEPUB: true, working: true, continueReading: true
        ).title == "Downloading…")
    }

    @Test func postRemovalActionRoutesByDeletionAndSource() {
        // The record survived removal (still saved/favorited/queued elsewhere).
        #expect(WorkDetailPresentation.postRemovalAction(
            isPendingDeletion: false, hasRemoteSource: true
        ) == .keepLocal)
        #expect(WorkDetailPresentation.postRemovalAction(
            isPendingDeletion: false, hasRemoteSource: false
        ) == .keepLocal)
        // Soft-deleted with a remote summary to fall back to → show remote state.
        #expect(WorkDetailPresentation.postRemovalAction(
            isPendingDeletion: true, hasRemoteSource: true
        ) == .showRemote)
        // Soft-deleted and opened from the local record itself → dismiss; the
        // screen must not keep mutating a Recently Deleted record.
        #expect(WorkDetailPresentation.postRemovalAction(
            isPendingDeletion: true, hasRemoteSource: false
        ) == .dismiss)
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
