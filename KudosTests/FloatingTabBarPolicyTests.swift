import Testing
@testable import Kudos

/// T-482: Tab bar visibility and Comments write bar placement rules.
struct FloatingTabBarPolicyTests {
    @Test func tabBarStaysExceptUnderModalsReaderAndSelection() {
        // Standard pushed screens keep the tab bar visible.
        #expect(!FloatingTabBarPolicy.hidesTabBar(isModal: false, isReader: false, isSelecting: false))

        // Modals hide the bar.
        #expect(FloatingTabBarPolicy.hidesTabBar(isModal: true, isReader: false, isSelecting: false))

        // The reader hides the bar.
        #expect(FloatingTabBarPolicy.hidesTabBar(isModal: false, isReader: true, isSelecting: false))

        // Selection mode hides the bar.
        #expect(FloatingTabBarPolicy.hidesTabBar(isModal: false, isReader: false, isSelecting: true))
    }

    @Test func commentsUsesBottomAccessoryOnlyWhenPushedAndNonAccessibility() {
        // Pushed at standard size uses bottom accessory beside minimised tab.
        #expect(CommentsWriteBarPlacementPolicy.usesBottomAccessory(isModal: false, isAccessibilitySize: false))

        // Modal presentation (sheet from reader) does not use tab accessory.
        #expect(!CommentsWriteBarPlacementPolicy.usesBottomAccessory(isModal: true, isAccessibilitySize: false))

        // Accessibility sizes pin full-width under the list, not in the accessory.
        #expect(!CommentsWriteBarPlacementPolicy.usesBottomAccessory(isModal: false, isAccessibilitySize: true))
        #expect(!CommentsWriteBarPlacementPolicy.usesBottomAccessory(isModal: true, isAccessibilitySize: true))
    }
}
