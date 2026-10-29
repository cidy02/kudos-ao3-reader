import Foundation

/// T-473's "Then Rank Loaded Works by": orders worked out from the figures AO3
/// already printed on each loaded blurb (kudos, hits, comments, bookmarks, words,
/// the updated date).
///
/// These rank only the works already on screen. They never ask AO3 for more pages
/// (docs/AO3_NETWORKING_POLICY.md): what is loaded is what is ranked, and the
/// order is recomputed from `results` whenever that list changes.
enum LoadedWorksRank: String, CaseIterable, Identifiable {
    case ao3Order
    case kudosPerHitAdjusted
    case savesPerKudos
    case commentsPerKudos
    case momentum
    case kudosPerThousandWords

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ao3Order: "AO3’s Order"
        case .kudosPerHitAdjusted: "Kudos per Hit, Adjusted"
        case .savesPerKudos: "Saves per Kudos"
        case .commentsPerKudos: "Comments per Kudos"
        case .momentum: "Momentum"
        case .kudosPerThousandWords: "Kudos per 1,000 Words"
        }
    }

    var subtitle: String {
        switch self {
        case .ao3Order: "As AO3 sent them"
        // Length and age, not the spec's "length, chapters and age": with one page
        // of works a third axis leaves almost every group empty, and the word count
        // already tracks the chapter count closely.
        case .kudosPerHitAdjusted: "Against loaded works of similar length and age"
        case .savesPerKudos: "Public bookmarks ÷ kudos"
        case .commentsPerKudos: "Comments ÷ kudos"
        case .momentum: "Kudos gained since you last saw each work"
        case .kudosPerThousandWords: "Kudos ÷ word count × 1,000"
        }
    }
}

enum LoadedWorksRankOrder: String, CaseIterable, Identifiable {
    case highestFirst
    case lowestFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .highestFirst: "Highest First"
        case .lowestFirst: "Lowest First"
        }
    }
}

/// The Sort By screen's ranking choices. Held by Search for the session, beside its
/// filters, and applied as they are tapped: ranking costs no request.
///
/// Not in `AO3SearchFilters`: that struct is a SwiftData composite attribute
/// (`SavedSearch.filters`) and a backup payload, and none of this is sent to AO3.
struct LoadedWorksRanking: Equatable {
    var rank: LoadedWorksRank = .ao3Order
    var order: LoadedWorksRankOrder = .highestFirst
    var ranksCautiously = true
    var setsAsideUnusual = true
    var showsSignal = true

    var isActive: Bool { rank != .ao3Order }

    /// The T-473 row's minimum-hits cut-off: below this a ratio says little.
    static let defaultMinimumHits = "500"

    /// Choosing a rank. Leaving AO3's order also puts AO3's own direction back to
    /// its column's natural one — the Order control now ranks, so a hidden
    /// "ascending" would quietly load the least-liked works — and, when no hits
    /// range is set, seeds the minimum-hits cut-off. That cut-off is an AO3
    /// parameter (`work_search[hits]`), so it takes effect when the search runs.
    mutating func select(_ newRank: LoadedWorksRank, filters: inout AO3SearchFilters) {
        guard newRank != rank else { return }
        if !isActive, newRank != .ao3Order {
            filters.sortDirection = filters.sort.naturalDirection
            if filters.hitsFrom.trimmingCharacters(in: .whitespaces).isEmpty,
               filters.hitsTo.trimmingCharacters(in: .whitespaces).isEmpty {
                filters.hitsFrom = Self.defaultMinimumHits
            }
        }
        rank = newRank
    }
}

/// One loaded work in ranked position.
struct RankedWork: Identifiable {
    let work: AO3WorkSummary
    /// The figure the order was decided on (shrunk when ranking cautiously). nil when
    /// the work's figures cannot give one — no hits, no kudos, no earlier sighting.
    let score: Double?
    let isSetAside: Bool
    /// What "Show the signal on each result" prints under the row's figures.
    let signal: String?

    var id: Int { work.id }
}

