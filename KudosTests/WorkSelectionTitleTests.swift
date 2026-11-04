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
}
