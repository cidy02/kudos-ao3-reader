import Foundation
import SwiftUI
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
            ("Downloads & storage", [.downloads, .preservation, .readingQueues]),
            ("Library & sync", [.library, .backup, .syncFolder, .importFiles]),
            ("Account & privacy", [.account, .privacySettings]),
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
            auth: .signedIn(username: "reader"),
            speechEngineID: "kokoro", speechVoiceID: "af_bella", speechVoiceName: "Bella"
        )
        let second = SettingsHubInputs(
            appTheme: .oled, readerTheme: .sepia, themesMatched: true, fontName: "Menlo",
            readingMode: .scroll, downloadOnSubscribe: false, autoPreserveSeries: true, seriesLimit: 3,
            hidesMature: false, matureMode: .obscure, folderSync: Self.sync(connected: true, auto: true),
            auth: .signedOut,
            speechEngineID: "system",
            speechVoiceID: "com.apple.voice.compact.en-US.Samantha",
            speechVoiceName: "Samantha"
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
                .listening: "Kokoro · Bella",
                .downloads: "On subscribe", .readingQueues: "Auto up to 7 works", .syncFolder: "Paused",
                .account: "reader", .privacySettings: "Off", .about: "Version \(Changelog.currentVersion)"
            ]),
            (second, [
                .appearance: "OLED", .font: "Menlo", .reader: "Scrolled",
                .listening: "Apple · Samantha",
                .downloads: "Manual", .readingQueues: "Auto up to 3 works", .syncFolder: "On",
                .account: "Not signed in", .privacySettings: "Off", .about: "Version \(Changelog.currentVersion)"
            ]),
            (third, [
                .appearance: "Sepia", .font: "System", .reader: "Paged",
                .listening: "Automatic",
                .downloads: "On subscribe", .readingQueues: "Ask first", .syncFolder: "Off",
                .account: "Checking…", .privacySettings: "Hide mature works", .about: "Version \(Changelog.currentVersion)"
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

    // MARK: Icon tiles & Search

    @Test func everyRouteHasValidTileColorAndSystemImage() {
        for route in SettingsRoute.allCases {
            #expect(!route.iconTileSystemImage.isEmpty, "Missing system image for \(route)")
            #expect(route.iconTileHex.hasPrefix("#"), "Hex must start with # for \(route)")
            #expect(route.iconTileHex.count == 7, "Hex must be #RRGGBB for \(route)")
            #expect(Color(hex: route.iconTileHex) != nil, "Invalid hex for \(route)")
        }

        let customAccent = Color.purple
        #expect(SettingsRoute.downloads.iconTileColor(accent: customAccent) == customAccent)
        #expect(SettingsRoute.account.iconTileColor(accent: customAccent) == customAccent)
        #expect(SettingsRoute.reader.iconTileColor(accent: customAccent) != customAccent)
    }

    @Test func settingsRouteSearchMatching() {
        // Empty query matches everything
        #expect(SettingsRoute.appearance.matches(query: "", currentValue: ""))
        #expect(SettingsRoute.appearance.matches(query: "   ", currentValue: ""))

        // Matches title
        #expect(SettingsRoute.appearance.matches(query: "appear", currentValue: "Dark"))
        #expect(SettingsRoute.font.matches(query: "font", currentValue: "Georgia"))

        // Matches current value
        #expect(SettingsRoute.appearance.matches(query: "sepia", currentValue: "Sepia"))
        #expect(SettingsRoute.account.matches(query: "AddictedFic", currentValue: "AddictedFicLover"))

        // Matches keywords
        #expect(SettingsRoute.listening.matches(query: "tts", currentValue: ""))
        #expect(SettingsRoute.listening.matches(query: "kokoro", currentValue: ""))
        #expect(SettingsRoute.syncFolder.matches(query: "icloud", currentValue: "On"))
        #expect(SettingsRoute.importFiles.matches(query: "epub", currentValue: ""))
        #expect(SettingsRoute.privacySettings.matches(query: "mature", currentValue: "Off"))
        #expect(SettingsRoute.backup.matches(query: "archive", currentValue: ""))
        #expect(SettingsRoute.appearance.matches(query: "cover", currentValue: ""))
        #expect(SettingsRoute.appearance.matches(query: "art", currentValue: ""))

        // Non-matching query
        #expect(!SettingsRoute.font.matches(query: "xyznonexistent", currentValue: "Georgia"))
    }

    @Test func hubFirstSectionFooterCarriesFactAndVoiceOverValue() {
        #expect(SettingsHubView.hubFooterText == "Changes here affect Kudos, not your AO3 account")
        #expect(SettingsHubView.hubFooterAccessibilityValue == "These settings are stored on this device only and are never sent to AO3.")
    }

    // MARK: Listening & Backup

    @Test func listeningValueShowsEngineAndVoiceOrAutomatic() {
        #expect(SettingsHubValue.listening(engineID: "", voiceID: "", voiceName: "") == "Automatic")
        #expect(SettingsHubValue.listening(engineID: "kokoro", voiceID: "", voiceName: "") == "Automatic")
        #expect(SettingsHubValue.listening(engineID: "system", voiceID: "", voiceName: "Samantha") == "Automatic")
        #expect(SettingsHubValue.listening(engineID: "", voiceID: "af_bella", voiceName: "") == "Automatic")

        #expect(
            SettingsHubValue.listening(engineID: "kokoro", voiceID: "af_bella", voiceName: "Bella")
                == "Kokoro · Bella"
        )
        #expect(
            SettingsHubValue.listening(engineID: "", voiceID: "af_bella", voiceName: "Bella")
                == "Kokoro · Bella"
        )
        #expect(
            SettingsHubValue.listening(
                engineID: "system",
                voiceID: "com.apple.voice.compact.en-US.Samantha",
                voiceName: "Samantha"
            ) == "Apple · Samantha"
        )
        #expect(
            SettingsHubValue.listening(
                engineID: "",
                voiceID: "com.apple.voice.compact.en-US.Samantha",
                voiceName: "Samantha"
            ) == "Apple · Samantha"
        )
    }

    @Test func speechVoiceNameRoundTripsThroughBackupSettingsAndIsOmittedWhenUnset() throws {
        let sourceSuite = "SettingsHubTests.source.\(UUID().uuidString)"
        let source = try #require(UserDefaults(suiteName: sourceSuite))
        defer { source.removePersistentDomain(forName: sourceSuite) }

        // Unset -> both id and name omitted from exported JSON.
        let unsetCaptured = KudosBackupSettings.capture(defaults: source)
        #expect(unsetCaptured.readerSpeechVoiceID == nil)
        #expect(unsetCaptured.readerSpeechVoiceName == nil)
        let unsetJSON = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(unsetCaptured)) as? [String: Any]
        )
        #expect(unsetJSON["readerSpeechVoiceID"] == nil)
        #expect(unsetJSON["readerSpeechVoiceName"] == nil)

        // Empty strings -> also omitted from exported JSON.
        source.set("", forKey: ReaderSpeechPreferences.voiceIDKey)
        source.set("", forKey: ReaderSpeechPreferences.voiceNameKey)
        let emptyCaptured = KudosBackupSettings.capture(defaults: source)
        #expect(emptyCaptured.readerSpeechVoiceID == nil)
        #expect(emptyCaptured.readerSpeechVoiceName == nil)
        let emptyJSON = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(emptyCaptured)) as? [String: Any]
        )
        #expect(emptyJSON["readerSpeechVoiceID"] == nil)
        #expect(emptyJSON["readerSpeechVoiceName"] == nil)

        // Stored voice id + name -> travel together through JSON and restore onto destination.
        source.set("af_bella", forKey: ReaderSpeechPreferences.voiceIDKey)
        source.set("Bella", forKey: ReaderSpeechPreferences.voiceNameKey)
        let setCaptured = KudosBackupSettings.capture(defaults: source)
        #expect(setCaptured.readerSpeechVoiceID == "af_bella")
        #expect(setCaptured.readerSpeechVoiceName == "Bella")
        let encoded = try JSONEncoder().encode(setCaptured)
        let setJSON = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(setJSON["readerSpeechVoiceID"] as? String == "af_bella")
        #expect(setJSON["readerSpeechVoiceName"] as? String == "Bella")

        let decoded = try JSONDecoder().decode(KudosBackupSettings.self, from: encoded)
        #expect(decoded.readerSpeechVoiceID == "af_bella")
        #expect(decoded.readerSpeechVoiceName == "Bella")

        let destinationSuite = "SettingsHubTests.dest.\(UUID().uuidString)"
        let destination = try #require(UserDefaults(suiteName: destinationSuite))
        defer { destination.removePersistentDomain(forName: destinationSuite) }
        decoded.apply(to: destination)
        #expect(destination.string(forKey: ReaderSpeechPreferences.voiceIDKey) == "af_bella")
        #expect(destination.string(forKey: ReaderSpeechPreferences.voiceNameKey) == "Bella")

        // Pin Samantha locally; an archive carrying Bella's name WITHOUT an id
        // must never overwrite Samantha's name onto Samantha's id.
        destination.set("com.apple.voice.compact.en-US.Samantha", forKey: ReaderSpeechPreferences.voiceIDKey)
        destination.set("Samantha", forKey: ReaderSpeechPreferences.voiceNameKey)
        var nameWithoutID = unsetCaptured
        nameWithoutID.readerSpeechVoiceName = "Bella"
        let decodedNameWithoutID = try JSONDecoder().decode(
            KudosBackupSettings.self,
            from: JSONEncoder().encode(nameWithoutID)
        )
        decodedNameWithoutID.apply(to: destination)
        #expect(
            destination.string(forKey: ReaderSpeechPreferences.voiceIDKey)
                == "com.apple.voice.compact.en-US.Samantha"
        )
        #expect(destination.string(forKey: ReaderSpeechPreferences.voiceNameKey) == "Samantha")

        // Absent id + name in an older archive leaves both local values intact.
        let unsetDecoded = try JSONDecoder().decode(
            KudosBackupSettings.self,
            from: JSONEncoder().encode(unsetCaptured)
        )
        unsetDecoded.apply(to: destination)
        #expect(
            destination.string(forKey: ReaderSpeechPreferences.voiceIDKey)
                == "com.apple.voice.compact.en-US.Samantha"
        )
        #expect(destination.string(forKey: ReaderSpeechPreferences.voiceNameKey) == "Samantha")

        // An archive carrying a different voice id WITHOUT a name clears the stale
        // local name instead of leaving Samantha's label on Bella's id.
        var idWithoutName = unsetCaptured
        idWithoutName.readerSpeechVoiceID = "af_bella"
        let decodedIDWithoutName = try JSONDecoder().decode(
            KudosBackupSettings.self,
            from: JSONEncoder().encode(idWithoutName)
        )
        decodedIDWithoutName.apply(to: destination)
        #expect(destination.string(forKey: ReaderSpeechPreferences.voiceIDKey) == "af_bella")
        #expect(destination.string(forKey: ReaderSpeechPreferences.voiceNameKey) == nil)
    }

    @Test func voiceNameReconciliationClearsMissingVoiceAndPreservesOnFailedLoad() {
        let kokoroCatalog = [
            (identifier: "af_heart", name: "Heart"),
            (identifier: "af_bella", name: "Bella")
        ]
        // Pinned voice present in loaded catalog -> keeps/updates display name.
        #expect(
            ReaderSpeechPreferences.reconciledVoiceName(
                voiceID: "af_bella",
                currentVoiceName: "Old Bella",
                catalogEntries: kokoroCatalog
            ) == "Bella"
        )
        // Pinned Apple voice missing after switching to Kokoro -> clears stale name so hub says Automatic.
        #expect(
            ReaderSpeechPreferences.reconciledVoiceName(
                voiceID: "com.apple.voice.compact.en-US.Samantha",
                currentVoiceName: "Samantha",
                catalogEntries: kokoroCatalog
            ) == ""
        )
        // Catalog failed to load (empty list) -> never clears the stored name.
        #expect(
            ReaderSpeechPreferences.reconciledVoiceName(
                voiceID: "com.apple.voice.compact.en-US.Samantha",
                currentVoiceName: "Samantha",
                catalogEntries: []
            ) == "Samantha"
        )
        // No voice id pinned -> always clears.
        #expect(
            ReaderSpeechPreferences.reconciledVoiceName(
                voiceID: "",
                currentVoiceName: "Samantha",
                catalogEntries: kokoroCatalog
            ) == ""
        )
    }
}
