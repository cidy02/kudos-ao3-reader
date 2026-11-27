import Foundation

/// Words in one sprint at one moment, for the five-minute bars.
nonisolated struct SprintSample: Equatable, Sendable {
    var offset: TimeInterval
    var words: Int
}

/// A finished sprint, as the Sprint Done sheet and the share card show it.
nonisolated struct SprintResult: Identifiable, Equatable, Sendable {
    var id: UUID
    var endedAt: Date
    /// Whole minutes the sprint ran: the planned length, or the time to the early end rounded up.
    var minutes: Int
    var plannedMinutes: Int
    var words: Int
    /// Words written in each five-minute slice.
    var buckets: [Int]
    var isBestThisWeek: Bool
    var workID: UUID?
}

/// One line of the sprint history (`Sprints/sprints.json`), used for the "best this week" line.
nonisolated struct SprintRecord: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var date: Date
    var minutes: Int
    var words: Int
    var workID: UUID?
}

/// What the editor's status line shows while a sprint runs.
nonisolated struct SprintStatusInfo: Equatable, Hashable, Sendable {
    var startedAt: Date
    var endsAt: Date
    var words: Int
}

/// The pure rules of a sprint, so tests need no UI.
nonisolated enum SprintMath {
    static let hapticStep = 100
    static let sliceSeconds: TimeInterval = 5 * 60

    /// Words written since the sprint began; deleting below the start never goes under zero.
    static func words(current: Int, start: Int) -> Int {
        max(0, current - start)
    }

    /// The multiples of `step` that a count passing from `old` to `new` crosses (a light tap each).
    static func hapticThresholds(from old: Int, to new: Int, every step: Int = hapticStep) -> [Int] {
        guard new > old, step > 0 else { return [] }
        let first = (max(old, 0) / step + 1) * step
        return Array(stride(from: first, through: new, by: step))
    }

    /// Words per five-minute slice. `samples` are the sprint's running total over time, oldest first.
    /// One bar per started slice, at least one.
    static func buckets(
        samples: [SprintSample],
        elapsed: TimeInterval,
        slice: TimeInterval = sliceSeconds
    ) -> [Int] {
        guard slice > 0 else { return [max(0, samples.last?.words ?? 0)] }
        let count = max(1, Int((max(0, elapsed) / slice).rounded(.up)))
        func total(at time: TimeInterval) -> Int {
            samples.last { $0.offset <= time }?.words ?? 0
        }
        return (0..<count).map { index in
            let startTotal = index == 0 ? 0 : total(at: Double(index) * slice)
            return max(0, total(at: Double(index + 1) * slice) - startTotal)
        }
    }

    /// True when `words` beats every earlier sprint in the same calendar week as `date`. A first
    /// sprint of the week has nothing to beat, so it isn't called the best.
    static func isBestThisWeek(
        words: Int,
        at date: Date,
        among earlier: [SprintRecord],
        calendar: Calendar
    ) -> Bool {
        guard words > 0, let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return false }
        let sameWeek = earlier.filter { $0.words > 0 && $0.date >= week.start && $0.date < week.end }
        return !sameWeek.isEmpty && sameWeek.allSatisfy { $0.words < words }
    }
}

/// A running sprint. The end is a `Date`, so leaving the app and coming back still ends it
/// correctly: `finish(now:)` clamps to the planned length.
nonisolated struct SprintState: Equatable, Sendable, Identifiable {
    let id: UUID
    let startedAt: Date
    let plannedMinutes: Int
    let startWords: Int
    let workID: UUID?
    private(set) var words = 0
    private(set) var samples: [SprintSample] = []
    private var buzzedUpTo = 0

    init(id: UUID = UUID(), startedAt: Date, plannedMinutes: Int, startWords: Int, workID: UUID? = nil) {
        self.id = id
        self.startedAt = startedAt
        self.plannedMinutes = max(1, plannedMinutes)
        self.startWords = startWords
        self.workID = workID
    }

    var plannedSeconds: TimeInterval { TimeInterval(plannedMinutes * 60) }
    var endsAt: Date { startedAt.addingTimeInterval(plannedSeconds) }

    func elapsedSeconds(at now: Date) -> TimeInterval {
        min(max(0, now.timeIntervalSince(startedAt)), plannedSeconds)
    }

    /// Takes the editor's current word count. Returns the 100-word marks newly crossed; a mark
    /// already tapped is not tapped again if the writer deletes and retypes.
    @discardableResult
    mutating func update(currentWords: Int, now: Date) -> [Int] {
        let new = SprintMath.words(current: currentWords, start: startWords)
        let crossed = SprintMath.hapticThresholds(from: words, to: new).filter { $0 > buzzedUpTo }
        if let top = crossed.last { buzzedUpTo = top }
        if new != words {
            words = new
            samples.append(SprintSample(offset: elapsedSeconds(at: now), words: new))
        }
        return crossed
    }

    func finish(now: Date) -> SprintResult {
        let elapsed = elapsedSeconds(at: now)
        let minutes = elapsed >= plannedSeconds ? plannedMinutes : max(1, Int((elapsed / 60).rounded(.up)))
        return SprintResult(
            id: id,
            endedAt: min(max(now, startedAt), endsAt),
            minutes: minutes,
            plannedMinutes: plannedMinutes,
            words: words,
            buckets: SprintMath.buckets(samples: samples, elapsed: elapsed),
            isBestThisWeek: false,
            workID: workID
        )
    }
}

private nonisolated struct SprintHistoryFile: Codable {
    var sprints: [SprintRecord]
}

/// The sprint history: date, minutes, words and work id, in one JSON file in Application Support
/// (`Sprints/sprints.json`). Device-only. A file that can't be read throws and is left alone.
actor SprintHistory {
    nonisolated static let shared = SprintHistory()
    nonisolated static let retained = 500
    nonisolated private static let ioLock = NSLock()

    nonisolated static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sprints", isDirectory: true)
            .appendingPathComponent("sprints.json")
    }

    private let url: URL

    init(url: URL = SprintHistory.defaultURL) {
        self.url = url
    }

    func list() throws -> [SprintRecord] {
        try withLock { try readUnlocked() }
    }

    func append(_ record: SprintRecord) throws {
        try withLock {
            let all = try readUnlocked() + [record]
            try writeUnlocked(Array(all.suffix(Self.retained)))
        }
    }

    private func readUnlocked() throws -> [SprintRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try WritingDocumentIO.readJSON(SprintHistoryFile.self, from: url).sprints
    }

    private func writeUnlocked(_ sprints: [SprintRecord]) throws {
        try WritingDocumentIO.writeJSON(SprintHistoryFile(sprints: sprints), to: url)
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        Self.ioLock.lock()
        defer { Self.ioLock.unlock() }
        return try body()
    }
}
