import Foundation
import SwiftData

/// Persistent user configuration for Reading Insights (D5).
///
/// Stored locally in `UserDefaults` and optionally carried in `KudosBackupSettings`
/// so backups and Folder Sync can mirror choices without breaking older payloads.
nonisolated struct InsightsOptions: Equatable, Sendable {
    var discreetMode: Bool
    var hideReadingTime: Bool
    var countRereads: Bool
    var countReadAloud: Bool
    var askAboutUntouched: Bool
    var untouchedDays: Int
    var excludedFandoms: [String]
    var excludedTags: [String]
    var excludedWorkIDs: [String]

    init(
        discreetMode: Bool = false,
        hideReadingTime: Bool = false,
        countRereads: Bool = true,
        countReadAloud: Bool = true,
        askAboutUntouched: Bool = true,
        untouchedDays: Int = Self.defaultUntouchedDays,
        excludedFandoms: [String] = [],
        excludedTags: [String] = [],
        excludedWorkIDs: [String] = []
    ) {
        self.discreetMode = discreetMode
        self.hideReadingTime = hideReadingTime
        self.countRereads = countRereads
        self.countReadAloud = countReadAloud
        self.askAboutUntouched = askAboutUntouched
        self.untouchedDays = Self.clampUntouchedDays(untouchedDays)
        self.excludedFandoms = Self.normalizedNames(excludedFandoms)
        self.excludedTags = Self.normalizedNames(excludedTags)
        self.excludedWorkIDs = Self.normalizedWorkIDs(excludedWorkIDs)
    }

    static let defaultUntouchedDays = 21
    static let untouchedDaysRange = 1...365

    enum Keys {
        static let discreetMode = "kudos.insights.discreetMode"
        static let hideReadingTime = "kudos.insights.hideReadingTime"
        static let countRereads = "kudos.insights.countRereads"
        static let countReadAloud = "kudos.insights.countReadAloud"
        static let askAboutUntouched = "kudos.insights.askAboutUntouched"
        static let untouchedDays = "kudos.insights.untouchedDays"
        static let excludedFandoms = "kudos.insights.excludedFandoms"
        static let excludedTags = "kudos.insights.excludedTags"
        static let excludedWorkIDs = "kudos.insights.excludedWorkIDs"
    }

    var excludedCount: Int {
        excludedFandoms.count + excludedTags.count + excludedWorkIDs.count
    }

    var untouchedThresholdInterval: TimeInterval {
        TimeInterval(clampedUntouchedDays) * 86_400
    }

    var clampedUntouchedDays: Int {
        Self.clampUntouchedDays(untouchedDays)
    }

    static func clampUntouchedDays(_ value: Int) -> Int {
        min(untouchedDaysRange.upperBound, max(untouchedDaysRange.lowerBound, value))
    }

    static func normalizedNames(_ raw: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for entry in raw {
            let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                result.append(trimmed)
            }
        }
        return result
    }

    static func normalizedWorkIDs(_ raw: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for entry in raw {
            let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let canonical = UUID(uuidString: trimmed)?.uuidString.lowercased() ?? trimmed.lowercased()
            if seen.insert(canonical).inserted {
                result.append(canonical)
            }
        }
        return result
    }

    static func load(from defaults: UserDefaults = .standard) -> InsightsOptions {
        let discreetMode = defaults.object(forKey: Keys.discreetMode) == nil
            ? false : defaults.bool(forKey: Keys.discreetMode)
        let hideReadingTime = defaults.object(forKey: Keys.hideReadingTime) == nil
            ? false : defaults.bool(forKey: Keys.hideReadingTime)
        let countRereads = defaults.object(forKey: Keys.countRereads) == nil
            ? true : defaults.bool(forKey: Keys.countRereads)
        let countReadAloud = defaults.object(forKey: Keys.countReadAloud) == nil
            ? true : defaults.bool(forKey: Keys.countReadAloud)
        let askAboutUntouched = defaults.object(forKey: Keys.askAboutUntouched) == nil
            ? true : defaults.bool(forKey: Keys.askAboutUntouched)
        let rawDays = defaults.object(forKey: Keys.untouchedDays) == nil
            ? defaultUntouchedDays : defaults.integer(forKey: Keys.untouchedDays)
        let excludedFandoms = normalizedNames(defaults.stringArray(forKey: Keys.excludedFandoms) ?? [])
        let excludedTags = normalizedNames(defaults.stringArray(forKey: Keys.excludedTags) ?? [])
        let excludedWorkIDs = normalizedWorkIDs(defaults.stringArray(forKey: Keys.excludedWorkIDs) ?? [])
        return InsightsOptions(
            discreetMode: discreetMode,
            hideReadingTime: hideReadingTime,
            countRereads: countRereads,
            countReadAloud: countReadAloud,
            askAboutUntouched: askAboutUntouched,
            untouchedDays: clampUntouchedDays(rawDays),
            excludedFandoms: excludedFandoms,
            excludedTags: excludedTags,
            excludedWorkIDs: excludedWorkIDs
        )
    }

    func save(to defaults: UserDefaults = .standard, notifySync: Bool = true) {
        defaults.set(discreetMode, forKey: Keys.discreetMode)
        defaults.set(hideReadingTime, forKey: Keys.hideReadingTime)
        defaults.set(countRereads, forKey: Keys.countRereads)
        defaults.set(countReadAloud, forKey: Keys.countReadAloud)
        defaults.set(askAboutUntouched, forKey: Keys.askAboutUntouched)
        defaults.set(clampedUntouchedDays, forKey: Keys.untouchedDays)
        defaults.set(Self.normalizedNames(excludedFandoms), forKey: Keys.excludedFandoms)
        defaults.set(Self.normalizedNames(excludedTags), forKey: Keys.excludedTags)
        defaults.set(Self.normalizedWorkIDs(excludedWorkIDs), forKey: Keys.excludedWorkIDs)
        if notifySync {
            NotificationCenter.default.post(name: .kudosSyncRelevantSettingChanged, object: nil)
        }
    }

    // MARK: - Single Filter Function

    /// Computes normalized exclusion lookup sets once for a gather pass.
    private struct ExclusionMatchers {
        let excludedWorkIDs: Set<String>
        let excludedFandomKeys: Set<String>
        let excludedTagKeys: Set<String>

        init(options: InsightsOptions, aliases: TagAliasResolver) {
            excludedWorkIDs = Set(InsightsOptions.normalizedWorkIDs(options.excludedWorkIDs))

            var fandomKeys: Set<String> = []
            for name in options.excludedFandoms {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                fandomKeys.insert(trimmed.lowercased())
                let resolved = aliases.resolve(trimmed, kind: .fandom)
                if !resolved.isEmpty { fandomKeys.insert(resolved.lowercased()) }
            }
            excludedFandomKeys = fandomKeys

            var tagKeys: Set<String> = []
            for name in options.excludedTags {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                tagKeys.insert(trimmed.lowercased())
                for kind in TagAliasKind.allCases where kind != .fandom {
                    let resolved = aliases.resolve(trimmed, kind: kind)
                    if !resolved.isEmpty { tagKeys.insert(resolved.lowercased()) }
                }
            }
            excludedTagKeys = tagKeys
        }

        func containsFandom(_ candidates: [String], aliases: TagAliasResolver) -> Bool {
            guard !excludedFandomKeys.isEmpty else { return false }
            for raw in candidates {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                if excludedFandomKeys.contains(trimmed.lowercased()) { return true }
                let resolved = aliases.resolve(trimmed, kind: .fandom)
                if !resolved.isEmpty && excludedFandomKeys.contains(resolved.lowercased()) { return true }
            }
            return false
        }

        func containsTag(_ candidates: [(String, TagAliasKind?)], aliases: TagAliasResolver) -> Bool {
            guard !excludedTagKeys.isEmpty else { return false }
            for (raw, kind) in candidates {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                if excludedTagKeys.contains(trimmed.lowercased()) { return true }
                if let kind {
                    let resolved = aliases.resolve(trimmed, kind: kind)
                    if !resolved.isEmpty && excludedTagKeys.contains(resolved.lowercased()) { return true }
                }
            }
            return false
        }
    }

    /// **The single filter point** where Reading Insights and Export gather data.
    ///
    /// Applies work/fandom/tag exclusions (checking both live `SavedWork` and
    /// `ReadingSession` D1 snapshot fields), Read Aloud inclusion (`countReadAloud`),
    /// and reread exclusion (`countRereads`, keeping only first read-through sessions).
    @MainActor
    func filter(
        sessions: [ReadingSession],
        works: [SavedWork],
        aliases: TagAliasResolver = .empty
    ) -> InsightsFilteredData {
        let matchers = ExclusionMatchers(options: self, aliases: aliases)

        var excludedLiveWorkIDs: Set<UUID> = []
        var includedWorks: [SavedWork] = []
        includedWorks.reserveCapacity(works.count)

        for work in works {
            let workIDKey = work.id.uuidString.lowercased()
            let isWorkIDExcluded = matchers.excludedWorkIDs.contains(workIDKey)
            if isWorkIDExcluded || isExcluded(work: work, matchers: matchers, aliases: aliases) {
                excludedLiveWorkIDs.insert(work.id)
                continue
            }
            includedWorks.append(work)
        }

        var filteredSessions: [ReadingSession] = []
        filteredSessions.reserveCapacity(sessions.count)

        for session in sessions {
            if !countReadAloud && session.mode == .listen {
                continue
            }
            let sessionWorkKey = session.workID.uuidString.lowercased()
            if matchers.excludedWorkIDs.contains(sessionWorkKey) || excludedLiveWorkIDs.contains(session.workID) {
                continue
            }
            if isExcluded(session: session, matchers: matchers, aliases: aliases) {
                continue
            }
            filteredSessions.append(session)
        }

        if !countRereads {
            let firstReadIDs = Self.firstReadThroughSessionIDs(from: filteredSessions)
            filteredSessions = filteredSessions.filter { firstReadIDs.contains($0.id) }
        }

        return InsightsFilteredData(works: includedWorks, sessions: filteredSessions)
    }

    @MainActor
    private func isExcluded(work: SavedWork, matchers: ExclusionMatchers, aliases: TagAliasResolver) -> Bool {
        let fandomCandidates = work.workFandoms.isEmpty ? work.workTags : work.workFandoms
        if matchers.containsFandom(fandomCandidates, aliases: aliases) {
            return true
        }
        var tagCandidates: [(String, TagAliasKind?)] = []
        for entry in work.workFreeforms { tagCandidates.append((entry, .freeform)) }
        for entry in work.workTags { tagCandidates.append((entry, .freeform)) }
        for entry in work.workRelationships { tagCandidates.append((entry, .relationship)) }
        for entry in work.workCharacters { tagCandidates.append((entry, .character)) }
        for entry in work.workWarnings { tagCandidates.append((entry, nil)) }
        for tag in work.tags { tagCandidates.append((tag.name, nil)) }
        if !work.stopTag.isEmpty { tagCandidates.append((work.stopTag, .freeform)) }
        return matchers.containsTag(tagCandidates, aliases: aliases)
    }

    @MainActor
    private func isExcluded(session: ReadingSession, matchers: ExclusionMatchers, aliases: TagAliasResolver) -> Bool {
        if matchers.containsFandom(session.fandoms, aliases: aliases) {
            return true
        }
        var tagCandidates: [(String, TagAliasKind?)] = []
        for entry in session.freeformTags { tagCandidates.append((entry, .freeform)) }
        for entry in session.relationships { tagCandidates.append((entry, .relationship)) }
        for entry in session.characters { tagCandidates.append((entry, .character)) }
        for entry in session.warnings { tagCandidates.append((entry, nil)) }
        return matchers.containsTag(tagCandidates, aliases: aliases)
    }

    /// Returns the IDs of sessions belonging to each work's first read-through
    /// (`readThrough == 1`, matching `ReadingHistoryTimeline`'s reread boundary:
    /// every chronological sitting up to and including the first `didFinish == true`).
    @MainActor
    static func firstReadThroughSessionIDs(from sessions: [ReadingSession]) -> Set<UUID> {
        var keep: Set<UUID> = []
        for group in Dictionary(grouping: sessions, by: \.workID).values {
            let sorted = group.sorted {
                ($0.startedAt, $0.id.uuidString) < ($1.startedAt, $1.id.uuidString)
            }
            var finishes = 0
            for session in sorted {
                if finishes == 0 {
                    keep.insert(session.id)
                }
                if session.didFinish {
                    finishes += 1
                }
            }
        }
        return keep
    }
}

