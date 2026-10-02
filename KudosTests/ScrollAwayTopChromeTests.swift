import Testing
@testable import Kudos

/// T-349: the top chrome scrolls away going down and returns going up or at the top.
struct ScrollAwayTopChromeTests {
    @Test func hidesGoingDownAndReturnsGoingUpOrAtTheTop() {
        // Near the top it always shows, whichever way you scroll.
        #expect(!ScrollAwayTopChrome.hides(false, from: 0, to: 30, fromTop: 30))
        // Down past the bar hides; a small jitter up keeps it hidden.
        #expect(ScrollAwayTopChrome.hides(false, from: 200, to: 210, fromTop: 210))
        #expect(ScrollAwayTopChrome.hides(true, from: 210, to: 207, fromTop: 207))
        // A deliberate upward scroll brings it back.
        #expect(!ScrollAwayTopChrome.hides(true, from: 400, to: 380, fromTop: 380))
        // No offset change (only the inset moved as the bar toggled) changes nothing.
        #expect(ScrollAwayTopChrome.hides(true, from: 500, to: 500, fromTop: 450))
        #expect(!ScrollAwayTopChrome.hides(false, from: 500, to: 500, fromTop: 550))
    }
}
