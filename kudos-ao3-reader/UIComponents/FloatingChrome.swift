import SwiftUI

/// Visibility policy for the app's floating tab bar introduced by T-482.
/// The tab bar stays visible on pushed screens, hiding only under modals,
/// the reader, and selection mode.
enum FloatingTabBarPolicy {
    static func hidesTabBar(isModal: Bool = false, isReader: Bool = false, isSelecting: Bool = false) -> Bool {
        isModal || isReader || isSelecting
    }
}

/// Placement policy for the Comments screen's comment write bar introduced by T-482.
/// When pushed and at standard Dynamic Type sizes on iOS, Comments uses the
/// system bottom accessory beside the minimised active tab. At accessibility
/// sizes or when presented in a sheet (under modals), it uses in-view placement.
enum CommentsWriteBarPlacementPolicy {
    static func usesBottomAccessory(isModal: Bool, isAccessibilitySize: Bool) -> Bool {
        !isModal && !isAccessibilitySize
    }
}