enum LoadedWorksRanker {
    /// "Rank cautiously": every ratio is pulled toward the loaded median as if the
    /// work had this many more hits at exactly the median. A work with 50 hits keeps
    /// a tenth of its own figure; one with 20,000 keeps nearly all of it.
    static let cautiousPseudoHits = 500.0
    /// A length × age group needs this many loaded works before its median means
    /// anything; smaller groups fall back to the length alone, then to every work.
    static let minimumGroupSize = 3
    /// "Thousands of kudos and almost no bookmarks": at least this many kudos with
    /// fewer than one bookmark per hundred.
    static let unusualKudosFloor = 1_000

    /// Orders `works` by `settings`. AO3's order is returned untouched.
    ///
    /// Works with a figure come first, highest or lowest first as asked; ties keep
    /// AO3's order. Works with no figure follow in AO3's order, then any set-aside
    /// works, also in AO3's order.
    static func rank(
        _ works: [AO3WorkSummary],
        by settings: LoadedWorksRanking,
        previousKudos: [Int: Int] = [:],
        now: Date = Date()
    ) -> [RankedWork] {
        guard settings.isActive else {
            return works.map { RankedWork(work: $0, score: nil, isSetAside: false, signal: nil) }
        }
        let figures = works.map { Figures($0, now: now) }
        let setAside = figures.map { settings.setsAsideUnusual && isUnusual($0) }
        let raw: [Double?] = works.indices.map { index in
            settings.rank == .momentum
                ? momentum(kudos: figures[index].kudos, previous: previousKudos[works[index].id])
                : rawFigure(settings.rank, figures[index])
        }
        let priors = self.priors(for: settings.rank, figures: figures, raw: raw, setAside: setAside)

        var entries: [(index: Int, entry: RankedWork)] = []
        for index in works.indices {
            let value = raw[index]
            let prior = priors[index]
            let shrunk = value.map { own in
                guard settings.ranksCautiously, let prior else { return own }
                return shrink(own, toward: prior, hits: figures[index].hits)
            }
            let score: Double?
            let shown: Double?
            if settings.rank == .kudosPerHitAdjusted {
                // Against the work's own group: a zero median has nothing to compare with.
                if let prior, prior > 0 {
                    score = shrunk.map { $0 / prior }
                    shown = value.map { $0 / prior }
                } else {
                    score = nil
                    shown = nil
                }
            } else {
                score = shrunk
                shown = value
            }
            entries.append((index: index, entry: RankedWork(
                work: works[index],
                score: score,
                isSetAside: setAside[index],
                signal: signal(settings.rank, shown: shown, setAside: setAside[index],
                               hasPrevious: previousKudos[works[index].id] != nil)
            )))
        }

        let highestFirst = settings.order == .highestFirst
        let ranked = entries
            .filter { !$0.entry.isSetAside && $0.entry.score != nil }
            .sorted { lhs, rhs in
                let left = lhs.entry.score ?? 0
                let right = rhs.entry.score ?? 0
                if left != right { return highestFirst ? left > right : left < right }
                return lhs.index < rhs.index
            }
        let unscored = entries.filter { !$0.entry.isSetAside && $0.entry.score == nil }
        let aside = entries.filter { $0.entry.isSetAside }
        return (ranked + unscored + aside).map { $0.entry }
    }

    // MARK: - Figures

    /// A blurb's figures as numbers. On a full blurb (it always prints a word count)
    /// a missing count is AO3 leaving out a zero; on a sparse row it is unknown —
    /// the same rule `AO3WorkRow.ledgerMetadata` uses.
    struct Figures {
        let kudos: Int?
        let hits: Int?
        let comments: Int?
        let bookmarks: Int?
        let words: Int?
        let lengthGroup: Int?
        let ageGroup: Int?

        init(_ work: AO3WorkSummary, now: Date) {
            let isFullBlurb = work.words != nil
            func count(_ value: Int?) -> Int? { value ?? (isFullBlurb ? 0 : nil) }
            kudos = count(work.kudos)
            hits = count(work.hits)
            comments = count(work.comments)
            bookmarks = count(work.bookmarks)
            words = work.words
            lengthGroup = LoadedWorksRanker.lengthGroup(words: work.words)
            ageGroup = LoadedWorksRanker.ageGroup(updated: WorkStat.date(from: work.dateUpdated), now: now)
        }
    }

