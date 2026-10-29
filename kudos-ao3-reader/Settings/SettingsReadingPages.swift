import SwiftUI

// Settings › Reading: Appearance, Font, Reader, Listening. Font, Reader and
// Listening are the same sections the reader's options sheet shows
// (`ReaderOptionsForm`), so the two can never drift apart.

/// App-wide theme and text size. The reader's own theme picker stays in the
/// reader's sheet; app controls use the fixed AO3-red brand colour.
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
                Text((themeManager.matchAppAndReader
                        ? "Choose Light, Sepia, Dark, or OLED for Kudos and the reader."
                        : "You can choose different themes for Kudos and the reader.")
                    + " Controls use AO3 red; Sepia keeps its warm tint.")
            }
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
