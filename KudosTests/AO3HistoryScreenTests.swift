import Foundation
import Testing
@testable import Kudos

/// 1t's pure pieces: the history write routes, the visit-phrase buckets, and
/// the local-progress fact paired with a visit count. Nothing here signs in
/// or posts.
struct AO3HistoryScreenTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    /// 2026-09-21, the day these buckets were pinned.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 21))!
    }

    /// Pins otwarchive's readings routes: member destroy, and the collection
    /// `confirm_clear` / `clear` pair. Page 1 omits the query the blurb only
    /// adds when `params[:page]` is set.
    @Test func historyWriteRoutesMatchOtwarchive() {
        #expect(
            AO3Client.deleteReadingURL(username: "testuser", readingID: 7, page: 1)?.absoluteString
                == "https://archiveofourown.org/users/testuser/readings/7"
        )
        #expect(
            AO3Client.deleteReadingURL(username: "testuser", readingID: 7, page: 4)?.absoluteString
                == "https://archiveofourown.org/users/testuser/readings/7?page=4"
        )
        #expect(
            AO3Client.confirmClearReadingsURL(username: "testuser")?.absoluteString
                == "https://archiveofourown.org/users/testuser/readings/confirm_clear"
        )
        #expect(
            AO3Client.clearReadingsURL(username: "testuser")?.absoluteString
                == "https://archiveofourown.org/users/testuser/readings/clear"
        )
        #expect(AO3Client.deleteReadingURL(username: " ", readingID: 7, page: 1) == nil)
        #expect(AO3Client.deleteReadingURL(username: "testuser", readingID: 0, page: 1) == nil)
        #expect(AO3Client.confirmClearReadingsURL(username: "") == nil)
        #expect(AO3Client.clearReadingsURL(username: "") == nil)
    }

    @Test func relativePhrasesLandInTheNearestHeading() {
        let samples: [(String, AO3HistoryVisitBucket)] = [
            ("less than a minute", .today),
            ("12 minutes", .today),
            ("about 1 hour", .today),
            ("about 5 hours", .today),
            ("1 day", .yesterday),
            ("2 days", .thisWeek),
            ("6 days", .thisWeek),
            ("7 days", .thisMonth),
            ("29 days", .thisMonth),
            ("about 1 month", .thisMonth),
            ("3 months", .earlier),
            ("", .earlier),
            ("not a date", .earlier)
        ]
        for (phrase, bucket) in samples {
            #expect(
                AO3HistoryVisitBucket.bucket(lastVisited: phrase, now: now, calendar: calendar) == bucket
            )
        }
    }

    @Test func absoluteDatesUseTheCalendarMonth() {
        #expect(
            AO3HistoryVisitBucket.bucket(lastVisited: "21 Sep 2026", now: now, calendar: calendar)
                == .thisMonth
        )
        #expect(
            AO3HistoryVisitBucket.bucket(lastVisited: "04 Mar 2024", now: now, calendar: calendar)
                == .earlier
        )
        #expect(
            AO3HistoryVisitBucket.bucket(lastVisited: "31 Aug 2026", now: now, calendar: calendar)
                == .earlier
        )
    }

    /// A heading is inserted where the page's own order changes bucket. Rows
    /// are not pulled into calendar order.
    @Test func groupsFollowSourceOrder() {
        let phrases = ["04 Mar 2024", "about 1 hour", "3 minutes", "2 days", "6 days"]
        let groups = AO3HistoryVisitGrouping.groups(
            phrases, now: now, calendar: calendar, lastVisited: { $0 }
        )
        #expect(groups.map(\.bucket) == [.earlier, .today, .thisWeek])
        #expect(groups.map(\.items.count) == [1, 2, 2])
    }

    @Test func progressPillsUseLocalStateOnly() {
        #expect(AO3HistoryProgressFilter.everything.includes(isInProgress: false, isFinished: false))
        #expect(!AO3HistoryProgressFilter.inProgress.includes(isInProgress: false, isFinished: false))
        #expect(!AO3HistoryProgressFilter.finished.includes(isInProgress: false, isFinished: false))
        #expect(AO3HistoryProgressFilter.inProgress.includes(isInProgress: true, isFinished: false))
        #expect(!AO3HistoryProgressFilter.inProgress.includes(isInProgress: true, isFinished: true))
        #expect(AO3HistoryProgressFilter.finished.includes(isInProgress: false, isFinished: true))
    }

    @Test func localProgressPairsChapterOrFinished() {
        #expect(
            AO3HistoryLocalProgress.label(
                isFinished: false, lastSpineIndex: 13, chapters: "14/24", readingProgress: 0.5
            ) == "Ch. 14 of 24"
        )
        #expect(
            AO3HistoryLocalProgress.label(
                isFinished: true, lastSpineIndex: 13, chapters: "14/24", readingProgress: 1
            ) == "Finished"
        )
        #expect(
            AO3HistoryLocalProgress.label(
                isFinished: false, lastSpineIndex: 0, chapters: "14/24", readingProgress: 0.42
            ) == "42%"
        )
        #expect(
            AO3HistoryLocalProgress.label(
                isFinished: false, lastSpineIndex: 0, chapters: "", readingProgress: nil
            ) == nil
        )
    }

    /// `AO3AuthService.readingsWriteResult` — the classification the two
    /// history writes share. Both routes end in a Rails destroy-style
    /// redirect, so a bare 3xx counts; a silent 2xx with neither an error nor
    /// a success flash must NOT be read as success — that was the original
    /// bug this pins against regressing.
    @MainActor
    @Test func readingsWriteResultRequiresPositiveEvidence() throws {
        // An explicit flash notice.
        #expect(
            try AO3AuthService.readingsWriteResult(
                status: 200,
                body: "<div class=\"flash notice\">Reading was successfully removed.</div>",
                success: "Removed.", rejectedFallback: "Couldn't remove."
            ) == "Removed."
        )
        // A bare redirect with no rendered flash — the ordinary Rails destroy shape.
        #expect(
            try AO3AuthService.readingsWriteResult(
                status: 302, body: "", success: "Removed.", rejectedFallback: "Couldn't remove."
            ) == "Removed."
        )
        // A recognized error flash always rejects, whatever the status.
        #expect(throws: AO3WriteError.self) {
            try AO3AuthService.readingsWriteResult(
                status: 200,
                body: "<p class=\"error\">You can't do that.</p>",
                success: "Removed.", rejectedFallback: "Couldn't remove."
            )
        }
        // The bug: a 200 with neither flash — a maintenance page, an
        // interstitial, a blank body — must throw unconfirmed, not claim
        // success just because nothing explicitly rejected it.
        #expect {
            try AO3AuthService.readingsWriteResult(
                status: 200, body: "<html><body>Under maintenance</body></html>",
                success: "Removed.", rejectedFallback: "Couldn't remove."
            )
        } throws: { error in
            (error as? AO3WriteError) == .unconfirmed
        }
        // Outside 2xx/3xx entirely: a real rejection, using the fallback
        // message since AO3 sent no specific reason.
        #expect {
            try AO3AuthService.readingsWriteResult(
                status: 500, body: "", success: "Removed.", rejectedFallback: "Couldn't remove."
            )
        } throws: { error in
            (error as? AO3WriteError) == .rejected("Couldn't remove.")
        }
    }
}
