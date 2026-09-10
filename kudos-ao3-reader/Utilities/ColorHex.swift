import Foundation
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

    /// The colour's hue as a 0…1 fraction, which is what every subject-derived
    /// surface in the redesign is built from (`SubjectPalette`). Saturation and
    /// brightness are deliberately dropped: the palette re-derives those per
    /// theme so a wash stays legible whatever accent the user picked, and a
    /// near-grey accent should still produce a coherent (if quiet) wash rather
    /// than an unusable one.
    ///
    /// Grey has no meaningful hue; `UIColor`/`NSColor` report 0 (red) for it,
    /// which is passed through as-is — a deliberately colourless accent gets the
    /// red end of the wheel rather than a crash or a special case.
    var hueComponent: Double {
        let platform = PlatformColor(self)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        #if canImport(UIKit)
        platform.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        #else
        (platform.usingColorSpace(.sRGB) ?? platform)
            .getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        #endif
        return Double(hue)
    }

    /// WCAG relative luminance (0 = black, 1 = white). Used to pick a readable
    /// foreground for an arbitrary background color — unlike the `ReaderTheme` role
    /// colors, an app accent isn't one of a few fixed cases (the user can set it to
    /// any hex via `ThemeManager.setAccent`), so contrast has to be computed from
    /// the actual chosen color rather than switched on a case.
    var relativeLuminance: Double {
        let platform = PlatformColor(self)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        #if canImport(UIKit)
        platform.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #else
        (platform.usingColorSpace(.sRGB) ?? platform).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #endif
        func channel(_ component: CGFloat) -> Double {
            let value = Double(component)
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }
}
