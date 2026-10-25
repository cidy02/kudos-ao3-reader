import SwiftUI
import Testing
@testable import Kudos

@Suite(.serialized)
struct AccentInkTests {
    @Test func ao3RedReadsOnBothDarkPages() throws {
        let red = try #require(Color(hex: "#990000"))
        for theme in [ReaderTheme.dark, .oled] {
            let page = theme.cardBackdrop
            #expect(red.contrastRatio(on: page) < 4.5)
            #expect(theme.accentInk(for: red).contrastRatio(on: page) >= 4.5)
            #expect(SubjectPalette.controlColor(red, on: theme) == red)
        }
    }

    @Test func anAlreadyReadableColourIsReturnedUnchanged() {
        let readable = Color.white
        for theme in [ReaderTheme.dark, .oled] {
            #expect(readable.readable(on: theme.cardBackdrop) == readable)
            #expect(theme.accentInk(for: readable) == readable)
        }
    }

    @Test func lightAndSepiaKeepTheTintItself() throws {
        let tint = try #require(Color(hex: "#990000"))
        for theme in [ReaderTheme.light, .sepia] {
            #expect(theme.accentInk(for: tint) == tint)
        }
    }

    @Test func ao3RedMatchesAndroidsByteRoundedWhiteMix() throws {
        let red = try #require(Color(hex: "#990000"))
        // Android readableOn: original RGB + (1 - original RGB) * step / 20f,
        // rounded to sRGB bytes by Compose Color. Dark stops at step 8; OLED at 7.
        #expect(ReaderTheme.dark.cardBackdrop.hexString == "#0B0B0D")
        #expect(ReaderTheme.dark.accentInk(for: red).hexString == "#C26666")
        #expect(ReaderTheme.oled.accentInk(for: red).hexString == "#BD5959")
        let previousDarkStep = try #require(Color(hex: "#BD5959"))
        #expect(previousDarkStep.contrastRatio(on: ReaderTheme.dark.cardBackdrop) < 4.5)
    }

