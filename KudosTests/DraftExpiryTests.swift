import Foundation
import Testing
@testable import Kudos

/// 1x's "N days left" and "Created …" on Drafts, from the deletion date AO3
/// prints on every unposted work's blurb (otwarchive-facts-wave3 Q17).
@MainActor
struct DraftExpiryTests {
    /// Built from otwarchive's own templates at 00ad85b4: `works/_work_blurb`
    /// (`li#work_<id>`), `works/_work_module` (header module, `p.datetime`, and
    /// the `p.caution.notice` for `!work.posted?`), and `en.yml`'s
    /// `draft_deletion_notice_html` and `date_short_html`. The second draft has
    /// no notice, so it must be absent from the result rather than guessed.
    private let draftsHTML = """
    <ul class="work index group">
    <li id="work_41234567" class="own work blurb group work-41234567 user-123" role="article">
      <div class="header module">
        <!-- updated_at=1788700000 -->
        <h4 class="heading">
          <a href="/works/41234567">Untitled — diner scene</a>
          by
          <a rel="author" href="/users/tester/pseuds/tester">tester</a>
        </h4>
        <h5 class="fandoms heading">
          <span class="landmark">Fandoms:</span>
          <a class="tag" href="/tags/Supernatural/works">Supernatural</a>
          &nbsp;
        </h5>
        <p class="datetime">06 Sep 2026</p>
      </div>
      <p class="caution notice">This draft will be <strong>scheduled for deletion</strong> on \
    <abbr class="day" title="Monday">Mon</abbr> <span class="date">05</span> \
    <abbr class="month" title="October">Oct</abbr> <span class="year">2026</span>.</p>
      <h6 class="landmark heading">Tags</h6>
      <ul class="tags commas"></ul>
    </li>
    <li id="work_41234568" class="own work blurb group work-41234568 user-123" role="article">
      <div class="header module">
        <h4 class="heading"><a href="/works/41234568">No notice</a></h4>
        <p class="datetime">01 Sep 2026</p>
      </div>
    </li>
    </ul>
    """

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test func parsesTheNoticeDateAndSkipsABlurbWithout() {
        let dates = AO3Client.parseDraftDeletionDates(draftsHTML)
        #expect(dates[41_234_567] == DateComponents(year: 2026, month: 10, day: 5))
        #expect(dates[41_234_568] == nil)
        #expect(dates.count == 1)
    }

    @Test func daysLeftCountsWholeDaysAndNeverGoesNegative() {
        let deletion = DateComponents(year: 2026, month: 10, day: 5)
        #expect(DraftExpiry.daysLeft(until: deletion, now: date(2026, 10, 5), calendar: calendar) == 0)
        #expect(DraftExpiry.daysLeft(until: deletion, now: date(2026, 10, 4, hour: 23), calendar: calendar) == 1)
        #expect(DraftExpiry.daysLeft(until: deletion, now: date(2026, 10, 9), calendar: calendar) == 0)
        #expect(DraftExpiry.daysLeft(until: deletion, now: date(2026, 9, 28), calendar: calendar) == 7)
        let incomplete = DateComponents(month: 10)
        #expect(DraftExpiry.daysLeft(until: incomplete, now: date(2026, 10, 1), calendar: calendar) == nil)
    }

    /// Created is the deletion date less AO3's 29 days.
    @Test func createdIsTwentyNineDaysBeforeDeletion() {
        let created = DraftExpiry.createdDate(
            fromDeletion: DateComponents(year: 2026, month: 10, day: 5), calendar: calendar
        )
        #expect(created.map { calendar.dateComponents([.year, .month, .day], from: $0) }
            == DateComponents(year: 2026, month: 9, day: 6))
    }

    @Test func expiringThisWeekCountsSevenDaysOrFewer() {
        let now = date(2026, 10, 1)
        let deletions = [
            DateComponents(year: 2026, month: 10, day: 3),   // 2 days
            DateComponents(year: 2026, month: 10, day: 8),   // 7 days
            DateComponents(year: 2026, month: 10, day: 20)   // 19 days
        ]
        #expect(DraftExpiry.expiringThisWeek(deletions, now: now, calendar: calendar) == 2)
    }

    @Test func chipTextSaysLastDayRatherThanZero() {
        #expect(DraftExpiry.chipText(daysLeft: 0) == "Last day")
        #expect(DraftExpiry.chipText(daysLeft: 1) == "1 day left")
        #expect(DraftExpiry.chipText(daysLeft: 22) == "22 days left")
    }
}
