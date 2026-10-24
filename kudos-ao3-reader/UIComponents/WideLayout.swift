#if os(iOS)
import SwiftUI

enum WideLayout {
    /// A regular width alone also includes compact-height phone landscapes.
    static func isAvailable(
        horizontal: UserInterfaceSizeClass?,
        vertical: UserInterfaceSizeClass?
    ) -> Bool {
        horizontal == .regular && vertical == .regular
    }
}
#endif