/// Result of `InsightsOptions.filter(sessions:works:aliases:)`.
@MainActor
struct InsightsFilteredData {
    var works: [SavedWork]
    var sessions: [ReadingSession]
}

// MARK: - Discreet Mode Masker

/// Produces stable Discreet Mode placeholders (`"Fandom A"`, `"Ship B"`,
/// `"Character C"`, `"Tag D"`, `"Work E"`, `"Author F"`) within a single
/// Insights screen snapshot or a single Export run.
nonisolated struct InsightsDiscreetMasker: Equatable, Sendable {
    enum Category: Sendable {
        case fandom
        case ship
        case character
        case tag
        case work
        case author

        var prefix: String {
            switch self {
            case .fandom: return "Fandom"
            case .ship: return "Ship"
            case .character: return "Character"
            case .tag: return "Tag"
            case .work: return "Work"
            case .author: return "Author"
            }
        }
    }

    private let fandomMap: [String: String]
    private let shipMap: [String: String]
    private let characterMap: [String: String]
    private let tagMap: [String: String]
    private let workByIDMap: [UUID: String]
    private let workByTitleMap: [String: String]
    private let authorMap: [String: String]
    private let aliases: TagAliasResolver

    static let empty = InsightsDiscreetMasker(
        fandomMap: [:],
        shipMap: [:],
        characterMap: [:],
        tagMap: [:],
        workByIDMap: [:],
        workByTitleMap: [:],
        authorMap: [:],
        aliases: .empty
    )

    static func letterCode(for index: Int) -> String {
        var value = max(0, index)
        var result = ""
        repeat {
            let remainder = value % 26
            if let scalar = UnicodeScalar(65 + remainder) {
                result = String(Character(scalar)) + result
            }
            value = (value / 26) - 1
        } while value >= 0
        return result
    }

    private static func normalizedKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Accumulates real entities in deterministic presentation order and emits
    /// stable alphabetical labels per category.
    struct Builder {
        private let aliases: TagAliasResolver
        private var fandoms: [String: String] = [:]
        private var ships: [String: String] = [:]
        private var characters: [String: String] = [:]
        private var tags: [String: String] = [:]
        private var worksByID: [UUID: String] = [:]
        private var worksByTitle: [String: String] = [:]
        private var authors: [String: String] = [:]

        init(aliases: TagAliasResolver = .empty) {
            self.aliases = aliases
        }

        mutating func registerFandom(_ raw: String) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != ReadingInsights.remainderName else { return }
            let resolved = aliases.resolve(trimmed, kind: .fandom)
            let key = resolved.lowercased()
            guard fandoms[key] == nil else { return }
            fandoms[key] = "\(Category.fandom.prefix) \(letterCode(for: fandoms.count))"
        }

        mutating func registerShip(_ raw: String) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let resolved = aliases.resolve(trimmed, kind: .relationship)
            let key = resolved.lowercased()
            guard ships[key] == nil else { return }
            ships[key] = "\(Category.ship.prefix) \(letterCode(for: ships.count))"
        }

        mutating func registerCharacter(_ raw: String) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let resolved = aliases.resolve(trimmed, kind: .character)
            let key = resolved.lowercased()
            guard characters[key] == nil else { return }
            characters[key] = "\(Category.character.prefix) \(letterCode(for: characters.count))"
        }

        mutating func registerTag(_ raw: String) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let resolved = aliases.resolve(trimmed, kind: .freeform)
            let key = resolved.lowercased()
            guard tags[key] == nil else { return }
            tags[key] = "\(Category.tag.prefix) \(letterCode(for: tags.count))"
        }

        mutating func registerWork(id: UUID, title: String) {
            if worksByID[id] == nil {
                worksByID[id] = "\(Category.work.prefix) \(letterCode(for: worksByID.count))"
            }
            let titleKey = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !titleKey.isEmpty, worksByTitle[titleKey] == nil {
                worksByTitle[titleKey] = worksByID[id]
            }
        }

        mutating func registerAuthor(_ raw: String) {
            let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty else { return }
            guard authors[key] == nil else { return }
            authors[key] = "\(Category.author.prefix) \(letterCode(for: authors.count))"
        }

        func build() -> InsightsDiscreetMasker {
            InsightsDiscreetMasker(
                fandomMap: fandoms,
                shipMap: ships,
                characterMap: characters,
                tagMap: tags,
                workByIDMap: worksByID,
                workByTitleMap: worksByTitle,
                authorMap: authors,
                aliases: aliases
            )
        }
    }

    func fandom(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == ReadingInsights.remainderName { return trimmed }
        guard !trimmed.isEmpty else { return Category.fandom.prefix }
        let resolved = aliases.resolve(trimmed, kind: .fandom)
        return fandomMap[resolved.lowercased()]
            ?? fandomMap[trimmed.lowercased()]
            ?? Category.fandom.prefix
    }

    func ship(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Category.ship.prefix }
        let resolved = aliases.resolve(trimmed, kind: .relationship)
        return shipMap[resolved.lowercased()]
            ?? shipMap[trimmed.lowercased()]
            ?? Category.ship.prefix
    }

    func character(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Category.character.prefix }
        let resolved = aliases.resolve(trimmed, kind: .character)
        return characterMap[resolved.lowercased()]
            ?? characterMap[trimmed.lowercased()]
            ?? Category.character.prefix
    }

    func tag(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Category.tag.prefix }
        let resolved = aliases.resolve(trimmed, kind: .freeform)
        return tagMap[resolved.lowercased()]
            ?? tagMap[trimmed.lowercased()]
            ?? Category.tag.prefix
    }

    func work(id: UUID, title: String = "") -> String {
        if let mapped = workByIDMap[id] { return mapped }
        let key = Self.normalizedKey(title)
        if !key.isEmpty, let byTitle = workByTitleMap[key] { return byTitle }
        return Category.work.prefix
    }

    func author(_ raw: String) -> String {
        let key = Self.normalizedKey(raw)
        guard !key.isEmpty else { return Category.author.prefix }
        return authorMap[key] ?? Category.author.prefix
    }

    /// Snapshot inputs used to seed deterministic Discreet Mode labels.
    @MainActor
    struct ScreenSeed {
        var insights: ReadingInsights
        var taste: ReadingTasteInsights?
        var habits: ReadingHabitsInsights?
        var library: ReadingLibraryInsights?
        var stats: ReadingStatistics?
        var finishedWorks: [SavedWork]
        var works: [SavedWork]
        var sessions: [ReadingSession]
    }

    /// Builds a screen-wide masker seeded in visible card order, then falls back
    /// through remaining filtered works and sessions so every entity on every tab
    /// gets a stable alphabetical placeholder.
    @MainActor
    static func forScreen(
        _ seed: ScreenSeed,
        aliases: TagAliasResolver = .empty
    ) -> InsightsDiscreetMasker {
        var builder = Builder(aliases: aliases)
        registerOverview(seed.insights, finishedWorks: seed.finishedWorks, into: &builder)
        registerTaste(seed.taste, into: &builder)
        registerHabits(seed.habits, into: &builder)
        registerLibrary(seed.library, stats: seed.stats, into: &builder)
        registerRemaining(works: seed.works, sessions: seed.sessions, into: &builder)
        return builder.build()
    }

    @MainActor
    private static func registerOverview(
        _ insights: ReadingInsights,
        finishedWorks: [SavedWork],
        into builder: inout Builder
    ) {
        for item in insights.fandomWordsShares where !item.isRemainder {
            builder.registerFandom(item.name)
        }
        for item in insights.byFandom where !item.isRemainder {
            builder.registerFandom(item.name)
        }
        for work in finishedWorks {
            builder.registerWork(id: work.id, title: work.title)
            work.workFandoms.forEach { builder.registerFandom($0) }
            work.workTags.forEach { builder.registerTag($0) }
        }
    }

    private static func registerTaste(_ taste: ReadingTasteInsights?, into builder: inout Builder) {
        guard let taste else { return }
        for fandom in taste.fandoms where !fandom.isRemainder {
            builder.registerFandom(fandom.name)
        }
        for rel in taste.relationships {
            builder.registerShip(rel.name)
            if !rel.fandom.isEmpty { builder.registerFandom(rel.fandom) }
        }
        for conc in taste.shipConcentrations where !conc.fandom.isEmpty {
            builder.registerFandom(conc.fandom)
        }
        for charItem in taste.characters {
            builder.registerCharacter(charItem.name)
            if !charItem.fandom.isEmpty { builder.registerFandom(charItem.fandom) }
        }
        taste.tags.forEach { builder.registerTag($0.name) }
        for pair in taste.oftenTogether {
            builder.registerTag(pair.tagA)
            builder.registerTag(pair.tagB)
        }
    }

    private static func registerHabits(_ habits: ReadingHabitsInsights?, into builder: inout Builder) {
        guard let habits else { return }
        for reread in habits.rereads {
            builder.registerWork(id: reread.id, title: reread.title)
            if !reread.fandom.isEmpty { builder.registerFandom(reread.fandom) }
        }
        habits.fandomTimeline.forEach { builder.registerFandom($0.name) }
        habits.commonStopTags.forEach { builder.registerTag($0.name) }
    }

    private static func registerLibrary(
        _ library: ReadingLibraryInsights?,
        stats: ReadingStatistics?,
        into builder: inout Builder
    ) {
        if let candidate = library?.stillReadingCandidate {
            builder.registerWork(id: candidate.id, title: candidate.title)
            if !candidate.fandom.isEmpty { builder.registerFandom(candidate.fandom) }
        }
        stats?.topFandoms.forEach { builder.registerFandom($0.name) }
    }

    @MainActor
    private static func registerRemaining(
        works: [SavedWork],
        sessions: [ReadingSession],
        into builder: inout Builder
    ) {
        let sortedWorks = works.sorted {
            ($0.title, $0.id.uuidString) < ($1.title, $1.id.uuidString)
        }
        for work in sortedWorks {
            builder.registerWork(id: work.id, title: work.title)
            builder.registerAuthor(work.author)
            work.workFandoms.forEach { builder.registerFandom($0) }
            work.workRelationships.forEach { builder.registerShip($0) }
            work.workCharacters.forEach { builder.registerCharacter($0) }
            (work.workFreeforms + work.workTags).forEach { builder.registerTag($0) }
            if !work.stopTag.isEmpty { builder.registerTag(work.stopTag) }
        }

        let sortedSessions = sessions.sorted {
            ($0.startedAt, $0.id.uuidString) < ($1.startedAt, $1.id.uuidString)
        }
        for session in sortedSessions {
            builder.registerWork(id: session.workID, title: session.workTitle)
            session.authorAccounts.forEach { builder.registerAuthor($0) }
            session.fandoms.forEach { builder.registerFandom($0) }
            session.relationships.forEach { builder.registerShip($0) }
            session.characters.forEach { builder.registerCharacter($0) }
            session.freeformTags.forEach { builder.registerTag($0) }
        }
    }
}
