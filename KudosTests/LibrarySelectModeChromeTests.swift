import Foundation
import Testing
@testable import Kudos

/// Select-mode chrome contracts on library screens (boards 08, 09 / FID53):
/// 1. No bottom toolbar in select mode on either screen.
/// 2. Header controls match the boards: Select All leading, solid accent Done trailing.
/// 3. All bulk actions remain reachable:
///    - Recently Deleted: Restore (Undo) and Delete Permanently in top-bar Menu.
///    - Shelf list: shared WorkBulkActionBar inside top-bar ellipsis Menu.
@MainActor
struct LibrarySelectModeChromeTests {
    @Test func recentlyDeletedSelectModeUsesNoBottomBar() {
        #expect(RecentlyDeletedView.usesBottomBarInSelectMode == false)
    }

    @Test func recentlyDeletedSelectModeKeepsAllActionsReachable() {
        let actions = RecentlyDeletedView.selectModeActions()
        #expect(actions.contains(.selectAll))
        #expect(actions.contains(.restore))
        #expect(actions.contains(.deletePermanently))
        #expect(actions.contains(.done))

        // Explicitly assert Undo and Delete per FID53 rules:
        #expect(actions.contains(.restore), "Restore (Undo) must be reachable")
        #expect(actions.contains(.deletePermanently), "Delete Permanently must be reachable")
    }

    @Test func librarySectionListSelectModeUsesNoBottomBar() {
        #expect(LibrarySectionListView.usesBottomBarInSelectMode == false)
    }

    @Test func librarySectionListSelectModeReachesSharedWorkBulkActionBar() {
        #expect(LibrarySectionListView.usesBottomBarInSelectMode == false)
        let bar = WorkBulkActionBar(selectedWorks: [], onDeleted: {}, onDone: {})
        let reflected = String(reflecting: type(of: bar.body))
        #expect(reflected.contains("Menu"))
        #expect(reflected.contains("Button"))
    }
}
