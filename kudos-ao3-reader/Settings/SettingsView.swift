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
    @Environment(AO3AuthService.self) private var auth
    @Query(sort: \CustomFont.dateAdded) private var customFonts: [CustomFont]
    @Query(sort: \SavedWork.dateAdded) private var works: [SavedWork]
    @Query(sort: \Bookmark.dateAdded) private var bookmarks: [Bookmark]
    @Query(sort: \ReadingQueue.sortOrder) private var readingQueues: [ReadingQueue]

    @AppStorage("readerFontID") private var fontID: String = "system"
    @AppStorage("readerMode") private var readingMode: ReadingMode = .scroll
    @AppStorage("readerTwoPage") private var twoPageEnabled = false
    @AppStorage("confirmBeforeDelete") private var confirmBeforeDelete = true
    @AppStorage("hideMatureContent") private var hideMatureContent = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure
    @AppStorage("requireBiometricToReveal") private var requireBiometric = false
    @AppStorage("autoPreserveSmallSeriesOnSaveForLater")
    private var autoPreserveSmallSeriesOnSaveForLater = false
    @AppStorage("autoPreserveSeriesWorkThreshold")
    private var autoPreserveSeriesWorkThreshold = 5

    @State private var importing = false
    @State private var showCustomize = false
    @State private var showAO3Login = false
    @State private var showAbout = false
    @State private var exportingBackup = false
    @State private var importingBackup = false
    @State private var importingEPUB = false
    @State private var isImportingEPUB = false
    @State private var epubImportProgress: String?
    @State private var showImportConfirmation = false
    @State private var showSavedWorkMigrationConfirmation = false
    @State private var isMigratingSavedWorks = false
    @State private var savedWorkMigrationProgress: String?
    @State private var backupDocument: KudosBackupDocument?
    @State private var pendingBackup: KudosBackupContents?
    @State private var backupNotice: BackupNotice?
    @State private var epubNotice: BackupNotice?

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

    private var legacySavedWorksForQueueMigration: [SavedWork] {
        works.filter { $0.isSaved && !$0.isQueuedForLater }
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
    private var accentBinding: Binding<Color> {
        Binding(get: { themeManager.accentColor }, set: { themeManager.setAccent($0) })
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
                    switch auth.status {
                    case .restoring:
                        // Restoring the AO3 session — show the shape of the signed-in row.
                        SkeletonListRow(width: 96, trailingWidth: 120)

                    case .signedIn(let username):
                        LabeledContent {
                            Text(username)
                        } label: {
                            Label("Signed In", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }

                        Button(role: .destructive) {
                            Task { await auth.logout() }
                        } label: {
                            Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }

                    case .signedOut, .signingIn, .usingFallback:
                        Button {
                            showAO3Login = true
                        } label: {
                            Label("Log In to AO3…", systemImage: "person.badge.key")
                        }
                    }
                } header: {
                    Text("AO3 Account")
                } footer: {
                    if let notice = auth.noticeMessage {
                        Text(notice)
                    } else {
                        Text("A login enables future synced bookmarks, history, "
                             + "subscriptions, kudos, comments, and restricted works.")
                    }
                }

                Section {
                    themePicker("App Theme", selection: appThemeBinding)
                    Toggle("Match App & Reader Theme", isOn: matchThemeBinding)
                    if !themeManager.matchAppAndReader {
                        themePicker("Reader Theme", selection: readerThemeBinding)
                    }
                    ColorPicker("Accent Color", selection: accentBinding, supportsOpacity: false)
                    Button("Reset to AO3 Red") { themeManager.resetAccent() }
                        .disabled(themeManager.accentHex.caseInsensitiveCompare(ThemeManager.ao3Red) == .orderedSame)
                } header: {
                    Text("Theme")
                } footer: {
                    Text(themeManager.matchAppAndReader
                        ? "Light, Sepia, or Dark across the whole app. The reader uses the same theme."
                        : "The app and reader use separate themes.")
                    + Text(" The accent colour applies in Light and Dark; Sepia keeps its warm tint.")
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

                BackupSettingsSection(
                    onExport: exportBackup,
                    onImport: { importingBackup = true }
                )

                EPUBImportSettingsSection(
                    isImporting: isImportingEPUB,
                    progressText: epubImportProgress,
                    onImport: { importingEPUB = true }
                )

                Section {
                    NavigationLink {
                        ReadingQueueStorageView()
                    } label: {
                        Label("Queue Storage", systemImage: "externaldrive")
                    }

                    Toggle(
                        "Auto-preserve small series",
                        isOn: $autoPreserveSmallSeriesOnSaveForLater
                    )
                    Stepper(
                        "Series limit: \(autoPreserveSeriesWorkThreshold)",
                        value: $autoPreserveSeriesWorkThreshold,
                        in: 2...25
                    )
                    .disabled(!autoPreserveSmallSeriesOnSaveForLater)

                    if !legacySavedWorksForQueueMigration.isEmpty {
                        Button {
                            showSavedWorkMigrationConfirmation = true
                        } label: {
                            Label("Add Saved Works to Saved for Later", systemImage: "arrow.right.doc.on.clipboard")
                        }
                        .disabled(isMigratingSavedWorks)
                    }

                    if isMigratingSavedWorks {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(savedWorkMigrationProgress ?? "Updating Saved for Later…")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Reading Queues")
                } footer: {
                    Text("Saved for Later keeps a local EPUB. Series preservation asks first "
                         + "unless this option is enabled and the series is within the limit.")
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
                            ? "Mature and Explicit works are hidden from your Library, "
                                + "History, and Favorites until you reveal them."
                            : "Mature and Explicit works are blurred in your Library, "
                                + "History, and Favorites until you tap to reveal them.")
                        : "Mature and Explicit works are shown normally.")
                }

                Section {
                    Button {
                        showAbout = true
                    } label: {
                        Label("About Kudos", systemImage: "info.circle")
                    }
                }
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
        .fileExporter(
            isPresented: $exportingBackup,
            document: backupDocument,
            contentType: .kudosBackup,
            defaultFilename: "Kudos Backup \(Self.backupDateFormatter.string(from: Date()))"
        ) { result in
            switch result {
            case .success:
                backupNotice = BackupNotice(
                    title: "Backup Exported",
                    message: "\(works.count.formatted()) Library records were included."
                )
            case .failure(let error):
                backupNotice = BackupNotice(
                    title: "Couldn't Export Backup",
                    message: error.localizedDescription
                )
            }
            backupDocument = nil
        }
        .fileImporter(
            isPresented: $importingBackup,
            allowedContentTypes: [.kudosBackup],
            allowsMultipleSelection: false
        ) { result in
            importBackup(result)
        }
        .fileImporter(
            isPresented: $importingEPUB,
            allowedContentTypes: [Self.epubContentType],
            allowsMultipleSelection: true
        ) { result in
            importEPUBSelection(result)
        }
        .confirmationDialog(
            "Import this backup?",
            isPresented: $showImportConfirmation,
            titleVisibility: .visible
        ) {
            Button("Import and Merge") { restorePendingBackup() }
            Button("Cancel", role: .cancel) { pendingBackup = nil }
        } message: {
            if let backup = pendingBackup {
                Text(
                    "This backup contains \(backup.manifest.works.count) Library records, "
                        + "\(backup.manifest.bookmarks.count) saved links, and "
                        + "\(backup.manifest.fonts.count) custom fonts. Existing items won't "
                        + "be deleted."
                )
            }
        }
        .confirmationDialog(
            "Add saved works to Saved for Later?",
            isPresented: $showSavedWorkMigrationConfirmation,
            titleVisibility: .visible
        ) {
            Button(savedWorkMigrationButtonTitle) {
                Task { await migrateLegacySavedWorksToSavedForLater() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Kudos will add existing saved works to the native Saved for Later queue. "
                    + "It keeps their current saved state and preserves EPUBs one at a time."
            )
        }
        .alert(item: $backupNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert(item: $epubNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
        #if os(iOS)
        .sheet(isPresented: $showCustomize) {
            CustomizeThemeView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        #endif
        .sheet(isPresented: $showAO3Login) {
            AO3LoginView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAbout) {
            NavigationStack { AboutView() }
        }
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

    // MARK: EPUB import

    private func importEPUBSelection(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard !urls.isEmpty else { return }
            Task { await importEPUBs(urls) }
        } catch {
            guard !error.isUserCancellation else {
                return
            }
            epubNotice = BackupNotice(
                title: "Couldn't Import EPUB",
                message: error.localizedDescription
            )
        }
    }

    @MainActor
    private func importEPUBs(_ urls: [URL]) async {
        isImportingEPUB = true
        epubImportProgress = nil
        defer {
            isImportingEPUB = false
            epubImportProgress = nil
        }

        var summary = EPUBImportNoticeSummary()
        for (index, url) in urls.enumerated() {
            epubImportProgress = "Importing \(index + 1) of \(urls.count)…"
            let accessed = url.startAccessingSecurityScopedResource()
            do {
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let outcome = try await importUserEPUB(url, into: context)
                summary.record(outcome)
            } catch {
                summary.recordFailure(fileName: url.lastPathComponent, message: error.localizedDescription)
            }
        }

        epubNotice = BackupNotice(title: summary.title, message: summary.message)
    }

    // MARK: Backup export / import

    private func exportBackup() {
        do {
            backupDocument = try KudosBackupService.makeDocument(
                works: works,
                bookmarks: bookmarks,
                fonts: customFonts,
                readingQueues: readingQueues
            )
            exportingBackup = true
        } catch {
            backupNotice = BackupNotice(
                title: "Couldn't Create Backup",
                message: error.localizedDescription
            )
        }
    }

    private func importBackup(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            pendingBackup = try KudosBackupContents.read(from: url)
            showImportConfirmation = true
        } catch {
            backupNotice = BackupNotice(
                title: "Couldn't Read Backup",
                message: error.localizedDescription
            )
        }
    }

    private func restorePendingBackup() {
        guard let backup = pendingBackup else { return }
        pendingBackup = nil
        do {
            let summary = try KudosBackupService.restore(backup, into: context)
            applyRestoredTheme(backup.manifest.settings)
            backupNotice = BackupNotice(
                title: "Backup Imported",
                message: "Merged \(summary.works) Library records, "
                    + "\(summary.bookmarks) saved links, and \(summary.fonts) custom fonts."
            )
        } catch {
            backupNotice = BackupNotice(
                title: "Couldn't Import Backup",
                message: error.localizedDescription
            )
        }
    }

    private func applyRestoredTheme(_ settings: KudosBackupSettings) {
        themeManager.matchAppAndReader = false
        themeManager.appTheme = ReaderTheme(rawValue: settings.appTheme) ?? .light
        themeManager.readerTheme = ReaderTheme(rawValue: settings.readerTheme) ?? .light
        themeManager.accentHex = settings.accentColorHex
        themeManager.matchAppAndReader = settings.matchAppReaderTheme
    }

    private var savedWorkMigrationButtonTitle: String {
        let count = legacySavedWorksForQueueMigration.count
        return "Add \(count) Work\(count == 1 ? "" : "s")"
    }

    @MainActor
    private func migrateLegacySavedWorksToSavedForLater() async {
        let candidates = legacySavedWorksForQueueMigration
        guard !candidates.isEmpty, !isMigratingSavedWorks else { return }

        isMigratingSavedWorks = true
        savedWorkMigrationProgress = nil
        defer {
            isMigratingSavedWorks = false
            savedWorkMigrationProgress = nil
        }

        for (index, work) in candidates.enumerated() {
            savedWorkMigrationProgress = "Updating \(index + 1) of \(candidates.count)…"
            _ = await ReadingQueueService.addToSavedForLater(work, in: context)
        }

        backupNotice = BackupNotice(
            title: "Saved for Later Updated",
            message: "Added \(candidates.count.formatted()) saved work"
                + "\(candidates.count == 1 ? "" : "s") to Saved for Later."
        )
    }

    private struct BackupNotice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private static let backupDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let epubContentType: UTType = {
        UTType(filenameExtension: "epub")
            ?? UTType(importedAs: "org.idpf.epub-container", conformingTo: .data)
    }()
}

struct BackupSettingsSection: View {
    let onExport: () -> Void
    let onImport: () -> Void

    var body: some View {
        Section {
            Button(action: onExport) {
                Label("Export Backup…", systemImage: "square.and.arrow.up")
            }
            Button(action: onImport) {
                Label("Import Backup…", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("Backup")
        } footer: {
            Text("Backups include Library records, Reading Queues, preserved EPUBs, "
                 + "User Tags, saved links, custom fonts, and app settings. Import "
                 + "merges without deleting items already on this device. AO3 sessions "
                 + "and passwords are never included.")
        }
    }
}

struct EPUBImportSettingsSection: View {
    let isImporting: Bool
    let progressText: String?
    let onImport: () -> Void

    var body: some View {
        Section {
            Button(action: onImport) {
                Label("Import EPUB", systemImage: "doc.badge.plus")
            }
            .disabled(isImporting)
            .accessibilityLabel("Import EPUB")

            if isImporting {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(progressText ?? "Importing EPUB…")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("EPUB")
        } footer: {
            Text("Import AO3 EPUB files into your local Library. Files are copied "
                 + "into Kudos storage and remain readable offline.")
        }
    }
}

private struct EPUBImportNoticeSummary {
    var imported = 0
    var restored = 0
    var duplicates = 0
    var failures: [(fileName: String, message: String)] = []

    var title: String {
        failures.isEmpty ? "EPUB Import Complete" : "EPUB Import Finished"
    }

    var message: String {
        var parts: [String] = []
        if imported > 0 { parts.append("Imported \(imported.formatted()).") }
        if restored > 0 {
            parts.append("Restored \(restored.formatted()) existing Library file\(restored == 1 ? "" : "s").")
        }
        if duplicates > 0 {
            parts.append("Skipped \(duplicates.formatted()) duplicate\(duplicates == 1 ? "" : "s").")
        }
        if failures.isEmpty {
            return parts.isEmpty ? "No EPUB files were selected." : parts.joined(separator: " ")
        }
        let failureText = failures.prefix(3)
            .map { "\($0.fileName): \($0.message)" }
            .joined(separator: "\n")
        let extra = failures.count > 3 ? "\n…and \(failures.count - 3) more." : ""
        return (parts.isEmpty ? "No EPUBs were imported." : parts.joined(separator: " "))
            + "\n\n" + failureText + extra
    }

    mutating func record(_ outcome: UserEPUBImportOutcome) {
        switch outcome {
        case .imported:
            imported += 1
        case .restored:
            restored += 1
        case .duplicate:
            duplicates += 1
        }
    }

    mutating func recordFailure(fileName: String, message: String) {
        failures.append((fileName, message))
    }
}

private extension Error {
    var isUserCancellation: Bool {
        let error = self as NSError
        return error.domain == NSCocoaErrorDomain
            && error.code == CocoaError.Code.userCancelled.rawValue
    }
}
