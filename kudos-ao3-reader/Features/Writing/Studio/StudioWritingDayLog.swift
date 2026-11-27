import Foundation
import SwiftUI

/// One local calendar day's recorded word total for the Writing Studio Today card.
nonisolated struct StudioDayWords: Equatable, Hashable, Identifiable, Sendable {
    var dayKey: String
    var weekdayInitial: String
    var words: Int
    var isToday: Bool

    var id: String { dayKey }
}

/// Snapshot of local writing progress for the Today card on Writing Studio › Overview.
nonisolated struct StudioDayLogSnapshot: Equatable, Sendable {
    var wordsToday: Int
    var streak: Int
    var recentDays: [StudioDayWords]

    static let empty = StudioDayLogSnapshot(wordsToday: 0, streak: 0, recentDays: [])
}

private nonisolated struct StudioDayLogFile: Codable, Equatable, Sendable {
    var days: [String: Int]
}

/// Pure date-key, delta, streak, and 7-day history math for `StudioWritingDayLog`.
nonisolated enum StudioWritingDayLogMath {
    /// Local calendar day key formatted as `yyyy-MM-dd` using `calendar`.
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 1970
        let month = parts.month ?? 1
        let day = parts.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Only positive word-count increases are recorded; deletions and zero changes count as 0.
    static func positiveDelta(previous: Int, current: Int) -> Int {
        max(0, current - previous)
    }

    /// Consecutive local days with any words written (`> 0`).
    ///
    /// Today is counted once it has words; while today is still at 0, an unbroken run ending
    /// yesterday stays alive until the day rolls over.
    static func streak(
        counts: [String: Int],
        asOf date: Date,
        calendar: Calendar = .current
    ) -> Int {
        let today = calendar.startOfDay(for: date)
        let todayKey = dayKey(for: today, calendar: calendar)
        var offset = (counts[todayKey] ?? 0) > 0 ? 0 : -1
        var run = 0
        while let day = calendar.date(byAdding: .day, value: offset, to: today) {
            let key = dayKey(for: day, calendar: calendar)
            guard (counts[key] ?? 0) > 0 else { break }
            run += 1
            offset -= 1
        }
        return run
    }

    /// Returns `count` consecutive local days ending on `date`, oldest first.
    static func recentDays(
        counts: [String: Int],
        count: Int = 7,
        endingOn date: Date,
        calendar: Calendar = .current
    ) -> [StudioDayWords] {
        guard count > 0 else { return [] }
        let today = calendar.startOfDay(for: date)
        let symbols = calendar.veryShortStandaloneWeekdaySymbols.isEmpty
            ? calendar.shortWeekdaySymbols
            : calendar.veryShortStandaloneWeekdaySymbols
        return (0 ..< count).compactMap { index in
            let offset = index - (count - 1)
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else {
                return nil
            }
            let key = dayKey(for: day, calendar: calendar)
            let weekdayIndex = calendar.component(.weekday, from: day) - 1
            let initial = symbols.indices.contains(weekdayIndex) ? symbols[weekdayIndex] : ""
            return StudioDayWords(
                dayKey: key,
                weekdayInitial: initial,
                words: max(0, counts[key] ?? 0),
                isToday: offset == 0
            )
        }
    }

    static func snapshot(
        counts: [String: Int],
        asOf date: Date,
        calendar: Calendar = .current,
        recentDayCount: Int = 7
    ) -> StudioDayLogSnapshot {
        let todayKey = dayKey(for: date, calendar: calendar)
        return StudioDayLogSnapshot(
            wordsToday: max(0, counts[todayKey] ?? 0),
            streak: streak(counts: counts, asOf: date, calendar: calendar),
            recentDays: recentDays(
                counts: counts,
                count: recentDayCount,
                endingOn: date,
                calendar: calendar
            )
        )
    }
}

