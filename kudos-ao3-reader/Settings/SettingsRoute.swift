import Foundation

/// Pushable destinations owned by the Settings surface (`ReaderOptionsForm` with
/// `includeAppSettings`), so Settings rows don't depend on the Account tab's own
/// route type. Registered by whichever host pushes Settings as a screen
/// (currently `AccountView`) — the reader's quick Display sheet constructs
/// `ReaderOptionsForm` without app settings and never links here.
enum SettingsRoute: Hashable {
    case privacy
}
