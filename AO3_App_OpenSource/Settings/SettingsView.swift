import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

/// The toggleable reading options, grouped into categories. Shared between the
/// reader's inspector (quick access while reading) and the Settings page, so the
/// two always show the same controls and stay in sync via `@AppStorage`.
struct ReaderOptionsForm: View {
    /// Whether the two-page spread can take effect (the reader passes its window
    /// width; Settings has no window context, so it allows the toggle freely).
    var twoPageAvailable: Bool = true
    /// When true, also shows app-wide settings (e.g. Library) that don't belong in
    /// the reader's quick Display sheet. The Settings page opts in; the reader doesn't.
    var includeAppSettings: Bool = false

    @Environment(\.modelContext) private var context
    @Environment(ThemeManager.self) private var themeManager
    @Query(sort: \CustomFont.dateAdded) private var customFonts: [CustomFont]

    @AppStorage("readerFontID") private var fontID: String = "system"
    @AppStorage("readerMode") private var readingMode: ReadingMode = .scroll
    @AppStorage("readerTwoPage") private var twoPageEnabled = false
    @AppStorage("confirmBeforeDelete") private var confirmBeforeDelete = true
    @AppStorage("hideMatureContent") private var hideMatureContent = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure
    @AppStorage("requireBiometricToReveal") private var requireBiometric = false

    @State private var importing = false
    @State private var showCustomize = false

    /// All selectable fonts: built-ins followed by imported ones.
    private var fontOptions: [ReaderFontOption] {
        ReaderFontOption.options(customFonts: customFonts)
    }

    /// Two-page spread is offered on iPad and macOS but never on iPhone. (iPad
    /// compiles under `os(iOS)`, so this is a runtime idiom check.)
    private var twoPageSpreadAvailable: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom != .phone
        #else
        return true
        #endif
    }

    // Bindings into the central ThemeManager (an @Observable in the environment).
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

    /// A segmented Light/Sepia/Dark picker bound to the given selection.
    private func themePicker(_ title: String, selection: Binding<ReaderTheme>) -> some View {
        Picker(title, selection: selection) {
            ForEach(ReaderTheme.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelStyle(.titleOnly)
    }

    var body: some View {
        Form {
          // Group so .appThemedRows() (a .listRowBackground) reaches every section's
          // rows — it does NOT propagate from the Form container, only from a Group/
          // Section/ForEach around the rows.
          Group {
            // App-wide theme lives in the main Settings page. The reader's own theme
            // picker (below, in Appearance) is shown only inside the reader, since here
            // it's covered by this section.
            if includeAppSettings {
                Section {
                    themePicker("App Theme", selection: appThemeBinding)
                    Toggle("Match App & Reader Theme", isOn: matchThemeBinding)
                    if !themeManager.matchAppAndReader {
                        themePicker("Reader Theme", selection: readerThemeBinding)
                    }
                } header: {
                    Text("Theme")
                } footer: {
                    Text(themeManager.matchAppAndReader
                        ? "Light, Sepia, or Dark across the whole app. The reader uses the same theme."
                        : "The app and reader use separate themes.")
                }
            }

            Section("Appearance") {
                if !includeAppSettings {
                    // Inside the reader: this picks the reader theme (which re-themes
                    // the app too while App & Reader are matched).
                    themePicker("Theme", selection: readerThemeBinding)
                }

                #if os(iOS)
                Button {
                    showCustomize = true
                } label: {
                    Label("Customize Theme…", systemImage: "slider.horizontal.3")
                }
                #endif
            }

            #if os(iOS)
            Section("Text Size") {
                TextSizeSlider()
            }
            #endif

            Section {
                Picker("Layout", selection: $readingMode) {
                    ForEach(ReadingMode.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelStyle(.titleOnly)

                // Two-page spread is hidden on iPhone (no practical use); shown on
                // iPad and macOS.
                if twoPageSpreadAvailable {
                    Toggle("Two-page spread", isOn: $twoPageEnabled)
                        .disabled(readingMode != .paged || !twoPageAvailable)
                }
            } header: {
                Text("Reading")
            } footer: {
                Text(twoPageSpreadAvailable
                    ? "Two-page spread is available in Paged mode on wider windows."
                    : "Choose how pages turn while reading.")
            }

            Section("Font") {
                ForEach(fontOptions) { option in
                    Button {
                        fontID = option.id
                    } label: {
                        HStack {
                            Text(option.name).foregroundStyle(.primary)
                            if option.isCustom {
                                Image(systemName: "person.crop.circle")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if option.id == fontID {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: deleteCustomFonts)

                Button {
                    importing = true
                } label: {
                    Label("Add Font…", systemImage: "plus")
                }
            }

            if includeAppSettings {
                Section {
                    Toggle("Confirm before deleting", isOn: $confirmBeforeDelete)
                } header: {
                    Text("Library")
                } footer: {
                    Text("Ask before a swipe-to-delete removes a work from your Library.")
                }

                Section {
                    Toggle("Hide mature content", isOn: $hideMatureContent)
                    if hideMatureContent {
                        Picker("When locked", selection: $matureMode) {
                            ForEach(MaturePrivacyMode.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)

                        Toggle("Require Face ID to reveal", isOn: $requireBiometric)
                    }
                } header: {
                    Text("Privacy")
                } footer: {
                    Text(hideMatureContent
                        ? (matureMode == .hide
                            ? "Mature and Explicit works are hidden from your Library, History, and Favorites until you reveal them."
                            : "Mature and Explicit works are blurred in your Library, History, and Favorites until you tap to reveal them.")
                        : "Mature and Explicit works are shown normally.")
                }

                #if os(iOS)
                // Phase 0 exploration only: a sandboxed entry point to the
                // Readium-based reader proof-of-concept. The production reader
                // (ReaderView) is unchanged. Safe to delete with the POC.
                Section {
                    NavigationLink {
                        ReadiumPOCView()
                    } label: {
                        Label("Readium Reader (POC)", systemImage: "flask")
                    }
                } header: {
                    Text("Experimental")
                } footer: {
                    Text("Proof-of-concept reader built on the Readium toolkit. Pick a local EPUB to try it.")
                }
                #endif
            }
          }
          .appThemedRows()
        }
        .formStyle(.grouped)
        .appThemedScroll()
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.font],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { urls.forEach(importFont) }
        }
        #if os(iOS)
        .sheet(isPresented: $showCustomize) {
            CustomizeThemeView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        #endif
    }

    // MARK: Font import / delete

    private func importFont(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else { return }
        let ext = url.pathExtension.isEmpty ? "ttf" : url.pathExtension
        let fileName = "\(UUID().uuidString).\(ext)"
        let destination = Storage.fontsDirectory.appendingPathComponent(fileName)
        guard (try? data.write(to: destination)) != nil else { return }

        let font = CustomFont(name: url.deletingPathExtension().lastPathComponent, fileName: fileName)
        context.insert(font)
        try? context.save()
        fontID = font.selectionID
    }

    private func deleteCustomFonts(at offsets: IndexSet) {
        for index in offsets where index < fontOptions.count {
            let option = fontOptions[index]
            guard option.isCustom,
                  let font = customFonts.first(where: { $0.selectionID == option.id })
            else { continue }
            if fontID == font.selectionID { fontID = "system" }
            try? FileManager.default.removeItem(at: font.fileURL)
            context.delete(font)
        }
        try? context.save()
    }
}