/// Device-local daily writing word-count log stored as JSON in Application Support
/// (`Writing/day-log.json`). Records only positive word-count deltas while a chapter is open
/// in the editor. Never sent to AO3, and throws on corrupt JSON instead of overwriting it.
actor StudioWritingDayLog {
    nonisolated static let shared = StudioWritingDayLog()
    nonisolated static let didChangeNotification = Notification.Name("KudosWritingStudioDayLogDidChange")
    nonisolated private static let ioLock = NSLock()

    nonisolated static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Writing", isDirectory: true)
            .appendingPathComponent("day-log.json")
    }

    private let url: URL
    private let calendarProvider: @Sendable () -> Calendar
    private let now: @Sendable () -> Date

    init(
        url: URL = StudioWritingDayLog.defaultURL,
        calendar: @escaping @Sendable () -> Calendar = { .current },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.url = url
        self.calendarProvider = calendar
        self.now = now
    }

    func counts() throws -> [String: Int] {
        try withLock { try readUnlocked() }
    }

    func words(on date: Date? = nil) throws -> Int {
        let targetDate = date ?? now()
        let key = StudioWritingDayLogMath.dayKey(for: targetDate, calendar: calendarProvider())
        let all = try withLock { try readUnlocked() }
        return max(0, all[key] ?? 0)
    }

    func snapshot(asOf date: Date? = nil, recentDayCount: Int = 7) throws -> StudioDayLogSnapshot {
        let targetDate = date ?? now()
        let all = try withLock { try readUnlocked() }
        return StudioWritingDayLogMath.snapshot(
            counts: all,
            asOf: targetDate,
            calendar: calendarProvider(),
            recentDayCount: recentDayCount
        )
    }

    /// Adds a positive word delta to the local calendar day of `date` (defaulting to `now()`).
    /// Non-positive deltas are ignored without writing to disk.
    @discardableResult
    func record(delta: Int, at date: Date? = nil) throws -> Int {
        let targetDate = date ?? now()
        let key = StudioWritingDayLogMath.dayKey(for: targetDate, calendar: calendarProvider())
        let updated: Int = try withLock {
            var all = try readUnlocked()
            let existing = max(0, all[key] ?? 0)
            guard delta > 0 else { return existing }
            let next = existing + delta
            all[key] = next
            try writeUnlocked(all)
            return next
        }
        if delta > 0 {
            Self.postDidChange()
        }
        return updated
    }

    /// Records the positive increase between `previous` and `current` word counts.
    @discardableResult
    func recordChange(from previous: Int, to current: Int, at date: Date? = nil) throws -> Int {
        let delta = StudioWritingDayLogMath.positiveDelta(previous: previous, current: current)
        return try record(delta: delta, at: date)
    }

    private func readUnlocked() throws -> [String: Int] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        return try WritingDocumentIO.readJSON(StudioDayLogFile.self, from: url).days
    }

    private func writeUnlocked(_ days: [String: Int]) throws {
        try WritingDocumentIO.writeJSON(StudioDayLogFile(days: days), to: url)
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        Self.ioLock.lock()
        defer { Self.ioLock.unlock() }
        return try body()
    }

    nonisolated private static func postDidChange() {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: didChangeNotification, object: nil)
            }
        }
    }
}

/// Device-local daily writing goal preference (default 1,000 words; 0 means off).
nonisolated enum StudioWritingGoal {
    static let storageKey = "writingStudioDailyWordGoal"
    static let defaultGoal = 1_000
    static let presets: [Int] = [250, 500, 1_000, 1_500, 2_000]

    static func storedValue(in defaults: UserDefaults = .standard) -> Int {
        guard defaults.object(forKey: storageKey) != nil else { return defaultGoal }
        return max(0, defaults.integer(forKey: storageKey))
    }

    static func resolvedGoal(fromStored value: Int) -> Int? {
        value > 0 ? value : nil
    }

    static func goal(in defaults: UserDefaults = .standard) -> Int? {
        resolvedGoal(fromStored: storedValue(in: defaults))
    }

    static func setGoal(_ words: Int?, in defaults: UserDefaults = .standard) {
        if let words, words > 0 {
            defaults.set(words, forKey: storageKey)
        } else {
            defaults.set(0, forKey: storageKey)
        }
    }

    static func progress(wordsToday: Int, goal: Int?) -> Double {
        guard let goal, goal > 0 else { return 0 }
        return min(1, max(0, Double(max(0, wordsToday)) / Double(goal)))
    }

    static func percent(wordsToday: Int, goal: Int?) -> Int {
        Int((progress(wordsToday: wordsToday, goal: goal) * 100).rounded())
    }

    static func summaryText(for goal: Int?) -> String {
        guard let goal, goal > 0 else { return "Off" }
        return "\(goal.formatted()) words"
    }
}

/// Tracks the last observed word count for an open editor session so opening an existing
/// manuscript seeds a baseline instead of crediting existing words to today.
nonisolated struct StudioWritingDayLogTracker: Equatable, Sendable {
    private(set) var sessionKey: String?
    private(set) var lastObservedWords: Int?

    /// Receives an editor word-count update and returns the positive delta to record, if any.
    mutating func receive(words: Int, isReady: Bool, sessionKey: String) -> Int {
        let clamped = max(0, words)
        guard isReady else {
            if self.sessionKey != sessionKey {
                self.sessionKey = sessionKey
                lastObservedWords = nil
            }
            return 0
        }
        guard self.sessionKey == sessionKey, let previous = lastObservedWords else {
            self.sessionKey = sessionKey
            lastObservedWords = clamped
            return 0
        }
        lastObservedWords = clamped
        return StudioWritingDayLogMath.positiveDelta(previous: previous, current: clamped)
    }
}

