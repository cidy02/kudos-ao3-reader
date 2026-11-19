import Foundation

/// A smart queue's rules, stored as one JSON string on `ReadingQueue.smartRulesJSON`.
///
/// Not a SwiftData composite: a composite whose `CodingKeys` omit a stored property
/// crashes every later fetch. The queue holds the encoded document and nothing else.
/// Members are computed from the library; they are never memberships.
nonisolated struct SmartQueueDocument: Codable, Equatable, Sendable, Hashable {
    var match: Match
    var rules: [Rule]
    var sort: Sort
    var limit: Int?

    static let starter = SmartQueueDocument(
        match: .all,
        rules: [],
        sort: .shortestFirst,
        limit: 25
    )

    /// `nil` and any limit of 0 or less mean no cap. An empty rule list matches
    /// nothing: "all of no rules" must not mean the whole library.
    func matching(
        _ works: [SmartQueueWorkFacts],
        aliases: TagAliasResolver = .empty
    ) -> [SmartQueueWorkFacts] {
        guard !rules.isEmpty else { return [] }
        let hits = works.filter { work in
            switch match {
            case .all: rules.allSatisfy { $0.matches(work, aliases: aliases) }
            case .any: rules.contains { $0.matches(work, aliases: aliases) }
            }
        }
        let ordered = Self.ordered(hits, by: sort)
        guard let limit, limit > 0 else { return ordered }
        return Array(ordered.prefix(limit))
    }

    var limitTitle: String {
        guard let limit, limit > 0 else { return "No limit" }
        return limit == 1 ? "1 work" : "\(limit.formatted()) works"
    }

    static let limitChoices: [Int?] = [10, 25, 50, 100, nil]

    enum Match: String, Codable, Sendable, CaseIterable, Hashable {
        case all
        case any

        var title: String {
            switch self {
            case .all: "All rules"
            case .any: "Any rule"
            }
        }
    }

    enum Sort: String, Codable, Sendable, CaseIterable, Hashable {
        case shortestFirst
        case longestFirst
        case recentlyAdded
        case title

        var title: String {
            switch self {
            case .shortestFirst: "Shortest first"
            case .longestFirst: "Longest first"
            case .recentlyAdded: "Recently added"
            case .title: "Title"
            }
        }
    }

    struct Rule: Codable, Equatable, Sendable, Hashable, Identifiable {
        var id: UUID
        var kind: Kind
        var lengthComparison: LengthComparison?
        var words: Int?
        var readingStatus: SmartQueueReadingStatus?
        var progress: Progress?
        var completion: Completion?
        var fandom: String?

        enum Kind: String, Codable, Sendable, CaseIterable, Hashable {
            case length
            case readingStatus
            case progress
            case completion
            case fandom

            /// Board order, then the two kinds the board does not draw.
            static let addOrder: [Kind] = [.length, .completion, .progress, .readingStatus, .fandom]

            var rowLabel: String {
                switch self {
                case .length: "Length"
                case .readingStatus: "Reading"
                case .progress: "Progress"
                case .completion: "Status"
                case .fandom: "Fandom"
                }
            }

            func makeDefault() -> Rule {
                switch self {
                case .length:
                    Rule(id: UUID(), kind: .length, lengthComparison: .under, words: 20_000)
                case .readingStatus:
                    Rule(id: UUID(), kind: .readingStatus, readingStatus: .reading)
                case .progress:
                    Rule(id: UUID(), kind: .progress, progress: .notStarted)
                case .completion:
                    Rule(id: UUID(), kind: .completion, completion: .complete)
                case .fandom:
                    Rule(id: UUID(), kind: .fandom, fandom: "")
                }
            }
        }

        enum LengthComparison: String, Codable, Sendable, CaseIterable, Hashable {
            case under
            case atLeast

            var title: String {
                switch self {
                case .under: "Under"
                case .atLeast: "At least"
                }
            }
        }

        enum Progress: String, Codable, Sendable, CaseIterable, Hashable {
            case notStarted
            case inProgress
            case finished

            var title: String {
                switch self {
                case .notStarted: "Not started"
                case .inProgress: "In progress"
                case .finished: "Finished"
                }
            }
        }

        enum Completion: String, Codable, Sendable, CaseIterable, Hashable {
            case complete
            case wip

            var title: String {
                switch self {
                case .complete: "Complete"
                case .wip: "WIP"
                }
            }
        }

        var summary: String {
            switch kind {
            case .length:
                guard let words, words >= 0 else { return "Choose a word count" }
                let count = words.formatted()
                switch lengthComparison ?? .under {
                case .under: return "Under \(count) words"
                case .atLeast: return "At least \(count) words"
                }
            case .readingStatus:
                return readingStatus?.title ?? "Choose a status"
            case .progress:
                return (progress ?? .notStarted).title
            case .completion:
                return (completion ?? .complete).title
            case .fandom:
                let name = fandom?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return name.isEmpty ? "Choose a fandom" : name
            }
        }

        func matches(
            _ work: SmartQueueWorkFacts,
            aliases: TagAliasResolver = .empty
        ) -> Bool {
            switch kind {
            case .length:
                // 0 is "word count unknown", not a length match in either direction.
                guard let words, words >= 0, work.wordCount > 0 else { return false }
                switch lengthComparison ?? .under {
                case .under:
                    return work.wordCount < words
                case .atLeast:
                    return work.wordCount >= words
                }
            case .readingStatus:
                guard let readingStatus else { return false }
                return work.readingStatus == readingStatus
            case .progress:
                switch progress ?? .notStarted {
                case .notStarted: return !work.hasStartedReading && !work.isFinished
                case .inProgress: return work.hasStartedReading && !work.isFinished
                case .finished: return work.isFinished
                }
            case .completion:
                switch completion ?? .complete {
                case .complete: return work.isComplete
                case .wip: return !work.isComplete
                }
            case .fandom:
                let wanted = aliases.resolveIgnoringCase(fandom ?? "", kind: .fandom)
                guard !wanted.isEmpty else { return false }
                return work.fandoms.contains {
                    aliases.resolveIgnoringCase($0, kind: .fandom).caseInsensitiveCompare(wanted) == .orderedSame
                }
            }
        }
    }

    init(match: Match, rules: [Rule], sort: Sort, limit: Int?) {
        self.match = match
        self.rules = rules
        self.sort = sort
        self.limit = limit
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        match = try container.decodeIfPresent(Match.self, forKey: .match) ?? .all
        rules = try container.decodeIfPresent([Rule].self, forKey: .rules) ?? []
        sort = try container.decodeIfPresent(Sort.self, forKey: .sort) ?? .shortestFirst
        limit = try container.decodeIfPresent(Int.self, forKey: .limit)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(match, forKey: .match)
        try container.encode(rules, forKey: .rules)
        try container.encode(sort, forKey: .sort)
        try container.encodeIfPresent(limit, forKey: .limit)
    }

    private enum CodingKeys: String, CodingKey {
        case match, rules, sort, limit
    }

    private static func ordered(_ works: [SmartQueueWorkFacts], by sort: Sort) -> [SmartQueueWorkFacts] {
        works.sorted { lhs, rhs in
            switch sort {
            case .shortestFirst:
                return lengthOrder(lhs, rhs, longest: false)
            case .longestFirst:
                return lengthOrder(lhs, rhs, longest: true)
            case .recentlyAdded:
                if lhs.dateAdded != rhs.dateAdded { return lhs.dateAdded > rhs.dateAdded }
                return titleOrder(lhs, rhs)
            case .title:
                return titleOrder(lhs, rhs)
            }
        }
    }

    /// Unknown word counts (0) sort last for both directions, then title.
    private static func lengthOrder(
        _ lhs: SmartQueueWorkFacts,
        _ rhs: SmartQueueWorkFacts,
        longest: Bool
    ) -> Bool {
        let lhsUnknown = lhs.wordCount <= 0
        let rhsUnknown = rhs.wordCount <= 0
        if lhsUnknown != rhsUnknown { return rhsUnknown }
        if !lhsUnknown, lhs.wordCount != rhs.wordCount {
            return longest ? lhs.wordCount > rhs.wordCount : lhs.wordCount < rhs.wordCount
        }
        return titleOrder(lhs, rhs)
    }

    private static func titleOrder(_ lhs: SmartQueueWorkFacts, _ rhs: SmartQueueWorkFacts) -> Bool {
        let compared = lhs.title.localizedStandardCompare(rhs.title)
        if compared != .orderedSame { return compared == .orderedAscending }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

/// The slice of a library work a smart queue is allowed to see. Privacy stays
/// in the views that draw the result; this type does not know about it.
nonisolated struct SmartQueueWorkFacts: Equatable, Sendable, Hashable, Identifiable {
    var id: UUID
    var title: String
    var wordCount: Int
    var dateAdded: Date
    var isComplete: Bool
    var isFinished: Bool
    var hasStartedReading: Bool
    var readingStatus: SmartQueueReadingStatus
    var fandoms: [String]
}

/// Insights' partition, with its "saved for later" bucket named as not started.
nonisolated enum SmartQueueReadingStatus: String, Codable, Sendable, CaseIterable, Hashable {
    case notStarted
    case reading
    case onHold
    case stacking
    case stopped
    case caughtUp
    case finished

    var title: String {
        switch self {
        case .notStarted: "Not started"
        case .reading: "Reading"
        case .onHold: "On hold"
        case .stacking: "Stacking"
        case .stopped: "Stopped"
        case .caughtUp: "Caught up"
        case .finished: "Finished"
        }
    }

    init(_ status: SavedWork.InsightsReadingStatus) {
        switch status {
        case .stopped: self = .stopped
        case .onHold: self = .onHold
        case .stacking: self = .stacking
        case .finished: self = .finished
        case .caughtUp: self = .caughtUp
        case .reading: self = .reading
        case .savedForLater: self = .notStarted
        }
    }
}

enum SmartQueueRules {
    /// `nil` when the document cannot be encoded. Callers keep the previous string.
    static func encode(_ document: SmartQueueDocument) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(document) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// `nil` for a missing, empty, or unreadable document. Does not rewrite the
    /// stored string: a future rule kind fails the decode and the editor leaves it.
    static func decode(_ json: String?) -> SmartQueueDocument? {
        guard let json, let data = json.data(using: .utf8), !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(SmartQueueDocument.self, from: data)
    }
}

extension SmartQueueWorkFacts {
    @MainActor
    init(work: SavedWork) {
        self.init(
            id: work.id,
            title: work.title,
            wordCount: work.wordCount,
            dateAdded: work.dateAdded,
            isComplete: work.isComplete,
            isFinished: work.isFinished,
            hasStartedReading: work.hasStartedReading,
            readingStatus: SmartQueueReadingStatus(work.insightsReadingStatus),
            fandoms: work.workFandoms
        )
    }
}
