import SwiftUI

/// One release's plain-English notes for the in-app "What's New" sheet. Bundled in
/// the app rather than fetched from GitHub, so it works offline and always matches
/// the running build exactly — the design already planned for Android's own
/// (network-backed) changelog, mirrored here without the network dependency since
/// iOS has no app-update-check system to hang a fetch off of.
struct ChangelogEntry: Identifiable, Equatable {
    let version: String
    let notes: String
    var id: String { version }
}

/// Newest-first release notes, plus the "has this device seen the latest one"
/// bookkeeping. Add one entry per release — the same plain-English paragraph a
/// release's GitHub notes would use, not authored twice.
enum Changelog {
    static let entries: [ChangelogEntry] = [
        ChangelogEntry(
            version: "1.0",
            notes: "Welcome to Kudos — a native SwiftUI reader for Archive of Our Own."
        )
    ]

    private static let lastSeenKey = "lastSeenChangelogVersion"

    /// The running build's marketing version (`CFBundleShortVersionString`).
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// Entries newer than what this device has already seen, newest first.
    ///
    /// Empty on a fresh install — a first-time user gets the welcome onboarding
    /// instead, not a changelog for a version they just installed — and empty again
    /// immediately after `markSeen()`. If the last-seen version isn't in `entries` at
    /// all (an old install predating this feature, or a version whose entry was
    /// skipped), every entry is returned rather than silently losing notes.
    static func unseenEntries(defaults: UserDefaults = .standard) -> [ChangelogEntry] {
        guard let lastSeen = defaults.string(forKey: lastSeenKey) else {
            defaults.set(currentVersion, forKey: lastSeenKey)
            return []
        }
        guard lastSeen != currentVersion else { return [] }
        guard let lastSeenIndex = entries.firstIndex(where: { $0.version == lastSeen }) else {
            return entries
        }
        return Array(entries[..<lastSeenIndex])
    }

    static func markSeen(defaults: UserDefaults = .standard) {
        defaults.set(currentVersion, forKey: lastSeenKey)
    }
}

/// Sheet listing every changelog entry the device hasn't seen yet. `onDone` marks
/// the current version seen — the host decides *when* (dismissal, not appearance),
/// so a user who ignores the sheet without reading it still sees it again.
struct WhatsNewView: View {
    let entries: [ChangelogEntry]
    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(entries) { entry in
                    Section("Version \(entry.version)") {
                        Text(entry.notes)
                            .font(.subheadline)
                            .cardRow()
                    }
                }
            }
            .appThemedRows()
            .appThemedScroll()
            .navigationTitle("What's New")
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: onDone) {
                            Image(systemName: "checkmark")
                        }
                        .accessibilityLabel("Done")
                    }
                }
        }
        .presentationDragIndicator(.visible)
    }
}
