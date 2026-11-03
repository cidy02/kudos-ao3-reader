import SwiftUI

/// The device's everyday name for labels like "Kudos on this iPhone", which read wrong on an iPad or a Mac.
enum ThisDevice {
    @MainActor static var name: String {
        #if os(macOS)
        "Mac"
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }
}
