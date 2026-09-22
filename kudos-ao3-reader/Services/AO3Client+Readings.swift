import Foundation
import SwiftSoup

/// One row's reading metadata on `/users/:id/readings` — artboard **1t**.
///
/// AO3 renders this page with `readings/_reading_blurb`, which wraps the
/// ordinary `works/work_module` in a `li.reading.work` and then adds a
/// `div.user.module` the plain work blurb never has. Everything in this type
/// lives in that extra block, which is why routing history through the generic
/// blurb parser silently discarded all of it.
nonisolated struct AO3ReadingEntry: Equatable, Sendable {
    /// What AO3 knows about the version you read versus the one posted now.
    enum VersionStatus: Equatable, Sendable {
        case updateAvailable
        case minorEdits
        case latestVersion
        /// The row said none of the three — never guess which.
        case unknown
    }

    var workID: Int?
    /// The reading record's own id, from the row's `form.ajax-remove` action
    /// (`/users/:user/readings/:id`). That is not the work id: otwarchive's
    /// destroy looks up `@user.readings.find(params[:id])`. Nil when the row
    /// rendered no delete form — the app then offers no delete.
    var readingID: Int?
    /// AO3's own wording, kept rather than re-derived: `set_format_for_date`
    /// gives `time_ago_in_words` ("2 days") within 30 days and an rfc822 date
    /// ("04 Mar 2024") beyond it, so there is no single timestamp to parse back
    /// out. Storing the text means the screen can never disagree with the site.
    var lastVisited: String = ""
    var visitCount: Int?
    var versionStatus: VersionStatus = .unknown
    var isMarkedForLater = false
    var isFlaggedToSkip = false
    /// AO3 keeps the reading after the work goes: the row has no `id` and no
    /// work module, only "(Deleted work, last visited …)".
    var isDeletedWork = false

    /// "2 days" needs "ago"; "04 Mar 2024" must not get it. The rfc822 form is
    /// the only one shaped `DD Mon YYYY`, so anything else is a duration.
    var lastVisitedIsRelative: Bool {
        lastVisited.range(of: #"^\d{1,2} \w{3} \d{4}$"#, options: .regularExpression) == nil
    }

    /// 1t's line: "Last visited 2d ago".
    var lastVisitedDisplay: String? {
        guard !lastVisited.isEmpty else { return nil }
        return lastVisitedIsRelative
            ? "Last visited \(lastVisited) ago"
            : "Last visited \(lastVisited)"
    }

    /// 1t draws "Visited once" / "Visited twice" / "Visited 7 times". AO3 itself
    /// only special-cases 1 and writes "Visited 2 times"; the board's "twice" is
    /// the nicety, and the tree is what this screen follows.
    var visitCountDisplay: String? {
        guard let visitCount, visitCount > 0 else { return nil }
        switch visitCount {
        case 1: return "Visited once"
        case 2: return "Visited twice"
        default: return "Visited \(visitCount.formatted()) times"
        }
    }

    var versionDisplay: String? {
        switch versionStatus {
        case .updateAvailable: "Update available"
        case .minorEdits: "Minor edits since then"
        case .latestVersion: "Latest version"
        case .unknown: nil
        }
    }
}

extension AO3Client {
    /// Parse the per-row reading metadata from a readings page.
    ///
    /// Returned in page order. Rows for deleted works carry no `workID` — AO3
    /// omits the `id` attribute when the work is gone — so a caller keying by
    /// work id will not find them; that is the same reason they have no blurb to
    /// attach to either.
    ///
    /// Scoped to `ol.reading.work` and then to each row's own `div.user.module`,
    /// because the work module above it has headings of its own.
    static func parseReadingEntries(from html: String) throws -> [AO3ReadingEntry] {
        let doc = try SwiftSoup.parse(html)
        guard let list = try doc.select("ol.reading.work").first() else { return [] }
        var entries: [AO3ReadingEntry] = []
        for row in try list.select("> li").array() {
            guard let heading = try row.select("div.user.module h4.viewed").first() else { continue }
            let text = try heading.text()
            var entry = AO3ReadingEntry()
            entry.workID = Int((try? row.attr("id"))?
                .replacingOccurrences(of: "work_", with: "") ?? "")
            entry.readingID = try Self.readingID(in: row)
            entry.isDeletedWork = try row.hasClass("deleted") || text.contains("Deleted work")
            entry.lastVisited = Self.lastVisitedText(in: text)
            entry.visitCount = Self.visitCount(in: text)
            entry.versionStatus = Self.versionStatus(in: text)
            entry.isMarkedForLater = text.contains("Marked for Later")
            entry.isFlaggedToSkip = text.contains("Flagged to skip")
            entries.append(entry)
        }
        return entries
    }

    /// Two shapes: "Last visited: 2 days (Latest version.) …" and, for a work
    /// AO3 no longer has, "(Deleted work, last visited 04 Mar 2024)".
    private static func lastVisitedText(in text: String) -> String {
        if let range = text.range(of: "last visited", options: .caseInsensitive) {
            let tail = text[range.upperBound...]
                .trimmingCharacters(in: CharacterSet(charactersIn: ": "))
            // Stops at the parenthesis that opens the version note, or at the
            // closing one on the deleted-work sentence.
            let cut = tail.prefix { $0 != "(" && $0 != ")" }
            return cut.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    private static func visitCount(in text: String) -> Int? {
        if text.contains("Visited once") { return 1 }
        guard let match = text.range(
            of: #"Visited ([\d,]+) times"#,
            options: .regularExpression
        ) else { return nil }
        let digits = text[match].filter(\.isNumber)
        return Int(digits)
    }

    private static func versionStatus(in text: String) -> AO3ReadingEntry.VersionStatus {
        if text.contains("Update available") { return .updateAvailable }
        if text.contains("Minor edits") { return .minorEdits }
        if text.contains("Latest version") { return .latestVersion }
        return .unknown
    }

    /// Last path segment of `form.ajax-remove`'s action. The fixture and
    /// `_reading_blurb.html.erb` both post to `/users/:user/readings/:reading_id`.
    private static func readingID(in row: Element) throws -> Int? {
        guard let action = try row.select("form.ajax-remove").first()?.attr("action"),
              !action.isEmpty
        else { return nil }
        let path = action.split(separator: "?", maxSplits: 1).first.map(String.init) ?? action
        guard let raw = path.split(separator: "/").last else { return nil }
        return Int(raw)
    }

    /// `DELETE /users/:user_id/readings/:id` — the member route from
    /// `resources :readings` under `resources :users` in otwarchive `config/routes.rb`.
    /// Page is what the blurb's form passes through (`page: params[:page]`); page 1
    /// omits it, matching a first-page form with no query.
    static func deleteReadingURL(username: String, readingID: Int, page: Int) -> URL? {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, readingID > 0 else { return nil }
        var components = URLComponents(string: "https://archiveofourown.org")
        components?.path = "/users/\(name)/readings/\(readingID)"
        if page > 1 {
            components?.queryItems = [URLQueryItem(name: "page", value: String(page))]
        }
        return components?.url
    }

    /// `GET /users/:user_id/readings/confirm_clear` — collection route `get :confirm_clear`.
    static func confirmClearReadingsURL(username: String) -> URL? {
        readingsCollectionURL(username: username, action: "confirm_clear")
    }

    /// `POST /users/:user_id/readings/clear` — collection route `post :clear`.
    static func clearReadingsURL(username: String) -> URL? {
        readingsCollectionURL(username: username, action: "clear")
    }

    private static func readingsCollectionURL(username: String, action: String) -> URL? {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        var components = URLComponents(string: "https://archiveofourown.org")
        components?.path = "/users/\(name)/readings/\(action)"
        return components?.url
    }
}

/// 1t's Everything / In progress / Finished pills. They filter the loaded page
/// by the local library copy's reading state. AO3's history page has no such
/// query: a row with no saved copy matches only Everything.
enum AO3HistoryProgressFilter: String, CaseIterable, Identifiable, Sendable {
    case everything
    case inProgress
    case finished

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everything: "Everything"
        case .inProgress: "In progress"
        case .finished: "Finished"
        }
    }

    func includes(isInProgress: Bool, isFinished: Bool) -> Bool {
        switch self {
        case .everything: true
        case .inProgress: isInProgress && !isFinished
        case .finished: isFinished
        }
    }
}

/// The local fact 1t pairs with the visit count. Finished wins over a chapter
/// position, matching the board's third row ("Finished" where the others say
/// "Ch. N of M"). Nil when the library copy has nothing to report — the visit
/// line then stays the remote facts alone.
enum AO3HistoryLocalProgress {
    static func label(
        isFinished: Bool,
        lastSpineIndex: Int,
        chapters: String,
        readingProgress: Double?
    ) -> String? {
        if isFinished { return "Finished" }
        if lastSpineIndex > 0 {
            let current = lastSpineIndex + 1
            let parts = chapters.split(separator: "/")
            if parts.count == 2,
               let total = Int(parts[1].trimmingCharacters(in: .whitespaces)),
               total > 0 {
                return "Ch. \(current) of \(total)"
            }
            return "Ch. \(current)"
        }
        guard let readingProgress, readingProgress > 0 else { return nil }
        let percent = Int((min(readingProgress, 1) * 100).rounded())
        guard percent > 0 else { return nil }
        return "\(percent)%"
    }
}

/// Headings for 1t's time groups.
///
/// AO3's readings index does not bucket. `set_format_for_date` prints
/// `time_ago_in_words` inside 30 days and an rfc822 date after that, and the
/// list is one flat `ol` ordered `last_viewed DESC`. These cases are the
/// closest heading that phrase can support. "2 days" through "6 days" is
/// "This week" as a span, not a calendar week: the words are not a timestamp,
/// so `LibraryHistoryGrouping.TimeBucket` (which needs a real `Date`) cannot
/// be reused without inventing a clock time the page does not have.
enum AO3HistoryVisitBucket: String, CaseIterable, Sendable {
    case today
    case yesterday
    case thisWeek
    case thisMonth
    case earlier

    var title: String {
        switch self {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .thisWeek: "This week"
        case .thisMonth: "This month"
        case .earlier: "Earlier"
        }
    }

    static func bucket(
        lastVisited: String,
        now: Date,
        calendar: Calendar = .current
    ) -> AO3HistoryVisitBucket {
        let text = lastVisited.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return .earlier }
        if text.range(of: #"^\d{1,2} [A-Za-z]{3} \d{4}$"#, options: .regularExpression) != nil {
            return absoluteBucket(text, now: now, calendar: calendar)
        }
        let lower = text.lowercased()
        if lower.contains("second") || lower.contains("minute") || lower.contains("hour") {
            return .today
        }
        if let days = prefixedCount(lower, unit: "day") {
            switch days {
            case ...1: return .yesterday
            case 2 ... 6: return .thisWeek
            default: return .thisMonth
            }
        }
        if let months = prefixedCount(lower, unit: "month") {
            return months <= 1 ? .thisMonth : .earlier
        }
        return .earlier
    }

    private static func absoluteBucket(
        _ text: String, now: Date, calendar: Calendar
    ) -> AO3HistoryVisitBucket {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "d MMM yyyy"
        guard let date = formatter.date(from: text) else { return .earlier }
        if calendar.isDate(date, equalTo: now, toGranularity: .month) { return .thisMonth }
        return .earlier
    }

    /// "2 days", "1 day", "about 1 month" — the shapes `time_ago_in_words` emits.
    private static func prefixedCount(_ text: String, unit: String) -> Int? {
        let pattern = "^(?:about\\s+)?(\\d+)\\s+\(unit)"
        guard let match = text.range(of: pattern, options: .regularExpression) else { return nil }
        let digits = text[match].filter(\.isNumber)
        return Int(digits)
    }
}

/// One source-ordered run of rows that share a visit bucket. A later row in an
/// earlier bucket starts a new group rather than being pulled upward: the page
/// order is AO3's, and a heading is inserted where that order changes bucket.
struct AO3HistoryVisitGroup<Element>: Identifiable {
    let id: Int
    let bucket: AO3HistoryVisitBucket
    var items: [Element]
}

enum AO3HistoryVisitGrouping {
    static func groups<Element>(
        _ items: [Element],
        now: Date = Date(),
        calendar: Calendar = .current,
        lastVisited: (Element) -> String
    ) -> [AO3HistoryVisitGroup<Element>] {
        var result: [AO3HistoryVisitGroup<Element>] = []
        for item in items {
            let bucket = AO3HistoryVisitBucket.bucket(
                lastVisited: lastVisited(item), now: now, calendar: calendar
            )
            if var last = result.last, last.bucket == bucket {
                last.items.append(item)
                result[result.count - 1] = last
            } else {
                result.append(AO3HistoryVisitGroup(
                    id: result.count, bucket: bucket, items: [item]
                ))
            }
        }
        return result
    }
}
