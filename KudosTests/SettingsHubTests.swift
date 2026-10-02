import Foundation
import Testing
@testable import Kudos

/// Settings became a hub of value rows (artboard 1ab, T-266). These pin the two
/// things a later edit could quietly break: which page each route lands on, and
/// the value each hub row states.
@Suite(.serialized)
struct SettingsHubTests {
    // MARK: Routing

    /// The hub is drawn from `hubGroups`, so this is the page's own layout: the
    /// groups in 1ab's order, each route under the group REDESIGN_DECISIONS.md
    /// files it in. A route dropped from here is a page nothing links to.
    @Test func hubGroupsFollowTheDecisionsTable() {
        let groups = SettingsRoute.hubGroups.map { ($0.title, $0.routes) }
        var reading: [SettingsRoute] = [.appearance, .font, .reader]
        #if os(iOS)
        reading.append(.listening) // the Readium read-aloud player; macOS has none
        #endif
        let expected: [(String, [SettingsRoute])] = [
            ("Reading", reading),
            ("Downloads & Storage", [.downloads, .preservation, .readingQueues]),
            ("Library & Sync", [.library, .backup, .syncFolder, .importFiles]),
            ("Account & Privacy", [.account, .privacySettings]),
            ("About", [.about])
        ]
        #expect(groups.map(\.0) == expected.map(\.0))
        #expect(groups.map(\.1) == expected.map(\.1))
    }

    /// Every page is one hub row exactly once — except Privacy and local data
    /// (1ac), the pre-hub deep link, which the Privacy and About pages push.
    @Test func everyPageIsOneHubRowExceptThePreHubDeepLink() {
        let rows = SettingsRoute.hubGroups.flatMap(\.routes)
        #expect(Set(rows).count == rows.count)
        var notRows: Set<SettingsRoute> = [.privacy]
        #if !os(iOS)
        notRows.insert(.listening)
        #endif
        #expect(Set(rows) == Set(SettingsRoute.allCases).subtracting(notRows))
    }

    /// What each route actually pushes — read off `SettingsDestination`'s own
    /// switch, so a case wired to the wrong page fails here. The comments name
    /// the controls each page holds; the pages' contents are NOT checked here
    /// (their bodies need the app's environment) — the screenshot gate is.
    @MainActor
    @Test func everyRoutePushesThePageHoldingItsControls() {
        var expected: [SettingsRoute: String] = [
            .appearance: "SettingsAppearancePage", // theme, accent, text size
            .font: "SettingsFontPage", // font list, Add Font…
            .reader: "SettingsReaderPage", // layout, two-page spread, keep screen awake
            .downloads: "SettingsDownloadsPage", // download on subscribe, storage used
            .preservation: "SettingsPreservationPage", // Check Availability…
            .readingQueues: "SettingsReadingQueuesPage", // queue storage, auto-preserve, migration
            .library: "SettingsLibraryPage", // confirm before deleting, show zero counts
            .backup: "SettingsBackupPage", // export / import
            .syncFolder: "SettingsSyncFolderPage", // deletion signing, folder sync
            .importFiles: "SettingsImportPage", // EPUB / document import
            .account: "SettingsAccountPage", // signed-in row, log in / out
            .privacySettings: "SettingsPrivacyPage", // mature content, → Privacy and local data
            .about: "SettingsAboutPage", // version, About Kudos, bug report, source
            .privacy: "PrivacyDataView" // 1ac, the pre-hub deep link
        ]
        #if os(iOS)
        expected[.listening] = "SettingsListeningPage" // read-aloud, Developer Settings link
        #endif
        for route in SettingsRoute.allCases {
            #expect(Self.pushedPage(for: route) == expected[route], "\(route)")
        }
    }

    /// The first page type inside the destination's body, breadth-first.
    @MainActor
    private static func pushedPage(for route: SettingsRoute) -> String? {
        var queue: [Any] = [SettingsDestination(route: route).body]
        while !queue.isEmpty {
            let value = queue.removeFirst()
            let name = String(describing: type(of: value))
            if (name.hasPrefix("Settings") && name.hasSuffix("Page")) || name == "PrivacyDataView" {
                return name
            }
            queue += Mirror(reflecting: value).children.map(\.value)
        }
        return nil
    }

    // MARK: Hub values

