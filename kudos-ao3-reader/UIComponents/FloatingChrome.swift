import SwiftUI

extension View {
    /// Hides the floating tab bar (and, with it, the global Search button) on pushed
    /// screens such as Work Detail, AO3 account lists, and Browse results. On iOS 26
    /// the tab bar otherwise keeps floating over a pushed view's content. The floating
    /// tab/search UI stays only on the root tab screens. No-op on macOS, which uses a
    /// sidebar split rather than a tab bar.
    func hidesFloatingTabBar() -> some View {
        #if os(iOS)
        toolbar(.hidden, for: .tabBar)
        #else
        self
        #endif
    }
}
