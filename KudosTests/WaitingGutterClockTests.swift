import Foundation
import Testing
@testable import Kudos

struct WaitingGutterClockTests {
    private func clock(hour: Int, identifier: String, hourCycle: Locale.HourCycle) -> WaitingGutterClock {
        var components = Locale.Components(identifier: identifier)
        components.hourCycle = hourCycle
        let locale = Locale(components: components)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = locale
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: hour, minute: 0))!
        return WaitingGutterClock.parts(for: date, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }

    @Test func twelveHourKeepsTheMarkerOffTheTime() {
        let afternoon = clock(hour: 15, identifier: "en_US", hourCycle: .oneToTwelve)
        #expect(afternoon.time == "3:00")
        #expect(afternoon.marker == "PM")

        let morning = clock(hour: 3, identifier: "en_US", hourCycle: .oneToTwelve)
        #expect(morning.time == "3:00")
        #expect(morning.marker == "AM")
    }

    @Test func twentyFourHourIsOneToken() {
        let english = clock(hour: 15, identifier: "en_GB", hourCycle: .zeroToTwentyThree)
        #expect(english.time == "15:00")
        #expect(english.marker == nil)

        let forced = clock(hour: 15, identifier: "en_US", hourCycle: .zeroToTwentyThree)
        #expect(forced.time == "15:00")
        #expect(forced.marker == nil)

        // The locale's separator stays; the hour cycle contributes no marker.
        let danish = clock(hour: 15, identifier: "da_DK", hourCycle: .zeroToTwentyThree)
        #expect(danish.time == "15.00")
        #expect(danish.marker == nil)
    }

    @Test func dayPeriodBeforeTheHourStaysItsOwnToken() {
        let korean = clock(hour: 15, identifier: "ko_KR", hourCycle: .oneToTwelve)
        #expect(korean.time == "3:00")
        #expect(korean.marker == "오후")

        let traditionalChinese = clock(hour: 15, identifier: "zh_TW", hourCycle: .oneToTwelve)
        #expect(traditionalChinese.time == "3:00")
        #expect(traditionalChinese.marker == "下午")
    }
}
