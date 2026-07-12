import Foundation

/// Parses AO3's comment timestamp text once and presents it in the user's
/// current calendar/time zone. All methods accept explicit clock/locale inputs
/// so calendar-boundary behavior stays deterministic in tests.
nonisolated enum AO3CommentTimestamp {
    nonisolated private static let parseFormats = [
        "EEE dd MMM yyyy hh:mma zzz",
        "EEE dd MMM yyyy h:mma zzz",
        "EEE dd MMM yyyy hh:mm a zzz",
        "EEE dd MMM yyyy HH:mm zzz",
        "dd MMM yyyy hh:mma zzz",
        "EEE dd MMM yyyy hh:mma XXXXX",
        "EEE dd MMM yyyy HH:mm XXXXX",
        "EEE dd MMM yyyy hh:mma Z",
        "EEE dd MMM yyyy HH:mm Z"
    ]

    /// Built once rather than nine fresh `DateFormatter`s per call — `displayText`
    /// falls back to `parse` on every render for any comment whose timestamp didn't
    /// parse at scrape time. Configured here and only read afterwards, which is the
    /// documented thread-safe use of `DateFormatter`.
    // Configured once and only read afterwards (thread-safe DateFormatter usage).
    // Under approachable concurrency the array is treated as Sendable enough for
    // a nonisolated constant; avoid nonisolated(unsafe) so the compiler stays quiet.
    nonisolated private static let parseFormatters: [DateFormatter] = parseFormats.map {
        format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        formatter.isLenient = false
        return formatter
    }

    nonisolated static func parse(_ rawText: String) -> Date? {
        let normalized = rawText
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !normalized.isEmpty else { return nil }

        for formatter in parseFormatters {
            if let date = formatter.date(from: normalized) {
                return date
            }
        }
        return nil
    }

    nonisolated static func displayText(
        rawText: String,
        date parsedDate: Date?,
        relativeTo now: Date = Date(),
        calendar: Calendar = .current,
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) -> String {
        guard let date = parsedDate ?? parse(rawText) else { return rawText }

        var localCalendar = calendar
        localCalendar.timeZone = timeZone
        let age = now.timeIntervalSince(date)

        if age >= 0, age < 24 * 60 * 60 {
            let relative = RelativeDateTimeFormatter()
            relative.locale = locale
            relative.unitsStyle = .full
            return relative.localizedString(for: date, relativeTo: now)
        }

        let startOfToday = localCalendar.startOfDay(for: now)
        let startOfCommentDay = localCalendar.startOfDay(for: date)
        let startOfYesterday = localCalendar.date(
            byAdding: .day,
            value: -1,
            to: startOfToday
        )
        if startOfCommentDay == startOfYesterday {
            return "Yesterday at \(timeText(for: date, calendar: localCalendar, timeZone: timeZone, locale: locale))"
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.calendar = localCalendar
        dateFormatter.timeZone = timeZone
        dateFormatter.setLocalizedDateFormatFromTemplate("yMd")
        return "\(dateFormatter.string(from: date)) at "
            + timeText(for: date, calendar: localCalendar, timeZone: timeZone, locale: locale)
    }

    nonisolated private static func timeText(
        for date: Date,
        calendar: Calendar,
        timeZone: TimeZone,
        locale: Locale
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("jm")
        let zone = timeZone.abbreviation(for: date) ?? timeZone.identifier
        let time = formatter.string(from: date)
            .replacingOccurrences(of: "\u{202f}", with: " ")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
        return "\(time) \(zone)"
    }
}
