import Foundation
import os

/// The figures Writing Studio's Stats tracks, in the order the board lists them.
/// The raw value is the key a snapshot saves them under, so don't rename a case.
nonisolated enum StudioStatsMetric: String, CaseIterable, Hashable, Sendable {
    case hits, kudos, comments, bookmarks, subscriptions, words

    var title: String {
        switch self {
        case .hits: "Hits"
        case .kudos: "Kudos"
        case .comments: "Comment Threads"
        case .bookmarks: "Bookmarks"
        case .subscriptions: "Subscriptions"
        case .words: "Words Posted"
        }
    }

    func total(in stats: AO3UserStats) -> Int? {
        switch self {
        case .hits: stats.hits
        case .kudos: stats.kudos
        case .comments: stats.commentThreads
        case .bookmarks: stats.bookmarks
        case .subscriptions: stats.subscriptions
        case .words: stats.wordCount
        }
    }

    func value(in work: AO3UserStats.Work) -> Int? {
        switch self {
        case .hits: work.hits
        case .kudos: work.kudos
        case .comments: work.commentThreads
        case .bookmarks: work.bookmarks
        case .subscriptions: work.subscriptions
        case .words: work.wordCount
        }
    }
}

/// One look at AO3's stats page: the totals and every work's figures, with the time.
/// `year` is the page's year filter (nil is "All Years"), because each filter shows
/// different totals and so needs its own history to compare against.
nonisolated struct StudioStatsSnapshot: Codable, Equatable, Sendable {
    struct Work: Codable, Equatable, Sendable {
        var id: Int
        /// `StudioStatsMetric.rawValue` to value; a figure the page didn't show is absent.
        var figures: [String: Int]

        func figure(_ metric: StudioStatsMetric) -> Int? { figures[metric.rawValue] }
    }

    var date: Date
    var year: Int?
    var totals: [String: Int]
    var works: [Work]

    init(date: Date, year: Int?, totals: [String: Int], works: [Work]) {
        self.date = date
        self.year = year
        self.totals = totals
        self.works = works
    }

    init(stats: AO3UserStats, year: Int?, at date: Date) {
        self.date = date
        self.year = year
        totals = Self.figures { $0.total(in: stats) }
        // The flat list merges a work that sits under several fandoms into one row.
        let flat = stats.sections(grouping: .flat, sortedBy: .date).first?.works ?? []
        works = flat.map { work in Work(id: work.id, figures: Self.figures { $0.value(in: work) }) }
    }

    func total(_ metric: StudioStatsMetric) -> Int? { totals[metric.rawValue] }

    func work(id: Int) -> Work? { works.first { $0.id == id } }

    private static func figures(_ read: (StudioStatsMetric) -> Int?) -> [String: Int] {
        var result: [String: Int] = [:]
        for metric in StudioStatsMetric.allCases {
            if let value = read(metric) { result[metric.rawValue] = value }
        }
        return result
    }
}

/// Kudos' own record of the stats page, because AO3 keeps no history: a small JSON
/// file per account in Application Support, one snapshot a day per year filter,
/// a year kept. Nothing leaves the device. It is not excluded from the device's
/// own backup: unlike a cache it can't be rebuilt from AO3.
nonisolated struct StudioStatsHistoryStore: Sendable {
    static let keptDays = 365

    private struct File: Codable {
        var version = 1
        var snapshots: [StudioStatsSnapshot]
    }

    private let url: URL
    /// One lock for every account: two year pages finishing together must not
    /// each write a file that is missing the other's snapshot.
    private static let writeLock = OSAllocatedUnfairLock(initialState: ())

    /// `directory` is for tests; the app uses Application Support/StudioStats.
    init(account: String, directory: URL? = nil) {
        let folder = directory ?? (FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("StudioStats", isDirectory: true)
        url = folder.appendingPathComponent(Self.fileName(for: account) + ".json")
    }

    func load() -> [StudioStatsSnapshot] { read() ?? [] }

    /// Saves this look and returns the whole history, oldest first. A file that
    /// can't be read is set aside as `.unreadable` rather than overwritten.
    @discardableResult
    func record(
        _ stats: AO3UserStats, year: Int?, at date: Date = Date(), calendar: Calendar = .current
    ) -> [StudioStatsSnapshot] {
        Self.writeLock.withLock { _ in
            let existing = read()
            let snapshot = StudioStatsSnapshot(stats: stats, year: year, at: date)
            // A file that cannot be decoded is moved aside. If that move fails,
            // leave the bytes where they are instead of writing over them.
            if existing == nil, !preserveUnreadableFile() {
                return [snapshot]
            }
            let merged = Self.merging(existing ?? [], adding: snapshot, calendar: calendar)
            // Best effort: a failed write still lets this screen draw from memory.
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try Self.encoder.encode(File(snapshots: merged)).write(to: url, options: .atomic)
            } catch {}
            return merged
        }
    }

    /// Moves a corrupt file to `.unreadable`. False when the bytes could not be kept.
    private func preserveUnreadableFile() -> Bool {
        let aside = url.appendingPathExtension("unreadable")
        do {
            if FileManager.default.fileExists(atPath: aside.path) {
                try FileManager.default.removeItem(at: aside)
            }
            try FileManager.default.moveItem(at: url, to: aside)
            return true
        } catch {
            return false
        }
    }

    /// One snapshot per local calendar day and year filter: the later look
    /// replaces that day, even when a total fell (a work was deleted).
    /// Anything before the calendar day `keptDays` earlier is dropped.
    static func merging(
        _ existing: [StudioStatsSnapshot], adding new: StudioStatsSnapshot, calendar: Calendar
    ) -> [StudioStatsSnapshot] {
        // Start of that day, not the same clock time: an evening look must not
        // drop the morning of the day a year ago.
        let cutoff = calendar.date(
            byAdding: .day, value: -keptDays, to: calendar.startOfDay(for: new.date)
        ) ?? .distantPast
        var kept = existing.filter { $0.date >= cutoff }
        // Two loads can finish out of order. The later look wins; an earlier
        // one must not replace the snapshot this day already has.
        let newerAlreadyKept = kept.contains {
            $0.year == new.year && calendar.isDate($0.date, inSameDayAs: new.date) && $0.date > new.date
        }
        if !newerAlreadyKept {
            kept.removeAll {
                $0.year == new.year && calendar.isDate($0.date, inSameDayAs: new.date)
            }
            kept.append(new)
        }
        return kept.sorted { $0.date < $1.date }
    }

    private func read() -> [StudioStatsSnapshot]? {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? Self.decoder.decode(File.self, from: data))?.snapshots
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func fileName(for account: String) -> String {
        let name = String(account.lowercased().map { $0.isLetter || $0.isNumber || $0 == "_" ? $0 : "-" })
        return name.isEmpty ? "account" : name
    }
}

