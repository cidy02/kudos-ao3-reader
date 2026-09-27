import SwiftUI

// Settings › Reading: Appearance, Font, Reader, Listening. Font, Reader and
// Listening are the same sections the reader's options sheet shows
// (`ReaderOptionsForm`), so the two can never drift apart.

/// App-wide theme, accent and text size — moved as-is from the old single page's
/// Theme section. The reader's own theme picker stays in the reader's sheet.
struct SettingsAppearancePage: View {
    @Environment(ThemeManager.self) private var themeManager
    @State private var showCustomize = false

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

    private var accentBinding: Binding<Color> {
        Binding(get: { themeManager.accentColor }, set: { themeManager.setAccent($0) })
    }

    var body: some View {
        SettingsPageForm(route: .appearance) {
            Section {
                ReaderThemePicker(title: "App Theme", selection: appThemeBinding)
                Toggle("Match App & Reader Theme", isOn: matchThemeBinding)
                if !themeManager.matchAppAndReader {
                    ReaderThemePicker(title: "Reader Theme", selection: readerThemeBinding)
                }
                ColorPicker("Accent Color", selection: accentBinding, supportsOpacity: false)
                Button("Reset to AO3 Red") { themeManager.resetAccent() }
                    .disabled(themeManager.accentHex.caseInsensitiveCompare(ThemeManager.ao3Red)
                        == .orderedSame)
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
                Text((themeManager.matchAppAndReader
                        ? "Light, Sepia, Dark, or OLED across the whole app. The reader uses the same theme."
                        : "The app and reader use separate themes.")
                    + " The accent colour applies in Light, Dark, and OLED; Sepia keeps its warm tint.")
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showCustomize) {
            CustomizeThemeView()
                .environment(themeManager)
                .tint(themeManager.effectiveTint)
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
    var body: some View {
        SettingsPageForm(route: .listening) {
            ReaderSpeechSettingsSection()
        }
    }
}
#endif
