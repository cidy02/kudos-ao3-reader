import Testing
@testable import Kudos

/// 1ae's pills: Unread is "new chapters not yet seen", not "never opened".
@MainActor
struct HomeUpdatePillTests {
    @Test func unreadMeansUnseenNewChapters() {
        let updated = SavedWork(title: "Updated", author: "X")
        updated.chapters = "5/?"
        updated.knownChapterCount = 4
        let current = SavedWork(title: "Current", author: "X")
        current.chapters = "4/?"
        current.knownChapterCount = 4

        #expect(HomeUpdatePill.unread.apply(to: [updated, current]).map(\.title) == ["Updated"])
        #expect(HomeUpdatePill.all.apply(to: [updated, current]).count == 2)
    }
}
