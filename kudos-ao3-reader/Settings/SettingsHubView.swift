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
    @Query(sort: \CustomFont.dateAdded) private var customFonts: [CustomFont]

    @AppStorage("readerFontID") private var fontID: String = "system"
    @AppStorage("readerMode") private var readingMode: ReadingMode = .scroll
    @AppStorage("downloadOnSubscribe") private var downloadOnSubscribe = false
    @AppStorage(WorkLifecycle.keepsWorksYouReadKey) private var keepsWorksYouRead = false
    @AppStorage("autoPreserveSmallSeriesOnSaveForLater") private var autoPreserveSeries = false
    @AppStorage("autoPreserveSeriesWorkThreshold") private var seriesLimit = 5
    @AppStorage("hideMatureContent") private var hideMatureContent = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure

    @State private var folderSyncStatus = FolderSyncService.snapshot()
    @State private var searchText = ""

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
        .overlay {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if filteredGroups.isEmpty && !query.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        // Sync can be connected or dropped on its page; re-read on the way back.
        .onAppear { folderSyncStatus = FolderSyncService.snapshot() }
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
            auth: auth.status
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
                    if !value.isEmpty {
                        Text(value)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
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
