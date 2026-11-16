import Foundation

/// Pure scheduling and count rules; the queue page supplies the fetcher and clock.
enum QueueSourceChecks {
    static let cooldown: TimeInterval = 6 * 60 * 60
    static let spacing: TimeInterval = 3

    static func eligible<T>(
        _ sources: [T], checkedAt: (T) -> Date?, now: Date
    ) -> [T] {
        sources.filter { source in
            checkedAt(source).map { now.timeIntervalSince($0) >= cooldown } ?? true
        }
        .sorted { (checkedAt($0) ?? .distantPast) < (checkedAt($1) ?? .distantPast) }
        .prefix(5).map { $0 }
    }

    static func count(_ page: AO3SearchPage, since opened: Date?) -> Int {
        guard let opened else { return page.works.count }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["yyyy-MM-dd", "dd MMM yyyy", "d MMM yyyy"] {
            formatter.dateFormat = format
            let dates = page.works.map { formatter.date(from: $0.dateUpdated) }
            if dates.contains(where: { $0 != nil }) {
                return dates.filter { $0.map { $0 > opened } ?? false }.count
            }
        }
        return 0
    }

    static func badge(_ count: Int) -> String {
        count >= 20 ? "20+ new" : "\(count) new"
    }

    @MainActor
    // swiftlint:disable:next function_parameter_count
    static func run<Source>(
        sources: [Source],
        checkedAt: (Source) -> Date?,
        now: () -> Date,
        sleep: (TimeInterval) async throws -> Void,
        attempt: (Source, Date) -> Bool,
        fetch: (Source) async throws -> AO3SearchPage,
        received: (Source, AO3SearchPage) -> Void
    ) async {
        let selected = eligible(sources, checkedAt: checkedAt, now: now())
        var previousStart: Date?
        for source in selected {
            do {
                try Task.checkCancellation()
                if let previousStart {
                    let remaining = spacing - now().timeIntervalSince(previousStart)
                    if remaining > 0 { try await sleep(remaining) }
                }
                try Task.checkCancellation()
                let started = now()
                guard attempt(source, started) else { return }
                previousStart = started
                let page = try await fetch(source)
                try Task.checkCancellation()
                received(source, page)
            } catch is CancellationError {
                return
            } catch AO3Error.rateLimited {
                return
            } catch AO3Error.forbidden {
                return
            } catch AO3Error.maintenance {
                return
            } catch {
                // The attempt remains stamped; another eligible source may run.
            }
        }
    }
}
