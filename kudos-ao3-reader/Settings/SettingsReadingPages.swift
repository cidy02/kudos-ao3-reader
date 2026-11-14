import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// Settings › Reading: Appearance, Font, Reader, Listening. Font, Reader and
// Listening are the same sections the reader's options sheet shows
// (`ReaderOptionsForm`), so the two can never drift apart.

/// App-wide theme, accent colour, and text size. The reader's own theme picker
/// stays in the reader's sheet. Sepia keeps its warm brown for controls.
struct SettingsAppearancePage: View {
    @Environment(ThemeManager.self) private var themeManager
    @State private var showCustomize = false
    @State private var showCustomWarning = false
    @State private var customPick: Task<Void, Never>?
    @State private var pickerBridge = AccentColorPickerBridge()
    @AppStorage(WorkSymbolPlacement.storageKey) private var symbolPlacement: WorkSymbolPlacement = .defaultValue

    /// Bindings into the central ThemeManager (an @Observable in the environment).
    private var appThemeBinding: Binding<ReaderTheme> {
        Binding(get: { themeManager.appTheme }, set: { themeManager.appTheme = $0 })
    }

    private var readerThemeBinding: Binding<ReaderTheme> {
        Binding(get: { themeManager.readerTheme }, set: { themeManager.readerTheme = $0 })
    }

    private var matchThemeBinding: Binding<Bool> {
        Binding(get: { themeManager.matchAppAndReader },
                set: { themeManager.matchAppAndReader = $0 })
    }

