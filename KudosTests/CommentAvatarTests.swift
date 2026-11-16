import SwiftUI
import Testing
@testable import Kudos
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@Suite(.serialized)
struct CommentAvatarTests {
    private static let sampleNames = [
        "Alice",
        "Bob",
        "Charlie",
        "Delta_42",
        "ember-writes",
        "Fable",
        "graceful",
        "Halcyon",
        "Iris",
        "juniper",
        "Kestrel",
        "Lumen",
        "mothman",
        "Nyx",
        "Orion",
        "Pallas",
        "Quill",
        "Rowan",
        "Sage",
        "Tamsin",
        "Umber",
        "Vesper",
        "Wren",
        "Xeno",
        "Yarrow",
        "Zephyr",
        "Avery_Archive",
        "night-shift",
        "Reader_One",
        "Élodie",
        "雪",
        "✨Starlight",
        "a",
        "12345"
    ]

    @Test func sameNameProducesIdenticalTintAcrossCalls() {
        for theme in ReaderTheme.allCases {
            for name in Self.sampleNames {
                let first = CommentAvatar.tintPalette(forName: name, theme: theme)
                let second = CommentAvatar.tintPalette(forName: name, theme: theme)
                let padded = CommentAvatar.tintPalette(forName: "  \(name)\n", theme: theme)
                #expect(first == second)
                #expect(first == padded)
            }
        }
    }

    @Test func spreadOfNamesProducesVariedTintsNotJustAppAccent() {
        for theme in ReaderTheme.allCases {
            let backgrounds = Set(Self.sampleNames.map {
                CommentAvatar.tintPalette(forName: $0, theme: theme).background.hexString
            })
            #expect(backgrounds.count > 10)

            let appRed = ThemeManager.appTint(for: theme).hexString
            let foregrounds = Set(Self.sampleNames.map {
                CommentAvatar.tintPalette(forName: $0, theme: theme).foreground.hexString
            })
            #expect(foregrounds != [appRed])
        }
    }

    @Test func initialClearsMinimumContrastOnAllFourThemesAndBackgrounds() throws {
        for theme in ReaderTheme.allCases {
            let grounds = Self.themeGrounds(for: theme)
            for name in Self.sampleNames {
                let palette = CommentAvatar.tintPalette(forName: name, theme: theme)
                for (groundName, ground) in grounds {
                    let composited = try Self.composite(
                        foreground: palette.background,
                        over: ground,
                        theme: theme
                    )
                    let foreground = Self.resolve(palette.foreground, for: theme)
                    let ratio = foreground.contrastRatio(on: composited)
                    #expect(
                        ratio >= 4.5,
                        "\(name) on \(theme).\(groundName) had contrast \(ratio) (< 4.5)"
                    )
                }
            }
        }
    }

    private static func themeGrounds(for theme: ReaderTheme) -> [(String, Color)] {
        [
            ("cardBackdrop", theme.cardBackdrop),
            ("cardSurface", theme.cardSurface),
            ("contentBackdrop", theme.contentBackdrop),
            ("nestedCardSurface", theme.nestedCardSurface)
        ]
    }

    private static func resolve(_ color: Color, for theme: ReaderTheme) -> Color {
        let components = rgba(color, for: theme)
        return Color(
            red: components.red,
            green: components.green,
            blue: components.blue,
            opacity: components.alpha
        )
    }

    private static func composite(
        foreground: Color,
        over background: Color,
        theme: ReaderTheme
    ) throws -> Color {
        let fg = rgba(foreground, for: theme)
        let bg = rgba(background, for: theme)
        let alpha = fg.alpha
        return Color(
            red: bg.red * (1 - alpha) + fg.red * alpha,
            green: bg.green * (1 - alpha) + fg.green * alpha,
            blue: bg.blue * (1 - alpha) + fg.blue * alpha
        )
    }

    private struct RGBA {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
    }

    private static func rgba(_ color: Color, for theme: ReaderTheme) -> RGBA {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        #if canImport(UIKit)
        let traits = UITraitCollection(
            userInterfaceStyle: theme.colorScheme == .dark ? .dark : .light
        )
        let resolved = UIColor(color).resolvedColor(with: traits)
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #elseif canImport(AppKit)
        let appearanceName: NSAppearance.Name = theme.colorScheme == .dark ? .darkAqua : .aqua
        let appearance = NSAppearance(named: appearanceName)
        var srgb = NSColor(color)
        appearance?.performAsCurrentDrawingAppearance {
            srgb = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        }
        srgb.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #endif
        return RGBA(
            red: Double(red),
            green: Double(green),
            blue: Double(blue),
            alpha: Double(alpha)
        )
    }
}