    /// Which input each hub row reads — the wiring `SettingsHubView` hands to
    /// `SettingsHubValue.row`. The four flags take a different on/off pattern
    /// across the three runs, so a row fed a sibling's flag fails in one of them.
    @Test func eachHubRowReadsItsOwnInput() {
        let first = SettingsHubInputs(
            appTheme: .dark, readerTheme: .sepia, themesMatched: false, fontName: "Georgia",
            readingMode: .paged, downloadOnSubscribe: true, autoPreserveSeries: true, seriesLimit: 7,
            hidesMature: false, matureMode: .hide, folderSync: Self.sync(connected: true, auto: false),
            auth: .signedIn(username: "reader")
        )
        let second = SettingsHubInputs(
            appTheme: .oled, readerTheme: .sepia, themesMatched: true, fontName: "Menlo",
            readingMode: .scroll, downloadOnSubscribe: false, autoPreserveSeries: true, seriesLimit: 3,
            hidesMature: false, matureMode: .obscure, folderSync: Self.sync(connected: true, auto: true),
            auth: .signedOut
        )
        let third = SettingsHubInputs(
            appTheme: .sepia, readerTheme: .dark, themesMatched: true, fontName: "System",
            readingMode: .paged, downloadOnSubscribe: true, autoPreserveSeries: false, seriesLimit: 9,
            hidesMature: true, matureMode: .hide, folderSync: Self.sync(connected: false, auto: true),
            auth: .restoring
        )
        let cases: [(SettingsHubInputs, [SettingsRoute: String])] = [
            (first, [
                .appearance: "Dark, Sepia reader", .font: "Georgia", .reader: "Paged",
                .downloads: "On subscribe", .readingQueues: "Auto up to 7 works", .syncFolder: "Paused",
                .account: "reader", .privacySettings: "Off", .about: Changelog.currentVersion
            ]),
            (second, [
                .appearance: "OLED", .font: "Menlo", .reader: "Scrolled",
                .downloads: "Manual", .readingQueues: "Auto up to 3 works", .syncFolder: "On",
                .account: "Not signed in", .privacySettings: "Off", .about: Changelog.currentVersion
            ]),
            (third, [
                .appearance: "Sepia", .font: "System", .reader: "Paged",
                .downloads: "On subscribe", .readingQueues: "Ask first", .syncFolder: "Off",
                .account: "Checking…", .privacySettings: "Hide mature works", .about: Changelog.currentVersion
            ])
        ]
        for (inputs, expected) in cases {
            for route in SettingsRoute.allCases {
                #expect(SettingsHubValue.row(route, inputs) == expected[route, default: ""], "\(route)")
            }
        }
    }

    private static func sync(connected: Bool, auto: Bool, error: String = "") -> FolderSyncSnapshot {
        FolderSyncSnapshot(
            isConnected: connected, folderDisplayName: "", folderPath: "", lastSyncAt: nil,
            lastError: error, isDirty: false, autoSyncEnabled: auto
        )
    }

    @Test func themeValueNamesOneThemeWhileMatched() {
        #expect(SettingsHubValue.theme(app: .dark, reader: .sepia, matched: true) == "Dark")
        #expect(SettingsHubValue.theme(app: .oled, reader: .oled, matched: false) == "OLED")
        #expect(SettingsHubValue.theme(app: .dark, reader: .sepia, matched: false) == "Dark, Sepia reader")
    }

    @Test func downloadsValueStatesDownloadOnSubscribe() {
        #expect(SettingsHubValue.downloads(onSubscribe: true) == "On subscribe")
        #expect(SettingsHubValue.downloads(onSubscribe: false) == "Manual")
        #expect(SettingsHubValue.downloads(onSubscribe: true, keepsWorksYouRead: true) == "Keep what you read")
    }

    /// "On" only while connected and syncing on its own — a Replace import's
    /// pause and a failed sync must not read as "On".
    @Test func syncFolderValueIsOnOnlyWhenConnectedAndSyncing() {
        #expect(SettingsHubValue.syncFolder(Self.sync(connected: true, auto: true)) == "On")
        #expect(SettingsHubValue.syncFolder(Self.sync(connected: true, auto: false)) == "Paused")
        #expect(SettingsHubValue.syncFolder(Self.sync(connected: true, auto: true, error: "No access")) == "Error")
        #expect(SettingsHubValue.syncFolder(Self.sync(connected: true, auto: false, error: "No access")) == "Error")
        #expect(SettingsHubValue.syncFolder(Self.sync(connected: false, auto: true)) == "Off")
        #expect(SettingsHubValue.syncFolder(Self.sync(connected: false, auto: false, error: "x")) == "Off")
    }

    @Test func accountValueIsTheUsernameOrNotSignedIn() {
        #expect(SettingsHubValue.account(.signedIn(username: "AddictedFicLover")) == "AddictedFicLover")
        #expect(SettingsHubValue.account(.restoring) == "Checking…")
        for status in [AO3AuthStatus.signedOut, .signingIn, .usingFallback] {
            #expect(SettingsHubValue.account(status) == "Not signed in")
        }
    }

    @Test func readingQueuesValueStatesTheSeriesLimitOnlyWhenAutoPreserving() {
        #expect(SettingsHubValue.readingQueues(autoPreserve: true, seriesLimit: 7) == "Auto up to 7 works")
        #expect(SettingsHubValue.readingQueues(autoPreserve: false, seriesLimit: 7) == "Ask first")
    }

    @Test func privacyValueNamesTheMatureMode() {
        #expect(SettingsHubValue.privacy(hidesMature: true, mode: .obscure) == "Blur mature works")
        #expect(SettingsHubValue.privacy(hidesMature: true, mode: .hide) == "Hide mature works")
        #expect(SettingsHubValue.privacy(hidesMature: false, mode: .hide) == "Off")
    }
}