    @MainActor @Test func themeManagerSeparatesInkFromTheExactFill() throws {
        let defaults = UserDefaults.standard
        let keys = ["appTheme", "accentColorHex"]
        let previous = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, previous) { defaults.set(value, forKey: key) }
        }
        let manager = ThemeManager()
        manager.accentHex = "#990000"
        for theme in ReaderTheme.allCases {
            manager.appTheme = theme
            #expect(manager.accentInk == theme.accentInk(for: manager.effectiveTint))
            if theme == .dark || theme == .oled {
                #expect(manager.effectiveTint.hexString == "#990000")
                #expect(manager.accentInk.contrastRatio(on: theme.cardBackdrop) >= 4.5)
            } else {
                #expect(manager.accentInk == manager.effectiveTint)
            }
        }
    }

    #if os(iOS)
    @MainActor @Test func ao3FilterRootKeepsTheScopeAccentOutsideItsNavigationStack() {
        let panel = AO3FilterPanel(
            filters: .constant(AO3SearchFilters()), canReset: false,
            onApply: {}, onReset: {}
        )
        // Inspect only the root modifier chain, not the stack's lazy pages.
        // The rendering test below checks the modifier's ink/fill behavior.
        var root: Any = panel.body
        var hasScopeAccent = false
        while true {
            let children = Mirror(reflecting: root).children
            if children.contains(where: { $0.label == "modifier" && $0.value is ScopeSurfaceAccent }) {
                hasScopeAccent = true
                break
            }
            guard let content = children.first(where: { $0.label == "content" }) else { break }
            root = content.value
        }
        #expect(hasScopeAccent)
    }

    @MainActor @Test func sectionFiltersChooseAppAccentOverAnInheritedHeroAccent() throws {
        let defaults = UserDefaults.standard
        let keys = ["appTheme", "accentColorHex"]
        let previous = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, previous) { defaults.set(value, forKey: key) }
        }
        defaults.removeObject(forKey: "accentColorHex")
        let manager = ThemeManager()
        #expect(manager.accentHex == "#990000")
        let heroTint = Color.purple

        for accent in ["#990000", "#356A72"] {
            manager.accentHex = accent
            for theme in ReaderTheme.allCases {
                manager.appTheme = theme
                var received: (fill: Color, ink: Color)?
                let probe = SectionFilterAccentProbe { received = ($0, $1) }
                    .modifier(ScopeSurfaceAccent())
                    .accentTint(heroTint, on: theme)
                    .environment(manager)
                _ = ImageRenderer(content: Color.clear.frame(width: 1, height: 1)).cgImage
                let renderer = ImageRenderer(content: probe)
                _ = renderer.cgImage

                let actual = try #require(received)
                #expect(actual.fill == manager.effectiveTint)
                #expect(actual.ink == manager.accentInk)
                #expect(actual.fill != heroTint)
                if theme == .sepia {
                    #expect(actual.fill == theme.appTint)
                } else {
                    #expect(actual.fill.hexString == accent)
                }
            }
        }
    }

    @MainActor @Test func selectedPillsRenderTheExactTintAndItsContrastingLabel() throws {
        let defaults = UserDefaults.standard
        let keys = ["appTheme", "accentColorHex"]
        let previous = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, previous) { defaults.set(value, forKey: key) }
        }
        let manager = ThemeManager()
        for accent in ["#990000", "#EEDDBB"] {
            manager.accentHex = accent
            for theme in ReaderTheme.allCases {
                manager.appTheme = theme
                for usePalette in [true, false] {
                    let tint = manager.effectiveTint
                    let expected = try renderedPixels(tint.frame(width: 1, height: 1))
                        .pixel(x: 0, y: 0)
                    let label = try renderedPixels(ThemeManager.label(on: tint).frame(width: 1, height: 1))
                        .pixel(x: 0, y: 0)
                    for size in [DynamicTypeSize.large, .accessibility5] {
                        let pill = SubjectChip(
                            text: "All", style: .pill(isSelected: true),
                            palette: usePalette ? manager.scopePalette : nil
                        )
                        .fixedSize()
                        .dynamicTypeSize(size)
                        .accentTint(tint, on: theme)
                        .environment(manager)
                        .environment(\.colorScheme, theme.colorScheme)
                        let pixels = try renderedPixels(pill)
                        #expect(pixels.pixel(x: pixels.width / 2, y: 2) == expected)
                        #expect(pixels.countContrastingInkPixels(on: expected, toward: label) > 4)
                    }
                }
            }
        }
    }

    @MainActor @Test func worksFilterHeaderGroundIsSepiaAndOtherThemesKeepTheirGround() throws {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "appTheme")
        defer { defaults.set(previous, forKey: "appTheme") }
        let manager = ThemeManager()
        let inheritedGround = Color(red: 1, green: 0, blue: 1)
        for theme in ReaderTheme.allCases {
            manager.appTheme = theme
            let header = Color.clear.frame(width: 40, height: 40)
                .modifier(WorksFilterSheetGround())
                .background(inheritedGround)
                .environment(manager)
            let pixels = try renderedPixels(header)
            let ground = theme == .sepia ? theme.cardBackdrop : inheritedGround
            let expected = try renderedPixels(ground.frame(width: 1, height: 1))
            #expect(pixels.pixel(x: 20, y: 20) == expected.pixel(x: 0, y: 0))
        }
    }

    @MainActor @Test func bugReportLabelDimsBothRolesOnlyWhenDisabled() throws {
        for theme in ReaderTheme.allCases {
            for enabled in [true, false] {
                // Solid shapes stand in for the label's text and symbol so both
                // roles can be sampled without depending on font rasterization.
                let label = Label {
                    Rectangle().frame(width: 12, height: 12)
                } icon: {
                    Rectangle().frame(width: 12, height: 12)
                }
                .labelStyle(BugReportContinueLabelStyle())
                .fixedSize()
                .environment(\.isEnabled, enabled)
                .accentTint(Color.red, on: theme)
                .background(theme.cardSurface)
                .environment(\.colorScheme, theme.colorScheme)
                let pixels = try renderedPixels(label)
                let titleInk = enabled ? Color.primary : .secondary
                let iconInk = enabled ? theme.accentInk(for: .red) : Color.secondary
                let title = try renderedPixels(titleInk.frame(width: 1, height: 1)
                    .background(theme.cardSurface).environment(\.colorScheme, theme.colorScheme))
                let icon = try renderedPixels(iconInk.frame(width: 1, height: 1)
                    .background(theme.cardSurface).environment(\.colorScheme, theme.colorScheme))
                #expect(pixels.pixel(x: 3, y: pixels.height / 2) == icon.pixel(x: 0, y: 0))
                #expect(pixels.pixel(x: pixels.width - 4, y: pixels.height / 2) == title.pixel(x: 0, y: 0))
            }
        }
    }
    #endif
}

#if os(iOS)
private struct SectionFilterAccentProbe: View {
    @Environment(\.accentFill) private var fill
    @Environment(\.accentInk) private var ink
    let report: (Color, Color) -> Void

    var body: some View {
        report(fill, ink)
        return Color.clear.frame(width: 1, height: 1)
    }
}

private struct AccentRenderedPixels {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    func pixel(x: Int, y: Int) -> [UInt8] {
        let offset = (y * width + x) * 4
        return Array(bytes[offset ..< offset + 4])
    }

    func countContrastingInkPixels(on fill: [UInt8], toward label: [UInt8]) -> Int {
        let fillSum = fill.prefix(3).reduce(0) { $0 + Int($1) }
        let labelSum = label.prefix(3).reduce(0) { $0 + Int($1) }
        // Small glyphs can be entirely antialiased: require visible ink in the
        // correct direction, not a font-dependent number of pure-white pixels.
        return stride(from: 0, to: bytes.count, by: 4).filter { offset in
            guard bytes[offset + 3] == 255 else { return false }
            let sum = (0..<3).reduce(0) { $0 + Int(bytes[offset + $1]) }
            return labelSum > fillSum ? sum > fillSum + 60 : sum < fillSum - 60
        }.count
    }
}

@MainActor
private func renderedPixels(_ content: some View) throws -> AccentRenderedPixels {
    // ImageRenderer's first pass can be blank. Warm it before taking the image.
    _ = ImageRenderer(content: Color.clear.frame(width: 1, height: 1)).cgImage
    let renderer = ImageRenderer(content: content)
    renderer.scale = 1
    _ = renderer.cgImage
    let image = try #require(renderer.cgImage)
    let width = image.width
    let height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    try bytes.withUnsafeMutableBytes { buffer in
        let context = try #require(CGContext(
            data: buffer.baseAddress, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
    }
    return AccentRenderedPixels(width: width, height: height, bytes: bytes)
}
#endif