    var body: some View {
        SettingsPageForm(route: .appearance) {
            Section {
                if !themeManager.matchAppAndReader {
                    Text("App Theme")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ThemePreviewTilePicker(selection: appThemeBinding)
                Toggle("Match App & Reader Theme", isOn: matchThemeBinding).accentFill()
                if !themeManager.matchAppAndReader {
                    Text("Reader Theme")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ThemePreviewTilePicker(selection: readerThemeBinding)
                }
                #if os(iOS)
                // Labelled like "Reader Theme" above: this slider is bound to
                // `readerFontPt`, so it sizes the reader's text, not the app's.
                // Unlabelled under a "Theme" header it read as app-wide.
                Text("Reader Text Size")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextSizeSlider()
                #endif
            } header: {
                Text("Theme")
            } footer: {
                Text(themeManager.matchAppAndReader
                    ? "Choose Light, Sepia, Dark, or OLED for Kudos and the reader."
                    : "You can choose different themes for Kudos and the reader.")
            }

            Section {
                AccentColourPicker(
                    accentHex: themeManager.accentHex,
                    onSelectNamed: { themeManager.accentHex = $0 },
                    onCustom: { showCustomWarning = true }
                )
            } header: {
                Text("Accent colour")
            } footer: {
                Text("Delete and other destructive actions stay system red with every colour. "
                    + "Sepia keeps its warm tint.")
            }

            Section {
                Picker("Work Symbols", selection: $symbolPlacement) {
                    ForEach(WorkSymbolPlacement.allCases) { placement in
                        Text(placement.title).tag(placement)
                    }
                }
            } header: {
                Text("Lists")
            } footer: {
                Text("Where work lists show the rating, category, warnings and status symbols. "
                    + "Under the Title puts them in a row under the title and gives the text the full width.")
            }
            // Backed up like the Library layout (UserDefaults, which the folder-sync
            // observer does not query), so it marks the sync folder dirty the same way.
            .onChange(of: symbolPlacement) { _, _ in
                NotificationCenter.default.post(name: .kudosSyncRelevantSettingChanged, object: nil)
            }

            #if os(iOS)
            Section {
                Button {
                    showCustomize = true
                } label: {
                    HStack {
                        Text("Customize Theme")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.secondary.opacity(0.6))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            #endif
        }
        .alert("Use a Custom Colour?", isPresented: $showCustomWarning) {
            Button("Choose a Colour") {
                let hex = themeManager.accentHex
                pickerBridge.onPick = { color in
                    let picked = color.hexString
                    guard picked.caseInsensitiveCompare(themeManager.accentHex) != .orderedSame else { return }
                    themeManager.setAccent(color)
                }
                customPick?.cancel()
                customPick = Task { @MainActor in
                    // UIKit drops a present started while this alert is still dismissing.
                    try? await Task.sleep(for: .milliseconds(450))
                    guard !Task.isCancelled else { return }
                    pickerBridge.present(initialHex: hex)
                }
            }
            Button("Keep AO3 Red", role: .cancel) {}
        } message: {
            Text("Kudos is designed around its six accent colours. They keep text readable in Light, "
                + "Sepia, Dark and OLED, and stay clear of the red used for Delete. A custom colour "
                + "may make some buttons and links harder to read.")
        }
        .onDisappear {
            customPick?.cancel()
            pickerBridge.close()
        }
        #if DEBUG
        .task { if DebugLaunchRoute.takeSheet("customizetheme") { showCustomize = true } }
        #endif
        #if os(iOS)
        .sheet(isPresented: $showCustomize) {
            CustomizeThemeView()
                .environment(themeManager)
                .accentTint(themeManager.effectiveTint, on: themeManager.appTheme)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        #endif
    }
}

/// Four tappable preview tiles (Light, Sepia, Dark, OLED) with a mock page in that theme's
/// background and text colors, the theme title, and an accentFill selection ring (board 48).
struct ThemePreviewTilePicker: View {
    @Binding var selection: ReaderTheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// VoiceOver label for a theme tile: "Light theme", etc.
    static func accessibilityLabel(for theme: ReaderTheme) -> String {
        "\(theme.title) theme"
    }

    /// Number of grid columns: 2 at accessibility sizes (2x2), 4 otherwise (1x4).
    static func columnCount(isAccessibilitySize: Bool) -> Int {
        isAccessibilitySize ? 2 : 4
    }

    private var columns: [GridItem] {
        let count = Self.columnCount(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(ReaderTheme.allCases) { theme in
                ThemePreviewTile(
                    theme: theme,
                    isSelected: selection == theme,
                    onSelect: { selection = theme }
                )
            }
        }
        .padding(.vertical, 4)
    }
}

/// An individual theme tile: mock page with proportional lines in the theme's colors,
/// the theme name below, and an accent-tinted ring when selected.
struct ThemePreviewTile: View {
    let theme: ReaderTheme
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(\.accentFill) private var accentFill
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 6) {
                ThemePreviewPageMock(theme: theme)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                isSelected ? accentFill : Color.secondary.opacity(0.3),
                                lineWidth: isSelected ? 2.5 : 0.5
                            )
                    }
                Text(theme.title)
                    .font(.footnote.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(0.8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ThemePreviewTilePicker.accessibilityLabel(for: theme))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Small mock page drawing four left-aligned text lines of varying widths (70%, 90%, 80%, 60%)
/// in the theme's own background and text colors (board 48).
struct ThemePreviewPageMock: View {
    let theme: ReaderTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            FractionalCapsule(fraction: 0.70)
                .fill(theme.textColor.opacity(0.80))
                .frame(height: 5)
            FractionalCapsule(fraction: 0.90)
                .fill(theme.textColor.opacity(0.45))
                .frame(height: 5)
            FractionalCapsule(fraction: 0.80)
                .fill(theme.textColor.opacity(0.45))
                .frame(height: 5)
            FractionalCapsule(fraction: 0.60)
                .fill(theme.textColor.opacity(0.45))
                .frame(height: 5)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(height: 88)
        .background(theme.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// A horizontal capsule shape that spans a fraction of the available width from the leading edge.
struct FractionalCapsule: Shape {
    let fraction: CGFloat

    func path(in rect: CGRect) -> Path {
        let width = max(0, rect.width * fraction)
        let lineRect = CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height)
        let radius = rect.height / 2
        return Path(roundedRect: lineRect, cornerRadius: radius)
    }
}

struct SettingsFontPage: View {
    @State private var isImportingFonts = false

    var body: some View {
        SettingsPageForm(route: .font) {
            ReaderFontSection(onAddFont: { isImportingFonts = true })
        }
        .readerFontImporter(isPresented: $isImportingFonts)
    }
}

/// Reading mode, two-page spread and keep screen awake.
struct SettingsReaderPage: View {
    var body: some View {
        SettingsPageForm(route: .reader) {
            ReaderLayoutSection()
        }
    }
}

#if os(iOS)
/// Voice, speed and pitch for the Readium read-aloud player. Developer Settings
/// stay where they were, behind their own link inside this section.
struct SettingsListeningPage: View {
    #if DEBUG
    @State private var debugPronunciations = false
    #endif

    var body: some View {
        SettingsPageForm(route: .listening) {
            ReaderSpeechSettingsSection()
        }
        #if DEBUG
        // On the page, not on the Read Aloud section that holds the Pronunciations row: the form
        // builds that section only once it scrolls into view, so at the largest text its `.task`
        // never ran and the shot stopped on this page (A88c).
        .task { if DebugLaunchRoute.takePush("pronunciations") { debugPronunciations = true } }
        .navigationDestination(isPresented: $debugPronunciations) {
            ReaderPronunciationSettingsView(onScanChapter: nil)
        }
        #endif
    }
}
#endif

/// The six named swatches plus a custom well. Each swatch is its own button,
/// with the colour's name and a selected trait, the way `SubjectChip` marks a
/// chosen pill. The custom well says "Custom colour" and never a raw hex.
private struct AccentColourPicker: View {
    let accentHex: String
    let onSelectNamed: (String) -> Void
    let onCustom: () -> Void

    /// A stored string that is not a colour is AO3 Red here. The stored string
    /// is left unchanged.
    private var shownHex: String { AppAccent.pickerHex(for: accentHex) }

    private var selectedFill: String? {
        AppAccent.named(hex: shownHex)?.fillHex
    }

    private var customHex: String? {
        AppAccent.named(hex: shownHex) == nil ? shownHex : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(AppAccent.named(hex: shownHex)?.name ?? "Custom")
                    .font(.body)
                Spacer()
                if shownHex.caseInsensitiveCompare(ThemeManager.ao3Red) == .orderedSame {
                    Text("Default")
                        .font(.subheadline)
                        .foregroundStyle(Color(hex: "#8E8E93") ?? .secondary)
                }
            }
            .accessibilityHidden(true)

            HStack(spacing: 0) {
                ForEach(AppAccent.all) { accent in
                    let selected = selectedFill == accent.fillHex
                    Button {
                        onSelectNamed(accent.fillHex)
                    } label: {
                        AccentSwatch(fillHex: accent.fillHex, selected: selected)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel(accent.name)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
                Button(action: onCustom) {
                    AccentCustomWell(selectedHex: customHex)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("Custom colour")
                .accessibilityAddTraits(customHex == nil ? [] : .isSelected)
            }
        }
    }
}

/// 32pt fill. Selected draws a 2pt ring of the fill, a 2pt gap in the row
/// colour, then the fill. The board's gap is white because its card is white.
/// Here the gap is the settings cell, so Dark, OLED and Sepia have no white halo.
private struct AccentSwatch: View {
    @Environment(ThemeManager.self) private var themeManager
    let fillHex: String
    let selected: Bool

    var body: some View {
        ZStack {
            if selected {
                Circle()
                    .strokeBorder(color, lineWidth: 2)
                    .frame(width: 40, height: 40)
                Circle()
                    .fill(gap)
                    .frame(width: 36, height: 36)
            }
            Circle()
                .fill(color)
                .frame(width: 32, height: 32)
        }
        .frame(width: 40, height: 40)
    }

    private var color: Color { Color(hex: fillHex) ?? .black }
    /// The form row these swatches sit on. Light's cell is white.
    private var gap: Color { themeManager.appTheme.cardSurface }
}

/// The (+) well. A selected custom colour rings it; the rainbow stays the well.
/// The ring's gap and the well's centre use the row colour, same as a swatch.
private struct AccentCustomWell: View {
    @Environment(ThemeManager.self) private var themeManager
    let selectedHex: String?

    var body: some View {
        ZStack {
            if let selectedHex {
                Circle()
                    .strokeBorder(Color(hex: selectedHex) ?? .black, lineWidth: 2)
                    .frame(width: 40, height: 40)
                Circle()
                    .fill(gap)
                    .frame(width: 36, height: 36)
            }
            Circle()
                .fill(AngularGradient(colors: Self.wheel, center: .center))
                .frame(width: 32, height: 32)
            Circle()
                .fill(gap)
                .frame(width: 24, height: 24)
            Image(systemName: "plus")
                .font(.caption2.weight(.bold))
                // Not `label(on:)`: on Light the gap is a dynamic system colour,
                // which resolves against the phone's scheme, not the app's.
                .foregroundStyle(themeManager.appTheme.isDarkFamily ? Color.white : Color(hex: "#1C1C1E") ?? .black)
        }
        .frame(width: 40, height: 40)
    }

    private var gap: Color { themeManager.appTheme.cardSurface }

    private static let wheel: [Color] = [
        "#F5C400", "#5FBF5F", "#5A9BE0", "#A57BD8", "#E86AA0", "#E5484D", "#F5C400"
    ].map { Color(hex: $0) ?? .gray }
}

/// Presents the system colour picker after the custom-colour warning. The iOS
/// delegate is weak, and the Mac panel does not retain its target, so the page
/// holds this object and clears it on disappear.
@MainActor
private final class AccentColorPickerBridge: NSObject {
    var onPick: (Color) -> Void = { _ in }

    #if os(iOS)
    private var picker: UIColorPickerViewController?
    #elseif os(macOS)
    /// `NSColorPanel` has setters for target and action, and no getter. The
    /// target is not retained, so this flag is how `close` knows the panel is ours.
    private var panelIsOurs = false
    #endif

    func present(initialHex: String) {
        let parts = Self.components(initialHex)
        #if os(iOS)
        let picker = UIColorPickerViewController()
        picker.supportsAlpha = false
        picker.selectedColor = UIColor(red: parts.r, green: parts.g, blue: parts.b, alpha: 1)
        picker.delegate = self
        self.picker = picker
        guard let host = Self.topViewController() else { return }
        host.present(picker, animated: true)
        #elseif os(macOS)
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.isContinuous = false
        panel.setTarget(nil)
        panel.color = NSColor(srgbRed: parts.r, green: parts.g, blue: parts.b, alpha: 1)
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panelIsOurs = true
        panel.orderFront(nil)
        #endif
    }

    func close() {
        #if os(iOS)
        picker?.dismiss(animated: false)
        picker = nil
        #elseif os(macOS)
        guard panelIsOurs else { return }
        let panel = NSColorPanel.shared
        panel.setTarget(nil)
        panel.setAction(nil)
        panel.close()
        panelIsOurs = false
        #endif
    }

    private static func components(_ hex: String) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasPrefix("#") { string.removeFirst() }
        let value = UInt64(string, radix: 16) ?? 0x821019
        return (
            CGFloat((value >> 16) & 0xFF) / 255,
            CGFloat((value >> 8) & 0xFF) / 255,
            CGFloat(value & 0xFF) / 255
        )
    }

    #if os(iOS)
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController, !presented.isBeingDismissed {
            controller = presented
        }
        return controller
    }
    #endif

    #if os(macOS)
    @objc private func colorChanged(_ sender: NSColorPanel) {
        onPick(Color(nsColor: sender.color))
    }
    #endif
}

#if os(iOS)
extension AccentColorPickerBridge: UIColorPickerViewControllerDelegate {
    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        onPick(Color(uiColor: viewController.selectedColor))
        picker = nil
    }
}
#endif
