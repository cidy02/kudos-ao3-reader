import SwiftData
import SwiftUI

/// Account → Settings, artboard **1ab**: a short hub of grouped value rows, each
/// pushing the page that holds its controls (`SettingsRoute.hubGroups`).
///
/// It used to be one native `Form` of seventeen sections. The controls moved to
/// the pages unchanged — same views, same `@AppStorage` keys and `ThemeManager`
/// bindings — so nothing a reader set changes; only where it lives does.
struct SettingsHubView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AO3AuthService.self) private var auth
    @Environment(AppRouter.self) private var router: AppRouter?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \CustomFont.dateAdded) private var customFonts: [CustomFont]

    @AppStorage("readerFontID") private var fontID: String = "system"
    @AppStorage("readerMode") private var readingMode: ReadingMode = .scroll
    @AppStorage("downloadOnSubscribe") private var downloadOnSubscribe = false
    @AppStorage(WorkLifecycle.keepsWorksYouReadKey) private var keepsWorksYouRead = false
    @AppStorage("autoPreserveSmallSeriesOnSaveForLater") private var autoPreserveSeries = false
    @AppStorage("autoPreserveSeriesWorkThreshold") private var seriesLimit = 5
    @AppStorage("hideMatureContent") private var hideMatureContent = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure
    @AppStorage(ReaderSpeechPreferences.engineKey) private var speechEngineID = ""
    @AppStorage(ReaderSpeechPreferences.voiceIDKey) private var speechVoiceID = ""
    @AppStorage(ReaderSpeechPreferences.voiceNameKey) private var speechVoiceName = ""
    @AppStorage(RichEditorFeatureFlag.storageKey) private var richEditorEnabled = false
    @AppStorage(StudioWritingGoal.storageKey) private var storedDailyGoal: Int = StudioWritingGoal.defaultGoal

    @State private var folderSyncStatus = FolderSyncService.snapshot()
    @State private var searchText = ""
    @State private var showingWritingGoalSheet = false
    @State private var startWritingDocument: StudioLocalDocumentTarget?
    @State private var isStartingWriting = false
    @State private var startWritingError: String?

    static let hubFooterText = "Changes here affect Kudos, not your AO3 account"
    static let hubFooterAccessibilityValue = "These settings are stored on this device only and are never sent to AO3."

    private var filteredGroups: [SettingsHubGroup] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return SettingsRoute.hubGroups
        }
        let currentInputs = inputs
        return SettingsRoute.hubGroups.compactMap { group in
            let matching = group.routes.filter { route in
                route.matches(query: query, currentValue: SettingsHubValue.row(route, currentInputs))
            }
            return matching.isEmpty ? nil : SettingsHubGroup(title: group.title, routes: matching)
        }
    }

    private var showsWritingSection: Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let terms = [
            "Writing",
            "Start Writing",
            "Daily Writing Goal",
            "goal",
            "daily",
            "words",
            "draft",
            "document",
            "Rich Text editor (beta)",
            "rich text",
            "editor",
            "beta",
            "experimental"
        ]
        return terms.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        let inputs = self.inputs
        List {
            ForEach(filteredGroups) { group in
                Section {
                    ForEach(group.routes, id: \.self) { route in
                        let value = SettingsHubValue.row(route, inputs)
                        NavigationLink(value: route) {
                            SettingsHubRow(route: route, value: value)
                        }
                    }
                } header: {
                    Text(group.title)
                } footer: {
                    if group.id == SettingsRoute.hubGroups.first?.id {
                        Text(Self.hubFooterText)
                            .accessibilityLabel(Self.hubFooterText)
                            .accessibilityValue(Self.hubFooterAccessibilityValue)
                    }
                }
            }
            .appThemedRows()

            if showsWritingSection {
                Section {
                    Button {
                        startWritingFromSettings()
                    } label: {
                        HStack(spacing: 12) {
                            SettingsIconTile(
                                color: themeManager.effectiveTint,
                                systemImage: "pencil.line"
                            )
                            Text(isStartingWriting ? "Starting…" : "Start Writing")
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            if isStartingWriting {
                                ProgressView()
                                    .controlSize(.small)
                                    .accentFill()
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .disabled(isStartingWriting)
                    .accessibilityLabel("Start Writing")
                    .accessibilityHint("Creates a local document on this \(ThisDevice.name) and opens the editor")

                    Button {
                        showingWritingGoalSheet = true
                    } label: {
                        dailyWritingGoalRowLabel
                    }
                    .accessibilityLabel("Daily Writing Goal")
                    .accessibilityValue(dailyGoalValueText)

                    Toggle(isOn: $richEditorEnabled) {
                        HStack(spacing: 12) {
                            SettingsIconTile(
                                color: themeManager.effectiveTint,
                                systemImage: "square.and.pencil"
                            )
                            Text("Rich Text editor (beta)")
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accentFill()
                } header: {
                    Text("Writing")
                } footer: {
                    Text(
                        "Your writing, drafts and daily word goal stay on this \(ThisDevice.name). "
                            + "Start Writing creates a document and shows the Writing tab without an AO3 account."
                    )
                }
                .appThemedRows()
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
        .navigationBarTitleDisplayMode(.inline)
        #else
        .searchable(text: $searchText, prompt: "Search")
        #endif
        .navigationTitle("Settings")
        .appThemedScroll()
        .sheet(isPresented: $showingWritingGoalSheet) {
            StudioWritingGoalSheet()
        }
        .navigationDestination(item: $startWritingDocument) { target in
            LocalChapterEditorScreen(
                workID: target.workID,
                chapterID: target.chapterID,
                initialWorkTitle: target.title
            )
        }
        .alert(
            "Couldn't Start Document",
            isPresented: Binding(
                get: { startWritingError != nil },
                set: { if !$0 { startWritingError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { startWritingError = nil }
        } message: {
            Text(startWritingError ?? "")
        }
        .overlay {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if filteredGroups.isEmpty && !showsWritingSection && !query.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        // Sync can be connected or dropped on its page; re-read on the way back.
        .onAppear { folderSyncStatus = FolderSyncService.snapshot() }
    }

    private var dailyGoalValueText: String {
        StudioWritingGoal.summaryText(for: StudioWritingGoal.resolvedGoal(fromStored: storedDailyGoal))
    }

    @ViewBuilder
    private var dailyWritingGoalRowLabel: some View {
        if dynamicTypeSize.isAccessibilitySize {
            HStack(alignment: .top, spacing: 12) {
                SettingsIconTile(
                    color: themeManager.effectiveTint,
                    systemImage: "target"
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text("Daily Writing Goal")
                        .font(.body)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(dailyGoalValueText)
                        .font(.subheadline)
                        .foregroundStyle(.secondaryInk)
                }
            }
        } else {
            HStack(spacing: 12) {
                SettingsIconTile(
                    color: themeManager.effectiveTint,
                    systemImage: "target"
                )
                Text("Daily Writing Goal")
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer()
                Text(dailyGoalValueText)
                    .font(.body)
                    .foregroundStyle(.secondaryInk)
                    .lineLimit(1)
            }
        }
    }

    private func startWritingFromSettings() {
        guard !isStartingWriting else { return }
        isStartingWriting = true
        startWritingError = nil
        Task {
            defer { isStartingWriting = false }
            do {
                startWritingDocument = try await StudioStartWritingAction.createFirstDocument(router: router)
            } catch {
                startWritingError = UserFacingError.message(for: error)
            }
        }
    }

    private var inputs: SettingsHubInputs {
        SettingsHubInputs(
            appTheme: themeManager.appTheme,
            readerTheme: themeManager.readerTheme,
            themesMatched: themeManager.matchAppAndReader,
            fontName: ReaderFontOption.current(id: fontID, customFonts: customFonts).name,
            readingMode: readingMode,
            downloadOnSubscribe: downloadOnSubscribe,
            keepsWorksYouRead: keepsWorksYouRead,
            autoPreserveSeries: autoPreserveSeries,
            seriesLimit: seriesLimit,
            hidesMature: hideMatureContent,
            matureMode: matureMode,
            folderSync: folderSyncStatus,
            auth: auth.status,
            speechEngineID: speechEngineID,
            speechVoiceID: speechVoiceID,
            speechVoiceName: speechVoiceName
        )
    }
}

/// A grouped Settings hub row with a 29 pt coloured icon tile and value label.
struct SettingsHubRow: View {
    let route: SettingsRoute
    let value: String

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            HStack(alignment: .top, spacing: 12) {
                SettingsIconTile(
                    color: route.iconTileColor(accent: themeManager.effectiveTint),
                    systemImage: route.iconTileSystemImage
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(route.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(route.title.contains(where: \.isWhitespace) ? nil : 1)
                        .minimumScaleFactor(route.title.contains(where: \.isWhitespace) ? 1 : 0.5)
                        .fixedSize(horizontal: false, vertical: true)
                    if !value.isEmpty {
                        Text(value)
                            .font(.subheadline)
                            .foregroundStyle(.secondaryInk)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(route.title)
            .accessibilityValue(value)
        } else {
            HStack(spacing: 12) {
                SettingsIconTile(
                    color: route.iconTileColor(accent: themeManager.effectiveTint),
                    systemImage: route.iconTileSystemImage
                )
                Text(route.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer()
                if !value.isEmpty {
                    Text(value)
                        .font(.body)
                        .foregroundStyle(.secondaryInk)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(route.title)
            .accessibilityValue(value)
        }
    }
}

/// The page each `SettingsRoute` pushes. The host registers this once
/// (`.navigationDestination(for: SettingsRoute.self)`), so a new page is a new
/// case here and nowhere else.
struct SettingsDestination: View {
    let route: SettingsRoute

    var body: some View {
        switch route {
        case .appearance: SettingsAppearancePage()
        case .font: SettingsFontPage()
        case .reader: SettingsReaderPage()
        case .listening:
            #if os(iOS)
            SettingsListeningPage()
            #else
            EmptyView() // not on the macOS hub; see `SettingsRoute.hubGroups`
            #endif
        case .downloads: SettingsDownloadsPage()
        case .preservation: SettingsPreservationPage()
        case .readingQueues: SettingsReadingQueuesPage()
        case .library: SettingsLibraryPage()
        case .backup: SettingsBackupPage()
        case .syncFolder: SettingsSyncFolderPage()
        case .importFiles: SettingsImportPage()
        case .account: SettingsAccountPage()
        case .privacySettings: SettingsPrivacyPage()
        case .about: SettingsAboutPage()
        case .privacy: PrivacyDataView()
        }
    }
}

/// The frame every Settings page shares: 1ab's breadcrumb head over the page's
/// own native `Form` sections — pickers, toggles and destructive buttons are the
/// right tool there — themed for Sepia the way the old single page was.
struct SettingsPageForm<Content: View>: View {
    let route: SettingsRoute
    @ViewBuilder var content: () -> Content

    var body: some View {
        Form {
            // Group so .appThemedRows() (a .listRowBackground) reaches every section's
            // rows — it does NOT propagate from the Form container, only from a Group/
            // Section/ForEach around the rows.
            Group {
                content()
            }
            .appThemedRows()
        }
        .formStyle(.grouped)
        .appThemedScroll()
        .navigationTitle(route.title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// A page's result alert. Each page carries ONE `.alert` — SwiftUI honours only
/// one per view, and the old single page lost every backup result to a second.
struct SettingsNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

extension View {
    func settingsNoticeAlert(_ notice: Binding<SettingsNotice?>) -> some View {
        alert(item: notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}
