import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

private final class SecurityScopedURL: Sendable {
    let url: URL
    let accessed: Bool

    init(_ url: URL) {
        self.url = url
        accessed = url.startAccessingSecurityScopedResource()
    }

    deinit {
        if accessed {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

// Lint: this existing form is kept together to avoid behavior refactors.
// swiftlint:disable file_length
/// The toggleable reading options, grouped into categories. Shared between the
/// reader's inspector (quick access while reading) and the Settings page, so the
/// two always show the same controls and stay in sync via `@AppStorage`.
struct ReaderOptionsForm: View { // swiftlint:disable:this type_body_length
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
    @Query(sort: \WorkCollection.dateAdded) private var collections: [WorkCollection]
    @Query(sort: \ReadingQueue.sortOrder) private var readingQueues: [ReadingQueue]
    @Query private var syncTombstones: [SyncTombstone]
    @Query(sort: \ReadingAnnotation.createdAt) private var readingAnnotations: [ReadingAnnotation]
    @Query(sort: \SavedSearch.dateAdded, order: .reverse) private var savedSearches: [SavedSearch]

    @AppStorage("readerFontID") private var fontID: String = "system"
    @AppStorage("readerMode") private var readingMode: ReadingMode = .scroll
    @AppStorage("readerTwoPage") private var twoPageEnabled = false
    @AppStorage("confirmBeforeDelete") private var confirmBeforeDelete = true
    @AppStorage("showsZeroStats") private var showsZeroStats = true
    @AppStorage("hideMatureContent") private var hideMatureContent = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure
    @AppStorage("requireBiometricToReveal") private var requireBiometric = false
    @AppStorage("autoPreserveSmallSeriesOnSaveForLater")
    private var autoPreserveSmallSeriesOnSaveForLater = false
    @AppStorage("autoPreserveSeriesWorkThreshold")
    private var autoPreserveSeriesWorkThreshold = 5

    @State private var activeImport: FileImportKind?
    /// The kind most recently presented — only ever overwritten, never cleared — so
    /// the shared importer's completion can still route its result if dismissal
    /// already niled `activeImport`. Recorded by the `.onChange` below the importer.
    @State private var lastPresentedImport: FileImportKind?
    @State private var showCustomize = false
    @State private var showAO3Login = false
    @State private var showAbout = false
    @State private var showingBugReport = false
    @State private var exportingBackup = false
    @State private var isImportingEPUB = false
    @State private var epubImportProgress: String?
    @State private var showImportConfirmation = false
    @State private var showSavedWorkMigrationConfirmation = false
    @State private var isMigratingSavedWorks = false
    @State private var savedWorkMigrationProgress: String?
    @State private var savedWorkMigrationCompleted = 0
    @State private var savedWorkMigrationTotal = 0
    @State private var savedWorkMigrationTask: Task<Void, Never>?
    @State private var backupExportURL: URL?
    @State private var isPreparingBackupExport = false
    @State private var isImportingBackup = false
    // RC merge: the import flow below is the tombstone tree's three-mode
    // product, which holds the decoded contents. WP-A/WP-C's lazier
    // (SecurityScopedURL + manifest) pre-confirm pair is tracked as an open
    // RC fix; see the tombstone merge commit message.
    @State private var pendingBackup: KudosBackupContents?
    @State private var backupNotice: BackupNotice?
    @State private var epubNotice: BackupNotice?
    @State private var persistenceStatus = PersistenceStatusStore.snapshot()
    @State private var isPreparingPersistence = false
    @State private var folderSyncStatus = FolderSyncService.snapshot()
    @State private var isFolderSyncing = false
    @State private var showingSyncDetails = false
    @State private var showingAvailabilitySweep = false
    @State private var lastFolderSyncResult: FolderSyncResult?
    @State private var showImportModeChoice = false
    @State private var showReplaceConfirmation = false

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
        // Recently Deleted works aren't migrated into Saved for Later — queueing one
        // would resurrect a record the user explicitly deleted.
        works.filter { $0.isSaved && !$0.isQueuedForLater && !$0.isPendingDeletion }
    }

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

    /// A segmented Light/Sepia/Dark/OLED picker bound to the given selection.
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

                        case let .signedIn(username):
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
                            .disabled(themeManager.accentHex.caseInsensitiveCompare(ThemeManager.ao3Red)
                                == .orderedSame)
                    } header: {
                        Text("Theme")
                    } footer: {
                        Text((themeManager.matchAppAndReader
                                ? "Light, Sepia, Dark, or OLED across the whole app. The reader uses the same theme."
                                : "The app and reader use separate themes.")
                            + " The accent colour applies in Light, Dark, and OLED; Sepia keeps its warm tint.")
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

                #if os(iOS)
                // Voice / rate / pitch for the Readium read-aloud mini player.
                // macOS still uses the legacy WKWebView reader without TTS.
                ReaderSpeechSettingsSection()
                #endif

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
                        activeImport = .fonts
                    } label: {
                        Label("Add Font…", systemImage: "plus")
                    }
                }

