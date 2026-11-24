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


    @Test func composerWinsAndTheCustomBarHasNoSystemAccessory() {
        #expect(CommentsWriteBarPlacementPolicy.usesBottomAccessory(isModal: false, isAccessibilitySize: false))
        #expect(!CommentsWriteBarPlacementPolicy.usesSystemAccessory(composerOwnsAccessory: true, customBar: true))
        #expect(CommentsWriteBarPlacementPolicy.usesSystemAccessory(composerOwnsAccessory: true, customBar: false))
        #expect(!ReaderSpeechSessionPolicy.showsMiniPlayer(
            sessionActive: true, readerOpen: false, commentAccessoryTab: .library, selectedTab: .library))
        #expect(ShrinkingTabBarPolicy.pillDrop(isShrunk: true) == 18)
    }

    @Test func scrollToTopPicksTallVerticalScrollersAndNeverFightTheUser() {
        #expect(ScrollToTopPolicy.qualifies(size: CGSize(width: 390, height: 700), contentHeight: 2000, alwaysBounceVertical: false))
        #expect(!ScrollToTopPolicy.qualifies(size: CGSize(width: 390, height: 240), contentHeight: 240, alwaysBounceVertical: false)) // carousel
        #expect(!ScrollToTopPolicy.qualifies(size: CGSize(width: 390, height: 700), contentHeight: 300, alwaysBounceVertical: false))
        #expect(ScrollToTopPolicy.shouldSettle(offset: -60, top: -100, initialTop: -60, userIsScrolling: false))
        #expect(!ScrollToTopPolicy.shouldSettle(offset: -60, top: -100, initialTop: -60, userIsScrolling: true))
        #expect(!ScrollToTopPolicy.shouldSettle(offset: 900, top: -100, initialTop: -60, userIsScrolling: false))
    }

    /// A popped or sheet-contained screen stops contributing because the combined value is
    /// recomputed from the live tree: a tab whose tree has no hiding screen reports false.
    @Test func hiddenPreferenceIsTheOrOfTheLiveScreens() {
        var value = TabBarHiddenKey.defaultValue
        TabBarHiddenKey.reduce(value: &value) { false }
        #expect(!value) // nothing hiding (popped screen contributes nothing)
        TabBarHiddenKey.reduce(value: &value) { true }
        TabBarHiddenKey.reduce(value: &value) { false }
        #expect(value)
    }

    @MainActor @Test func theBarShowsTheSelectedTabsCombinedValueOnly() {
        let chrome = TabChromeState()
        chrome.selectedTab = .home
        chrome.setHidden(true, in: .writing)
        #expect(!chrome.isBarHidden)
        chrome.setHidden(true, in: .home)
        #expect(chrome.isBarHidden)
        chrome.setHidden(false, in: .home) // the screen popped: the root's preference falls back
        #expect(!chrome.isBarHidden)
    }

    @Test func pillOnlyDropsOnTheShrunkPushedCustomBar() {
        // CommentsView's own predicate: the system bar and modal sheets never shift.
        #expect(CommentsWriteBarPlacementPolicy.customBarDrop(customBar: true, isModal: false, isShrunk: true) == 18)
        #expect(CommentsWriteBarPlacementPolicy.customBarDrop(customBar: true, isModal: false, isShrunk: false) == 0)
        #expect(CommentsWriteBarPlacementPolicy.customBarDrop(customBar: false, isModal: false, isShrunk: true) == 0)
        #expect(CommentsWriteBarPlacementPolicy.customBarDrop(customBar: true, isModal: true, isShrunk: true) == 0)
    }

    @Test func onlyTheScreenOnTopHidesTheBar() {
        #expect(TabBarHiddenPolicy.emitted(hidden: true, onScreen: true))
        #expect(!TabBarHiddenPolicy.emitted(hidden: true, onScreen: false)) // covered by a push
        #expect(!TabBarHiddenPolicy.emitted(hidden: false, onScreen: true))
    }

    @Test func theTabBarShrinksWhateverTheNavBarFlagSays() {
        // Nav bar still hidden from before a tab switch; the bar was reset to expanded.
        let step = ScrollAwayTopChrome.step(navHidden: true, barShrunk: false, from: 500, to: 900, fromTop: 900)
        #expect(step.nav)
        #expect(step.bar)
        let up = ScrollAwayTopChrome.step(navHidden: false, barShrunk: true, from: 900, to: 700, fromTop: 700)
        #expect(!up.nav && !up.bar)
    }

    @MainActor @Test func aSheetIsNotTheRootAndUnknownIsNotRootEither() {
        let chrome = TabChromeState()
        #expect(TabChromeState.scoped(chrome, inRoot: true) === chrome)
        #expect(TabChromeState.scoped(chrome, inRoot: false) == nil)
        #expect(TabChromeState.scoped(chrome, inRoot: nil) == nil)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        let rootChild = UIView()
        root.view.addSubview(rootChild)
        #expect(!TabChromeCover.isModal(rootChild))

        let sheet = UIViewController()
        let sheetChild = UIView()
        sheet.view.addSubview(sheetChild)
        let nav = UINavigationController(rootViewController: sheet)
        root.present(nav, animated: false)
        #expect(TabChromeCover.isModal(sheetChild))
        #expect(!TabChromeCover.isModal(rootChild))
    }

    @Test func scrollToTopSettlesOnlyWhenTheTopInsetGrew() {
        #expect(ScrollToTopPolicy.shouldSettle(offset: -60, top: -100, initialTop: -60, userIsScrolling: false))
        #expect(!ScrollToTopPolicy.shouldSettle(offset: -60, top: -100, initialTop: -100, userIsScrolling: false))
        #expect(!ScrollToTopPolicy.qualifies(size: CGSize(width: 390, height: 700), contentHeight: 300,
                                             alwaysBounceVertical: false, alwaysBounceHorizontal: true))
    }
}
