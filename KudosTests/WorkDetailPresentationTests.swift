import Foundation
import SwiftUI
import Testing
@testable import Kudos

/// The Work Details redesign moved the old view's inline label/state logic into
/// `WorkDetailPresentation`; these tests lock in that moved behavior.
struct WorkDetailPresentationTests {
    /// Read never mentions downloading (owner, 2026-10-01): the copy it fetches
    /// is not a download.
    @Test func readActionNeverSaysDownload() {
        #expect(WorkDetailPresentation.readAction(working: false).title == "Read")
        #expect(WorkDetailPresentation.readAction(working: true).title == "Opening…")
        #expect(WorkDetailPresentation.readAction(working: false, continueReading: true).title == "Continue Reading")
        // A fetch in flight wins over Continue.
        #expect(WorkDetailPresentation.readAction(working: true, continueReading: true).title == "Opening…")
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
        #expect(WorkDetailPresentation.downloadState(nil).title == "Download")
        #expect(WorkDetailPresentation.downloadState(.download).title == "Download")
        #expect(WorkDetailPresentation.downloadState(.removeDownload).title == "Downloaded")
        #expect(WorkDetailPresentation.downloadState(.removeDownload).systemImage
            == WorkActionLabels.downloadedSymbol)
        #expect(WorkDetailPresentation.downloadState(.keptBy("Neon reread")).isEnabled == false)

        #expect(WorkDetailPresentation.laterAction(isQueued: false).title == "Save for Later")
        #expect(WorkDetailPresentation.laterAction(isQueued: true).title == "Remove from Later")
        #expect(WorkDetailPresentation.laterAction(isQueued: false).systemImage
            == WorkActionLabels.savedForLater(isQueued: false).systemImage)
    }

    @Test func summaryFromLocalRequiresAO3Identity() {
        let withID = SavedWork(title: "T", author: "A", sourceURL: "https://archiveofourown.org/works/99")
        withID.ao3WorkID = 99
        #expect(WorkDetailPresentation.summaryFromLocal(withID)?.id == 99)

        let noID = SavedWork(title: "Local", author: "B", sourceURL: "file:///tmp/x.epub")
        #expect(WorkDetailPresentation.summaryFromLocal(noID) == nil)
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

    // MARK: My copy summary (artboard 1a's row at the foot of the page)

    @Test func myCopySummaryNamesOnlyWhatIsTrue() {
        // Spec 1a's own example line.
        #expect(WorkDetailPresentation.myCopySummary(
            isDownloaded: true, queueCount: 2, tagCount: 1, collectionCount: 0
        ) == "Downloaded · 2 queues · 1 tag")
    }

    @Test func myCopySummarySkipsEmptyFactsRatherThanPrintingZero() {
        // A work in no queues says nothing about queues. "0 queues" is a fact
        // about nothing, and it would crowd out the ones that matter.
        #expect(WorkDetailPresentation.myCopySummary(
            isDownloaded: true, queueCount: 0, tagCount: 0, collectionCount: 0
        ) == "Downloaded")
        #expect(WorkDetailPresentation.myCopySummary(
            isDownloaded: false, queueCount: 3, tagCount: 0, collectionCount: 0
        ) == "3 queues")
    }

    @Test func myCopySummarySingularAndPluralAgreeWithTheCount() {
        #expect(WorkDetailPresentation.myCopySummary(
            isDownloaded: false, queueCount: 1, tagCount: 1, collectionCount: 1
        ) == "1 queue · 1 collection · 1 tag")
        #expect(WorkDetailPresentation.myCopySummary(
            isDownloaded: false, queueCount: 2, tagCount: 2, collectionCount: 2
        ) == "2 queues · 2 collections · 2 tags")
    }

    @Test func myCopySummarySaysSoWhenThereIsNothingLocal() {
        // The row is only shown for a work that has a local record at all, but a
        // record can exist with nothing attached to it — a blank line under
        // "My copy" would read as a rendering fault rather than as a state.
        #expect(WorkDetailPresentation.myCopySummary(
            isDownloaded: false, queueCount: 0, tagCount: 0, collectionCount: 0
        ) == "You haven't saved anything on this device yet")
    }

    // MARK: Warning figures (the strip under the title, spec 1a)

    @Test func warningFigureTextDropsTheFieldNameTheLabelAlreadyGives() {
        // `text` says "No Warnings" because it stands alone beside an icon; the
        // strip prints it under a WARNINGS label, where that is the field twice.
        #expect(WorkWarningStatus(rawWarnings: []).figureText == "None")
        #expect(WorkWarningStatus(rawWarnings: ["No Archive Warnings Apply"]).figureText == "None")
        #expect(WorkWarningStatus(rawWarnings: ["Creator Chose Not To Use Archive Warnings"])
            .figureText == "Undisclosed")
        #expect(WorkWarningStatus(rawWarnings: ["Graphic Depictions Of Violence"]).figureText == "1")
        #expect(WorkWarningStatus(rawWarnings: ["Graphic Depictions Of Violence", "Major Character Death"])
            .figureText == "2")
    }

    @Test func warningFigureColourDiffersFromTheBadgeRampOnlyForNoWarnings() {
        // The documented disagreement, locked in: gray reads as "nothing
        // flagged" among badge icons and as "dimmed out" as a cell's only text,
        // so the figure form takes green. The other two states must not drift.
        #expect(WorkWarningStatus(rawWarnings: []).color == .gray)
        #expect(WorkWarningStatus(rawWarnings: []).figureColor == .green)

        let undisclosed = WorkWarningStatus(rawWarnings: ["Creator Chose Not To Use Archive Warnings"])
        #expect(undisclosed.color == undisclosed.figureColor)

        let present = WorkWarningStatus(rawWarnings: ["Major Character Death"])
        #expect(present.color == present.figureColor)
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
