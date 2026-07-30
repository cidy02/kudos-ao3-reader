import Foundation

/// How a saved copy stands relative to the site it came from.
nonisolated enum WorkPreservationState: Sendable {
    /// Still on its site as far as we know.
    case available
    /// The site no longer has it and we still hold the file — the last copy the user
    /// will ever get, and the reason the preservation features exist.
    case preservedLastCopy
    /// The site no longer has it and the file has already been freed. Nothing to
    /// re-download; worth flagging honestly rather than showing it as ordinary
    /// history the user could tap to restore.
    case goneWithNoCopy

    /// Card-sized label, or nil when there is nothing worth saying.
    var badgeLabel: String? {
        switch self {
        case .available: nil
        case .preservedLastCopy: "Last Copy"
        case .goneWithNoCopy: "Unavailable"
        }
    }

    var badgeSymbol: String {
        switch self {
        case .available: "checkmark.circle"
        case .preservedLastCopy: "archivebox.fill"
        case .goneWithNoCopy: "exclamationmark.triangle.fill"
        }
    }

    /// Full sentence for Work Details, where there is room to explain.
    func explanation(origin: WorkOrigin) -> String? {
        switch self {
        case .available:
            return nil
        case .preservedLastCopy:
            return "\(origin.displayName) no longer has this work. Your downloaded copy "
                + "is the only one Kudos can open, so it is kept and never freed automatically."
        case .goneWithNoCopy:
            return "\(origin.displayName) no longer has this work, and its file is no longer "
                + "stored on this device. It cannot be re-downloaded."
        }
    }
}

/// Which site a work came from, derived from its `sourceURL`.
///
/// Kudos is an AO3 reader, so AO3 is the unmarked default and everything else is
/// worth saying out loud: a fic rescued from fanfiction.net behaves differently
/// (no live page to refresh tags from, no kudos to give) and the reader should not
/// imply otherwise.
///
/// **Derived, not stored.** Computed from `sourceURL` on demand, so this needed no
/// schema change and no `.kudosbackup` bump — every existing work in every existing
/// archive gets an origin the moment this ships. T-155's `sourceSite` field will
/// eventually persist a *verified* origin (read from FanFicFare's
/// `fanficfare-uid:<site>-…` identifiers, which are far better evidence than a URL);
/// until then this is the best available answer and costs nothing.
///
/// ## Adding a site
///
/// Append to `hostPatterns`. One line: a host fragment and the case it maps to.
/// Match on the *host*, never the whole URL, so a fic whose text happens to mention
/// another archive is not misattributed. Add a case to `WorkOriginTests` with a real
/// URL from that site.
nonisolated enum WorkOrigin: String, CaseIterable, Sendable {
    case archiveOfOurOwn
    case fanfictionNet
    case wattpad
    case fictionPress
    case royalRoad
    case spaceBattles
    case sufficientVelocity
    case squidgeWorld
    case tumblr
    case liveJournal
    case archiveOfOurOwnMirror
    /// No source URL at all — a file the user imported, with no site behind it.
    case importedFile
    /// A source URL that resolves to no site we know.
    case unknown

    /// Full name, for Work Details and accessibility labels.
    var displayName: String {
        switch self {
        case .archiveOfOurOwn: "Archive of Our Own"
        case .fanfictionNet: "FanFiction.net"
        case .wattpad: "Wattpad"
        case .fictionPress: "FictionPress"
        case .royalRoad: "Royal Road"
        case .spaceBattles: "SpaceBattles"
        case .sufficientVelocity: "Sufficient Velocity"
        case .squidgeWorld: "SquidgeWorld"
        case .tumblr: "Tumblr"
        case .liveJournal: "LiveJournal"
        case .archiveOfOurOwnMirror: "AO3 mirror"
        case .importedFile: "Imported file"
        case .unknown: "Other site"
        }
    }

    /// Card-sized label. Kept short because it shares a row with Offline/Saved/etc.
    var shortLabel: String {
        switch self {
        case .archiveOfOurOwn: "AO3"
        case .fanfictionNet: "FFN"
        case .wattpad: "Wattpad"
        case .fictionPress: "FictionPress"
        case .royalRoad: "Royal Road"
        case .spaceBattles: "SpaceBattles"
        case .sufficientVelocity: "SufficientVelocity"
        case .squidgeWorld: "SquidgeWorld"
        case .tumblr: "Tumblr"
        case .liveJournal: "LiveJournal"
        case .archiveOfOurOwnMirror: "AO3 mirror"
        case .importedFile: "Imported"
        case .unknown: "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .archiveOfOurOwn, .archiveOfOurOwnMirror: "books.vertical"
        case .importedFile: "doc"
        case .unknown: "globe"
        default: "globe"
        }
    }

    /// True when Kudos can talk to the site about this work — refresh its tags, check
    /// whether it still exists, give kudos. Only AO3 has a native path, so this is
    /// what stops the UI implying otherwise for everything else.
    var supportsLiveLookup: Bool {
        self == .archiveOfOurOwn
    }

    /// Host fragments, most specific first. Matched against the URL's host only.
    private static let hostPatterns: [(fragment: String, origin: WorkOrigin)] = [
        ("archiveofourown.org", .archiveOfOurOwn),
        ("ao3.org", .archiveOfOurOwn),
        ("fanfiction.net", .fanfictionNet),
        ("fictionpress.com", .fictionPress),
        ("wattpad.com", .wattpad),
        ("royalroad.com", .royalRoad),
        ("forums.spacebattles.com", .spaceBattles),
        ("spacebattles.com", .spaceBattles),
        ("forums.sufficientvelocity.com", .sufficientVelocity),
        ("sufficientvelocity.com", .sufficientVelocity),
        ("squidgeworld.org", .squidgeWorld),
        ("tumblr.com", .tumblr),
        ("livejournal.com", .liveJournal),
        // Mirrors and proxies of AO3 itself: still AO3 content, but not a URL the
        // native client can talk to, so they are called out separately.
        ("ao3.satr.dev", .archiveOfOurOwnMirror),
        ("archive.org", .archiveOfOurOwnMirror)
    ]

    static func detect(sourceURL: String) -> WorkOrigin {
        let trimmed = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .importedFile }
        // Host only. Matching the whole string would let a fic that *mentions*
        // fanfiction.net in its text be filed under it.
        let host = URL(string: trimmed)?.host?.lowercased()
            ?? trimmed.lowercased()
        guard let match = hostPatterns.first(where: { host.contains($0.fragment) }) else {
            return .unknown
        }
        return match.origin
    }
}
