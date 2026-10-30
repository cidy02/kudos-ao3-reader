import SwiftUI
import Testing
@testable import Kudos

@Suite(.serialized)
struct AccentInkTests {
    @Test func legacyRedNeedsAReadableStepOnDarkPages() throws {
        // `#990000` is the pre-T-459c red, not one of the six named fills.
        let red = try #require(Color(hex: "#990000"))
        #expect(AppAccent.named(hex: "#990000") == nil)
        for theme in [ReaderTheme.dark, .oled] {
            let page = theme.cardBackdrop
            #expect(red.contrastRatio(on: page) < 4.5)
            #expect(theme.accentInk(for: red).contrastRatio(on: page) >= 4.5)
            #expect(theme.accentInk(for: red).hexString != "#EE8A93")
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
        let tint = try #require(Color(hex: "#821019"))
        for theme in [ReaderTheme.light, .sepia] {
            #expect(theme.accentInk(for: tint) == tint)
        }
    }

    @Test func legacyRedMatchesAndroidsByteRoundedWhiteMix() throws {
        let red = try #require(Color(hex: "#990000"))
        // Android readableOn: original RGB + (1 - original RGB) * step / 20f,
        // rounded to sRGB bytes by Compose Color. Dark stops at step 8; OLED at 7.
        // Named accents do not use this mix — AO3 Red's step is the fixed `#EE8A93`.
        #expect(ReaderTheme.dark.cardBackdrop.hexString == "#0B0B0D")
        #expect(ReaderTheme.dark.accentInk(for: red).hexString == "#C26666")
        #expect(ReaderTheme.oled.accentInk(for: red).hexString == "#BD5959")
        let previousDarkStep = try #require(Color(hex: "#BD5959"))
        #expect(previousDarkStep.contrastRatio(on: ReaderTheme.dark.cardBackdrop) < 4.5)
    }

    @Test func eachNamedAccentKeepsItsFillAndDarkStep() throws {
        // Literals from the Accent-Options board, not AppAccent's own fields.
        let table: [(name: String, fill: String, dark: String)] = [
            ("AO3 Red", "#821019", "#EE8A93"),
            ("Plum", "#7B2D6B", "#D88BC7"),
            ("Ink Blue", "#24508F", "#7FA6E8"),
            ("Deep Teal", "#11707A", "#5CC3CC"),
            ("Forest", "#2F6B4F", "#7CC59E"),
            ("Ochre", "#9A5B00", "#E7A84B"),
        ]
        #expect(AppAccent.all.map(\.name) == table.map(\.name))
        #expect(ThemeManager.ao3Red == "#821019")
        for row in table {
            let accent = try #require(AppAccent.all.first { $0.name == row.name })
            #expect(accent.fillHex == row.fill)
            #expect(accent.darkInkHex == row.dark)
            #expect(accent.isDefault == (row.fill == "#821019"))
            let fill = try #require(Color(hex: row.fill))
            #expect(fill.hexString == row.fill)
            #expect(AppAccent.named(hex: row.fill.lowercased())?.fillHex == row.fill)
            for theme in [ReaderTheme.dark, .oled] {
                #expect(theme.accentInk(for: fill).hexString == row.dark)
            }
            for theme in [ReaderTheme.light, .sepia] {
                #expect(theme.accentInk(for: fill).hexString == row.fill)
            }
        }
    }

    @Test func aCustomColourUsesTheReadableStep() throws {
        let custom = try #require(Color(hex: "#2468AC"))
        #expect(AppAccent.named(hex: custom.hexString) == nil)
        for theme in [ReaderTheme.dark, .oled] {
            let ink = theme.accentInk(for: custom)
            #expect(ink.hexString == custom.readable(on: theme.cardBackdrop).hexString)
            #expect(ink.contrastRatio(on: theme.cardBackdrop) >= 4.5)
        }
    }

    @MainActor @Test func subjectPalettesKeepTheirIdentityOutOfControlTint() throws {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "accentColorHex")
        defaults.removeObject(forKey: "accentColorHex")
        defer {
            if let previous {
                defaults.set(previous, forKey: "accentColorHex")
            } else {
                defaults.removeObject(forKey: "accentColorHex")
            }
        }
        let subject = try #require(Color(hex: "#356A72"))
        for theme in ReaderTheme.allCases {
            let palette = SubjectPalette(color: subject, theme: theme)
            #expect(palette.tint == ThemeManager.appTint(for: theme))
            if theme == .sepia {
                #expect(palette.tint == theme.appTint)
            } else {
                #expect(palette.tint.hexString == ThemeManager.ao3Red)
            }
        }
    }

