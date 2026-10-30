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
                ReaderThemePicker(title: "App Theme", selection: appThemeBinding)
                Toggle("Match App & Reader Theme", isOn: matchThemeBinding).accentFill()
                if !themeManager.matchAppAndReader {
                    ReaderThemePicker(title: "Reader Theme", selection: readerThemeBinding)
                }
                #if os(iOS)
                Button {
                    showCustomize = true
                } label: {
                    Label("Customize Theme…", systemImage: "slider.horizontal.3")
                }
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
                    // Let the alert finish dismissing before the system picker.
                    try? await Task.sleep(for: .milliseconds(450))
                    guard !Task.isCancelled else { return }
                    pickerBridge.present(initialHex: hex)
                }
            }
            Button("Keep AO3 Red", role: .cancel) {}
        } message: {
            Text("Kudos is designed around its six accent colours. They keep text readable in Light, Sepia, Dark and OLED, and stay clear of the red used for Delete. A custom colour may make some buttons and links harder to read.")
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
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(ThemeManager.label(on: gap))
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
