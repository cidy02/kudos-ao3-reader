import Foundation

/// Local-only reading insights derived from the Library's `SavedWork` records.
/// The app does not track sessions or per-word progress, so "words read" counts
/// only finished works whose AO3 word count is known.
struct ReadingStatistics {
    struct FandomCount: Identifiable, Equatable {
        let name: String
        let count: Int

        var id: String {
            name
        }
    }

    let totalWorks: Int
    let startedWorks: Int
    let finishedWorks: Int
    let inProgressWorks: Int
    let wordsRead: Int
    let openedLast7Days: Int
    let openedLast30Days: Int
    let latestReadDate: Date?
    let topFandoms: [FandomCount]

    var completionRate: Double {
        guard startedWorks > 0 else { return 0 }
        return Double(finishedWorks) / Double(startedWorks)
    }

    init(
        works: [SavedWork],
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        var started: [SavedWork] = []
        for work in works where Self.hasStarted(work) {
            started.append(work)
        }
        let finished = works.filter(\.isFinished)
        let inProgress = started.filter { !$0.isFinished }

        totalWorks = works.count
        startedWorks = started.count
        finishedWorks = finished.count
        inProgressWorks = inProgress.count
        wordsRead = finished.reduce(0) { total, work in
            total + max(0, work.wordCount)
        }
        latestReadDate = works.compactMap(\.lastReadDate).max()

        let startOfToday = calendar.startOfDay(for: now)
        let sevenDayStart = calendar.date(byAdding: .day, value: -6, to: startOfToday)
            ?? startOfToday
        let thirtyDayStart = calendar.date(byAdding: .day, value: -29, to: startOfToday)
            ?? startOfToday
        openedLast7Days = Self.countOpened(works, since: sevenDayStart, through: now)
        openedLast30Days = Self.countOpened(works, since: thirtyDayStart, through: now)
        topFandoms = Self.fandomCounts(in: started)
    }

    /// Finished counts as started even when the progress fields were reset. Defers
    /// to the model's canonical `hasStartedReading` — a private re-listing of its
    /// fields here once drifted (it missed the Readium reader's locator, undercounting
    /// works read only on iOS).
    private static func hasStarted(_ work: SavedWork) -> Bool {
        work.isFinished || work.hasStartedReading
    }

    private static func countOpened(
        _ works: [SavedWork],
        since start: Date,
        through end: Date
    ) -> Int {
        works.reduce(into: 0) { count, work in
            guard let date = work.lastReadDate, date >= start, date <= end else { return }
            count += 1
        }
    }

    private static func fandomCounts(in works: [SavedWork]) -> [FandomCount] {
        var counts: [String: Int] = [:]
        for work in works {
            let uniqueFandoms = Set(work.workFandoms.compactMap { raw -> String? in
                let fandom = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return fandom.isEmpty ? nil : fandom
            })
            for fandom in uniqueFandoms {
                counts[fandom, default: 0] += 1
            }
        }
        return counts
            .map(FandomCount.init(name:count:))
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }
}
