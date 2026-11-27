import Foundation

/// What the Lock Screen widget shows (T-576e): the work and chapter last open in the editor and the words written in
/// sprints today. The app writes it into its App Group; the widget extension only reads it. Titles and counts only.
nonisolated struct KudosWidgetSnapshot: Codable, Equatable, Sendable {
    var workTitle: String?
    var chapterTitle: String?
    var sprintWords = 0
    /// The day `sprintWords` counts.
    var sprintDay: Date?

    func sprintWordsToday(now: Date = Date(), calendar: Calendar = .current) -> Int {
        guard let sprintDay, calendar.isDate(sprintDay, inSameDayAs: now) else { return 0 }
        return sprintWords
    }

    mutating func addSprint(words: Int, at date: Date, calendar: Calendar = .current) {
        if let sprintDay, calendar.isDate(sprintDay, inSameDayAs: date) {
            sprintWords += max(0, words)
        } else {
            sprintWords = max(0, words)
            sprintDay = date
        }
    }
}

/// The App Group the app and its widgets share: `group.` and the app's bundle id, so Kudos and Kudos Next each have
/// their own. The extension's bundle id is the app's plus `.widgets`.
nonisolated enum KudosAppGroup {
    static func identifier(bundleID: String?) -> String? {
        guard var id = bundleID, !id.isEmpty else { return nil }
        if id.hasSuffix(".widgets") { id.removeLast(".widgets".count) }
        return "group." + id
    }

    /// Nil without the App Group entitlement (an unsigned simulator or test build): the widget then shows its defaults.
    static var snapshotURL: URL? {
        guard let group = identifier(bundleID: Bundle.main.bundleIdentifier),
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            return nil
        }
        return container.appendingPathComponent("widget-snapshot.json")
    }
}

nonisolated enum KudosWidgetSnapshotStore {
    static func read(from url: URL?) -> KudosWidgetSnapshot {
        guard let url, let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(KudosWidgetSnapshot.self, from: data) else {
            return KudosWidgetSnapshot()
        }
        return snapshot
    }

    /// Reads, changes and writes the snapshot. True only when it changed and was written, so the caller knows to
    /// reload the widget.
    @discardableResult
    static func update(at url: URL?, _ change: (inout KudosWidgetSnapshot) -> Void) -> Bool {
        guard let url else { return false }
        var snapshot = read(from: url)
        let before = snapshot
        change(&snapshot)
        guard snapshot != before, let data = try? JSONEncoder().encode(snapshot) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
