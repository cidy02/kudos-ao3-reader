import Foundation
import Testing
@testable import Kudos

/// T-572: which layouts draw Kudos's own bar, the shrink rule, and the shared hide merge.
struct ShrinkingTabBarTests {
    @Test func onlyCompactIPhoneUsesTheCustomBar() {
        #expect(ShrinkingTabBarPolicy.usesCustomBar(isPhone: true, isCompactWidth: true, isDuo: false))
        #expect(!ShrinkingTabBarPolicy.usesCustomBar(isPhone: false, isCompactWidth: true, isDuo: false))
        #expect(!ShrinkingTabBarPolicy.usesCustomBar(isPhone: true, isCompactWidth: false, isDuo: false))
        #expect(!ShrinkingTabBarPolicy.usesCustomBar(isPhone: true, isCompactWidth: true, isDuo: true))
    }

    @Test func contentInsetIsTheExpandedFootprint() {
        #expect(ShrinkingTabBarPolicy.contentInset(barHidden: true, hasAccessory: true) == 0)
        #expect(ShrinkingTabBarPolicy.contentInset(barHidden: false, hasAccessory: false) == 70)
        #expect(ShrinkingTabBarPolicy.contentInset(barHidden: false, hasAccessory: true) == 132)
    }

    @Test func barStaysHiddenWhileAnyCallerInTheSelectedTabHidesIt() {
        var hiders = TabBarHiders()
        let selection = UUID(), reader = UUID()
        #expect(!hiders.isHidden(in: .home))
        hiders.set(true, by: selection, in: .home)
        hiders.set(true, by: reader, in: .home)
        hiders.set(false, by: selection, in: .home)
        #expect(hiders.isHidden(in: .home))
        hiders.set(false, by: reader, in: .home)
        #expect(!hiders.isHidden(in: .home))
    }

    /// The review's inbox scenario: a Select left on in Writing's stack must not hide Home's bar.
    @MainActor @Test func aScreenInAnotherTabNeverHidesTheSelectedTabsBar() {
        let chrome = TabChromeState()
        chrome.selectedTab = .home
        chrome.setHidden(true, by: UUID(), in: .writing)
        #expect(!chrome.isBarHidden)
        chrome.selectedTab = .writing
        #expect(chrome.isBarHidden)
    }

    @Test func shrinkRuleIsTheTopChromeRule() {
        // Near the top: never shrunk. Scrolling down past it: shrunk. Deliberate upward scroll: expanded.
        #expect(!ScrollAwayTopChrome.hides(true, from: 0, to: 20, fromTop: 20))
        #expect(ScrollAwayTopChrome.hides(false, from: 100, to: 120, fromTop: 120))
        #expect(!ScrollAwayTopChrome.hides(true, from: 300, to: 280, fromTop: 280))
    }

    @MainActor @Test func reselectCountsEachTap() {
        let chrome = TabChromeState()
        chrome.reselected(.home)
        chrome.reselected(.home)
        #expect(chrome.reselect == TabReselect(tab: .home, count: 2))
    }
}