                if includeAppSettings {
                    Section {
                        Toggle("Confirm before deleting", isOn: $confirmBeforeDelete)
                        Toggle("Show zero counts", isOn: $showsZeroStats)
                    } header: {
                        Text("Library")
                    } footer: {
                        Text(
                            """
                            Ask before a swipe-to-delete removes a work from your Library. \
                            Show zero counts keeps every stat on a work card in place when \
                            it is zero — turn it off to hide empty stats instead.
                            """
                        )
                    }

                    BackupSettingsSection(
                        isPreparingExport: isPreparingBackupExport,
                        isImporting: isImportingBackup,
                        onExport: exportBackup,
                        onImport: { activeImport = .backup }
                    )

                    TombstoneTrustSettingsSection()

                    FolderSyncSettingsSection(
                        persistenceStatus: persistenceStatus,
                        folderStatus: folderSyncStatus,
                        isPreparing: isPreparingPersistence,
                        isSyncing: isFolderSyncing,
                        onChooseFolder: { activeImport = .syncFolder },
                        onSyncNow: startFolderSyncNow,
                        onDisconnect: disconnectSyncFolder,
                        onRetryPreparation: preparePersistenceForSync,
                        onToggleAutoSync: setAutoSyncEnabled,
                        onShowSyncDetails: { showingSyncDetails = true }
                    )

                    EPUBImportSettingsSection(
                        isImporting: isImportingEPUB,
                        progressText: epubImportProgress,
                        onImport: { activeImport = .epub }
                    )

                    Section {
                        Button {
                            showingAvailabilitySweep = true
                        } label: {
                            Label("Check Availability…", systemImage: "arrow.triangle.2.circlepath")
                        }
                    } header: {
                        Text("Preservation")
                    } footer: {
                        // Deliberately a button, never a background task: it is one AO3
                        // request per work and AO3 offers no "what changed" feed, so the
                        // user decides when that cost is worth paying.
                        Text("Asks AO3 which of your saved works still exist, so deleted ones are "
                            + "marked as the last copy you have. One request per work, sent slowly — "
                            + "start it when it suits you.")
                    }

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
                            in: 2 ... 25
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
                            VStack(alignment: .leading, spacing: 8) {
                                ProgressView(
                                    value: Double(savedWorkMigrationCompleted),
                                    total: Double(max(savedWorkMigrationTotal, 1))
                                )
                                HStack(spacing: 12) {
                                    Text(savedWorkMigrationProgress ?? "Updating Saved for Later…")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Cancel") {
                                        cancelSavedWorkMigration()
                                    }
                                }
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
                        NavigationLink(value: SettingsRoute.privacy) {
                            Label("Privacy & Local Data", systemImage: "hand.raised")
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

                    // Moved from Account's own "Help & Project" section as part of
                    // folding Account's App/Help rows into Settings.
                    Section("Help & Project") {
                        Button {
                            showAbout = true
                        } label: {
                            Label("About Kudos", systemImage: "info.circle")
                        }
                        Button {
                            showingBugReport = true
                        } label: {
                            Label("Report a Bug", systemImage: "ladybug")
                        }
                        if let url = URL(string: AppLinks.repository) {
                            Link(destination: url) {
                                Label("Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                            }
                        }
                    }
                }
            }
            .appThemedRows()
        }
        .formStyle(.grouped)
        .appThemedScroll()
        .onAppear {
            persistenceStatus = PersistenceStatusStore.snapshot()
            folderSyncStatus = FolderSyncService.snapshot()
        }
        // A view node honors only one file-dialog presenter, so every import
        // shares this modifier and an enum picks the configuration.
        .fileImporter(
            isPresented: Binding(
                get: { activeImport != nil },
                set: { if !$0 { activeImport = nil } }
            ),
            allowedContentTypes: activeImportContentTypes,
            allowsMultipleSelection: activeImportAllowsMultipleSelection
        ) { result in
            // Dismissal nils activeImport via the binding, and whether that happens
            // before or after this closure is an OS implementation detail — fall back
            // to the kind recorded at presentation time so the result is never dropped.
            let kind = activeImport ?? lastPresentedImport
            switch kind {
            case .fonts:
                if case let .success(urls) = result { urls.forEach(importFont) }
            case .backup:
                importBackup(result)
            case .epub:
                importEPUBSelection(result)
            case .syncFolder:
                connectSyncFolder(result)
            case nil:
                break
            }
        }
        .onChange(of: activeImport) { _, kind in
            if let kind { lastPresentedImport = kind }
        }
        // Item-based exporter: the archive is already streamed to a temp file,
        // so saving is a file copy — the archive never lives in memory.
        .sheet(isPresented: $showingAvailabilitySweep) {
            AvailabilitySweepView()
        }
        .fileExporter(
            isPresented: $exportingBackup,
            item: backupExportURL.map(KudosBackupArchiveFile.init),
            contentTypes: [.kudosBackup],
            // Derived from the archive's own filename so the two can never
            // disagree — that URL is what this exporter actually presents.
            defaultFilename: backupExportURL?.deletingPathExtension().lastPathComponent
        ) { result in
            cleanUpBackupExportFile()
            switch result {
            case .success:
                backupNotice = BackupNotice(
                    title: "Backup Exported",
                    message: "\(works.count.formatted()) Library records were included."
                )
            case let .failure(error):
                backupNotice = BackupNotice(
                    title: "Couldn't Export Backup",
                    message: error.localizedDescription
                )
            }
        } onCancellation: {
            cleanUpBackupExportFile()
        }
        // An `.alert`, not a `.confirmationDialog`: importing merges into the
        // user's whole library, so it wants a modal centred decision with both
        // choices spelled out. Presented from a List row, a confirmationDialog
        // renders as an anchored popover on iPhone and its `.cancel` button is
        // dropped entirely (dismiss-by-tapping-outside is the only way out) —
        // an alert always renders Cancel explicitly.
        // ONE alert modifier for this whole screen. SwiftUI honours only a
        // single `.alert` per view: this chain previously carried three
        // (import-confirmation, `backupNotice`, `epubNotice`), so the extras
        // were silently dropped and *no* backup ever reported its result —
        // export and import both looked like they had done nothing. Everything
        // is funnelled through `activeAlert` instead, so adding a future alert
        // means adding a case here rather than another competing modifier.
        .alert(item: activeAlertBinding) { alert in
            switch alert {
            case let .notice(notice):
                Alert(
                    title: Text(notice.title),
                    message: Text(notice.message),
                    dismissButton: .default(Text("OK"))
                )
            case let .confirmImport(backup):
                Alert(
                    title: Text("Restore from Backup"),
                    message: Text(
                        "This backup contains \(backup.manifest.works.count) Library records, "
                            + "\(backup.manifest.bookmarks.count) saved links, and "
                            + "\(backup.manifest.fonts.count) custom fonts."
                    ),
                    primaryButton: .default(Text("Restore from Backup")) {
                        restorePendingBackup(backup, mode: .merge)
                    },
                    secondaryButton: .cancel {
                        pendingBackup = nil
                    }
                )
            }
        }
        .confirmationDialog(
            "Add saved works to Saved for Later?",
            isPresented: $showSavedWorkMigrationConfirmation,
            titleVisibility: .visible
        ) {
            Button(savedWorkMigrationButtonTitle) {
                startSavedWorkMigration()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            // Split out of the ViewBuilder so the type checker can finish
            // (the surrounding modifier chain otherwise times out).
            let migrationMessage =
                "Kudos will add existing saved works to the native Saved for Later queue. "
                + "It keeps their current saved state and preserves EPUBs one at a time, "
                + "with a pause between AO3 requests."
            Text(migrationMessage)
        }
        .confirmationDialog(
            "Import this backup?",
            isPresented: $showImportModeChoice,
            titleVisibility: .visible
        ) {
            if let backup = pendingBackup {
                Button("Merge") {
                    restorePendingBackup(backup, mode: .merge)
                }
                Button("Replace Library…", role: .destructive) {
                    showReplaceConfirmation = true
                }
                Button("Cancel", role: .cancel) {
                    pendingBackup = nil
                }
            }
        } message: {
            if let backup = pendingBackup {
                let importMessage =
                    "This backup contains \(backup.manifest.works.count) works. "
                    + "Merge adds new works without removing existing ones. "
                    + "Replace Library makes your library match this backup."
                Text(importMessage)
            }
        }
        .sheet(isPresented: $showReplaceConfirmation) {
            if let backup = pendingBackup {
                ReplaceLibraryConfirmationView(
                    backup: backup,
                    localWorks: works.filter { !$0.isPendingDeletion },
                    syncIsConnected: folderSyncStatus.isConnected,
                    onConfirm: { pauseSync in
                        if pauseSync {
                            setAutoSyncEnabled(false)
                        }
                        showReplaceConfirmation = false
                        restorePendingBackup(backup, mode: .replaceLibrary)
                    },
                    onCancel: {
                        showReplaceConfirmation = false
                        pendingBackup = nil
                    },
                    makePreReplaceBackup: makePreReplaceBackup
                )
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
        .sheet(isPresented: $showAO3Login) {
            AO3LoginView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAbout) {
            NavigationStack { AboutView() }
                .environment(themeManager)
                .tint(themeManager.effectiveTint)
        }
        .sheet(isPresented: $showingBugReport) {
            BugReportView()
                .environment(themeManager)
                .tint(themeManager.effectiveTint)
        }
        .sheet(isPresented: $showingSyncDetails) {
            NavigationStack {
                FolderSyncDetailsView(folderStatus: folderSyncStatus, lastResult: lastFolderSyncResult)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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

        // Security scope is held for the whole pass (download wait + import), not
        // just the read — a not-yet-downloaded iCloud Drive file needs access while
        // it materializes, not only once it's finally readable.
        let accessedURLs = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer { accessedURLs.forEach { $0.stopAccessingSecurityScopedResource() } }

        // Kick off iCloud materialization for every file up front, so files later
        // in the list are already downloading by the time their turn comes instead
        // of each one only starting once the previous file's full import finishes.
        for url in urls {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }

        var summary = EPUBImportNoticeSummary()
        for (index, url) in urls.enumerated() {
            do {
                epubImportProgress = "Waiting for iCloud Drive… (\(index + 1) of \(urls.count))"
                try await waitForUbiquitousDownload(of: url)
                epubImportProgress = "Importing \(index + 1) of \(urls.count)…"
                // Accepts any supported format, converting non-EPUBs on the way in.
                let result = try await UserDocumentImport.perform(url, into: context)
                summary.record(result.outcome, convertedFrom: result.convertedFrom)
            } catch {
                summary.recordFailure(fileName: url.lastPathComponent, message: error.localizedDescription)
            }
        }

        epubNotice = BackupNotice(title: summary.title, message: summary.message)
    }

    // MARK: Backup export / import

    private func exportBackup() {
        guard !isPreparingBackupExport else { return }
        let plan: KudosBackupExportPlan
        do {
            plan = try KudosBackupService.makeExportPlan(
                works: works,
                bookmarks: bookmarks,
                fonts: customFonts,
                collections: collections,
                readingQueues: readingQueues,
                annotations: readingAnnotations,
                savedSearches: savedSearches,
                tombstones: syncTombstones
            )
        } catch {
            backupNotice = BackupNotice(
                title: "Couldn't Create Backup",
                message: error.localizedDescription
            )
            return
        }

        // The archive streams to a temp file off the main actor — constant
        // memory and no UI stall, however large the library is. The exporter
        // sheet is presented only once the file is complete.
        //
        // The temp file is given the name the user should see in the save
        // sheet, because the item-based `fileExporter` takes the presented
        // filename from the exported file's URL — `defaultFilename:` below is
        // not consulted for it. The UUID therefore lives in a wrapping
        // *directory* rather than in the filename, so concurrent or same-day
        // exports still can't collide while the file itself stays readable.
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KudosBackupExport-\(UUID().uuidString)", isDirectory: true)
        let destination = exportDirectory
            .appendingPathComponent("Kudos Backup \(Self.backupDateFormatter.string(from: Date()))")
            .appendingPathExtension("kudosbackup")
        do {
            try FileManager.default.createDirectory(
                at: exportDirectory, withIntermediateDirectories: true
            )
        } catch {
            backupNotice = BackupNotice(
                title: "Couldn't Create Backup",
                message: error.localizedDescription
            )
            return
        }
        isPreparingBackupExport = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try KudosBackupService.writeArchive(plan, to: destination) }
            }.value
            isPreparingBackupExport = false
            switch result {
            case .success:
                backupExportURL = destination
                exportingBackup = true
            case let .failure(error):
                backupNotice = BackupNotice(
                    title: "Couldn't Create Backup",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func cleanUpBackupExportFile() {
        if let url = backupExportURL {
            // Removes the per-export wrapping directory, not just the archive
            // inside it (see `exportBackup()`), so nothing is left behind in tmp.
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        backupExportURL = nil
    }

    private func importBackup(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            pendingBackup = try KudosBackupContents.read(from: url)
            let activeWorks = works.filter { !$0.isPendingDeletion }
            if activeWorks.isEmpty {
                // Empty library: single "Restore from Backup" button.
                showImportConfirmation = true
            } else {
                // Non-empty library: offer Merge vs Replace Library.
                showImportModeChoice = true
            }
        } catch {
            backupNotice = BackupNotice(
                title: "Couldn't Read Backup",
                message: error.localizedDescription
            )
        }
    }

    /// Runs the merge and reports what changed.
    ///
    /// Deliberately hops through a `Task` before doing any work. The call site
    /// is the confirmation alert's own button, and setting `backupNotice`
    /// straight from there raced that alert's dismissal — SwiftUI dropped the
    /// second presentation, so the "Backup Imported" summary silently never
    /// appeared and an import looked like it had done nothing. Yielding once
    /// lets the confirmation finish dismissing, after which the result alert
    /// presents reliably. The hop also gives the progress indicator on the
    /// Import row a chance to render before the merge begins.
    private func restorePendingBackup(_ backup: KudosBackupContents, mode: BackupImportMode = .merge) {
        pendingBackup = nil
        guard PersistenceOperationGate.begin(.backupImport) else {
            backupNotice = BackupNotice(
                title: "Import Already Busy",
                message: "Kudos is already running "
                    + "\(PersistenceOperationGate.active?.title ?? "another persistence operation")."
            )
            return
        }
        isImportingBackup = true
        Task { @MainActor in
            // WP-A kept a `_ = scopedURL` here to hold the security scope open,
            // because in its design the archive was read inside this Task. The
            // RC uses the tombstone tree's flow, where KudosBackupContents is
            // already decoded before we get here, so there is no scope to hold.
            defer {
                PersistenceOperationGate.end(.backupImport)
                isImportingBackup = false
            }
            do {
                let summary = try KudosBackupService.restore(
                    backup, into: context, mode: mode
                )
                if mode != .replaceLibrary {
                    applyRestoredTheme(backup.manifest.settings)
                }
                let verb = mode == .replaceLibrary ? "Replaced" : "Merged"
                let title = mode == .replaceLibrary ? "Library Replaced" : "Backup Imported"
                let conflictMessage = summary.conflictMessage
                backupNotice = BackupNotice(
                    title: title,
                    message: "\(verb) into your library:\n\(summary.changeMessage)"
                        + (conflictMessage.isEmpty ? "" : "\n\n\(conflictMessage)")
                )
            } catch {
                backupNotice = BackupNotice(
                    title: "Couldn't Import Backup",
                    message: error.localizedDescription
                )
            }
        }
    }

    /// Writes a timestamped copy of the current library so Replace can be undone
    /// by importing that file. Returns a user-visible path or an error string.
    private func makePreReplaceBackup() -> Result<String, Error> {
        do {
            let contents = try KudosBackupService.makeContents(
                works: works,
                bookmarks: bookmarks,
                fonts: customFonts,
                collections: collections,
                readingQueues: readingQueues,
                annotations: readingAnnotations,
                savedSearches: savedSearches,
                tombstones: syncTombstones
            )
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let name = "Kudos Library Before Replace \(Self.backupDateFormatter.string(from: Date()))"
            let url = docs.appendingPathComponent(name).appendingPathExtension("kudosbackup")
            try contents.zipData().write(to: url, options: .atomic)
            return .success(url.lastPathComponent)
        } catch {
            return .failure(error)
        }
    }

    private func applyRestoredTheme(_ settings: KudosBackupSettings) {
        themeManager.matchAppAndReader = false
        themeManager.appTheme = ReaderTheme(rawValue: settings.appTheme) ?? .light
        themeManager.readerTheme = ReaderTheme(rawValue: settings.readerTheme) ?? .light
        themeManager.accentHex = settings.accentColorHex
        themeManager.matchAppAndReader = settings.matchAppReaderTheme
    }

    private func preparePersistenceForSync() {
        guard !isPreparingPersistence else { return }
        isPreparingPersistence = true
        Task { @MainActor in
            let state = await PersistenceMigrationService.run(in: context)
            persistenceStatus = PersistenceStatusStore.snapshot()
            isPreparingPersistence = false
            if state == .failedRecoverable {
                backupNotice = BackupNotice(
                    title: "Folder Sync Prep Needs Retry",
                    message: persistenceStatus.detail
                )
            }
        }
    }

    private func connectSyncFolder(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            try FolderSyncService.connect(to: url)
            folderSyncStatus = FolderSyncService.snapshot()
            startFolderSyncNow()
        } catch {
            folderSyncStatus = FolderSyncService.snapshot()
            backupNotice = BackupNotice(
                title: "Couldn't Connect Sync Folder",
                message: error.localizedDescription
            )
        }
    }

    private func startFolderSyncNow() {
        guard !isFolderSyncing else { return }
        isFolderSyncing = true
        Task { @MainActor in
            defer {
                folderSyncStatus = FolderSyncService.snapshot()
                persistenceStatus = PersistenceStatusStore.snapshot()
                isFolderSyncing = false
            }
            do {
                lastFolderSyncResult = try await FolderSyncService.syncNow(in: context)
            } catch {
                backupNotice = BackupNotice(
                    title: "Folder Sync Couldn't Finish",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func disconnectSyncFolder() {
        FolderSyncService.disconnect()
        folderSyncStatus = FolderSyncService.snapshot()
    }

    private func setAutoSyncEnabled(_ enabled: Bool) {
        FolderSyncService.setAutoSyncEnabled(enabled)
        folderSyncStatus = FolderSyncService.snapshot()
    }

    private var savedWorkMigrationButtonTitle: String {
        let count = legacySavedWorksForQueueMigration.count
        return "Add \(count) Work\(count == 1 ? "" : "s")"
    }

    private func startSavedWorkMigration() {
        guard savedWorkMigrationTask == nil else { return }
        savedWorkMigrationTask = Task(priority: .utility) { @MainActor in
            await migrateLegacySavedWorksToSavedForLater()
            savedWorkMigrationTask = nil
        }
    }

    private func cancelSavedWorkMigration() {
        savedWorkMigrationTask?.cancel()
        savedWorkMigrationProgress = "Cancelling after the current work…"
    }

    @MainActor
    private func migrateLegacySavedWorksToSavedForLater() async {
        let candidates = legacySavedWorksForQueueMigration
        guard !candidates.isEmpty, !isMigratingSavedWorks else { return }

        isMigratingSavedWorks = true
        savedWorkMigrationCompleted = 0
        savedWorkMigrationTotal = candidates.count
        savedWorkMigrationProgress = "Preparing Saved for Later…"
        defer {
            isMigratingSavedWorks = false
            savedWorkMigrationProgress = nil
            savedWorkMigrationCompleted = 0
            savedWorkMigrationTotal = 0
        }

        var added = 0
        var unavailableOffline = 0
        var cancelled = false

        for (index, work) in candidates.enumerated() {
            if Task.isCancelled {
                cancelled = true
                break
            }

            savedWorkMigrationProgress = "Updating \(index + 1) of \(candidates.count)…"
            _ = await ReadingQueueService.addToSavedForLater(work, in: context)
            if work.isInSavedForLaterQueue { added += 1 }
            if !work.hasEPUB || work.epubPreservationStatus == .failed
                || work.epubPreservationStatus == .missingFile {
                unavailableOffline += 1
            }
            savedWorkMigrationCompleted = index + 1

            if Task.isCancelled {
                cancelled = true
                break
            }

            guard index + 1 < candidates.count else { continue }
            savedWorkMigrationProgress = "Pausing before the next AO3 request…"
            do {
                try await Task.sleep(nanoseconds: ReadingQueueService.preservationRequestPauseNanos)
            } catch {
                cancelled = true
                break
            }
        }

        var message = "Added \(added.formatted()) saved work"
            + "\(added == 1 ? "" : "s") to Saved for Later."
        if unavailableOffline > 0 {
            message += " \(unavailableOffline.formatted()) need preservation retry before offline reading."
        }
        if cancelled {
            message += " Migration was cancelled before the remaining works were touched."
        }

        backupNotice = BackupNotice(
            title: cancelled ? "Migration Cancelled" : "Saved for Later Updated",
            message: message
        )
    }

    private struct BackupNotice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    /// Every alert this screen can present, so they share one `.alert` modifier
    /// (see the call site — SwiftUI drops all but one per view).
    private enum SettingsAlert: Identifiable {
        case notice(BackupNotice)
        case confirmImport(KudosBackupContents)

        var id: String {
            switch self {
            case let .notice(notice): "notice-\(notice.id)"
            case .confirmImport: "confirm-import"
            }
        }
    }

    /// Projects the individual alert states onto the single modifier, newest
    /// decision first. Writing `nil` back (the user dismissed) clears whichever
    /// state produced the alert, so the existing call sites keep setting
    /// `backupNotice`/`epubNotice`/`showImportConfirmation` exactly as before.
    private var activeAlertBinding: Binding<SettingsAlert?> {
        Binding(
            get: {
                if showImportConfirmation, let pendingBackup {
                    return .confirmImport(pendingBackup)
                }
                if let backupNotice { return .notice(backupNotice) }
                if let epubNotice { return .notice(epubNotice) }
                return nil
            },
            set: { newValue in
                guard newValue == nil else { return }
                if showImportConfirmation {
                    showImportConfirmation = false
                    pendingBackup = nil
                } else if backupNotice != nil {
                    backupNotice = nil
                } else {
                    epubNotice = nil
                }
            }
        )
    }

    private enum FileImportKind { case fonts, backup, epub, syncFolder }

    private var activeImportContentTypes: [UTType] {
        switch activeImport {
        case .fonts: [.font]
        // `.folder` keeps the pre-archive directory-form backups from older
        // versions selectable — `KudosBackupContents.read(from:)` handles both
        // formats, and a plain directory is exactly what such a backup resolves
        // to. It cannot be narrowed to a package type: nothing declares
        // `.kudosbackup` as a package, so the system types those directories as
        // `public.folder` (verified on a real legacy backup). The previous
        // `UTType(filenameExtension:conformingTo: .package)` matched neither
        // them nor anything else, so legacy import was silently broken too.
        case .backup: [.kudosBackup, .folder]
        case .epub: Self.workImportContentTypes
        case .syncFolder: [.folder]
        case nil: [.item] // never presented; keeps the modifier well-formed
        }
    }

    private var activeImportAllowsMultipleSelection: Bool {
        switch activeImport {
        case .fonts, .epub: true
        case .backup, .syncFolder, nil: false
        }
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

    /// Everything the work importer can read. Wider than the formats T-152
    /// converts on purpose: a community copy arrives as whatever someone had, and
    /// a picker that greys the file out is a dead end, whereas letting it through
    /// produces a message naming the format and what to do about it.
    ///
    /// `.zip` matters more than it looks — forums and chat apps reject `.epub`
    /// attachments, so zipping the file is the normal way fanfic gets passed
    /// around, and `.data` catches the extensionless files Discord leaves behind.
    private static let workImportContentTypes: [UTType] = [
        epubContentType,
        .html,
        .plainText,
        .text,
        .zip,
        .pdf,
        .rtf,
        UTType(filenameExtension: "xhtml") ?? .html,
        UTType(filenameExtension: "md") ?? .plainText,
        UTType(filenameExtension: "docx") ?? .data,
        UTType(filenameExtension: "mobi") ?? .data,
        UTType(filenameExtension: "azw3") ?? .data,
        .data
    ]
}

struct BackupSettingsSection: View {
    var isPreparingExport = false
    var isImporting = false
    let onExport: () -> Void
    let onImport: () -> Void

    private var isBusy: Bool {
        isPreparingExport || isImporting
    }

    var body: some View {
        Section {
            Button(action: onExport) {
                HStack {
                    Label("Export Backup…", systemImage: "square.and.arrow.up")
                    if isPreparingExport {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isBusy)
            Button(action: onImport) {
                HStack {
                    Label("Import Backup…", systemImage: "square.and.arrow.down")
                    if isImporting {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isBusy)
            // A full-width bar while either side is working. Indeterminate on
            // purpose: neither `writeArchive` nor `restore` reports per-record
            // progress today, and a bar that invented a percentage would be
            // lying about how far along the merge actually is.
            if isBusy {
                ProgressView()
                    .progressViewStyle(.linear)
                    .accessibilityLabel(isImporting ? "Importing backup" : "Preparing backup")
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

struct TombstoneTrustSettingsSection: View {
    @State private var pastedKey = ""
    @State private var addMessage: String?

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("This device")
                Text(TombstoneSigning.publicKeyHex())
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            TextField("Paste another device's public key", text: $pastedKey)
                .font(.system(.caption, design: .monospaced))
                #if canImport(UIKit)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
            Button("Trust this key") {
                let trimmed = pastedKey.trimmingCharacters(in: .whitespacesAndNewlines)
                if TombstoneTrustStore.add(trimmed) {
                    pastedKey = ""
                    addMessage = "Trusted."
                } else {
                    addMessage = "Need a 64-character hex public key."
                }
            }
            .disabled(pastedKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if let addMessage {
                Text(addMessage)
                    .font(.footnote)
                    .foregroundStyle(addMessage == "Trusted." ? Color.secondary : Color.red)
            }
        } header: {
            Text("Deletion signing")
        } footer: {
            Text("Deletes are signed on this device. Other devices with the same Apple ID "
                + "pick up this public key automatically. To trust a phone on another "
                + "account, paste its public key. Backup files never add a trusted key.")
        }
        .onAppear {
            TombstoneTrustStore.add(TombstoneSigning.publicKeyHex())
        }
    }
}

struct FolderSyncSettingsSection: View {
    let persistenceStatus: PersistenceStatusSnapshot
    let folderStatus: FolderSyncSnapshot
    let isPreparing: Bool
    let isSyncing: Bool
    let onChooseFolder: () -> Void
    let onSyncNow: () -> Void
    let onDisconnect: () -> Void
    let onRetryPreparation: () -> Void
    let onToggleAutoSync: (Bool) -> Void
    let onShowSyncDetails: () -> Void

    var body: some View {
        Section {
            LabeledContent {
                Text(persistenceStatus.migrationState.title)
            } label: {
                Label("Metadata", systemImage: "externaldrive")
            }

            if folderStatus.isConnected {
                LabeledContent {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(folderStatus.folderDisplayName)
                        if !folderStatus.folderPath.isEmpty {
                            Text(folderStatus.folderPath)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                } label: {
                    Label("Folder", systemImage: "folder")
                }

                Toggle(isOn: Binding(
                    get: { folderStatus.autoSyncEnabled },
                    set: onToggleAutoSync
                )) {
                    Label("Auto Sync", systemImage: "arrow.triangle.2.circlepath.circle")
                }

                Button(action: onSyncNow) {
                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(isSyncing || isPreparing)

                Button(action: onChooseFolder) {
                    Label("Change Folder", systemImage: "folder.badge.gearshape")
                }
                .disabled(isSyncing || isPreparing)

                Button(action: onShowSyncDetails) {
                    Label("Sync Details", systemImage: "list.bullet.rectangle")
                }

                Button(role: .destructive, action: onDisconnect) {
                    Label("Disconnect", systemImage: "xmark.circle")
                }
                .disabled(isSyncing)
            } else {
                Button(action: onChooseFolder) {
                    Label("Choose Sync Folder", systemImage: "folder.badge.plus")
                }
                .disabled(isSyncing || isPreparing)
            }

            if let date = persistenceStatus.lastMigrationAttempt {
                LabeledContent("Last Checked", value: date.formatted(date: .abbreviated, time: .shortened))
            }

            if let date = folderStatus.lastSyncAt {
                LabeledContent("Last Synced", value: date.formatted(date: .abbreviated, time: .shortened))
            }

            Button(action: onRetryPreparation) {
                Label(
                    persistenceStatus.migrationState == .completed ? "Check Metadata" : "Retry Metadata Prep",
                    systemImage: "arrow.clockwise"
                )
            }
            .disabled(isPreparing || isSyncing)

            if isPreparing || isSyncing {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(isSyncing ? "Syncing library…" : "Preparing metadata…")
                        .foregroundStyle(.secondary)
                }
            }

            if !folderStatus.lastError.isEmpty {
                Text(folderStatus.lastError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Library Sync Folder")
        } footer: {
            Text(persistenceStatus.detail + " Your library data — including reading history — is written "
                + "to the folder you choose. If that folder is in iCloud Drive, Apple syncs it to your "
                + "other devices through your personal iCloud account. Kudos still works fully offline. "
                + "This is folder-based sync using the existing backup format, not real-time CloudKit sync. "
                + "Turning off Auto Sync stops automatic background/launch syncing — Sync Now still works.")
        }
    }
}

/// Lightweight diagnostics, mainly useful during development/testing — deliberately
/// tucked behind its own screen rather than cluttering the main Settings list.
struct FolderSyncDetailsView: View {
    let folderStatus: FolderSyncSnapshot
    let lastResult: FolderSyncResult?

    var body: some View {
        Form {
            Section("Status") {
                LabeledContent("Connected", value: folderStatus.isConnected ? "Yes" : "No")
                LabeledContent("Auto Sync", value: folderStatus.autoSyncEnabled ? "On" : "Off")
                LabeledContent("Pending Changes", value: folderStatus.isDirty ? "Yes" : "No")
                if let date = folderStatus.lastSyncAt {
                    LabeledContent("Last Synced", value: date.formatted(date: .abbreviated, time: .standard))
                }
                if !folderStatus.lastError.isEmpty {
                    LabeledContent("Last Error", value: folderStatus.lastError)
                }
            }
            if let lastResult {
                Section("Last Sync Result") {
                    LabeledContent("Read Remote File", value: lastResult.didReadRemoteFile ? "Yes" : "No")
                    LabeledContent("Wrote Remote File", value: lastResult.didWriteRemoteFile ? "Yes" : "No")
                    LabeledContent("Missing Remote File", value: lastResult.missingRemoteFile ? "Yes" : "No")
                    LabeledContent("Conflicts Folded", value: "\(lastResult.foldedConflicts)")
                    LabeledContent("Works Restored", value: "\(lastResult.restoredWorks)")
                    LabeledContent("Queues Suppressed", value: "\(lastResult.suppressedQueues)")
                    LabeledContent("Queues Revived", value: "\(lastResult.revivedQueues)")
                    LabeledContent("Ambiguous Queue Conflicts", value: "\(lastResult.ambiguousQueueConflicts)")
                }
            } else {
                Section {
                    Text("No sync has run yet this session.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Sync Details")
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

struct EPUBImportSettingsSection: View {
    let isImporting: Bool
    let progressText: String?
    let onImport: () -> Void

    var body: some View {
        Section {
            Button(action: onImport) {
                Label("Import Files", systemImage: "doc.badge.plus")
            }
            .disabled(isImporting)
            .accessibilityLabel("Import files")

            if isImporting {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(progressText ?? "Importing…")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Import")
        } footer: {
            Text("Import EPUB, HTML, or text files — including zipped chapters — into your "
                + "local Library. Anything that isn't already an EPUB is converted to one, "
                + "and the original file is kept alongside it. Files are copied into Kudos "
                + "storage and remain readable offline.")
        }
    }
}

private struct EPUBImportNoticeSummary {
    var imported = 0
    var restored = 0
    var duplicates = 0
    /// How many files were converted to EPUB on the way in, by source format, so
    /// the notice can say what happened rather than silently changing the file.
    var converted: [ImportedFileFormat: Int] = [:]
    var failures: [(fileName: String, message: String)] = []

    var title: String {
        failures.isEmpty ? "Import Complete" : "Import Finished"
    }

    var message: String {
        var parts: [String] = []
        if imported > 0 { parts.append("Imported \(imported.formatted()).") }
        if !converted.isEmpty { parts.append(conversionSentence) }
        if restored > 0 {
            parts.append("Restored \(restored.formatted()) existing Library file\(restored == 1 ? "" : "s").")
        }
        if duplicates > 0 {
            parts.append("Skipped \(duplicates.formatted()) duplicate\(duplicates == 1 ? "" : "s").")
        }
        if failures.isEmpty {
            return parts.isEmpty ? "No files were selected." : parts.joined(separator: " ")
        }
        let failureText = failures.prefix(3)
            .map { "\($0.fileName): \($0.message)" }
            .joined(separator: "\n")
        let extra = failures.count > 3 ? "\n…and \(failures.count - 3) more." : ""
        return (parts.isEmpty ? "Nothing was imported." : parts.joined(separator: " "))
            + "\n\n" + failureText + extra
    }

    /// "Converted 2 from HTML, 1 from plain text." Formats are sorted by name so
    /// the sentence is stable rather than dictionary-ordered.
    private var conversionSentence: String {
        let clauses = converted
            .sorted { $0.key.displayName < $1.key.displayName }
            .map { "\($0.value.formatted()) from \($0.key.displayName)" }
        return "Converted \(clauses.joined(separator: ", ")). The original file\(converted.count == 1 ? "" : "s")"
            + " \(converted.values.reduce(0, +) == 1 ? "was" : "were") kept."
    }

    mutating func record(_ outcome: UserEPUBImportOutcome, convertedFrom format: ImportedFileFormat? = nil) {
        switch outcome {
        case .imported:
            imported += 1
        case .restored:
            restored += 1
        case .duplicate:
            duplicates += 1
        }
        // A duplicate is not counted as a conversion: nothing new was stored, so
        // claiming "the original was kept" would be a lie.
        if let format, case .imported = outcome {
            converted[format, default: 0] += 1
        }
    }

    mutating func recordFailure(fileName: String, message: String) {
        failures.append((fileName, message))
    }
}

/// Classify Replace confirmation counts with the same identity order restore uses.
enum BackupReplaceWorkDelta {
    @MainActor
    static func classify(
        localWorks: [SavedWork],
        incoming: [KudosBackupWork]
    ) -> (willAdd: Int, willRemove: Int, inBoth: Int) {
        let index = WorkIdentityIndex(localWorks)
        var matchedLocalIDs = Set<UUID>()
        var willAdd = 0
        for archived in incoming {
            if let existing = index.existingWork(
                ao3WorkID: archived.ao3WorkID,
                sourceURL: archived.sourceURL,
                recordID: archived.id
            ) {
                matchedLocalIDs.insert(existing.id)
            } else {
                willAdd += 1
            }
        }
        return (
            willAdd,
            localWorks.filter { !matchedLocalIDs.contains($0.id) }.count,
            matchedLocalIDs.count
        )
    }
}

/// Extra step for Replace Library: counts, checkbox, delayed red button, optional
/// pause-sync, and a pre-replace backup of the current library.
struct ReplaceLibraryConfirmationView: View {
    let backup: KudosBackupContents
    let localWorks: [SavedWork]
    let syncIsConnected: Bool
    let onConfirm: (Bool) -> Void
    let onCancel: () -> Void
    let makePreReplaceBackup: () -> Result<String, Error>

    @State private var acknowledgedRemoval = false
    @State private var pauseSync = true
    @State private var replaceEnabled = false
    @State private var backupFileName: String?
    @State private var backupError: String?

    /// Same identity order restore uses: ao3WorkID → canonical sourceURL → recordID.
    private var replaceDelta: (willAdd: Int, willRemove: Int, inBoth: Int) {
        BackupReplaceWorkDelta.classify(localWorks: localWorks, incoming: backup.manifest.works)
    }

    private var willRemove: Int { replaceDelta.willRemove }
    private var willAdd: Int { replaceDelta.willAdd }
    private var inBoth: Int { replaceDelta.inBoth }
    private var backupIsMuchSmaller: Bool { willRemove >= 20 && willRemove >= willAdd * 10 }

    var body: some View {
        NavigationStack {
            Form {
                Section("This backup") {
                    LabeledContent("Works in your library", value: "\(localWorks.count)")
                    LabeledContent("Works in this backup", value: "\(backup.manifest.works.count)")
                    LabeledContent("Will be added", value: "\(willAdd)")
                    LabeledContent("Will be removed", value: "\(willRemove)")
                    LabeledContent("In both", value: "\(inBoth)")
                }
                if backupIsMuchSmaller {
                    Section {
                        Text("This backup is much smaller than your library.")
                            .foregroundStyle(.orange)
                    }
                }
                Section {
                    Toggle(isOn: $acknowledgedRemoval) {
                        Text("Remove \(willRemove) works that are not in this backup")
                    }
                    if syncIsConnected {
                        Toggle("Pause Library Sync on this device", isOn: $pauseSync)
                        Text("Sync will put removed works back. Pause sync for this device?")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let backupFileName {
                        Text("A copy of your current library was saved as \(backupFileName).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let backupError {
                        Text("Could not save an undo copy: \(backupError)")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text("Replace Library only changes this device. It does not plant deletion records that would block a later Merge of your own backup.")
                }
            }
            .navigationTitle("Replace Library")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Replace Library") {
                        onConfirm(syncIsConnected && pauseSync)
                    }
                    .disabled(!replaceEnabled)
                    .foregroundStyle(replaceEnabled ? .red : .secondary)
                }
            }
            .onAppear {
                switch makePreReplaceBackup() {
                case let .success(name): backupFileName = name
                case let .failure(error): backupError = error.localizedDescription
                }
            }
            .onChange(of: acknowledgedRemoval) { _, checked in
                replaceEnabled = false
                guard checked else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.5))
                    if acknowledgedRemoval { replaceEnabled = true }
                }
            }
        }
    }
}

private extension Error {
    var isUserCancellation: Bool {
        let error = self as NSError
        return error.domain == NSCocoaErrorDomain
            && error.code == CocoaError.Code.userCancelled.rawValue
    }
}
