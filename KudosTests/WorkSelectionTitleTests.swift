import Foundation
import Testing
@testable import Kudos

/// Select mode's title-bar text (spec 1af), shared by Library's dashboard and the
/// pushed Home and Library section lists.
@MainActor
struct WorkSelectionTitleTests {
    @Test func countsTheSelection() {
        #expect(WorkSelectionTitle.text(selectedCount: 0) == "Select Works")
        #expect(WorkSelectionTitle.text(selectedCount: 1) == "1 Selected")
        #expect(WorkSelectionTitle.text(selectedCount: 12) == "12 Selected")
    }

    @Test func remoteResultsSelectionPlacesCheckLeadingAndAvoidsBottomBarOverlap() {
        #expect(RemoteWorkSelectionToolbar.usesBottomBar == false)
        #expect(AO3WorkRow.selectionEdge(isSelecting: false) == .none)
        #expect(AO3WorkRow.selectionEdge(isSelecting: true) == .leading)
        #expect(AO3WorkRow.separatorInset(isSelecting: true) == 115)
        #expect(AO3WorkRow.separatorInset(isSelecting: false) == nil)
    }

    @Test func libraryAndRecentlyDeletedRowsUseLeadingSelectionCheckNotBubble() {
        #expect(WorkRow.selectionEdge(isSelecting: false) == .none)
        #expect(WorkRow.selectionEdge(isSelecting: true) == .leading)
        #expect(WorkRow.separatorInset(isSelecting: true) == 115)
        #expect(WorkRow.separatorInset(isSelecting: false) == nil)

        #expect(RecentlyDeletedRow.selectionEdge(isSelecting: false) == .none)
        #expect(RecentlyDeletedRow.selectionEdge(isSelecting: true) == .leading)
        #expect(RecentlyDeletedRow.separatorInset(isSelecting: true) == 115)
        #expect(RecentlyDeletedRow.separatorInset(isSelecting: false) == nil)

        let entry = RecentlyDeletedEntry(
            id: UUID(),
            kicker: "Local collection",
            noun: "collection",
            title: "Summer 2025",
            detail: "0 works",
            daysRemaining: 77,
            restore: { true },
            deletionMessage: { "" },
            deletePermanently: {}
        )
        let row = RecentlyDeletedRow(
            entry: entry,
            palette: SubjectPalette(hue: 0, theme: .light),
            showsSeparator: true,
            isSelecting: true,
            isSelected: true,
            onRestore: {},
            onDeletePermanently: {}
        )
        let reflected = String(reflecting: type(of: row.body))
        #expect(reflected.contains("WorkLeadingSelectionCheck"))
        #expect(!reflected.contains("WorkSelectionBubble"))
    }
}
