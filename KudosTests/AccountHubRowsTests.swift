import Testing
@testable import Kudos

/// The Account hub's rows per scope, which the signed-in groups and the
/// signed-out preview (1n) both draw from. The preview once listed string
/// literals and lacked Subscriptions, Drafts and History.
@MainActor
struct AccountHubRowsTests {
    @Test func everyScopeListsEveryHubRow() {
        #expect(AccountView.readingRowOrder.map(\.rawValue)
            == ["Marked for Later", "Bookmarks", "Collections", "Subscriptions"])
        #expect(AccountView.writingRowOrder.map(\.rawValue) == ["Works", "Series", "Drafts"])
        #expect(AccountView.activityRowOrder.map(\.rawValue) == ["History", "Inbox"])
    }

    /// A tab added to a scope must be placed in its row order, or it is on
    /// neither the hub nor the preview.
    @Test func noTabIsLeftOut() {
        #expect(Set(AccountView.readingRowOrder) == Set(AccountView.AccountReadingTab.allCases))
        #expect(Set(AccountView.writingRowOrder) == Set(AccountView.AccountWritingTab.allCases))
        #expect(Set(AccountView.activityRowOrder) == Set(AccountView.AccountActivityTab.allCases))
    }
}
