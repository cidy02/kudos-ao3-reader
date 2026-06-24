import Foundation
import OSLog

/// Centralized OSLog loggers — one `Logger` per area — so diagnostics are
/// categorized and filterable in Console.app / the `log` tool instead of being
/// scattered `print`s.
///
/// OSLog redacts interpolated strings/objects by default; technical values
/// (URLs, error text, counts) are marked `privacy: .public` at the call site,
/// while user content (e.g. work titles) is left to default redaction.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "Kudos"

    /// EPUB parsing and reader rendering.
    static let epub = Logger(subsystem: subsystem, category: "epub")
    /// AO3 network requests (search, downloads, tag pages).
    static let network = Logger(subsystem: subsystem, category: "network")
    /// AO3 login and session lifecycle. Never log credentials or cookie values.
    static let auth = Logger(subsystem: subsystem, category: "auth")
    /// Library and work import.
    static let library = Logger(subsystem: subsystem, category: "library")
    /// Mature-content privacy decisions (reveals, biometric gating).
    static let privacy = Logger(subsystem: subsystem, category: "privacy")
}