/// Hooks `ChapterEditorScreen`'s live word count into `StudioWritingDayLog` in one modifier.
private struct StudioWritingDayLogHost: ViewModifier {
    let words: Int
    let isReady: Bool
    let sessionKey: String
    let log: StudioWritingDayLog

    @State private var tracker = StudioWritingDayLogTracker()

    func body(content: Content) -> some View {
        content
            .onChange(of: sessionKey, initial: true) { _, newKey in
                handleUpdate(words: words, isReady: isReady, sessionKey: newKey)
            }
            .onChange(of: isReady, initial: true) { _, ready in
                handleUpdate(words: words, isReady: ready, sessionKey: sessionKey)
            }
            .onChange(of: words) { _, newWords in
                handleUpdate(words: newWords, isReady: isReady, sessionKey: sessionKey)
            }
    }

    private func handleUpdate(words: Int, isReady: Bool, sessionKey: String) {
        let delta = tracker.receive(words: words, isReady: isReady, sessionKey: sessionKey)
        guard delta > 0 else { return }
        Task {
            _ = try? await log.record(delta: delta)
        }
    }
}

extension View {
    /// Records positive word-count changes from an open chapter editor into `StudioWritingDayLog`.
    func writingDayLogHost(
        words: Int,
        isReady: Bool,
        sessionKey: String,
        log: StudioWritingDayLog = .shared
    ) -> some View {
        modifier(StudioWritingDayLogHost(words: words, isReady: isReady, sessionKey: sessionKey, log: log))
    }
}

/// Sheet for turning the daily writing goal on/off and choosing a word target.
/// Opened from Settings › Writing and by tapping the Today ring on Writing Studio › Overview.
struct StudioWritingGoalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @AppStorage(StudioWritingGoal.storageKey) private var storedGoal: Int = StudioWritingGoal.defaultGoal

    @State private var isEnabled = true
    @State private var targetWords = StudioWritingGoal.defaultGoal
    @State private var customText = ""

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section {
                        Toggle("Daily writing goal", isOn: $isEnabled)
                            .accentFill()
                            .accessibilityLabel("Daily writing goal")
                    } footer: {
                        Text(
                            "Counts words you write in the Kudos editor on this \(ThisDevice.name). "
                                + "Turn off to track your word count without a daily target."
                        )
                    }

                    if isEnabled {
                        Section("Daily target") {
                            presetGrid
                                .padding(.vertical, 4)

                            HStack(spacing: 12) {
                                Text("Custom words")
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 8)
                                TextField("1000", text: $customText)
                                    .multilineTextAlignment(.trailing)
                                    #if os(iOS)
                                    .keyboardType(.numberPad)
                                    #endif
                                    .monospacedDigit()
                                    .frame(maxWidth: 110)
                                    .accessibilityLabel("Custom daily word goal")
                                    .onChange(of: customText) { _, raw in
                                        let digits = raw.filter(\.isNumber)
                                        if digits != raw { customText = digits }
                                        if let parsed = Int(digits), parsed > 0 {
                                            targetWords = min(parsed, 100_000)
                                        }
                                    }
                            }
                        }
                    }
                }
                .appThemedRows()
            }
            .formStyle(.grouped)
            .appThemedScroll()
            .navigationTitle("Writing Goal")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveGoal()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(isEnabled && resolvedDraftGoal == nil)
                }
            }
            .onAppear { loadCurrentGoal() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var presetColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 8),
            count: dynamicTypeSize.isAccessibilitySize ? 2 : 3
        )
    }

    private var presetGrid: some View {
        LazyVGrid(columns: presetColumns, spacing: 8) {
            ForEach(StudioWritingGoal.presets, id: \.self) { preset in
                let selected = resolvedDraftGoal == preset
                Button {
                    targetWords = preset
                    customText = String(preset)
                } label: {
                    Text(preset.formatted())
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(
                            selected
                                ? ThemeManager.label(on: theme.effectiveTint)
                                : Color.primary
                        )
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(theme.effectiveTint)
                            } else {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(theme.appTheme.glassFill(0.10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(theme.appTheme.glassStroke(0.14), lineWidth: 0.5)
                                    )
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(preset.formatted()) words per day")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var resolvedDraftGoal: Int? {
        if let parsed = Int(customText.filter(\.isNumber)), parsed > 0 {
            return min(parsed, 100_000)
        }
        return targetWords > 0 ? targetWords : nil
    }

    private func loadCurrentGoal() {
        if let current = StudioWritingGoal.resolvedGoal(fromStored: storedGoal) {
            isEnabled = true
            targetWords = current
            customText = String(current)
        } else {
            isEnabled = false
            targetWords = StudioWritingGoal.defaultGoal
            customText = String(StudioWritingGoal.defaultGoal)
        }
    }

    private func saveGoal() {
        if isEnabled, let goal = resolvedDraftGoal {
            storedGoal = goal
        } else {
            storedGoal = 0
        }
    }
}