/// Whether a stats page already in memory may be shown again without asking AO3.
/// Fifteen minutes, the same window the Writing tab uses for its own pages.
enum StudioStatsFreshness {
    static let window: TimeInterval = 15 * 60

    /// `force` is a pull to refresh or Try Again. A missing load is always fetched.
    /// A load exactly `window` old is stale. The first look of a new local day
    /// is fetched too, so that day gets its snapshot even inside the window.
    static func shouldFetch(
        fetchedAt: Date?, force: Bool, now: Date = Date(),
        calendar: Calendar = .current, lastSnapshot: Date? = nil
    ) -> Bool {
        if force { return true }
        if let lastSnapshot, !calendar.isDate(lastSnapshot, inSameDayAs: now) { return true }
        guard let fetchedAt else { return true }
        return now.timeIntervalSince(fetchedAt) >= window
    }
}

/// The last stats page for each account, sign-in, and year filter. Memory only:
/// it holds titles, so it is never written to the history file. A new sign-in
/// drops the previous account's pages.
@MainActor
enum StudioStatsPageCache {
    struct Key: Hashable, Sendable {
        var account: String
        var sessionGeneration: Int
        var year: Int?
    }

    struct Entry {
        var stats: AO3UserStats
        var fetchedAt: Date
    }

    private static var entries: [Key: Entry] = [:]
    /// The year chip the reader picked, per account. The Stats view is created
    /// again each time the section is shown, and forgetting this would load
    /// All Years and ask AO3. Nil means All Years. Not written to disk.
    private static var selectedYears: [String: Int] = [:]

    static func entry(for key: Key) -> Entry? { entries[normalized(key)] }

    static func store(_ stats: AO3UserStats, for key: Key, at date: Date) {
        let key = normalized(key)
        entries = entries.filter {
            $0.key.account == key.account && $0.key.sessionGeneration == key.sessionGeneration
        }
        selectedYears = selectedYears.filter { $0.key == key.account }
        entries[key] = Entry(stats: stats, fetchedAt: date)
    }

    static func removeAll() {
        entries.removeAll()
        selectedYears.removeAll()
    }

    static func rememberYear(_ year: Int?, account: String) {
        let account = account.lowercased()
        if let year {
            selectedYears[account] = year
        } else {
            selectedYears.removeValue(forKey: account)
        }
    }

    static func rememberedYear(account: String) -> Int? {
        selectedYears[account.lowercased()]
    }

    private static func normalized(_ key: Key) -> Key {
        Key(account: key.account.lowercased(), sessionGeneration: key.sessionGeneration, year: key.year)
    }
}

/// One bar of Kudos per Week.
nonisolated struct StudioStatsWeek: Equatable, Sendable {
    let start: Date
    let gain: Int
    /// Kudos didn't look that week, so its share of the growth is spread evenly.
    let isEstimate: Bool
}

