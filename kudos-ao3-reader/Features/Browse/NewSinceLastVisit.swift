import Foundation
import SwiftUI

/// The "New since your last visit" divider on a fandom's Date Updated list.
enum NewSinceLastVisit {
    /// Index of the last work updated on a day strictly after `previousVisit`'s day;
    /// the divider goes right after it. Nil when the divider should not show: not
    /// page 1, not newest-first by Date Updated, no previous visit, no newer work,
    /// or every work newer (nothing older to divide from). A work whose date does
    /// not parse counts as not newer.
    static func dividerIndex(
        updatedDates: [String],
        previousVisit: Date?,
        page: Int,
        newestFirstByUpdated: Bool,
        calendar: Calendar = .current
    ) -> Int? {
        guard page == 1, newestFirstByUpdated, let previousVisit else { return nil }
        let visitDay = calendar.dateComponents([.year, .month, .day], from: previousVisit)
        // AO3's dates carry no time zone; read them as the calendar day they print.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let lastNewer = updatedDates.lastIndex { text in
            guard let date = SubscriptionScanWorkFacts.parseUpdatedDate(text) else { return false }
            return dayKey(utc.dateComponents([.year, .month, .day], from: date)) > dayKey(visitDay)
        }
        guard let lastNewer, lastNewer < updatedDates.count - 1 else { return nil }
        return lastNewer
    }

    private static func dayKey(_ parts: DateComponents) -> Int {
        (parts.year ?? 0) * 10000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
    }

    /// "↑ New since your last visit · Jul 7", with the year only when it is not this one.
    static func label(
        previousVisit: Date, now: Date = Date(),
        calendar: Calendar = .current, locale: Locale = .current
    ) -> String {
        "↑ New since your last visit · \(dateText(previousVisit, now: now, calendar: calendar, locale: locale))"
    }

    static func accessibilityLabel(
        previousVisit: Date, now: Date = Date(),
        calendar: Calendar = .current, locale: Locale = .current
    ) -> String {
        let date = dateText(previousVisit, now: now, calendar: calendar, locale: locale)
        return "New since your last visit on \(date) above, older works below"
    }

    private static func dateText(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "MMMd" : "MMMdy")
        return formatter.string(from: date)
    }
}

/// The thin divider row between this visit's new works and the older ones.
struct NewSinceLastVisitDivider: View {
    let previousVisit: Date
    let palette: SubjectPalette

    var body: some View {
        HStack(spacing: 10) {
            line
            Text(NewSinceLastVisit.label(previousVisit: previousVisit))
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.accent)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            line
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NewSinceLastVisit.accessibilityLabel(previousVisit: previousVisit))
    }

    private var line: some View {
        Rectangle().fill(palette.accent.opacity(0.4)).frame(height: 0.5)
    }
}
