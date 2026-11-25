import SwiftUI

/// Visibility policy for the app's floating tab bar introduced by T-482.
/// The tab bar stays visible on pushed screens, hiding only under modals,
/// the reader, selection mode, and full-screen editors (Board 42 / 43).
enum FloatingTabBarPolicy {
    static func hidesTabBar(
        isModal: Bool = false,
        isReader: Bool = false,
        isSelecting: Bool = false,
        isEditor: Bool = false
    ) -> Bool {
        isModal || isReader || isSelecting || isEditor
    }
}

extension View {
    /// Full-screen editors (Board 42 work form, chapter editor, and their child
    /// pickers) hide the persistent tab bar so form fields and formatting bars
    /// are never covered while typing.
    @ViewBuilder
    func hidesFloatingTabBarInEditor() -> some View {
        #if os(iOS)
        toolbar(FloatingTabBarPolicy.hidesTabBar(isEditor: true) ? .hidden : .automatic, for: .tabBar)
        #else
        self
        #endif
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
