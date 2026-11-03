import Foundation
import Testing
@testable import Kudos

struct AO3InboxTimeLabelTests {
    private let locale = Locale(identifier: "en_US_POSIX")
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Sat 24 Oct 2026, 14:00 UTC.
    private var now: Date { Date(timeIntervalSince1970: 1_792_850_400) }

    private func label(_ raw: String) -> AO3InboxTimeLabel.Label? {
        AO3InboxTimeLabel.label(for: raw, now: now, calendar: calendar, locale: locale)
    }

    @Test func todayShowsTheTime() {
        // The space before "AM" differs by OS version (narrow no-break space), so check the parts.
        let today = label("Sat 24 Oct 2026 9:12AM UTC")?.display ?? ""
        #expect(today.hasPrefix("9:12") && today.hasSuffix("AM"))
    }

    @Test func yesterdayWeekdayAndOlderDates() {
        #expect(label("Fri 23 Oct 2026 9:12AM UTC")?.display == "Yesterday")
        #expect(label("Tue 20 Oct 2026 9:12AM UTC")?.display == "Tue")
        #expect(label("Mon 12 Oct 2026 9:12AM UTC")?.display == "Oct 12")
        #expect(label("Sat 20 Sep 2025 9:12AM UTC")?.display == "Sep 20, 2025")
    }

    @Test func relativeTextIsBucketedAndSpokenAsAO3WroteIt() {
        let result = label("3 days ago")
        #expect(result?.display == "Wed")
        #expect(result?.spoken == "3 days ago")
        #expect(label("2 weeks ago")?.display == "Oct 10")
    }

    @Test func unparseableTextPassesThroughAndEmptyIsNil() {
        #expect(label("sometime")?.display == "sometime")
        #expect(label("  ") == nil)
    }

    @Test func summaryLineNamesTheFilterExceptAll() {
        let base = AO3InboxTally.headerLine(total: 12, unread: 3, awaitingOnPage: 1, totalPages: 2)
        #expect(AO3InboxTally.summaryLine(
            total: 12, unread: 3, awaitingOnPage: 1, totalPages: 2, showing: .unread
        ) == base + " · showing Unread")
        #expect(AO3InboxTally.summaryLine(
            total: 12, unread: 3, awaitingOnPage: 1, totalPages: 2, showing: .all
        ) == base)
        #expect(AO3InboxTally.summaryLine(
            total: 12, unread: 3, awaitingOnPage: 1, totalPages: 2, showing: nil
        ) == base)
    }
}
