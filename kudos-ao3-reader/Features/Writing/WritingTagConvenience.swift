import SwiftUI

// MARK: - Order

/// Moves a chosen tag chip. AO3 stores these lists as comma-separated strings
/// and keeps the order it was given, so the array after a drag is the posted
/// field — `AO3TagListDiff.joined` does not sort.
enum WritingTagReorder {
    /// Drops `name` in front of `target`. Dropping on the last chip lands
    /// after it, which is the only way a forward drag can make a chip last.
    static func move(_ names: inout [String], name: String, before target: String) {
        guard name != target, let from = names.firstIndex(of: name) else { return }
        let targetIndex = names.firstIndex(of: target)
        let landsLast = names.last == target && targetIndex.map { from < $0 } == true
        names.remove(at: from)
        if landsLast {
            names.append(name)
            return
        }
        let destination = names.firstIndex(of: target) ?? names.endIndex
        names.insert(name, at: destination)
    }

    static func moveEarlier(_ names: inout [String], name: String) {
        guard let index = names.firstIndex(of: name), index > names.startIndex else { return }
        names.swapAt(names.index(before: index), index)
    }

    static func moveLater(_ names: inout [String], name: String) {
        guard let index = names.firstIndex(of: name) else { return }
        let next = names.index(after: index)
        guard next < names.endIndex else { return }
        names.swapAt(index, next)
    }
}

// MARK: - Adding

/// Exact-string uniqueness for the posted list. A different spelling is a
/// different chip. Casefolding is for the recent list and for hiding a
/// suggestion, not for refusing the add.
enum WritingTagAddition {
    struct Outcome: Equatable {
        var values: [String]
        /// Unchanged when the add is a no-op, so the field stays put.
        var term: String
        var recordedName: String?
    }

    static func apply(name: String, values: [String], term: String) -> Outcome {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !values.contains(value) else {
            return Outcome(values: values, term: term, recordedName: nil)
        }
        return Outcome(values: values + [value], term: "", recordedName: value)
    }

    static func excludesSuggestion(_ name: String, chosen: [String]) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return chosen.contains { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
    }
}

// MARK: - Recently used

/// Tags the reader added, per autocomplete kind, newest first.
///
/// UserDefaults JSON, capped at 20 per kind. Not a SwiftData field and not an
/// AO3 list: the picker reads it back the next time that kind is opened.
struct RecentWritingTags: Equatable, Codable {
    static let cap = 20
    static let storageKey = "writing.recentTags.v1"

    var byKind: [String: [String]]

    init(byKind: [String: [String]] = [:]) {
        self.byKind = byKind
    }

    static func load(from defaults: UserDefaults) -> RecentWritingTags {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(RecentWritingTags.self, from: data)
        else { return RecentWritingTags() }
        return decoded
    }

    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    /// Inserts `name` at the front of `kind`, dropping an older spelling of the
    /// same tag and anything past the cap. `.tag` is the filter picker's "any
    /// tag" endpoint, not one of the four work-tag lists, so it is not stored.
    mutating func record(_ name: String, kind: AO3TagKind) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, kind != .tag else { return }
        var list = byKind[kind.rawValue] ?? []
        list.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        list.insert(trimmed, at: 0)
        if list.count > Self.cap {
            list.removeLast(list.count - Self.cap)
        }
        byKind[kind.rawValue] = list
    }

    func names(kind: AO3TagKind) -> [String] {
        byKind[kind.rawValue] ?? []
    }
}

// MARK: - From your other works

/// Tags already on works the caller has in memory. The function takes that
/// array and returns; it has no client and no URL, so it cannot start a request.
enum WritingOtherWorkTags {
    struct Source: Equatable {
        var workID: Int
        var fandoms: [String] = []
        var characters: [String] = []
        var relationships: [String] = []
        var additionalTags: [String] = []
    }

    static func sources(from works: [AO3WorkSummary]) -> [Source] {
        works.map { work in
            Source(
                workID: work.id,
                fandoms: work.fandoms,
                characters: work.characters,
                relationships: work.relationships,
                additionalTags: work.tags
            )
        }
    }

    /// First-seen order across `works`, skipping blanks, the work being edited,
    /// and names already chosen. Empty means the section stays hidden.
    static func names(
        kind: AO3TagKind,
        works: [Source],
        excluding chosen: [String],
        excludingWorkID: Int?
    ) -> [String] {
        let skip = Set(chosen.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        var seen = Set<String>()
        var result: [String] = []
        for work in works where work.workID != excludingWorkID {
            for name in list(kind, on: work) {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                let key = trimmed.lowercased()
                guard !key.isEmpty, !skip.contains(key), seen.insert(key).inserted else { continue }
                result.append(trimmed)
            }
        }
        return result
    }

    private static func list(_ kind: AO3TagKind, on work: Source) -> [String] {
        switch kind {
        case .fandom: work.fandoms
        case .character: work.characters
        case .relationship: work.relationships
        case .freeform: work.additionalTags
        case .tag: []
        }
    }
}

// MARK: - Environment

/// Loaded author-works blurbs, handed down by the profile that already fetched
/// them. Empty everywhere else, which hides the section.
private struct WritingOtherWorksKey: EnvironmentKey {
    static let defaultValue: [WritingOtherWorkTags.Source] = []
}

/// The work whose tags are open, so its own tags are not offered as "other".
private struct WritingEditedWorkIDKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

extension EnvironmentValues {
    var writingOtherWorks: [WritingOtherWorkTags.Source] {
        get { self[WritingOtherWorksKey.self] }
        set { self[WritingOtherWorksKey.self] = newValue }
    }

    var writingEditedWorkID: Int? {
        get { self[WritingEditedWorkIDKey.self] }
        set { self[WritingEditedWorkIDKey.self] = newValue }
    }
}