    /// Under 10,000 words, under 50,000, and longer.
    static func lengthGroup(words: Int?) -> Int? {
        guard let words else { return nil }
        return words < 10_000 ? 0 : (words < 50_000 ? 1 : 2)
    }

    /// Updated within a year, within three, and older.
    static func ageGroup(updated: Date?, now: Date) -> Int? {
        guard let updated else { return nil }
        let days = now.timeIntervalSince(updated) / 86_400
        return days < 365 ? 0 : (days < 3 * 365 ? 1 : 2)
    }

    /// More kudos than hits, or thousands of kudos with almost no bookmarks.
    static func isUnusual(_ figures: Figures) -> Bool {
        guard let kudos = figures.kudos else { return false }
        if let hits = figures.hits, kudos > hits { return true }
        if kudos >= unusualKudosFloor, let bookmarks = figures.bookmarks, bookmarks * 100 < kudos { return true }
        return false
    }

    /// The work's own ratio for `rank`, never dividing by zero: a zero or unknown
    /// denominator gives nil, and the work is left unranked. Momentum is not a
    /// ratio — see `momentum(kudos:previous:)`.
    static func rawFigure(_ rank: LoadedWorksRank, _ figures: Figures) -> Double? {
        func ratio(_ numerator: Int?, _ denominator: Int?, per scale: Double = 1) -> Double? {
            guard let numerator, let denominator, denominator > 0 else { return nil }
            return Double(numerator) / (Double(denominator) / scale)
        }
        switch rank {
        case .ao3Order, .momentum: return nil
        case .kudosPerHitAdjusted: return ratio(figures.kudos, figures.hits)
        case .savesPerKudos: return ratio(figures.bookmarks, figures.kudos)
        case .commentsPerKudos: return ratio(figures.comments, figures.kudos)
        case .kudosPerThousandWords: return ratio(figures.kudos, figures.words, per: 1_000)
        }
    }

    /// Kudos gained since the work was last seen in results. nil when it has not
    /// been seen before; never negative (AO3 drops kudos from deleted accounts).
    static func momentum(kudos: Int?, previous: Int?) -> Double? {
        guard let kudos, let previous else { return nil }
        return Double(max(0, kudos - previous))
    }

    /// The Bayesian pull: `hits` of evidence at the work's own figure, plus
    /// `cautiousPseudoHits` at the prior. Unknown hits keep the prior alone.
    static func shrink(_ value: Double, toward prior: Double, hits: Int?) -> Double {
        let evidence = Double(max(0, hits ?? 0))
        return (evidence * value + cautiousPseudoHits * prior) / (evidence + cautiousPseudoHits)
    }

