import Foundation
import SwiftUI
import Testing
@testable import Kudos

/// The Work Details redesign moved the old view's inline label/state logic into
/// `WorkDetailPresentation`; these tests lock in that moved behavior.
struct WorkDetailPresentationTests {
    #if os(iOS)
    @Test func detailUsesItsOwnUsableWidthAndKeepsPortraitSingle() {
        for width in [CGFloat(320), 393, 466, 600, 669, 703] {
            let regions = AdaptiveContentRegions(bounds: CGRect(x: 0, y: 0, width: width, height: 900))
            let panes = WorkDetailPresentation.contentPanes(in: regions, accessibilitySize: false)
            #expect(panes == [regions.viewport])
        }
        // Width consumed by a rail/safe area must not be counted toward fit.
        let inset = AdaptiveContentRegions(
            bounds: CGRect(x: 0, y: 0, width: 760, height: 600),
            safeAreaInsets: EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 50)
        )
        #expect(WorkDetailPresentation.contentPanes(in: inset, accessibilitySize: false).count == 1)
    }

    @Test func detailSplitsAtTwoReadableMeasuresWithAGutter() throws {
        for width in [CGFloat(704), 860, 951, 1_024] {
            let regions = AdaptiveContentRegions(bounds: CGRect(x: 0, y: 0, width: width, height: 600))
            let panes = WorkDetailPresentation.contentPanes(in: regions, accessibilitySize: false)
            try #require(panes.count == 2)
            #expect(panes.allSatisfy { $0.width >= 340 })
            #expect(panes.first?.minX == 0)
            #expect(panes.last?.maxX == width)
            #expect(panes[1].minX - panes[0].maxX == 24)
        }
    }

    @Test func detailKeepsShortPhoneLandscapeAndLargeTypeReadable() {
        let short = AdaptiveContentRegions(bounds: CGRect(x: 0, y: 0, width: 860, height: 393))
        #expect(WorkDetailPresentation.contentPanes(in: short, accessibilitySize: false).count == 1)
        let wide = AdaptiveContentRegions(bounds: CGRect(x: 0, y: 0, width: 900, height: 600))
        let largeType = WorkDetailPresentation.contentPanes(in: wide, accessibilitySize: true)
        #expect(largeType == [CGRect(x: 90, y: 0, width: 720, height: 600)])
        let iPad = AdaptiveContentRegions(bounds: CGRect(x: 0, y: 0, width: 1_200, height: 900))
        let panes = WorkDetailPresentation.contentPanes(in: iPad, accessibilitySize: true)
        #expect(panes.count == 2)
        #expect(panes.allSatisfy { $0.width >= 480 })
    }

    @Test func detailFollowsTheActualFoldAndLogicalReadingDirection() throws {
        let regions = AdaptiveContentRegions(
            bounds: CGRect(x: 0, y: 0, width: 900, height: 600),
            safeAreaInsets: EdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 72),
            reservations: [.init(frame: CGRect(x: 430, y: -20, width: 40, height: 640))]
        )
        let panes = WorkDetailPresentation.contentPanes(in: regions, accessibilitySize: false)
        try #require(panes.count == 2)
        #expect(panes == regions.viewportPanes)
        #expect(panes == [CGRect(x: 0, y: 0, width: 412, height: 600),
                          CGRect(x: 452, y: 0, width: 358, height: 600)])
        #expect(WorkDetailPresentation.contentPanes(
            in: regions, accessibilitySize: false, rightToLeft: true
        ) == Array(panes.reversed()))
        #expect(WorkDetailPresentation.contentPanes(in: regions, accessibilitySize: true) == [panes[0]])
        #expect(WorkDetailPresentation.contentPanes(
            in: regions, accessibilitySize: true, rightToLeft: true
        ) == [panes[1]])
    }

    @Test func detailNeverSubdividesOrCrossesAnUnusableReservedPane() {
        let bounds = CGRect(x: 0, y: 0, width: 900, height: 600)
        // Total width fits, but the trailing physical pane is too narrow.
        let divided = AdaptiveContentRegions(bounds: bounds, reservations: [
            .init(frame: CGRect(x: 560, y: 0, width: 40, height: 600))
        ])
        #expect(WorkDetailPresentation.contentPanes(
            in: divided, accessibilitySize: false
        ) == [CGRect(x: 0, y: 0, width: 560, height: 600)])
        let horizontal = AdaptiveContentRegions(bounds: bounds, reservations: [
            .init(frame: CGRect(x: 0, y: 270, width: 900, height: 40))
        ])
        #expect(WorkDetailPresentation.contentPanes(
            in: horizontal, accessibilitySize: false
        ) == [CGRect(x: 90, y: 0, width: 720, height: 290)])
        let blocked = AdaptiveContentRegions(bounds: bounds, reservations: [.init(frame: bounds)])
        #expect(WorkDetailPresentation.contentPanes(in: blocked, accessibilitySize: false).isEmpty)
    }

    @Test func detailReactsToReservationActivationWithoutAResize() {
        let bounds = CGRect(x: 0, y: 0, width: 900, height: 600)
        let frame = CGRect(x: 430, y: 0, width: 40, height: 600)
        let flat = AdaptiveContentRegions(bounds: bounds, reservations: [.init(frame: frame, isActive: false)])
        let book = AdaptiveContentRegions(bounds: bounds, reservations: [.init(frame: frame)])
        #expect(WorkDetailPresentation.contentPanes(in: flat, accessibilitySize: false)
            != WorkDetailPresentation.contentPanes(in: book, accessibilitySize: false))
    }
    #endif

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
        #expect(WorkWarningStatus(rawWarnings: []).figureColor == AO3TagPalette.general)

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
