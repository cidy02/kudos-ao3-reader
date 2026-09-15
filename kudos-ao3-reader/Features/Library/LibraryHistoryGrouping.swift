import Foundation

/// How artboards **1ah** and **1ai** slice the reading history: the same rows, four
/// groupings, chosen with a scope strip above the list.
///
/// The two artboards are one screen with the control in two positions — 1ah is
/// `.time`, 1ai is `.state` — which is why this is an enum on one list rather than
/// two views.
///
/// Pure and value-typed on purpose: "which bucket does this work go in" is the whole
/// content of these screens, several of the rules are arguable (is a work read this
/// morning and finished "today" or "finished"?), and a rule you can hand fixtures to
/// is a rule you can check.
nonisolated enum LibraryHistoryGrouping: String, CaseIterable, Hashable, Sendable {
    case time
    case state
    case fandom
    case flat

    var title: String {
        switch self {
        case .time: "Time"
        case .state: "State"
        case .fandom: "Fandom"
        case .flat: "Flat"
        }
    }

    /// One group as the list draws it: an uppercase kicker and its works.
    nonisolated struct Bucket: Identifiable, Equatable {
        var title: String
        var workIDs: [UUID]
        var id: String { title }
    }

    /// Buckets `works` under this grouping, preserving the incoming order inside each
    /// bucket — the caller has already sorted by most-recently-read, and re-sorting
    /// inside a bucket would lose that.
    ///
    /// Groups come back in a **fixed** order per grouping rather than by size:
    /// spec 1ah calls them "source-ordered section kickers", and a list whose sections
    /// reshuffle as you read is one you cannot learn the shape of.
    /// `@MainActor` while the enum around it is not: the cases and `title` are a
    /// plain value that `@AppStorage` stores and `Sendable` covers, but this reads
    /// `SavedWork`, which is a SwiftData `@Model` and so main-actor bound. Marking
    /// the whole type would make the stored setting main-actor too, for no reason.
    @MainActor
    static func groups(
        _ grouping: LibraryHistoryGrouping,
        works: [SavedWork],
        now: Date = Date(),
        calendar: Calendar = .current,
        isAbandoned: (SavedWork) -> Bool
    ) -> [Bucket] {
        switch grouping {
        case .flat:
            return works.isEmpty ? [] : [Bucket(title: "All", workIDs: works.map(\.id))]

        case .time:
            return ordered(
                TimeBucket.allCases.map(\.title),
                bucketing: works
            ) { TimeBucket.bucket(for: $0.lastReadDate, now: now, calendar: calendar).title }

        case .state:
            // Five buckets, not the spec's three, because `SavedWork.ReadingState`
            // is a four-way partition and one of the four needs splitting.
            //
            // Abandoned populates now. It could not while `LibrarySectionKind`
            // selected `!hasEPUB`: `ReadingLogService.isAbandoned` requires
            // `isInProgress`, which requires the EPUB on disk, so the two never
            // overlapped and this bucket was dead. That predicate is now "works you
            // have read", per 1ah, and mid-way works are in the shelf.
            //
            // "Read, not finished" stays and is not a duplicate: it is the same idea
            // for a work whose file has already been freed, which cannot be
            // `.inProgress` and so can never be judged abandoned.
            return ordered(
                ["In progress", "Abandoned", "Read, not finished", "Finished", "Not started"],
                bucketing: works
            ) { work in
                switch work.readingState {
                case .finished: return "Finished"
                case .freedHistory: return "Read, not finished"
                case .unread: return "Not started"
                case .inProgress:
                    // Abandoned before in-progress: it is a *kind* of in-progress, and
                    // a work in both would be counted twice in the header tally.
                    return isAbandoned(work) ? "Abandoned" : "In progress"
                }
            }

        case .fandom:
            // Fandoms have no fixed order, so this one *is* ranked — by size, then
            // alphabetically, which is stable across renders.
            var byFandom: [String: [UUID]] = [:]
            for work in works {
                let name = work.workFandoms.first(where: { !$0.isEmpty }) ?? "No fandom"
                byFandom[name, default: []].append(work.id)
            }
            return byFandom
                .sorted { lhs, rhs in
                    if lhs.value.count != rhs.value.count { return lhs.value.count > rhs.value.count }
                    return lhs.key < rhs.key
                }
                .map { Bucket(title: $0.key, workIDs: $0.value) }
        }
    }

    /// Buckets by `key`, then emits the buckets in `order`, dropping empty ones.
    @MainActor
    private static func ordered(
        _ order: [String],
        bucketing works: [SavedWork],
        key: (SavedWork) -> String
    ) -> [Bucket] {
        var buckets: [String: [UUID]] = [:]
        for work in works {
            buckets[key(work), default: []].append(work.id)
        }
        return order.compactMap { title in
            guard let ids = buckets[title], !ids.isEmpty else { return nil }
            return Bucket(title: title, workIDs: ids)
        }
    }

    /// The spec's TODAY / THIS WEEK / … kickers.
    nonisolated enum TimeBucket: CaseIterable {
        case today
        case yesterday
        case thisWeek
        case thisMonth
        case earlier
        case never

        var title: String {
            switch self {
            case .today: "Today"
            case .yesterday: "Yesterday"
            case .thisWeek: "This week"
            case .thisMonth: "This month"
            case .earlier: "Earlier"
            case .never: "Never opened"
            }
        }

        /// `nil` is a work that has a record but was never opened in the reader —
        /// its own bucket rather than folded into Earlier, because "never" and
        /// "a long time ago" are different answers and the second implies the first
        /// happened.
        static func bucket(for date: Date?, now: Date, calendar: Calendar) -> TimeBucket {
            guard let date else { return .never }
            // Against `now`, not the wall clock: `isDateInToday` ignores the
            // parameter every other bucket here honours.
            if calendar.isDate(date, inSameDayAs: now) { return .today }
            if calendar.isDate(date, inSameDayAs: calendar.startOfDay(for: now) - 60) { return .yesterday }
            if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) { return .thisWeek }
            if calendar.isDate(date, equalTo: now, toGranularity: .month) { return .thisMonth }
            return .earlier
        }
    }
}
