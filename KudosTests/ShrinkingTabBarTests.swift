import UIKit
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

/// Round 2/3 regressions: each fails if the matching fix is undone.
struct ShrinkingTabBarRegressionTests {
    @Test func hiderRegistersOnlyWhileVisible() {
        var registration = HiderRegistration()
        #expect(registration.changed(to: true) == nil) // off-screen copy: ignored
        let shown = registration.appeared(hidden: true)
        #expect(shown)
        #expect(registration.changed(to: false) == false)
        let left = registration.disappeared(coveredByPresentation: false)
        #expect(left == false)
        #expect(registration.changed(to: true) == nil)
    }

    @Test func aCoveredScreenKeepsItsHide() {
        var registration = HiderRegistration()
        _ = registration.appeared(hidden: true)
        let left = registration.disappeared(coveredByPresentation: true)
        #expect(left == nil)
    }

    @MainActor @Test func sheetsGetNoChrome() {
        let chrome = TabChromeState()
        #expect(TabChromeState.scoped(chrome, inRoot: true) === chrome)
        #expect(TabChromeState.scoped(chrome, inRoot: false) == nil)
    }

    @Test func barShrinksEvenWhenTheNavBarFlagIsStale() {
        // Nav bar still "hidden" from before a tab switch; the bar was reset to expanded.
        #expect(ScrollAwayTopChrome.barShrinks(false, from: 500, to: 900, fromTop: 900))
        #expect(!ScrollAwayTopChrome.barShrinks(true, from: 900, to: 800, fromTop: 800))
    }

    @MainActor @Test func dismantlingTheInsetProbeClearsTheTabControllerInset() {
        let controller = UITabBarController()
        let probe = TabBarContentInset.Probe()
        probe.controllerProvider = { _ in controller }
        probe.inset = 70
        probe.apply()
        #expect(controller.additionalSafeAreaInsets.bottom == 70)
        TabBarContentInset.dismantleUIView(probe, coordinator: ())
        #expect(controller.additionalSafeAreaInsets.bottom == 0)
    }

    @Test func onlyAKeyboardReachingTheBarTakesTheInset() {
        #expect(TabBarKeyboardPolicy.inset(base: 70, keyboardOverlap: 0, safeBottom: 34) == 70)
        #expect(TabBarKeyboardPolicy.inset(base: 70, keyboardOverlap: 55, safeBottom: 34) == 70) // shortcut strip
        #expect(TabBarKeyboardPolicy.inset(base: 70, keyboardOverlap: 336, safeBottom: 34) == 0)
    }

    @Test func composerWinsAndTheCustomBarHasNoSystemAccessory() {
        #expect(CommentsWriteBarPlacementPolicy.usesBottomAccessory(isModal: false, isAccessibilitySize: false))
        #expect(!CommentsWriteBarPlacementPolicy.usesSystemAccessory(composerOwnsAccessory: true, customBar: true))
        #expect(CommentsWriteBarPlacementPolicy.usesSystemAccessory(composerOwnsAccessory: true, customBar: false))
        #expect(!ReaderSpeechSessionPolicy.showsMiniPlayer(
            sessionActive: true, readerOpen: false, commentAccessoryTab: .library, selectedTab: .library))
        #expect(ShrinkingTabBarPolicy.pillDrop(isShrunk: true) == 18)
        #expect(ShrinkingTabBarPolicy.pillDrop(isShrunk: false) == 0)
    }

    @Test func scrollToTopPicksTallVerticalScrollersAndNeverFightTheUser() {
        #expect(ScrollToTopPolicy.qualifies(size: CGSize(width: 390, height: 700), contentHeight: 2000, alwaysBounceVertical: false))
        #expect(!ScrollToTopPolicy.qualifies(size: CGSize(width: 390, height: 240), contentHeight: 240, alwaysBounceVertical: false)) // carousel
        #expect(!ScrollToTopPolicy.qualifies(size: CGSize(width: 390, height: 700), contentHeight: 300, alwaysBounceVertical: false))
        #expect(ScrollToTopPolicy.shouldSettle(offset: -60, top: -100, userIsScrolling: false))
        #expect(!ScrollToTopPolicy.shouldSettle(offset: -60, top: -100, userIsScrolling: true))
        #expect(!ScrollToTopPolicy.shouldSettle(offset: 900, top: -100, userIsScrolling: false))
    }
}
