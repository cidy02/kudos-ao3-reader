import Foundation
import Testing
@testable import Kudos

/// Opening the Writing tab doesn't refetch AO3's drafts and stats pages every time (owner, 2026-11-26).
@MainActor
struct WritingTabReloadTests {
    @Test func draftsAndStatsLoadOnceThenOnlyWhenStale() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(WritingView.isStale(nil, now: now), "the first visit loads")
        #expect(!WritingView.isStale(now.addingTimeInterval(-60), now: now), "a minute later, switching back doesn't")
        #expect(!WritingView.isStale(now.addingTimeInterval(-(WritingView.freshFor - 1)), now: now))
        #expect(WritingView.isStale(now.addingTimeInterval(-WritingView.freshFor), now: now), "15 minutes on, it does")
        #expect(WritingView.isStale(now.addingTimeInterval(3600), now: now), "a clock set back counts as stale")
    }
}