/// What the Stats board reads off the saved history. Every function takes one
/// period's snapshots (see `snapshots(_:year:)`).
nonisolated enum StudioStatsHistory {
    static func snapshots(_ all: [StudioStatsSnapshot], year: Int?) -> [StudioStatsSnapshot] {
        all.filter { $0.year == year }.sorted { $0.date < $1.date }
    }

    /// Growth per calendar week: each week's last look minus the one before it.
    /// A week with no look sits in a gap: the growth across it is spread evenly
    /// over the weeks it covers and marked as an estimate. The first week has
    /// nothing to be measured against, so no bar until a second week has a look.
    /// A fall (a deleted work) draws as zero.
    static func weeks(
        _ snapshots: [StudioStatsSnapshot], metric: StudioStatsMetric, calendar: Calendar = .current
    ) -> [StudioStatsWeek] {
        let ends = weeklyEnds(snapshots, metric: metric, calendar: calendar)
        var result: [StudioStatsWeek] = []
        for (previous, current) in zip(ends, ends.dropFirst()) {
            let gap = max(1, calendar.dateComponents([.weekOfYear], from: previous.start, to: current.start).weekOfYear ?? 1)
            let growth = max(0, current.value - previous.value)
            for step in 1...gap {
                guard let start = calendar.date(byAdding: .weekOfYear, value: step - gap, to: current.start) else { continue }
                // The remainder goes to the week that was actually seen.
                let share = growth / gap + (step == gap ? growth % gap : 0)
                result.append(StudioStatsWeek(start: start, gain: share, isEstimate: gap > 1))
            }
        }
        return result
    }

    /// The biggest week (the latest on a tie); nil while every week is zero.
    static func best(_ weeks: [StudioStatsWeek]) -> StudioStatsWeek? {
        guard let top = weeks.map({ $0.gain }).max(), top > 0 else { return nil }
        return weeks.last { $0.gain == top }
    }

    /// The look to measure "change since last week" against: of the looks on an
    /// earlier day, the one nearest seven days ago (the older on a tie).
    static func baseline(
        _ snapshots: [StudioStatsSnapshot], now: Date, calendar: Calendar = .current
    ) -> StudioStatsSnapshot? {
        let target = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        return snapshots
            .filter { $0.date < now && !calendar.isDate($0.date, inSameDayAs: now) }
            .sorted { $0.date < $1.date }
            .min { abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target)) }
    }

    static func change(_ current: Int?, since previous: Int?) -> Int? {
        guard let current, let previous else { return nil }
        return current - previous
    }

    /// Bar heights, 0...1, from the last few weeks' end values, scaled between
    /// their lowest and highest so a total that crept up still shows its slope.
    /// Empty until two weeks have a look; flat history draws half height.
    static func sparkline(
        _ snapshots: [StudioStatsSnapshot], metric: StudioStatsMetric,
        calendar: Calendar = .current, points: Int = 8
    ) -> [Double] {
        let values = weeklyEnds(snapshots, metric: metric, calendar: calendar).suffix(points).map { $0.value }
        guard values.count > 1, let low = values.min(), let high = values.max() else { return [] }
        guard high > low else { return values.map { _ in 0.5 } }
        return values.map { Double($0 - low) / Double(high - low) }
    }

    /// The start of the first week that can have a bar: the week after
    /// the first look. Nil with no history.
    static func chartsBegin(_ snapshots: [StudioStatsSnapshot], calendar: Calendar = .current) -> Date? {
        guard let first = snapshots.min(by: { $0.date < $1.date }) else { return nil }
        return calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart(first.date, calendar))
    }

    /// What the chart says before it has a week to draw.
    static func emptyChartMessage(_ snapshots: [StudioStatsSnapshot], calendar: Calendar = .current) -> String {
        guard let begin = chartsBegin(snapshots, calendar: calendar) else {
            return "Charts begin once Kudos has saved your totals."
        }
        let style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).month(.abbreviated).day()
        return "Charts start \(begin.formatted(style)), after a full week of totals."
    }

    /// VoiceOver text for the bar chart: every week's value, not only the latest.
    static func spokenChart(_ weeks: [StudioStatsWeek], best: StudioStatsWeek?) -> String {
        guard !weeks.isEmpty else { return "Kudos per week" }
        var parts = ["Kudos per week for \(weeks.count) \(weeks.count == 1 ? "week" : "weeks")"]
        for week in weeks {
            var piece = "Week of \(week.start.studioStatsShort), \(week.gain.formatted())"
            if week.isEstimate { piece += ", estimated" }
            parts.append(piece)
        }
        if let best {
            parts.append("Best \(best.gain.formatted()), the week of \(best.start.studioStatsShort)")
        }
        return parts.joined(separator: ". ")
    }

    private static func weeklyEnds(
        _ snapshots: [StudioStatsSnapshot], metric: StudioStatsMetric, calendar: Calendar
    ) -> [(start: Date, value: Int)] {
        var ends: [(start: Date, value: Int)] = []
        for snapshot in snapshots.sorted(by: { $0.date < $1.date }) {
            guard let value = snapshot.total(metric) else { continue }
            let start = weekStart(snapshot.date, calendar)
            if let last = ends.last, last.start == start {
                ends[ends.count - 1].value = value
            } else {
                ends.append((start: start, value: value))
            }
        }
        return ends
    }

    private static func weekStart(_ date: Date, _ calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }
}
