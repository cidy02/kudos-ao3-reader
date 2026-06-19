import SwiftUI
#if canImport(UIKit)
import UIKit
private typealias PlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
private typealias PlatformColor = NSColor
#endif

extension Color {
    /// Creates a colour from a `#RRGGBB` (or `RRGGBB`) hex string; nil if malformed.
    init?(hex: String) {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasPrefix("#") { string.removeFirst() }
        guard string.count == 6, let value = UInt64(string, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// The colour as an uppercase `#RRGGBB` hex string (opacity dropped).
    var hexString: String {
        let platform = PlatformColor(self)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        #if canImport(UIKit)
        platform.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #else
        (platform.usingColorSpace(.sRGB) ?? platform).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #endif
        return String(format: "#%02X%02X%02X",
                      Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }
}
