import Foundation

/// Pushable destinations owned by the Settings surface: the pages the hub
/// (`SettingsHubView`, artboard 1ab) pushes, plus Privacy and local data (1ac).
/// Registered by whichever host pushes Settings as a screen (currently
/// `AccountView`, through `SettingsDestination`) — the reader's quick Display
/// sheet constructs `ReaderOptionsForm` and never links here.
enum SettingsRoute: Hashable, CaseIterable {
    // Reading
    case appearance, font, reader, listening
    // Downloads & Storage
    case downloads, preservation, readingQueues
    // Library & Sync
    case library, backup, syncFolder, importFiles
    // Account & Privacy
    case account, privacySettings
    // About
    case about
    /// Privacy and local data (1ac). The one route that predates the hub; it is
    /// pushed from the Privacy and About pages rather than from a hub row.
    case privacy

    /// The hub row's label and the pushed page's title.
    var title: String {
        switch self {
        case .appearance: "Appearance"
        case .font: "Font"
        case .reader: "Reader"
        case .listening: "Listening"
        case .downloads: "Downloads"
        case .preservation: "Preservation"
        case .readingQueues: "Reading Queues"
        case .library: "Library"
        case .backup: "Backup"
        case .syncFolder: "Sync Folder"
        case .importFiles: "Import"
        case .account: "AO3 Account"
        case .privacySettings: "Privacy"
        case .about: "About"
        case .privacy: "Privacy and local data"
        }
    }

    /// The hub's groups in 1ab's order (REDESIGN_DECISIONS.md, "Settings (1ab)").
    /// The hub draws from this table, so a test that reads it reads the page.
    ///
    /// "Library" is not in the decisions table: it holds the two Library toggles
    /// (confirm before deleting, show zero counts) the old page carried, and a
    /// reorganisation cannot drop them. Listening is iOS only — its section is
    /// the Readium read-aloud player's, which macOS does not have.
    static let hubGroups: [SettingsHubGroup] = {
        var reading: [SettingsRoute] = [.appearance, .font, .reader]
        #if os(iOS)
        reading.append(.listening)
        #endif
        return [
            SettingsHubGroup(title: "Reading", routes: reading),
            SettingsHubGroup(title: "Downloads & Storage", routes: [.downloads, .preservation, .readingQueues]),
            SettingsHubGroup(title: "Library & Sync", routes: [.library, .backup, .syncFolder, .importFiles]),
            SettingsHubGroup(title: "Account & Privacy", routes: [.account, .privacySettings]),
            SettingsHubGroup(title: "About", routes: [.about])
        ]
    }()
}

struct SettingsHubGroup: Identifiable {
    let title: String
    let routes: [SettingsRoute]

    var id: String { title }
}

/// Everything the hub's value column reads. The hub fills it from its stored
/// settings; `SettingsHubValue.row` picks each row's input from it, so which row
/// reads what is pure and pinned by the tests.
struct SettingsHubInputs {
    var appTheme: ReaderTheme
    var readerTheme: ReaderTheme
    var themesMatched: Bool
    var fontName: String
    var readingMode: ReadingMode
    var downloadOnSubscribe: Bool
    var autoPreserveSeries: Bool
    var seriesLimit: Int
    var hidesMature: Bool
    var matureMode: MaturePrivacyMode
    var folderSync: FolderSyncSnapshot
    var auth: AO3AuthStatus
}

/// The value each hub row shows on its right ("Appearance · Dark"). One rule per
/// row family, pure so the tests can pin them.
enum SettingsHubValue {
    static func row(_ route: SettingsRoute, _ inputs: SettingsHubInputs) -> String {
        switch route {
        case .appearance: theme(app: inputs.appTheme, reader: inputs.readerTheme, matched: inputs.themesMatched)
        case .font: inputs.fontName
        case .reader: inputs.readingMode.title
        case .downloads: downloads(onSubscribe: inputs.downloadOnSubscribe)
        case .readingQueues: readingQueues(autoPreserve: inputs.autoPreserveSeries, seriesLimit: inputs.seriesLimit)
        case .syncFolder: syncFolder(inputs.folderSync)
        case .account: account(inputs.auth)
        case .privacySettings: privacy(hidesMature: inputs.hidesMature, mode: inputs.matureMode)
        case .about: Changelog.currentVersion
        case .listening, .preservation, .library, .backup, .importFiles, .privacy: ""
        }
    }

    static func theme(app: ReaderTheme, reader: ReaderTheme, matched: Bool) -> String {
        matched || app == reader ? app.title : "\(app.title), \(reader.title) reader"
    }

    /// "Keep downloads for" is not shown: no retention sweep exists (see
    /// `StorageUsedRow`), so the one download setting there is to state is this.
    static func downloads(onSubscribe: Bool) -> String {
        onSubscribe ? "On subscribe" : "Manual"
    }

    static func readingQueues(autoPreserve: Bool, seriesLimit: Int) -> String {
        autoPreserve ? "Auto up to \(seriesLimit) works" : "Ask first"
    }

    /// "On" only while a folder is connected AND syncing on its own: a Replace
    /// import pauses auto sync, and a failed sync leaves `lastError` set — the
    /// old single page showed both, so the hub must not hide them behind "On".
    static func syncFolder(_ sync: FolderSyncSnapshot) -> String {
        if !sync.isConnected { return "Off" }
        if !sync.lastError.isEmpty { return "Error" }
        return sync.autoSyncEnabled ? "On" : "Paused"
    }

    static func account(_ status: AO3AuthStatus) -> String {
        switch status {
        case let .signedIn(username): username
        case .restoring: "Checking…"
        case .signedOut, .signingIn, .usingFallback: "Not signed in"
        }
    }

    static func privacy(hidesMature: Bool, mode: MaturePrivacyMode) -> String {
        hidesMature ? "\(mode.title) mature works" : "Off"
    }
}
