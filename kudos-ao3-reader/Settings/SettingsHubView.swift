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

    var body: some View {
        let inputs = self.inputs
        List {
            Section {
                SettingsHeaderBlock().pageBodyRow(top: 20, gutter: 0)
            }
            ForEach(SettingsRoute.hubGroups) { group in
                Section {
                    // Pads itself to `SubjectMetrics.gutter`, like the header.
                    // 1ab: 10 from the rule to its panel. The List's minimum
                    // row height used to supply the gap, and ~20 more with it.
                    SectionRuleHeader(title: group.title)
                        .padding(.bottom, 10)
                        .pageBodyRow(top: 22, gutter: 0)
                    // One `List` row per link: in one row, a tap fires every link.
                    ForEach(Array(group.routes.enumerated()), id: \.element) { index, route in
                        let value = SettingsHubValue.row(route, inputs)
                        SubjectFormRow(label: route.title, value: value, showsDisclosure: true)
                            .subjectRowNavigation(to: route, accessibilityLabel: route.title)
                            .panelSegment(index, of: group.routes.count, gutter: SubjectMetrics.accountGutter)
                    }
                }
            }
        }
        .cardList()
        // 1ab's rows are 11×14 around a 15pt line (~41pt); the List's own
        // minimum row height held every row at ~52 (L3-B10-1).
        .environment(\.defaultMinListRowHeight, 0)
        .subjectScreenWash(palette: themeManager.scopePalette)
        #if os(macOS)
            .navigationTitle("Settings")
        #endif
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

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        Form {
            // Group so .appThemedRows() (a .listRowBackground) reaches every section's
            // rows — it does NOT propagate from the Form container, only from a Group/
            // Section/ForEach around the rows.
            Group {
                Section {
                    // Reads "Settings › Appearance": the kicker is the page it
                    // came from, the title the page itself.
                    SubjectHeaderBlock(
                        kicker: "Settings",
                        title: route.title,
                        palette: themeManager.scopePalette,
                        gutter: SubjectMetrics.accountGutter
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                }
                content()
            }
            .appThemedRows()
        }
        .formStyle(.grouped)
        .appThemedScroll()
        .hidesFloatingTabBar()
        #if os(iOS)
            // The header names the page; a bar title would say it twice.
            .hidesNavigationBarChrome()
        #else
            .navigationTitle(route.title)
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