    /// Each work's prior: the median of the loaded works it is compared with.
    /// Set-aside works and works with no figure are left out of every median.
    /// Momentum is a count, not a ratio, and has no prior.
    private static func priors(
        for rank: LoadedWorksRank,
        figures: [Figures],
        raw: [Double?],
        setAside: [Bool]
    ) -> [Double?] {
        guard rank != .momentum else { return Array(repeating: nil, count: figures.count) }
        let eligible = figures.indices.filter { raw[$0] != nil && !setAside[$0] }
        let overall = median(eligible.compactMap { raw[$0] })
        guard rank == .kudosPerHitAdjusted else { return Array(repeating: overall, count: figures.count) }

        struct Group: Hashable {
            let length: Int?
            let age: Int?
        }
        var byGroup: [Group: [Double]] = [:]
        var byLength: [Int?: [Double]] = [:]
        for index in eligible {
            guard let value = raw[index] else { continue }
            let figure = figures[index]
            byGroup[Group(length: figure.lengthGroup, age: figure.ageGroup), default: []].append(value)
            byLength[figure.lengthGroup, default: []].append(value)
        }
        return figures.map { figure in
            let group = byGroup[Group(length: figure.lengthGroup, age: figure.ageGroup)] ?? []
            if group.count >= minimumGroupSize { return median(group) }
            let length = byLength[figure.lengthGroup] ?? []
            if length.count >= minimumGroupSize { return median(length) }
            return overall
        }
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    // MARK: - Signal

    /// The work's own figure, not the shrunk one: the line states a fact about the
    /// work, and "Rank cautiously" explains why a high figure can sit lower.
    static func signal(_ rank: LoadedWorksRank, shown: Double?, setAside: Bool, hasPrevious: Bool) -> String? {
        if setAside { return "Unusual stats, set aside" }
        switch rank {
        case .ao3Order:
            return nil
        case .momentum:
            guard hasPrevious, let gained = shown else { return "First time in your results" }
            return gained > 0
                ? "+\(Int(gained).formatted()) kudos since you last saw it"
                : "No new kudos since you last saw it"
        case .kudosPerHitAdjusted, .savesPerKudos, .commentsPerKudos, .kudosPerThousandWords:
            guard let value = shown else { return "Not enough figures to rank" }
            return switch rank {
            case .kudosPerHitAdjusted: "\(decimal(value))× typical kudos per hit"
            case .savesPerKudos: "\(decimal(value * 100)) saves per 100 kudos"
            case .commentsPerKudos: "\(decimal(value * 100)) comments per 100 kudos"
            default: "\(decimal(value)) kudos per 1,000 words"
            }
        }
    }

    /// One decimal below ten, none above: "2.4", "0.8", "26".
    private static func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value < 10 ? 1 : 0)))
    }
}

// MARK: - Momentum's record

/// The kudos a work had the last time it appeared in Search's results.
struct SeenKudos: Codable, Equatable {
    var kudos: Int
    var seenAt: Date
}

/// Momentum's baseline for one Search session: each work's kudos at its previous
/// sighting, taken the first time this session sees it. Taken once, so a work
/// seen again on a later page load does not drop back to nothing gained.
struct KudosSightings {
    private(set) var previousKudos: [Int: Int] = [:]
    private var checked: Set<Int> = []

    /// Notes these works as seen now and returns the updated stored record.
    mutating func record(
        _ works: [AO3WorkSummary],
        in stored: [Int: SeenKudos],
        now: Date = Date()
    ) -> [Int: SeenKudos] {
        var updated = stored
        for work in works {
            guard let kudos = LoadedWorksRanker.Figures(work, now: now).kudos else { continue }
            if checked.insert(work.id).inserted, let earlier = stored[work.id] {
                previousKudos[work.id] = earlier.kudos
            }
            updated[work.id] = SeenKudos(kudos: kudos, seenAt: now)
        }
        return updated
    }
}

/// Where Momentum's record lives: `UserDefaults`, under one key, as JSON keyed by
/// AO3 work id. Not SwiftData and not in `.kudosbackup` — like
/// `SubscriptionWatermarks`, it is a per-device convenience, and losing it only
/// means every work starts again at "First time in your results".
enum LastSeenKudosStore {
    static let key = "ao3.search.lastSeenKudos"
    /// About fifty pages of results. Past it, the works seen longest ago go first.
    static let entryLimit = 1_000

    static func load(from defaults: UserDefaults = .standard) -> [Int: SeenKudos] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: SeenKudos].self, from: data)
        else { return [:] }
        return Dictionary(
            decoded.compactMap { key, value in Int(key).map { ($0, value) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    static func save(_ entries: [Int: SeenKudos], to defaults: UserDefaults = .standard) {
        let encodable = Dictionary(
            bound(entries).map { (String($0.key), $0.value) }, uniquingKeysWith: { first, _ in first }
        )
        guard let data = try? JSONEncoder().encode(encodable) else { return }
        defaults.set(data, forKey: key)
    }

    static func bound(_ entries: [Int: SeenKudos]) -> [Int: SeenKudos] {
        guard entries.count > entryLimit else { return entries }
        let kept = entries.sorted { $0.value.seenAt > $1.value.seenAt }.prefix(entryLimit)
        return Dictionary(kept.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
    }
}