    @MainActor @Test func themeManagerSeparatesInkFromTheExactFill() throws {
        let defaults = UserDefaults.standard
        let keys = ["appTheme", "accentColorHex"]
        let previous = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, previous) { defaults.set(value, forKey: key) }
        }
        defaults.set("#2468AC", forKey: "accentColorHex")
        let manager = ThemeManager()
        for theme in ReaderTheme.allCases {
            manager.appTheme = theme
            #expect(manager.accentInk == theme.accentInk(for: manager.effectiveTint))
            if theme == .sepia {
                #expect(manager.effectiveTint == theme.appTint)
                #expect(manager.accentInk == manager.effectiveTint)
            } else if theme == .dark || theme == .oled {
                #expect(manager.effectiveTint.hexString == "#2468AC")
                let custom = try #require(Color(hex: "#2468AC"))
                #expect(manager.accentInk.hexString == custom.readable(on: theme.cardBackdrop).hexString)
                #expect(manager.accentInk.contrastRatio(on: theme.cardBackdrop) >= 4.5)
            } else {
                #expect(manager.effectiveTint.hexString == "#2468AC")
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
        defaults.set("#356A72", forKey: "accentColorHex")
        let manager = ThemeManager()
        let heroTint = Color.purple

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
                #expect(actual.fill.hexString == "#356A72")
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
        defaults.set("#EEDDBB", forKey: "accentColorHex")
        let manager = ThemeManager()
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

    /// A chip is a control: whatever subject it sits on, its selected pill and its
    /// tinted fill are the app colour, never that subject's `accent`/`chipFill`.
    @MainActor @Test func selectedChipsTakeTheAppTintNotTheSubjectsColour() throws {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "appTheme")
        defer { defaults.set(previous, forKey: "appTheme") }
        let manager = ThemeManager()
        for theme in ReaderTheme.allCases {
            manager.appTheme = theme
            let tint = manager.effectiveTint
            // A teal fandom: nowhere near AO3 red or Sepia's brown.
            let subject = SubjectPalette(hue: 0.5, theme: theme)
            let tintPixel = try renderedPixels(tint.frame(width: 1, height: 1)).pixel(x: 0, y: 0)
            let subjectPixel = try renderedPixels(subject.accent.frame(width: 1, height: 1)).pixel(x: 0, y: 0)
            #expect(tintPixel != subjectPixel)

            func rendered(_ style: SubjectChip.Style) throws -> AccentRenderedPixels {
                try renderedPixels(
                    SubjectChip(text: "All", style: style, palette: subject)
                        .fixedSize()
                        .accentTint(tint, on: theme)
                        .background(theme.cardBackdrop)
                        .environment(manager)
                        .environment(\.colorScheme, theme.colorScheme)
                )
            }

            let pill = try rendered(.pill(isSelected: true))
            #expect(pill.pixel(x: pill.width / 2, y: 2) == tintPixel)

            // The tinted chip is the app tint at the theme's chip strength over the page.
            let strength = theme.isDarkFamily ? 0.24 : 0.16
            let expected = try renderedPixels(
                tint.opacity(strength).frame(width: 1, height: 1).background(theme.cardBackdrop)
            ).pixel(x: 0, y: 0)
            let tinted = try rendered(.tinted)
            let actual = tinted.pixel(x: tinted.width / 2, y: 2)
            for channel in 0 ..< 3 {
                #expect(abs(Int(actual[channel]) - Int(expected[channel])) <= 2)
            }
            let oldFill = try renderedPixels(
                subject.chipFill.frame(width: 1, height: 1).background(theme.cardBackdrop)
            ).pixel(x: 0, y: 0)
            #expect(actual != oldFill)
        }
    }

    @MainActor @Test func defaultAccentIsAO3Red821019() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "accentColorHex")
        defaults.removeObject(forKey: "accentColorHex")
        defer {
            if let previous {
                defaults.set(previous, forKey: "accentColorHex")
            } else {
                defaults.removeObject(forKey: "accentColorHex")
            }
        }
        let manager = ThemeManager()
        #expect(manager.accentHex == "#821019")
        #expect(defaults.string(forKey: "accentColorHex") == nil)
        manager.appTheme = .light
        #expect(manager.effectiveTint.hexString == "#821019")
    }

    @MainActor @Test func storedLegacyRedIsReadAsAO3RedAndNotRewritten() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "accentColorHex")
        defer {
            if let previous {
                defaults.set(previous, forKey: "accentColorHex")
            } else {
                defaults.removeObject(forKey: "accentColorHex")
            }
        }
        defaults.set("#990000", forKey: "accentColorHex")
        let manager = ThemeManager()
        // The picker selects AppAccent.named(hex: accentHex).
        let selected = AppAccent.named(hex: manager.accentHex)
        #expect(manager.accentHex == "#821019")
        #expect(selected?.name == "AO3 Red")
        #expect(selected?.fillHex == "#821019")
        #expect(defaults.string(forKey: "accentColorHex") == "#990000")
        manager.appTheme = .light
        #expect(manager.effectiveTint.hexString == "#821019")
        #expect(ThemeManager.appTint(for: .light).hexString == "#821019")
        #expect(defaults.string(forKey: "accentColorHex") == "#990000")
    }

    @Test func presentAccentIsCapturedAndApplied() throws {
        let suite = "AccentInkTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("#112233", forKey: "accentColorHex")
        var settings = KudosBackupSettings.capture(defaults: defaults)
        #expect(settings.accentColorHex == "#112233")
        let data = try JSONEncoder().encode(settings)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["accentColorHex"] as? String == "#112233")

        defaults.set("#445566", forKey: "accentColorHex")
        settings.apply(to: defaults)
        #expect(defaults.string(forKey: "accentColorHex") == "#112233")
    }

    @Test func applyWritesPlumAndACustomHex() throws {
        let suite = "AccentInkTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        for chosen in ["#7B2D6B", "#2468AC"] {
            defaults.set("#111111", forKey: "accentColorHex")
            var settings = KudosBackupSettings.capture(defaults: defaults)
            settings.accentColorHex = chosen
            settings.apply(to: defaults)
            #expect(defaults.string(forKey: "accentColorHex") == chosen)
        }
    }

    @Test func absentAccentLeavesTheLocalValue() throws {
        let suite = "AccentInkTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("#445566", forKey: "accentColorHex")
        let captured = KudosBackupSettings.capture(defaults: defaults)
        let data = try JSONEncoder().encode(captured)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "accentColorHex")
        let missing = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(KudosBackupSettings.self, from: missing)
        #expect(decoded.accentColorHex == nil)
        decoded.apply(to: defaults)
        #expect(defaults.string(forKey: "accentColorHex") == "#445566")

        object["accentColorHex"] = NSNull()
        let nullKey = try JSONSerialization.data(withJSONObject: object)
        let fromNull = try JSONDecoder().decode(KudosBackupSettings.self, from: nullKey)
        #expect(fromNull.accentColorHex == nil)
        fromNull.apply(to: defaults)
        #expect(defaults.string(forKey: "accentColorHex") == "#445566")
    }

    @Test func applySkipsLegacyUnchosenRed() throws {
        let suite = "AccentInkTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        for incoming in ["#990000", "#990000".lowercased()] {
            defaults.set("#7B2D6B", forKey: "accentColorHex")
            var settings = KudosBackupSettings.capture(defaults: defaults)
            settings.accentColorHex = incoming
            settings.apply(to: defaults)
            #expect(defaults.string(forKey: "accentColorHex") == "#7B2D6B")
        }
    }

    @Test func captureOmitsTheAccentKeyWhenNothingIsStored() throws {
        let suite = "AccentInkTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.removeObject(forKey: "accentColorHex")
        let settings = KudosBackupSettings.capture(defaults: defaults)
        #expect(settings.accentColorHex == nil)
        let data = try JSONEncoder().encode(settings)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["accentColorHex"] == nil)
    }

    @Test func folderSyncRestoreFromAnUnchosenDeviceLeavesLocalPlum() throws {
        let remoteName = "AccentInkTests.remote.\(UUID().uuidString)"
        let remote = try #require(UserDefaults(suiteName: remoteName))
        defer { remote.removePersistentDomain(forName: remoteName) }
        remote.removeObject(forKey: "accentColorHex")
        let captured = KudosBackupSettings.capture(defaults: remote)
        let data = try JSONEncoder().encode(captured)
        let decoded = try JSONDecoder().decode(KudosBackupSettings.self, from: data)
        #expect(decoded.accentColorHex == nil)

        let localName = "AccentInkTests.local.\(UUID().uuidString)"
        let local = try #require(UserDefaults(suiteName: localName))
        defer { local.removePersistentDomain(forName: localName) }
        local.set("#7B2D6B", forKey: "accentColorHex")
        // FolderSyncService.restore ends in KudosBackupSettings.apply.
        decoded.apply(to: local)
        #expect(local.string(forKey: "accentColorHex") == "#7B2D6B")
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
