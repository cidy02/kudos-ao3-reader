import SwiftData
import SwiftUI

// MARK: - Board Copy Helpers

/// Pure presentation copy & formatting helpers matching the Reading Insights boards
/// (`InsightsTop`, `Insights-Overview`, `Insights-Taste`, `Insights-Habits`, `Insights-Library`).
/// Computes no new statistics — formats only figures already produced by `Services/`.
nonisolated enum InsightsBoardCopy {
    struct UsualFicText: Equatable, Sendable {
        var prefix: String
        var boldFandom: String?
        var suffix: String

        var plainText: String {
            prefix + (boldFandom ?? "") + suffix
        }
    }

    /// Board format: `"24 min"` under an hour; `"14 h 10 m"` or `"2 h"` at or above an hour.
    static func durationLabel(_ seconds: Double) -> String {
        let totalMinutes = Int((max(0, seconds) / 60).rounded())
        if totalMinutes < 60 { return "\(totalMinutes) min" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours) h" : "\(hours) h \(minutes) m"
    }

    /// Spelled-out duration for VoiceOver accessibility labels (e.g. `"12 hours 25 minutes"`).
    static func spokenDuration(_ seconds: Double) -> String {
        let totalMinutes = Int((max(0, seconds) / 60).rounded())
        guard totalMinutes > 0 else { return "0 minutes" }
        var parts: [String] = []
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            parts.append("\(hours) \(hours == 1 ? "hour" : "hours")")
        }
        if minutes > 0 {
            parts.append("\(minutes) \(minutes == 1 ? "minute" : "minutes")")
        }
        return parts.joined(separator: " ")
    }

    static func periodUnit(isYear: Bool) -> String {
        isYear ? "this year" : "this month"
    }

    static func countLabel(_ count: Int, singular: String, plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }

    /// `InsightsTop`: `"1–27 Oct · vs September"` (Month) or `"2026 · vs 2025"` (Year).
    static func periodSubtitle(
        isYear: Bool,
        referenceDate: Date,
        now: Date = Date(),
        scopeSuffix: String = "",
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        if isYear {
            let yearFmt = formatter(template: "y", calendar: calendar, locale: locale)
            let year = yearFmt.string(from: referenceDate)
            let prevDate = calendar.date(byAdding: .year, value: -1, to: referenceDate) ?? referenceDate
            let prevYear = yearFmt.string(from: prevDate)
            return "\(year) · vs \(prevYear)\(scopeSuffix)"
        }
        let isCurrentMonth = calendar.isDate(referenceDate, equalTo: now, toGranularity: .month)
        let endDay = isCurrentMonth
            ? calendar.component(.day, from: now)
            : (calendar.range(of: .day, in: .month, for: referenceDate)?.count ?? 30)
        let shortMonth = formatter(template: "LLL", calendar: calendar, locale: locale).string(from: referenceDate)
        let prevDate = calendar.date(byAdding: .month, value: -1, to: referenceDate) ?? referenceDate
        let prevMonthFull = formatter(template: "LLLL", calendar: calendar, locale: locale).string(from: prevDate)
        let daySpan = endDay <= 1 ? "1" : "1–\(endDay)"
        return "\(daySpan) \(shortMonth) · vs \(prevMonthFull)\(scopeSuffix)"
    }

    /// `Insights-Overview` hero comparison: `"Sep 1–27"` (like-for-like partial month),
    /// `"Sep"` (when the full prior month is covered), or `"2025"` (Year).
    static func previousComparisonLabel(
        isYear: Bool,
        referenceDate: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        if isYear {
            let prevDate = calendar.date(byAdding: .year, value: -1, to: referenceDate) ?? referenceDate
            return formatter(template: "y", calendar: calendar, locale: locale).string(from: prevDate)
        }
        let prevDate = calendar.date(byAdding: .month, value: -1, to: referenceDate) ?? referenceDate
        let prevShort = formatter(template: "LLL", calendar: calendar, locale: locale).string(from: prevDate)
        let isCurrentMonth = calendar.isDate(referenceDate, equalTo: now, toGranularity: .month)
        let endDay = isCurrentMonth
            ? calendar.component(.day, from: now)
            : (calendar.range(of: .day, in: .month, for: referenceDate)?.count ?? 30)
        let prevMonthDays = calendar.range(of: .day, in: .month, for: prevDate)?.count ?? 30
        if endDay < prevMonthDays {
            return endDay <= 1 ? "\(prevShort) 1" : "\(prevShort) 1–\(endDay)"
        }
        return prevShort
    }

    /// Date span for the longest reading streak inside `days`, e.g. `"Oct 10–20"`.
    static func streakDateRangeLabel(
        days: [ReadingInsights.DailyWordsBucket],
        expectedLength: Int,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String? {
        guard expectedLength > 0 else { return nil }
        let activeDates = days
            .filter { $0.hasReading || $0.words > 0 }
            .map { calendar.startOfDay(for: $0.date) }
            .sorted()
        guard let first = activeDates.first else { return nil }

        var bestStart = first
        var bestEnd = first
        var bestLen = 1
        var runStart = first
        var runEnd = first
        var runLen = 1

        for date in activeDates.dropFirst() {
            let gap = calendar.dateComponents([.day], from: runEnd, to: date).day ?? 0
            if gap == 0 { continue }
            if gap == 1 {
                runEnd = date
                runLen += 1
                if runLen > bestLen {
                    bestLen = runLen
                    bestStart = runStart
                    bestEnd = runEnd
                }
            } else {
                runStart = date
                runEnd = date
                runLen = 1
            }
        }
        guard bestLen == expectedLength else { return nil }

        let monthDayFmt = formatter(template: "MMM d", calendar: calendar, locale: locale)
        if calendar.isDate(bestStart, inSameDayAs: bestEnd) {
            return monthDayFmt.string(from: bestStart)
        }
        if calendar.isDate(bestStart, equalTo: bestEnd, toGranularity: .month) {
            let monthShort = formatter(template: "MMM", calendar: calendar, locale: locale).string(from: bestStart)
            let startDay = calendar.component(.day, from: bestStart)
            let endDay = calendar.component(.day, from: bestEnd)
            return "\(monthShort) \(startDay)–\(endDay)"
        }
        return "\(monthDayFmt.string(from: bestStart))–\(monthDayFmt.string(from: bestEnd))"
    }

    /// `Insights-Overview` Biggest day detail: `"Saturday, Oct 17"`.
    static func biggestDayDetail(
        date: Date?,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        guard let date else { return "no data" }
        return formatter(template: "EEEE MMM d", calendar: calendar, locale: locale).string(from: date)
    }

    /// `Insights-Overview` Typical sitting detail: `"median of 35 sittings"`.
    static func typicalSittingDetail(sittingsCount: Int) -> String {
        guard sittingsCount > 0 else { return "no sittings yet" }
        return "median of \(countLabel(sittingsCount, singular: "sitting", plural: "sittings"))"
    }

    /// `Insights-Overview` Pace detail: `"an hour, reading only"`.
    static func paceDetail(isCharacters: Bool = false) -> String {
        isCharacters ? "characters an hour, reading only" : "an hour, reading only"
    }

    /// `Insights-Overview` Words per Day X-axis ticks: `["Oct 1", "8", "15", "22", "27"]`.
    static func wordsPerDayTicks(
        days: [ReadingInsights.DailyWordsBucket],
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> [String] {
        guard let first = days.first else { return [] }
        let monthDayFmt = formatter(template: "MMM d", calendar: calendar, locale: locale)
        if days.count == 1 {
            return [monthDayFmt.string(from: first.date)]
        }
        let last = days[days.count - 1]
        let sameMonth = calendar.isDate(first.date, equalTo: last.date, toGranularity: .month) && days.count <= 31
        if sameMonth {
            let rawIndices: [Int]
            if days.count >= 20 {
                rawIndices = [0, 7, 14, 21, days.count - 1]
            } else if days.count >= 8 {
                rawIndices = [0, days.count / 2, days.count - 1]
            } else {
                rawIndices = [0, days.count - 1]
            }
            var seen: Set<Int> = []
            var ticks: [String] = []
            for idx in rawIndices where idx < days.count && seen.insert(idx).inserted {
                let bucket = days[idx]
                if idx == 0 {
                    ticks.append(monthDayFmt.string(from: bucket.date))
                } else {
                    ticks.append("\(bucket.dayNumber)")
                }
            }
            return ticks
        }
        let indices: [Int] = days.count >= 3 ? [0, days.count / 2, days.count - 1] : [0, days.count - 1]
        return indices.map { monthDayFmt.string(from: days[$0].date) }
    }

    /// `Insights-Overview` Reading and Listening chart accessibility description.
    static func readingAndListeningBarLabel(
        silentSeconds: Double,
        listeningSeconds: Double,
        hideReadingTime: Bool
    ) -> String {
        guard !hideReadingTime else { return "Reading and Read Aloud time split" }
        return "Read \(spokenDuration(silentSeconds)), listened \(spokenDuration(listeningSeconds))"
    }

    /// `Insights-Overview` Length of What You Read chart accessibility description.
    static func lengthMixBarLabel(_ mix: ReadingInsights.LengthMixCounts) -> String {
        "Works by length: \(mix.under5k) under 5,000 words, \(mix.from5kTo50k) from 5,000 to 50,000, "
            + "\(mix.from50kTo150k) from 50,000 to 150,000, \(mix.over150k) over 150,000"
    }

    /// `Insights-Overview` Finished work row detail: `"21,880 words · Read ×4"`.
    static func finishedWorkMeta(wordCount: Int, finishCount: Int) -> String {
        let parts: [String?] = [
            wordCount > 0 ? "\(wordCount.formatted()) words" : nil,
            finishCount > 1 ? "Read ×\(finishCount)" : nil
        ]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    /// `Insights-Taste` Your Usual Fic prose sentence matching board style, with bold fandom span.
    static func usualFicText(
        taste: ReadingTasteInsights,
        discreetMode: Bool = false,
        discreetMasker: InsightsDiscreetMasker = .empty
    ) -> UsualFicText {
        if taste.usualFicTags.isEmpty {
            return UsualFicText(prefix: taste.usualFicSummary, boldFandom: nil, suffix: "")
        }

        let statusAdj: String? = switch taste.usualStatus {
        case "Complete": "complete"
        case "Work in Progress": "in-progress"
        default: nil
        }

        let ratingAdj: String?
        if taste.usualRating.isEmpty || taste.usualRating == "varied" {
            ratingAdj = nil
        } else if taste.usualRating == "Not Rated" {
            ratingAdj = "unrated"
        } else {
            ratingAdj = "\(taste.usualRating)-rated"
        }

        let categoryAdj: String? = (taste.usualCategory.isEmpty || taste.usualCategory == "varied")
            ? nil : taste.usualCategory

        let fandomText = taste.usualTopFandom.map { discreetMode ? discreetMasker.fandom($0) : $0 }

        let lengthPhrase: String?
        if taste.usualLengthBand.isEmpty || taste.usualLengthBand == "varied" {
            lengthPhrase = nil
        } else if taste.usualLengthBand == "Under 5k" {
            lengthPhrase = "under 5k words long"
        } else {
            lengthPhrase = "\(taste.usualLengthBand) words long"
        }

        let withItemsRaw: [String?] = [
            taste.usualTopRelationship.map { discreetMode ? discreetMasker.ship($0) : $0 },
            taste.usualTopTag.map { discreetMode ? discreetMasker.tag($0) : $0 },
            taste.usualSecondTag.map { discreetMode ? discreetMasker.tag($0) : $0 }
        ]
        let withItems = withItemsRaw.compactMap { $0 }

        let hasAnySpecific = statusAdj != nil || ratingAdj != nil || categoryAdj != nil
            || fandomText != nil || lengthPhrase != nil || !withItems.isEmpty
        guard hasAnySpecific else {
            return UsualFicText(
                prefix: "Your reading in this period is varied across fandoms, ratings and tags.",
                boldFandom: nil,
                suffix: ""
            )
        }

        let trailingDescriptors: [String] = [ratingAdj, categoryAdj].compactMap { $0 }
        let descriptorCore: String
        if let statusAdj, !trailingDescriptors.isEmpty {
            descriptorCore = "\(statusAdj), \(trailingDescriptors.joined(separator: " "))"
        } else if let statusAdj {
            descriptorCore = statusAdj
        } else {
            descriptorCore = trailingDescriptors.joined(separator: " ")
        }

        let nounPhrase = descriptorCore.isEmpty ? "fic" : "\(descriptorCore) fic"
        let lead = "\(indefiniteArticle(for: nounPhrase)) \(nounPhrase)"

        var tailParts: [String] = []
        if let lengthPhrase {
            tailParts.append(lengthPhrase)
        }
        if !withItems.isEmpty {
            tailParts.append("with \(joinBritishList(withItems))")
        }
        let tail = tailParts.isEmpty ? "." : ", \(tailParts.joined(separator: ", "))."

        if let fandomText {
            return UsualFicText(prefix: "\(lead) in ", boldFandom: fandomText, suffix: tail)
        }
        return UsualFicText(prefix: "\(lead)\(tail)", boldFandom: nil, suffix: "")
    }

    /// `Insights-Taste` When They Were Posted contiguous bars and evenly spaced tick years.
    static func yearHistogramSeries(
        from yearCounts: [ReadingTasteInsights.YearCount]
    ) -> (bars: [ReadingTasteInsights.YearCount], ticks: [Int]) {
        guard let minYear = yearCounts.map(\.year).min(),
              let maxYear = yearCounts.map(\.year).max()
        else { return ([], []) }

        let byYear = Dictionary(yearCounts.map { ($0.year, $0.count) }, uniquingKeysWith: { first, _ in first })
        let bars = (minYear...maxYear).map { year in
            ReadingTasteInsights.YearCount(year: year, count: byYear[year] ?? 0)
        }

        let span = maxYear - minYear
        let ticks: [Int]
        if span == 0 {
            ticks = [minYear]
        } else if span <= 4 {
            ticks = Array(minYear...maxYear)
        } else {
            var raw: [Int] = []
            for step in 0..<5 {
                let year = minYear + Int((Double(span) * Double(step) / 4.0).rounded())
                if raw.last != year { raw.append(year) }
            }
            if raw.last != maxYear { raw[raw.count - 1] = maxYear }
            ticks = raw
        }
        return (bars, ticks)
    }

    /// `Insights-Habits` Time of Day header subtitle: `"most at 21:00–23:00"`.
    static func peakHoursLabel(hourly: [ReadingInsights.HourlyBucket]) -> String? {
        guard hourly.contains(where: { $0.seconds > 0 }) else { return nil }
        var byHour = Array(repeating: 0.0, count: 24)
        for bucket in hourly where (0..<24).contains(bucket.hour) {
            byHour[bucket.hour] += max(0, bucket.seconds)
        }

        var bestStart = 0
        var bestSum = -1.0
        for h in 0..<24 {
            let next = (h + 1) % 24
            let sum = byHour[h] + byHour[next]
            if sum > bestSum {
                bestSum = sum
                bestStart = h
            }
        }
        guard bestSum > 0 else { return nil }
        let second = (bestStart + 1) % 24
        if byHour[bestStart] > 0 && byHour[second] > 0 {
            let endHour = bestStart + 2 == 24 ? 24 : (bestStart + 2) % 24
            return "most at \(bestStart):00–\(endHour):00"
        }
        let activeHour = byHour[bestStart] > 0 ? bestStart : second
        let endHour = activeHour + 1
        return "most at \(activeHour):00–\(endHour):00"
    }

    /// `Insights-Habits` Time of Day footer: `"Late night, 1:00–5:00: 1 h 47 m this month"`.
    static func lateNightSummary(durationSeconds: Double, hideReadingTime: Bool, isYear: Bool) -> String {
        let duration = hideReadingTime ? "—" : durationLabel(durationSeconds)
        return "Late night, 1:00–5:00: \(duration) \(periodUnit(isYear: isYear))"
    }

    /// `Insights-Habits` Sittings header right: `"35 this month"`.
    static func sittingsHeaderSummary(total: Int, isYear: Bool) -> String {
        "\(total) \(periodUnit(isYear: isYear))"
    }

    /// `Insights-Habits` Rereads row subtitle: `"Persuasion · 87.5k words across reads"`.
    static func rereadDetail(
        fandom: String,
        totalWordsAcrossReads: Int,
        discreetMode: Bool = false,
        discreetMasker: InsightsDiscreetMasker = .empty
    ) -> String {
        let fandomPrefix = fandom.isEmpty
            ? ""
            : "\(discreetMode ? discreetMasker.fandom(fandom) : fandom) · "
        return "\(fandomPrefix)\(compactWords(totalWordsAcrossReads)) words across reads"
    }

    /// `Insights-Habits` Stopped Reading header right: `"3 this month · 23 in all"`.
    static func stoppedHeaderSummary(inPeriod: Int, total: Int, isYear: Bool) -> String {
        "\(inPeriod) \(periodUnit(isYear: isYear)) · \(total) in all"
    }

    /// `Insights-Library` Unread hero suffix: `"words · 86 works"`.
    static func unreadHeroSuffix(unreadCount: Int) -> String {
        "words · \(countLabel(unreadCount, singular: "work", plural: "works"))"
    }

    /// `Insights-Library` Works in Progress chart accessibility description.
    static func wipFreshnessBarLabel(_ freshness: WIPFreshness) -> String {
        "\(freshness.active) updated in the last 6 months, \(freshness.quiet) in 6 to 12 months, "
            + "\(freshness.dormant) not for over a year"
    }

    /// `Insights-Library` No Longer on AO3 subtitle: `"14 works · 1.1M words · 12 kept as your last copy"`.
    static func noLongerOnAO3Summary(count: Int, words: Int, lastCopies: Int) -> String {
        "\(countLabel(count, singular: "work", plural: "works")) · "
            + "\(compactWords(words)) words · \(lastCopies) kept as your last copy"
    }

    /// `Insights-Library` Authors row detail: `"9 read · 412k words · 7 finished"`.
    static func authorDetail(works: Int, words: Int, finished: Int) -> String {
        "\(works) read · \(compactWords(words)) words · \(finished) finished"
    }

    /// The boards write `412k`, `87.5k` and `1.1M`; `compactWordsLabel` always keeps one decimal
    /// (`412.0k`). Same rounding, trailing `.0` dropped; formats only.
    static func compactWords(_ words: Int) -> String {
        ReadingInsights.compactWordsLabel(words)
            .replacingOccurrences(of: ".0k", with: "k")
            .replacingOccurrences(of: ".0M", with: "M")
    }

    /// `Insights-Library` `"since July"` (same year) or `"since Jul 2025"` (earlier year).
    static func sinceLabel(
        date: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let template = sameYear ? "LLLL" : "MMM y"
        return "since \(formatter(template: template, calendar: calendar, locale: locale).string(from: date))"
    }

    /// `Insights-Library` Found Early first metric line.
    static func foundEarlyUnder500Detail(count: Int, recordedFinishedCount: Int) -> String {
        "of finished works had under 500 kudos when you saved them (\(count) of \(recordedFinishedCount))"
    }

    /// `Insights-Library` Found Early second metric line.
    static func foundEarlyTripledDetail(grownCount: Int) -> String {
        "have at least tripled their kudos since (\(grownCount))"
    }

    private static func formatter(template: String, calendar: Calendar, locale: Locale) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = locale
        f.timeZone = calendar.timeZone
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }

    private static func indefiniteArticle(for phrase: String) -> String {
        if phrase.hasPrefix("F/") || phrase.hasPrefix("M/") { return "An" }
        guard let first = phrase.lowercased().first else { return "A" }
        return ["a", "e", "i", "o", "u"].contains(first) ? "An" : "A"
    }

    private static func joinBritishList(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default:
            let head = items.dropLast().joined(separator: ", ")
            return "\(head) and \(items[items.count - 1])"
        }
    }
}

/// Shared proportional stacked horizontal bar (14pt on Overview/Library, 12pt on Taste).
private struct InsightsProportionalBar: View {
    struct Segment: Identifiable {
        let id: Int
        let value: Double
        let color: Color
    }

    let segments: [Segment]
    var height: CGFloat = 14
    var cornerRadius: CGFloat = 4
    var spacing: CGFloat = 2

    var body: some View {
        let active = segments.filter { $0.value > 0 }
        let total = active.reduce(0.0) { $0 + $1.value }
        if active.isEmpty || total <= 0 {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.08))
                .frame(height: height)
        } else {
            GeometryReader { proxy in
                let totalGap = CGFloat(max(0, active.count - 1)) * spacing
                let usableWidth = max(0, proxy.size.width - totalGap)
                HStack(spacing: spacing) {
                    ForEach(active) { segment in
                        Rectangle()
                            .fill(segment.color)
                            .frame(width: max(2, usableWidth * CGFloat(segment.value / total)))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .frame(height: height)
        }
    }
}

// MARK: - Overview Cards

struct WordsReadHeroCard: View {
    let insights: ReadingInsights
    let periodName: String
    let previousPeriodName: String
    let hideReadingTime: Bool
    let totalDaysElapsed: Int
    let palette: SubjectPalette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var theme
    @ScaledMetric(relativeTo: .largeTitle) private var heroNumberSize: CGFloat = 38

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Words read")
                .font(.footnote)
                .foregroundStyle(.secondaryInk)

            let heroLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 10))
            heroLayout {
                Text(insights.totalWordsRead.formatted())
                    .font(.system(size: min(heroNumberSize, 52), weight: .bold))
                    .tracking(-0.5)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                if let prevWords = insights.previousPeriodWordsRead, prevWords > 0 {
                    let delta = insights.totalWordsRead - prevWords
                    let pct = Int((Double(abs(delta)) / Double(prevWords) * 100).rounded())
                    HStack(spacing: 3) {
                        Image(systemName: delta >= 0 ? "arrow.up" : "arrow.down")
                            .font(.system(size: 11, weight: .bold))
                            .accessibilityHidden(true)
                        Text("\(pct)% vs \(previousPeriodName)")
                            .font(.subheadline)
                    }
                    .foregroundStyle(.secondaryInk)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(delta >= 0 ? "Up" : "Down") \(pct)% vs \(previousPeriodName)")
                }
            }

            if let novelStr = ReadingInsights.novelsWorthLabel(words: insights.totalWordsRead) {
                Text(novelStr)
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
                .overlay(theme.appTheme.cardBorder)
                .padding(.top, 10)
                .padding(.bottom, 8)

            // Three columns until accessibility sizes, where bold title3 values would break mid-figure.
            let statsLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
            statsLayout {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Time reading")
                        .font(.caption)
                        .foregroundStyle(.secondaryInk)
                    Text(hideReadingTime ? "—" : InsightsBoardCopy.durationLabel(insights.totalSeconds))
                        .font(.title3.bold())
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Finished")
                        .font(.caption)
                        .foregroundStyle(.secondaryInk)
                    Text(insights.finishedWorksCount.formatted())
                        .font(.title3.bold())
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Reading days")
                        .font(.caption)
                        .foregroundStyle(.secondaryInk)
                    Text("\(insights.readingDaysCount) of \(totalDaysElapsed)")
                        .font(.title3.bold())
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, SubjectMetrics.gutter)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }
}

struct WordsPerDayCard: View {
    let days: [ReadingInsights.DailyWordsBucket]
    let totalDays: Int
    @Environment(ThemeManager.self) private var theme

    private var maxWords: Int {
        max(1, days.map(\.words).max() ?? 1)
    }

    private var avgWords: Double {
        guard !days.isEmpty else { return 0 }
        let sum = days.reduce(0) { $0 + $1.words }
        return Double(sum) / Double(days.count)
    }

    private var avgWordsK: String {
        String(format: "%.1fk", avgWords / 1000.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Words per Day")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("avg \(avgWordsK)")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondaryInk)
            }

            // Bar chart container
            VStack(spacing: 4) {
                GeometryReader { proxy in
                    let chartH: CGFloat = 96
                    let avgHeight = max(3, min(chartH, CGFloat(avgWords / Double(maxWords)) * chartH))
                    let maxIndex = days.firstIndex { $0.isMax && $0.words > 0 }

                    ZStack(alignment: .bottomLeading) {
                        // Dashed average reference line
                        Rectangle()
                            .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(Color.secondary.opacity(0.35))
                            .frame(height: 1)
                            .offset(y: -avgHeight)

                        HStack(alignment: .bottom, spacing: 3) {
                            ForEach(days) { day in
                                let height: CGFloat = day.words > 0
                                    ? max(4.0, (CGFloat(day.words) / CGFloat(maxWords)) * chartH)
                                    : 3.0
                                UnevenRoundedRectangle(
                                    topLeadingRadius: 3,
                                    bottomLeadingRadius: 1,
                                    bottomTrailingRadius: 1,
                                    topTrailingRadius: 3
                                )
                                .fill(day.words > 0 ? theme.accentInk : Color.primary.opacity(0.08))
                                .frame(height: height)
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(height: chartH, alignment: .bottom)

                        if let maxIndex {
                            let step = (proxy.size.width + 3) / CGFloat(max(1, days.count))
                            let rawX = (CGFloat(maxIndex) + 0.5) * step - 1.5
                            let clampedX = min(max(24, rawX), max(24, proxy.size.width - 24))
                            Text(ReadingInsights.compactWordsLabel(days[maxIndex].words))
                                .font(.caption2.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.secondaryInk)
                                .fixedSize()
                                .position(x: clampedX, y: 7)
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
                }
                .frame(height: 112)

                // Date ticks below chart
                let ticks = InsightsBoardCopy.wordsPerDayTicks(days: days)
                if !ticks.isEmpty {
                    HStack {
                        ForEach(Array(ticks.enumerated()), id: \.offset) { index, label in
                            if index > 0 { Spacer(minLength: 0) }
                            Text(label)
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(.secondaryInk)
                        }
                    }
                    .accessibilityHidden(true)
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, SubjectMetrics.gutter)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(chartAccessibilityLabel)
    }

    private var chartAccessibilityLabel: String {
        if let peak = days.first(where: { $0.isMax && $0.words > 0 }) {
            let peakDate = InsightsBoardCopy.biggestDayDetail(date: peak.date)
            return "Words per Day. Average \(avgWordsK) words per day. Biggest day \(peakDate), \(peak.words.formatted()) words."
        }
        return "Words per Day. Average \(avgWordsK) words per day."
    }
}

struct WhereTheWordsWentCard: View {
    let fandoms: [ReadingInsights.FandomWordsShare]
    let discreetMode: Bool
    var discreetMasker: InsightsDiscreetMasker = .empty
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Where the Words Went")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(InsightsBoardCopy.countLabel(fandoms.count, singular: "fandom", plural: "fandoms"))
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
            }

            // Proportional stacked bar
            if !fandoms.isEmpty {
                InsightsProportionalBar(
                    segments: fandoms.enumerated().map { index, share in
                        .init(id: index, value: Double(share.words), color: fandomColor(for: share))
                    },
                    height: 14
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Share of words by fandom")
            }

            // Rows
            VStack(spacing: 0) {
                ForEach(Array(fandoms.enumerated()), id: \.element.id) { index, f in
                    if index > 0 {
                        Divider()
                            .overlay(theme.appTheme.cardBorder)
                    }

                    let displayName = discreetMode && !f.isRemainder ? discreetMasker.fandom(f.name) : f.name
                    let detailText = "\(formatK(f.words)) · \(InsightsBoardCopy.countLabel(f.worksCount, singular: "work", plural: "works"))"
                    let shareText = "\(Int((f.share * 100).rounded()))%"

                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(fandomColor(for: f))
                                    .frame(width: 10, height: 10)
                                    .accessibilityHidden(true)
                                Text(displayName)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                            }
                            HStack(spacing: 8) {
                                Text(detailText)
                                    .font(.footnote)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondaryInk)
                                Text(shareText)
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                        .accessibilityElement(children: .combine)
                    } else {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(fandomColor(for: f))
                                .frame(width: 10, height: 10)
                                .accessibilityHidden(true)

                            Text(displayName)
                                .font(.subheadline)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(detailText)
                                .font(.footnote)
                                .monospacedDigit()
                                .foregroundStyle(.secondaryInk)

                            Text(shareText)
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .lineLimit(1)
                                .fixedSize()
                                .frame(minWidth: 34, alignment: .trailing)
                        }
                        .frame(minHeight: 34)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, SubjectMetrics.gutter)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }

    private func fandomColor(for share: ReadingInsights.FandomWordsShare) -> Color {
        if share.isRemainder { return Color.secondary.opacity(0.4) }
        let hue = CoverArt.workHue(fandoms: [share.name], title: "")
        return theme.appTheme.subjectPalette(hue: hue).accent
    }

    private func formatK(_ words: Int) -> String {
        ReadingInsights.compactWordsLabel(words)
    }
}

struct ReadingAndListeningCard: View {
    let readingSeconds: Double
    let silentReadingSeconds: Double
    let listeningSeconds: Double
    var listeningPlaybackRate: Double? = nil
    var listeningWorksCount: Int = 0
    let hideReadingTime: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var theme

    private var listeningDetail: String? {
        var parts: [String] = []
        if let rate = listeningPlaybackRate, rate > 0 {
            parts.append(String(format: "%.1f×", rate))
        }
        if listeningWorksCount > 0 {
            parts.append(InsightsBoardCopy.countLabel(listeningWorksCount, singular: "work", plural: "works"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Reading and Listening")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(hideReadingTime ? "—" : InsightsBoardCopy.durationLabel(readingSeconds))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondaryInk)
            }

            if readingSeconds > 0 {
                InsightsProportionalBar(
                    segments: [
                        .init(id: 0, value: silentReadingSeconds, color: theme.accentInk),
                        .init(id: 1, value: listeningSeconds, color: theme.accentInk.opacity(0.45))
                    ],
                    height: 14
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    InsightsBoardCopy.readingAndListeningBarLabel(
                        silentSeconds: silentReadingSeconds,
                        listeningSeconds: listeningSeconds,
                        hideReadingTime: hideReadingTime
                    )
                )
            }

            VStack(spacing: 0) {
                modeRow(
                    title: "Reading",
                    detail: nil,
                    seconds: silentReadingSeconds,
                    swatchColor: theme.accentInk
                )
                Divider()
                    .overlay(theme.appTheme.cardBorder)
                modeRow(
                    title: "Read Aloud",
                    detail: listeningDetail,
                    seconds: listeningSeconds,
                    swatchColor: theme.accentInk.opacity(0.45)
                )
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, SubjectMetrics.gutter)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func modeRow(title: String, detail: String?, seconds: Double, swatchColor: Color) -> some View {
        let valueText = hideReadingTime ? "—" : InsightsBoardCopy.durationLabel(seconds)
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(swatchColor)
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                }
                Text(valueText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
        } else {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(swatchColor)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                Text(valueText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(minHeight: 30)
            .accessibilityElement(children: .combine)
        }
    }
}

struct InsightsUnavailableCard: View {
    let title: String
    let explanation: String
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(explanation).font(.footnote).foregroundStyle(.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
            .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5))
    }
}

struct LibraryArrivalCard: View {
    let rows: [ReadingLibraryInsights.ArrivalRow]
    let since: Date?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var theme

    private var visibleRows: [ReadingLibraryInsights.ArrivalRow] {
        rows.filter { $0.finished > 0 }
    }

    private var totalFinished: Int {
        visibleRows.reduce(0) { (partial: Int, row: ReadingLibraryInsights.ArrivalRow) -> Int in
            partial + row.finished
        }
    }

    private var maxSharePct: Int {
        max(1, visibleRows.map { $0.finishedSharePercent(totalFinished: totalFinished) }.max() ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("How Finished Works Arrived")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if let since {
                    Text(InsightsBoardCopy.sinceLabel(date: since))
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                }
            }

            VStack(spacing: 8) {
                ForEach(visibleRows) { row in
                    let sharePct = row.finishedSharePercent(totalFinished: totalFinished)
                    let ratio = min(1.0, max(0.04, Double(sharePct) / Double(maxSharePct)))
                    VStack(alignment: .leading, spacing: 2) {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(row.label)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text("\(sharePct)%")
                                        .font(.subheadline.weight(.semibold))
                                        .monospacedDigit()
                                }
                                arrivalBar(ratio: ratio)
                            }
                        } else {
                            HStack(spacing: 10) {
                                Text(row.label)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .frame(width: 124, alignment: .leading)

                                arrivalBar(ratio: ratio)

                                Text("\(sharePct)%")
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .fixedSize()
                                    .frame(minWidth: 38, alignment: .trailing)
                            }
                        }
                        Text("\(row.finishRatePercent)% finish rate · \(row.finished) finished of \(row.saved) saved")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondaryInk)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, SubjectMetrics.gutter)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }

    private func arrivalBar(ratio: Double) -> some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Color.primary.opacity(0.08))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary)
                        .frame(width: proxy.size.width * ratio)
                }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

struct LibraryFoundEarlyCard: View {
    let recordedFinishedCount: Int
    let count: Int
    let foundEarlyShare: Double?
    let grownCount: Int
    let grownShare: Double?
    let since: Date?
    let example: ReadingLibraryInsights.FoundEarlyExample?
    let discreetMode: Bool
    var discreetMasker: InsightsDiscreetMasker = .empty
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Found Early")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if let since {
                    Text(InsightsBoardCopy.sinceLabel(date: since))
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                }
            }

            if let foundEarlyShare {
                let pct = Int((foundEarlyShare * 100).rounded())
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(pct)%")
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                    Text(InsightsBoardCopy.foundEarlyUnder500Detail(count: count, recordedFinishedCount: recordedFinishedCount))
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            } else {
                Text("\(InsightsBoardCopy.countLabel(count, singular: "finished work", plural: "finished works")) had under 500 kudos when you saved them")
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
            }

            if let grownShare {
                let pct = Int((grownShare * 100).rounded())
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(pct)%")
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                    Text(InsightsBoardCopy.foundEarlyTripledDetail(grownCount: grownCount))
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }

            if let example {
                let title = discreetMode
                    ? discreetMasker.work(id: example.workID, title: example.title)
                    : example.title
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                    : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
                layout {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                        Text("\(example.kudosAtSave.formatted()) kudos when saved")
                            .font(.caption)
                            .foregroundStyle(.secondaryInk)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if !dynamicTypeSize.isAccessibilitySize {
                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondaryInk)
                            .accessibilityHidden(true)
                    }

                    VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 1) {
                        Text(example.kudosNow.formatted())
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                        Text("now")
                            .font(.caption)
                            .foregroundStyle(.secondaryInk)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(theme.appTheme.cardBackdrop)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .padding(.horizontal, SubjectMetrics.gutter)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }
}

struct LibrarySeriesCard: View {
    let started: Int
    let readToLast: Int
    let longestFinished: ReadingLibraryInsights.LongestFinishedSeries?
    let nextWaiting: Int
    let discreetMode: Bool
    var discreetMasker: InsightsDiscreetMasker = .empty
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Series")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                let countsLayout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
                countsLayout {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(started)")
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                        Text("started")
                            .font(.caption)
                            .foregroundStyle(.secondaryInk)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(readToLast)")
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                        Text("read to the last part")
                            .font(.caption)
                            .foregroundStyle(.secondaryInk)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }

                if let longest = longestFinished {
                    let title = discreetMode ? discreetMasker.series(longest.title) : longest.title
                    let partLabel = InsightsBoardCopy.countLabel(longest.partCount, singular: "part", plural: "parts")
                    let wordsPart = longest.wordCount > 0
                        ? ", \(ReadingInsights.compactWordsLabel(longest.wordCount))"
                        : ""
                    let styledTitle: Text = Text(title).fontWeight(.semibold).foregroundStyle(Color.primary)
                    Text("Longest finished: \(styledTitle) · \(partLabel)\(wordsPart)")
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 14)
            .padding(.horizontal, SubjectMetrics.gutter)
            .padding(.bottom, nextWaiting > 0 ? 10 : 14)

            if nextWaiting > 0 {
                Divider()
                    .overlay(theme.appTheme.cardBorder)
                HStack(spacing: 10) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.accentInk)
                        .accessibilityHidden(true)
                    Text("Next Part Waiting")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(nextWaiting) series")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondaryInk)
                }
                .padding(.horizontal, SubjectMetrics.gutter)
                .padding(.vertical, 12)
                .frame(minHeight: 48)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }
}

struct LibraryAuthorsCard: View {
    let authors: [ReadingLibraryInsights.AuthorRow]
    let discreetMode: Bool
    var discreetMasker: InsightsDiscreetMasker = .empty
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Authors")
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 4)
                .padding(.top, 6)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                let shown = Array(authors.prefix(5))
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, author in
                    if index > 0 {
                        Divider()
                            .overlay(theme.appTheme.cardBorder)
                    }

                    let displayName = discreetMode ? discreetMasker.author(author.name) : author.name
                    let initial = String(displayName.prefix(1)).uppercased()
                    let avatarHue = CoverArt.workHue(fandoms: [author.name], title: "")
                    let avatarPalette = theme.appTheme.subjectPalette(hue: avatarHue)

                    HStack(spacing: 12) {
                        Text(initial.isEmpty ? "?" : initial)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(discreetMode ? AnyShapeStyle(.secondaryInk) : AnyShapeStyle(avatarPalette.accent))
                            .frame(width: 34, height: 34)
                            .background(discreetMode ? Color.primary.opacity(0.08) : avatarPalette.chipFill)
                            .clipShape(Circle())
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(displayName)
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                            Text(InsightsBoardCopy.authorDetail(
                                works: author.works,
                                words: author.words,
                                finished: author.finished
                            ))
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, SubjectMetrics.gutter)
                    .padding(.vertical, 10)
                    .frame(minHeight: 58)
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.appTheme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
            )
        }
    }
}

struct RecordsGridCard: View {
    let streakDays: Int
    let biggestDayWords: Int
    let medianSessionSeconds: Double
    let wordsPerHour: Double
    let charactersPerHour: Double
    let hideReadingTime: Bool
    var streakDateRange: String? = nil
    var biggestDayDate: Date? = nil
    var sittingsCount: Int = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var theme

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            recordTile(
                title: "Longest streak",
                value: InsightsBoardCopy.countLabel(streakDays, singular: "day", plural: "days"),
                detail: streakDateRange ?? (streakDays > 0 ? "consecutive days" : "no sessions yet")
            )

            recordTile(
                title: "Biggest day",
                value: biggestDayWords > 0 ? ReadingInsights.compactWordsLabel(biggestDayWords) : "—",
                detail: biggestDayWords > 0 ? InsightsBoardCopy.biggestDayDetail(date: biggestDayDate) : "no data"
            )

            recordTile(
                title: "Typical sitting",
                value: (hideReadingTime || medianSessionSeconds <= 0)
                    ? "—"
                    : InsightsBoardCopy.durationLabel(medianSessionSeconds),
                detail: InsightsBoardCopy.typicalSittingDetail(sittingsCount: sittingsCount)
            )

            recordTile(
                title: "Pace",
                value: wordsPerHour > 0 && wordsPerHour.isFinite
                    ? ReadingInsights.compactWordsLabel(Int(min(wordsPerHour, Double(Int.max / 2)).rounded()))
                    : "—",
                detail: InsightsBoardCopy.paceDetail(isCharacters: false)
            )

            if charactersPerHour > 0 && charactersPerHour.isFinite {
                recordTile(
                    title: "Character pace",
                    value: ReadingInsights.compactWordsLabel(Int(min(charactersPerHour, Double(Int.max / 2)).rounded())),
                    detail: InsightsBoardCopy.paceDetail(isCharacters: true)
                )
            }
        }
    }

    private func recordTile(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondaryInk)
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondaryInk)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
    }
}

struct LengthOfWhatYouReadCard: View {
    let mix: ReadingInsights.LengthMixCounts
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var theme

    private var ramp: [Color] {
        [
            theme.accentInk.opacity(0.32),
            theme.accentInk.opacity(0.55),
            theme.accentInk.opacity(0.78),
            theme.accentInk
        ]
    }

    var body: some View {
        let colors = ramp
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Length of What You Read")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(InsightsBoardCopy.countLabel(mix.totalWorks, singular: "work", plural: "works"))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondaryInk)
            }

            // Proportional stacked bar
            InsightsProportionalBar(
                segments: [
                    .init(id: 0, value: Double(mix.under5k), color: colors[0]),
                    .init(id: 1, value: Double(mix.from5kTo50k), color: colors[1]),
                    .init(id: 2, value: Double(mix.from50kTo150k), color: colors[2]),
                    .init(id: 3, value: Double(mix.over150k), color: colors[3])
                ],
                height: 14
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(InsightsBoardCopy.lengthMixBarLabel(mix))

            // Breakdown
            if dynamicTypeSize.isAccessibilitySize {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    tierItems(colors: colors)
                }
            } else {
                HStack(alignment: .top, spacing: 6) {
                    tierItems(colors: colors)
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, SubjectMetrics.gutter)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func tierItems(colors: [Color]) -> some View {
        tierItem(label: "Under 5k", count: mix.under5k, color: colors[0])
        tierItem(label: "5k–50k", count: mix.from5kTo50k, color: colors[1])
        tierItem(label: "50k–150k", count: mix.from50kTo150k, color: colors[2])
        tierItem(label: "150k+", count: mix.over150k, color: colors[3])
    }

    private func tierItem(label: String, count: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondaryInk)
                    .lineLimit(1)
            }
            Text("\(count)")
                .font(.headline)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The Hidden section's top row (owner, 2026-11-19): hidden mature works' reading is
/// summarized on its own, below the main figures. Locked, this row is all there is: it
/// names no work, fandom or count, and offers the shared reveal control.
struct InsightsHiddenHeader: View {
    let isRevealed: Bool
    /// The main figures above include hidden works too (Include Hidden).
    let includesHidden: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var theme

    private var caption: String {
        if !isRevealed { return "Mature works are kept out of Insights." }
        return includesHidden
            ? "Hidden mature works only. The figures above include them."
            : "Hidden mature works only. The figures above leave them out."
    }

    var body: some View {
        // Side by side until accessibility sizes, where the reveal button needs its own line.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
        layout {
            HStack(spacing: 10) {
                Image(systemName: isRevealed ? "eye" : "eye.slash")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondaryInk)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Hidden")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(caption)
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .frame(maxWidth: .infinity, alignment: .leading)

            MatureRevealToggle()
                .font(.subheadline.weight(.medium))
        }
        .padding(14)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }
}

struct FinishedInPeriodSection: View {
    let works: [SavedWork]
    let discreetMode: Bool
    var discreetMasker: InsightsDiscreetMasker = .empty
    var rereadFinishCounts: [UUID: Int] = [:]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Finished")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                    Text("\(works.count)")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondaryInk)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

                Spacer()

                Text("See All")
                    .font(.subheadline)
                    .foregroundStyle(theme.accentInk)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                let shownWorks = Array(works.prefix(3))
                ForEach(Array(shownWorks.enumerated()), id: \.element.id) { index, work in
                    if index > 0 {
                        Divider()
                            .overlay(theme.appTheme.cardBorder)
                    }

                    NavigationLink(value: work) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 1) {
                                if let fandom = work.workFandoms.first, !fandom.isEmpty {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(fandomColor(for: fandom))
                                            .frame(width: 8, height: 8)
                                            .accessibilityHidden(true)
                                        let displayName = discreetMode ? discreetMasker.fandom(fandom) : fandom
                                        Text(displayName)
                                            .font(.caption)
                                            .foregroundStyle(.secondaryInk)
                                    }
                                }

                                Text(discreetMode ? discreetMasker.work(id: work.id, title: work.title) : work.title)
                                    .font(.callout)
                                    .foregroundStyle(.primary)
                                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)

                                let meta = InsightsBoardCopy.finishedWorkMeta(
                                    wordCount: work.wordCount,
                                    finishCount: rereadFinishCounts[work.id] ?? 0
                                )
                                if !meta.isEmpty {
                                    Text(meta)
                                        .font(.footnote)
                                        .foregroundStyle(.secondaryInk)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, SubjectMetrics.gutter)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                if works.count > 3 {
                    Divider()
                        .overlay(theme.appTheme.cardBorder)
                        .padding(.leading, SubjectMetrics.gutter)
                    HStack(spacing: 6) {
                        Text("\(works.count - 3) more")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.accentInk)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.accentInk)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, SubjectMetrics.gutter)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(theme.appTheme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
            )
        }
        .padding(.top, 6)
    }

    private func fandomColor(for fandom: String) -> Color {
        let hue = CoverArt.workHue(fandoms: [fandom], title: "")
        return theme.appTheme.subjectPalette(hue: hue).accent
    }
}

// MARK: - Taste Cards

struct YourUsualFicCard: View {
    let taste: ReadingTasteInsights
    let discreetMode: Bool
    var discreetMasker: InsightsDiscreetMasker = .empty
    @Environment(ThemeManager.self) private var theme

    private var displayedChips: [String] {
        guard discreetMode else { return taste.usualFicTags }
        if !taste.usualChips.isEmpty {
            return taste.usualChips.map { chip in
                if chip.text == "varied" { return "varied" }
                switch chip.kind {
                case .metadata: return chip.text
                case .fandom: return discreetMasker.fandom(chip.text)
                case .tag: return discreetMasker.tag(chip.text)
                case .ship: return discreetMasker.ship(chip.text)
                }
            }
        }
        return taste.usualFicTags.indices.map { index in
            "Tag \(InsightsDiscreetMasker.letterCode(for: index))"
        }
    }

    var body: some View {
        let summary = InsightsBoardCopy.usualFicText(
            taste: taste,
            discreetMode: discreetMode,
            discreetMasker: discreetMasker
        )

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your Usual Fic")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("from \(InsightsBoardCopy.countLabel(taste.totalWorksCount, singular: "work", plural: "works"))")
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
            }

            summaryView(summary)
                .font(.system(.title3, design: .serif))
                .lineSpacing(4)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            let chips = displayedChips
            if !chips.isEmpty {
                FlowLayout(spacing: 6, rowSpacing: 6) {
                    ForEach(chips.indices, id: \.self) { index in
                        Text(chips[index])
                            .font(.caption)
                            .foregroundStyle(.secondaryInk)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(theme.appTheme.cardSurface.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
                            )
                    }
                }
            }
        }
        .padding(SubjectMetrics.gutter)
        .background(
            LinearGradient(
                stops: [
                    .init(color: theme.appTheme.cardSurface, location: 0.4),
                    .init(color: theme.accentInk.opacity(theme.appTheme.isDarkFamily ? 0.14 : 0.08), location: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }

    private func summaryView(_ text: InsightsBoardCopy.UsualFicText) -> Text {
        if let boldFandom = text.boldFandom {
            let emphasized: Text = Text(boldFandom).fontWeight(.semibold)
            return Text("\(text.prefix)\(emphasized)\(text.suffix)")
        }
        return Text(text.prefix)
    }
}

struct TasteFandomsCard: View {
    let fandoms: [ReadingInsights.FandomWordsShare]
    let rankByWorks: Bool
    let onToggleRank: () -> Void
    let discreetMode: Bool
    var discreetMasker: InsightsDiscreetMasker = .empty
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var theme

    private var sortedFandoms: [ReadingInsights.FandomWordsShare] {
        // Keep `"Everything else"` last regardless of rank mode.
        fandoms.sorted { (lhs: ReadingInsights.FandomWordsShare, rhs: ReadingInsights.FandomWordsShare) -> Bool in
            if lhs.isRemainder != rhs.isRemainder { return !lhs.isRemainder }
            if rankByWorks {
                if lhs.worksCount != rhs.worksCount { return lhs.worksCount > rhs.worksCount }
                if lhs.words != rhs.words { return lhs.words > rhs.words }
            } else {
                if lhs.words != rhs.words { return lhs.words > rhs.words }
                if lhs.worksCount != rhs.worksCount { return lhs.worksCount > rhs.worksCount }
            }
            return lhs.name < rhs.name
        }
    }

    private var peakMetric: Double {
        if rankByWorks {
            return Double(max(1, fandoms.map(\.worksCount).max() ?? 1))
        }
        return Double(max(1, fandoms.map(\.words).max() ?? 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Text("Fandoms")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    onToggleRank()
                } label: {
                    HStack(spacing: 4) {
                        Text(rankByWorks ? "By Works" : "By Words")
                            .font(.footnote.weight(.medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .accessibilityHidden(true)
                    }
                    .padding(.leading, 11)
                    .padding(.trailing, 9)
                    .frame(minHeight: 28)
                    .background(Color.primary.opacity(0.08))
                    .foregroundStyle(.primary)
                    .clipShape(SubjectMetrics.controlShape(dynamicTypeSize))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Rank by: \(rankByWorks ? "Works" : "Words")")
                .accessibilityHint("Switch between ranking by words and by works")
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)

            VStack(spacing: 0) {
                ForEach(Array(sortedFandoms.enumerated()), id: \.element.id) { index, f in
                    if index > 0 {
                        Divider()
                            .overlay(theme.appTheme.cardBorder)
                    }

                    let name = discreetMode && !f.isRemainder ? discreetMasker.fandom(f.name) : f.name
                    let worksText = InsightsBoardCopy.countLabel(f.worksCount, singular: "work", plural: "works")

                    VStack(alignment: .leading, spacing: 6) {
                        let rowLayout = dynamicTypeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
                        rowLayout {
                            Text(name)
                                .font(.subheadline)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                if rankByWorks {
                                    if f.words > 0 {
                                        Text(formatK(f.words))
                                            .font(.footnote)
                                            .monospacedDigit()
                                            .foregroundStyle(.secondaryInk)
                                    }
                                    Text(worksText)
                                        .font(.subheadline.weight(.semibold))
                                        .monospacedDigit()
                                        .lineLimit(1)
                                        .fixedSize()
                                        .frame(minWidth: 48, alignment: .trailing)
                                } else {
                                    Text(worksText)
                                        .font(.footnote)
                                        .monospacedDigit()
                                        .foregroundStyle(.secondaryInk)

                                    Text(formatK(f.words))
                                        .font(.subheadline.weight(.semibold))
                                        .monospacedDigit()
                                        .lineLimit(1)
                                        .fixedSize()
                                        .frame(minWidth: 48, alignment: .trailing)
                                }
                            }
                        }

                        // Progress bar
                        GeometryReader { proxy in
                            let currentVal = rankByWorks ? Double(f.worksCount) : Double(f.words)
                            let ratio = min(1.0, max(0.04, currentVal / peakMetric))
                            Capsule()
                                .fill(Color.primary.opacity(0.08))
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(fandomColor(for: f))
                                        .frame(width: proxy.size.width * ratio)
                                }
                        }
                        .frame(height: 6)
                        .accessibilityHidden(true)
                    }
                    .padding(.vertical, 9)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, SubjectMetrics.gutter)
            .background(theme.appTheme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
            )
        }
    }

    private func fandomColor(for share: ReadingInsights.FandomWordsShare) -> Color {
        if share.isRemainder { return Color.secondary.opacity(0.4) }
        let hue = CoverArt.workHue(fandoms: [share.name], title: "")
        return theme.appTheme.subjectPalette(hue: hue).accent
    }

    private func formatK(_ words: Int) -> String {
        ReadingInsights.compactWordsLabel(words)
    }
}

struct TasteRelationshipsCard: View {
    let relationships: [RelationshipShare]
    let shipConcentrations: [ShipConcentration]
    let rankByWorks: Bool
    let discreetMode: Bool
    var discreetMasker: InsightsDiscreetMasker = .empty
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Relationships")
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 4)
                .padding(.top, 6)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                let shown = Array(relationships.prefix(4))
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, rel in
                    if index > 0 {
                        Divider()
                            .overlay(theme.appTheme.cardBorder)
                    }

                    let name = discreetMode ? discreetMasker.ship(rel.name) : rel.name
                    let kind = rel.isRomantic ? "Romantic" : "Platonic"
                    let fandomSegment = rel.fandom.isEmpty
                        ? ""
                        : "\(discreetMode ? discreetMasker.fandom(rel.fandom) : rel.fandom) · "
                    let worksLabel = InsightsBoardCopy.countLabel(rel.worksCount, singular: "work", plural: "works")
                    let metaLine = rankByWorks && rel.words > 0
                        ? "\(kind) · \(fandomSegment)\(formatK(rel.words))"
                        : "\(kind) · \(fandomSegment)\(worksLabel)"
                    let trailingValue = rankByWorks ? worksLabel : formatK(rel.words)

                    HStack(spacing: 12) {
                        // Tile with / or &
                        Text(ReadingInsights.relationshipGlyph(for: rel.name))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.primary.opacity(0.8))
                            .frame(width: 28, height: 28)
                            .background(Color.primary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(name)
                                .font(.subheadline)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 5) {
                                if !rel.fandom.isEmpty {
                                    Circle()
                                        .fill(fandomColor(for: rel.fandom))
                                        .frame(width: 7, height: 7)
                                        .accessibilityHidden(true)
                                }
                                Text(metaLine)
                                    .font(.caption)
                                    .foregroundStyle(.secondaryInk)
                                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text(trailingValue)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize()
                            .frame(minWidth: 48, alignment: .trailing)
                    }
                    .padding(.horizontal, SubjectMetrics.gutter)
                    .padding(.vertical, 9)
                    .accessibilityElement(children: .combine)
                }

                if !shipConcentrations.isEmpty {
                    Divider()
                        .overlay(theme.appTheme.cardBorder)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ship Concentration")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary)

                        ForEach(shipConcentrations) { ship in
                            let displayName = discreetMode ? discreetMasker.fandom(ship.fandom) : ship.fandom
                            if dynamicTypeSize.isAccessibilitySize {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(displayName)
                                        .font(.footnote)
                                        .foregroundStyle(.primary)
                                    concentrationBar(ship)
                                    Text(ship.label)
                                        .font(.caption)
                                        .foregroundStyle(.secondaryInk)
                                }
                                .accessibilityElement(children: .combine)
                            } else {
                                HStack(spacing: 10) {
                                    Text(displayName)
                                        .font(.footnote)
                                        .lineLimit(1)
                                        .frame(width: 118, alignment: .leading)

                                    concentrationBar(ship)

                                    Text(ship.label)
                                        .font(.caption)
                                        .foregroundStyle(.secondaryInk)
                                        .lineLimit(1)
                                        .frame(width: 116, alignment: .trailing)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                    .padding(.top, 12)
                    .padding(.horizontal, SubjectMetrics.gutter)
                    .padding(.bottom, 14)
                }
            }
            .background(theme.appTheme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
            )
        }
    }

    private func concentrationBar(_ ship: ShipConcentration) -> some View {
        GeometryReader { proxy in
            let ratio = min(1.0, max(0.0, CGFloat(ship.percentage) / 100.0))
            Capsule()
                .fill(Color.primary.opacity(0.08))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(fandomColor(for: ship.fandom))
                        .frame(width: proxy.size.width * ratio)
                }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }

    private func fandomColor(for fandom: String) -> Color {
        let hue = CoverArt.workHue(fandoms: [fandom], title: "")
        return theme.appTheme.subjectPalette(hue: hue).accent
    }

    private func formatK(_ words: Int) -> String {
        ReadingInsights.compactWordsLabel(words)
    }
}

struct TasteCharactersCard: View {
    let characters: [ReadingTasteInsights.CharacterShare]
    let discreetMode: Bool
    var discreetMasker: InsightsDiscreetMasker = .empty
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Characters")
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 4)
                .padding(.top, 6)
                .accessibilityAddTraits(.isHeader)

            FlowLayout(spacing: 8, rowSpacing: 8) {
                ForEach(Array(characters.prefix(9).enumerated()), id: \.element.id) { _, char in
                    let displayName = discreetMode ? discreetMasker.character(char.name) : char.name
                    HStack(spacing: 6) {
                        Circle()
                            .fill(fandomColor(for: char.fandom))
                            .frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                        Text(displayName)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Text("\(char.count)")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondaryInk)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .frame(minHeight: 30)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(SubjectMetrics.controlShape(dynamicTypeSize))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(displayName), \(InsightsBoardCopy.countLabel(char.count, singular: "work", plural: "works"))")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .padding(.horizontal, SubjectMetrics.gutter)
            .background(theme.appTheme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
            )
        }
    }

    private func fandomColor(for fandom: String) -> Color {
        let hue = CoverArt.workHue(fandoms: [fandom], title: "")
        return theme.appTheme.subjectPalette(hue: hue).accent
    }
}

struct TasteTagsCard: View {
    let tags: [ReadingTasteInsights.TagShare]
    let oftenTogether: [TagPair]
    let rankByWorks: Bool
    let discreetMode: Bool
    var discreetMasker: InsightsDiscreetMasker = .empty
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var theme

    private var maxWords: Int {
        rankByWorks ? max(1, tags.map(\.count).max() ?? 1) : max(1, tags.map(\.words).max() ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 4)
                .padding(.top, 6)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                let shownTags = Array(tags.prefix(8))
                ForEach(Array(shownTags.enumerated()), id: \.element.id) { index, tag in
                    if index > 0 {
                        Divider()
                            .overlay(theme.appTheme.cardBorder)
                    }

                    let name = discreetMode ? discreetMasker.tag(tag.name) : tag.name
                    let valueText = rankByWorks
                        ? InsightsBoardCopy.countLabel(tag.count, singular: "work", plural: "works")
                        : ReadingInsights.compactWordsLabel(tag.words)
                    let value = rankByWorks ? tag.count : tag.words
                    let ratio = min(1.0, max(0.04, Double(value) / Double(maxWords)))

                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(name)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(valueText)
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                            }
                            tagBar(ratio: ratio)
                        }
                        .padding(.vertical, 8)
                        .accessibilityElement(children: .combine)
                    } else {
                        HStack(spacing: 10) {
                            Text(name)
                                .font(.subheadline)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(width: 146, alignment: .leading)

                            tagBar(ratio: ratio)

                            Text(valueText)
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .lineLimit(1)
                                .fixedSize()
                                .frame(minWidth: 46, alignment: .trailing)
                        }
                        .frame(minHeight: 36)
                        .accessibilityElement(children: .combine)
                    }
                }

                if !oftenTogether.isEmpty {
                    Divider()
                        .overlay(theme.appTheme.cardBorder)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Often Together")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary)

                        ForEach(oftenTogether) { pair in
                            let tagA = discreetMode ? discreetMasker.tag(pair.tagA) : pair.tagA
                            let tagB = discreetMode ? discreetMasker.tag(pair.tagB) : pair.tagB
                            let countText = InsightsBoardCopy.countLabel(pair.worksCount, singular: "work", plural: "works")

                            let pairLayout = dynamicTypeSize.isAccessibilitySize
                                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                : AnyLayout(HStackLayout(alignment: .center, spacing: 6))
                            pairLayout {
                                FlowLayout(spacing: 6, rowSpacing: 4) {
                                    Text(tagA)
                                        .font(.footnote)
                                        .foregroundStyle(.primary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(Color.primary.opacity(0.06))
                                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                    Text("+")
                                        .font(.footnote)
                                        .foregroundStyle(.secondaryInk)
                                        .accessibilityHidden(true)
                                    Text(tagB)
                                        .font(.footnote)
                                        .foregroundStyle(.primary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(Color.primary.opacity(0.06))
                                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Text(countText)
                                    .font(.footnote)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondaryInk)
                                    .fixedSize()
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(tagA) and \(tagB), \(countText)")
                        }
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, SubjectMetrics.gutter)
            .background(theme.appTheme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
            )
        }
    }

    private func tagBar(ratio: Double) -> some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Color.primary.opacity(0.08))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary)
                        .frame(width: proxy.size.width * ratio)
                }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

struct TasteRatingsCategoriesWarningsCard: View {
    let ratings: [ReadingTasteInsights.CountBreakdown]
    let statuses: [ReadingTasteInsights.CountBreakdown]
    let categories: [ReadingTasteInsights.CountBreakdown]
    let warnings: [ReadingTasteInsights.CountBreakdown]
    let rankByWorks: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var theme

    private func ratingColor(for label: String, index: Int) -> Color {
        switch label {
        case "General": return theme.accentInk.opacity(0.32)
        case "Teen": return theme.accentInk.opacity(0.55)
        case "Mature": return theme.accentInk.opacity(0.78)
        case "Explicit": return theme.accentInk
        case "Not Rated": return Color.secondary.opacity(0.45)
        default:
            let steps: [Double] = [0.32, 0.55, 0.78, 1.0]
            return theme.accentInk.opacity(steps[min(index, steps.count - 1)])
        }
    }

    private func statusColor(for label: String) -> Color {
        label == "Complete" ? Color.primary.opacity(0.75) : Color.secondary.opacity(0.42)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ratings, Categories, Warnings")
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 4)
                .padding(.top, 6)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 12) {
                if !ratings.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Rating")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary)

                        InsightsProportionalBar(
                            segments: ratings.enumerated().map { idx, item in
                                .init(
                                    id: idx,
                                    value: Double(item.count),
                                    color: ratingColor(for: item.label, index: idx)
                                )
                            },
                            height: 12
                        )
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(ratings.map { "\($0.label) \($0.count)" }.joined(separator: ", "))

                        let gridCols = dynamicTypeSize.isAccessibilitySize
                            ? [GridItem(.flexible(), spacing: 8)]
                            : Array(repeating: GridItem(.flexible(), spacing: 4), count: min(4, max(1, ratings.count)))
                        LazyVGrid(columns: gridCols, alignment: .leading, spacing: 4) {
                            ForEach(Array(ratings.enumerated()), id: \.element.id) { idx, item in
                                HStack(spacing: 5) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(ratingColor(for: item.label, index: idx))
                                        .frame(width: 8, height: 8)
                                        .accessibilityHidden(true)
                                    Text(item.label)
                                        .font(.footnote)
                                        .foregroundStyle(.secondaryInk)
                                        .lineLimit(1)
                                    Text("\(item.count)")
                                        .font(.footnote.weight(.semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(.primary)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }

                if !statuses.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Status")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary)

                        InsightsProportionalBar(
                            segments: statuses.enumerated().map { idx, item in
                                .init(id: idx, value: Double(item.count), color: statusColor(for: item.label))
                            },
                            height: 12
                        )
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(statuses.map { "\($0.label) \($0.count)" }.joined(separator: ", "))

                        FlowLayout(spacing: 16, rowSpacing: 6) {
                            ForEach(statuses) { item in
                                HStack(spacing: 5) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(statusColor(for: item.label))
                                        .frame(width: 8, height: 8)
                                        .accessibilityHidden(true)
                                    Text(item.label)
                                        .font(.footnote)
                                        .foregroundStyle(.secondaryInk)
                                    Text("\(item.count)")
                                        .font(.footnote.weight(.semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(.primary)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }

                if !categories.isEmpty || !warnings.isEmpty {
                    Divider()
                        .overlay(theme.appTheme.cardBorder)

                    let tableLayout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                        : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
                    tableLayout {
                        if !categories.isEmpty {
                            countTable(title: "Category", items: categories)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if !warnings.isEmpty {
                            countTable(title: "Warnings", items: warnings)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    Text("A work may have several categories or warnings, so those totals may exceed works read.")
                        .font(.caption)
                        .foregroundStyle(.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, SubjectMetrics.gutter)
            .background(theme.appTheme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
            )
        }
    }

    private func countTable(title: String, items: [ReadingTasteInsights.CountBreakdown]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
            ForEach(items) { item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.label)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    Text("\(item.count)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

struct TasteWhenPostedCard: View {
    let yearCounts: [ReadingTasteInsights.YearCount]
    let medianYear: Int?
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        let series = InsightsBoardCopy.yearHistogramSeries(from: yearCounts)
        let maxCount = max(1, series.bars.map(\.count).max() ?? 1)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("When They Were Posted")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("median \(medianYear.map(String.init) ?? "—")")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondaryInk)
            }

            // Year histogram
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(series.bars) { item in
                    let height: CGFloat = item.count > 0
                        ? max(4.0, (CGFloat(item.count) / CGFloat(maxCount)) * 52.0 + 4.0)
                        : 3.0
                    UnevenRoundedRectangle(
                        topLeadingRadius: 2,
                        bottomLeadingRadius: 1,
                        bottomTrailingRadius: 1,
                        topTrailingRadius: 2
                    )
                    .fill(item.count > 0 ? Color.secondary : Color.primary.opacity(0.08))
                    .frame(height: min(56, height))
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 56, alignment: .bottom)

            if !series.ticks.isEmpty {
                HStack {
                    ForEach(Array(series.ticks.enumerated()), id: \.offset) { index, year in
                        if index > 0 { Spacer(minLength: 0) }
                        Text(String(year))
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondaryInk)
                    }
                }
                .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, SubjectMetrics.gutter)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(histogramAccessibilityLabel(ticks: series.ticks))
    }

    private func histogramAccessibilityLabel(ticks: [Int]) -> String {
        let rangeText: String
        if let first = ticks.first, let last = ticks.last, first != last {
            rangeText = ", \(first) to \(last)"
        } else if let only = ticks.first {
            rangeText = ", \(only)"
        } else {
            rangeText = ""
        }
        let medianText = medianYear.map { ". Median \($0)." } ?? "."
        return "When They Were Posted: works read by the year they were posted on AO3\(rangeText)\(medianText)"
    }
}

struct TasteCrossoversLanguagesGrid: View {
    let crossoverCount: Int
    let totalWorks: Int
    let languages: [ReadingTasteInsights.CountBreakdown]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var theme

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Crossovers")
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(crossoverCount)")
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                    Text("of \(totalWorks)")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondaryInk)
                }
                Text(crossoverCount > 0 ? "works with 2+ fandoms" : "none")
                    .font(.caption)
                    .foregroundStyle(.secondaryInk)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.appTheme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
            )
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: 1) {
                Text("Languages")
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                Text("\(languages.count)")
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                let langStr = languages.prefix(2).map { "\($0.label) \($0.count)" }.joined(separator: " · ")
                Text(langStr.isEmpty ? "English" : langStr)
                    .font(.caption)
                    .foregroundStyle(.secondaryInk)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.appTheme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
            )
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Habits Cards

struct HabitsTimeOfDayCard: View {
    let hourly: [ReadingInsights.HourlyBucket]
    let lateNightDuration: Double
    let lateNightSharePercent: Int
    var hideReadingTime: Bool = false
    var isYear: Bool = false
    @Environment(ThemeManager.self) private var theme

    private var maxSeconds: Double {
        max(1, hourly.map(\.seconds).max() ?? 1)
    }

    var body: some View {
        let peakLabel = InsightsBoardCopy.peakHoursLabel(hourly: hourly)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Time of Day")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if let peakLabel {
                    Text(peakLabel)
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondaryInk)
                }
            }

            // 24-hour bar chart with 1:00–5:00 late-night highlight band
            VStack(spacing: 4) {
                GeometryReader { proxy in
                    let spacing: CGFloat = 3
                    let barCount = max(1, hourly.count)
                    let barW = max(2, (proxy.size.width - CGFloat(barCount - 1) * spacing) / CGFloat(barCount))
                    let step = barW + spacing
                    let lateLeft = max(0, step - 2)
                    let lateWidth = max(16, 4 * step + 1)

                    ZStack(alignment: .bottomLeading) {
                        // 1:00–5:00 late-night band
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(theme.accentInk.opacity(theme.appTheme.isDarkFamily ? 0.18 : 0.12))
                            .frame(width: lateWidth, height: proxy.size.height)
                            .offset(x: lateLeft)
                            .accessibilityHidden(true)

                        if lateNightSharePercent > 0 {
                            Text("\(lateNightSharePercent)%")
                                .font(.caption2.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.secondaryInk)
                                .frame(width: lateWidth)
                                .position(x: lateLeft + lateWidth / 2, y: 12)
                                .accessibilityHidden(true)
                        }

                        HStack(alignment: .bottom, spacing: spacing) {
                            ForEach(hourly) { item in
                                let height: CGFloat = item.seconds > 0
                                    ? max(4.0, CGFloat(item.seconds / maxSeconds) * 86.0)
                                    : 3.0
                                UnevenRoundedRectangle(
                                    topLeadingRadius: 3,
                                    bottomLeadingRadius: 1,
                                    bottomTrailingRadius: 1,
                                    topTrailingRadius: 3
                                )
                                .fill(item.seconds > 0 ? theme.accentInk : Color.primary.opacity(0.08))
                                .frame(height: height)
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(height: proxy.size.height, alignment: .bottom)
                    }
                }
                .frame(height: 110)

                HStack {
                    Text("0:00")
                    Spacer()
                    Text("6:00")
                    Spacer()
                    Text("12:00")
                    Spacer()
                    Text("18:00")
                    Spacer()
                    Text("24:00")
                }
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondaryInk)
                .accessibilityHidden(true)
            }

            Text(InsightsBoardCopy.lateNightSummary(
                durationSeconds: lateNightDuration,
                hideReadingTime: hideReadingTime,
                isYear: isYear
            ))
            .font(.footnote)
            .foregroundStyle(.secondaryInk)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, SubjectMetrics.gutter)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(timeOfDayAccessibilityLabel(peak: peakLabel))
    }

    private func timeOfDayAccessibilityLabel(peak: String?) -> String {
        let peakClause = peak.map { "Most reading \($0.replacingOccurrences(of: "most at ", with: "between ")). " } ?? ""
        let lateClause = "\(lateNightSharePercent)% between 1:00 and 5:00."
        return "Time of Day. \(peakClause)\(lateClause)"
    }
}

struct HabitsCalendarCard: View {
    let days: [ReadingInsights.DailyWordsBucket]
    let longestStreak: Int
    let thresholds: [Int]
    var totalDaysElapsed: Int? = nil
    var isMonthPeriod: Bool = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var theme

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let weekdayInitials = ["M", "T", "W", "T", "F", "S", "S"]

    /// True only for a real single-month period with a contiguous 1…N day sequence
    /// inside one calendar month; never true for Year-mode active-day lists.
    static func isContiguousMonthGrid(
        days: [ReadingInsights.DailyWordsBucket],
        isMonthPeriod: Bool,
        calendar: Calendar = .current
    ) -> Bool {
        guard isMonthPeriod, !days.isEmpty, days.count <= 31, let first = days.first else {
            return false
        }
        let firstParts = calendar.dateComponents([.year, .month], from: first.date)
        for (offset, bucket) in days.enumerated() {
            guard bucket.dayNumber == offset + 1 else { return false }
            let parts = calendar.dateComponents([.year, .month], from: bucket.date)
            guard parts.year == firstParts.year && parts.month == firstParts.month else {
                return false
            }
        }
        return true
    }

    private var isMonthGrid: Bool {
        Self.isContiguousMonthGrid(days: days, isMonthPeriod: isMonthPeriod)
    }

    /// Day cells only show a number, so VoiceOver gets the grid as one chart (as the board's role="img").
    private var calendarAccessibilityLabel: String {
        guard isMonthGrid, let first = days.first?.date else {
            return "Reading days, each shaded by words read"
        }
        return "Calendar of \(first.formatted(.dateTime.month(.wide))) with each day shaded by words read"
    }

    private var leadingBlankCount: Int {
        guard isMonthGrid, let firstDate = days.first?.date else { return 0 }
        // Calendar.weekday: 1 = Sun, 2 = Mon, ..., 7 = Sat -> Mon-first offset = (weekday + 5) % 7.
        let weekday = Calendar.current.component(.weekday, from: firstDate)
        return (weekday + 5) % 7
    }

    private var remainingMonthDays: [Int] {
        guard isMonthGrid, let firstDate = days.first?.date,
              let total = Calendar.current.range(of: .day, in: .month, for: firstDate)?.count,
              days.count < total
        else { return [] }
        return Array((days.count + 1)...total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Reading Days")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                let readingDays = days.filter { $0.hasReading || $0.words > 0 }.count
                let elapsed = totalDaysElapsed ?? days.count
                Text("\(readingDays) of \(elapsed)")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondaryInk)
            }

            if isMonthGrid {
                HStack(spacing: 6) {
                    ForEach(Array(weekdayInitials.enumerated()), id: \.offset) { _, day in
                        Text(day)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondaryInk)
                            .frame(maxWidth: .infinity)
                    }
                }
                .accessibilityHidden(true)
            }

            // Days grid
            LazyVGrid(columns: columns, spacing: 6) {
                if leadingBlankCount > 0 {
                    ForEach(0..<leadingBlankCount, id: \.self) { _ in
                        Color.clear
                            .frame(height: 34)
                            .accessibilityHidden(true)
                    }
                }
                ForEach(days) { day in
                    let tier = heatTier(for: day)
                    ZStack(alignment: .topTrailing) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(tierColor(tier))
                            .frame(height: 34)

                        Text("\(day.dayNumber)")
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(
                                tier >= 2
                                    ? AnyShapeStyle(ThemeManager.label(on: theme.accentInk))
                                    : AnyShapeStyle(.secondaryInk)
                            )
                            .padding(.top, 3)
                            .padding(.trailing, 5)
                    }
                }
                ForEach(remainingMonthDays, id: \.self) { dayNumber in
                    ZStack(alignment: .topTrailing) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .foregroundStyle(Color.secondary.opacity(0.35))
                            .frame(height: 34)

                        Text("\(dayNumber)")
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(Color.secondary.opacity(0.45))
                            .padding(.top, 3)
                            .padding(.trailing, 5)
                    }
                    .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(calendarAccessibilityLabel)

            // Legend & Streak
            let footerLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
            footerLayout {
                Text("Longest streak \(InsightsBoardCopy.countLabel(longestStreak, singular: "day", plural: "days"))")
                    .font(.caption)
                    .foregroundStyle(.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 3) {
                    Text("Less")
                        .font(.caption)
                        .foregroundStyle(.secondaryInk)
                    ForEach(0..<5, id: \.self) { tier in
                        swatch(tierColor(tier))
                    }
                    Text("More")
                        .font(.caption)
                        .foregroundStyle(.secondaryInk)
                }
                .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, SubjectMetrics.gutter)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }

    private func swatch(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(color)
            .frame(width: 10, height: 10)
    }

    private func heatTier(for day: ReadingInsights.DailyWordsBucket) -> Int {
        guard day.words > 0 || day.hasReading else { return 0 }
        guard day.words > 0 else { return 1 }
        let q1 = thresholds.indices.contains(0) ? thresholds[0] : 5_000
        let q2 = thresholds.indices.contains(1) ? thresholds[1] : 10_000
        let q3 = thresholds.indices.contains(2) ? thresholds[2] : 20_000
        if day.words < q1 { return 1 }
        if day.words < q2 { return 2 }
        if day.words < q3 { return 3 }
        return 4
    }

    private func tierColor(_ tier: Int) -> Color {
        switch tier {
        case 0: return Color.primary.opacity(0.06)
        case 1: return theme.accentInk.opacity(0.35)
        case 2: return theme.accentInk.opacity(0.60)
        case 3: return theme.accentInk.opacity(0.82)
        default: return theme.accentInk
        }
    }
}

struct HabitsSittingsCard: View {
    let sittings: [ReadingInsights.SittingBucket]
    let typicalSeconds: Double
    var hideReadingTime: Bool = false
    var chapterTiming: InsightsProvenance.ChapterTimingFigure? = nil
    var isYear: Bool = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var theme

    private var maxCount: Int {
        max(1, sittings.map(\.count).max() ?? 1)
    }

    var body: some View {
        let total = sittings.reduce(0) { $0 + $1.count }

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sittings")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(InsightsBoardCopy.sittingsHeaderSummary(total: total, isYear: isYear))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondaryInk)
            }

            // Duration distribution bars
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(sittings) { sit in
                    let height = max(4.0, (Double(sit.count) / Double(maxCount)) * 64.0)
                    VStack(spacing: 4) {
                        Text("\(sit.count)")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(sit.count > 0 ? AnyShapeStyle(Color.primary) : AnyShapeStyle(.secondaryInk))
                        UnevenRoundedRectangle(
                            topLeadingRadius: 4,
                            bottomLeadingRadius: 1,
                            bottomTrailingRadius: 1,
                            topTrailingRadius: 4
                        )
                        .fill(sit.count > 0 ? theme.accentInk : Color.primary.opacity(0.08))
                        .frame(height: height)
                        Text(sit.label)
                            .font(.caption2)
                            .foregroundStyle(.secondaryInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(minHeight: 94, alignment: .bottom)

            Divider()
                .overlay(theme.appTheme.cardBorder)

            let statsLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
            statsLayout {
                statColumn(
                    label: "Typical sitting",
                    value: (hideReadingTime || typicalSeconds <= 0)
                        ? "—"
                        : InsightsBoardCopy.durationLabel(typicalSeconds)
                )
                if let timing = chapterTiming {
                    statColumn(
                        label: "Chapters each, avg",
                        value: timing.averageChaptersEach.map { String(format: "%.1f", $0) } ?? "—"
                    )
                    statColumn(
                        label: "End on a chapter",
                        value: timing.chapterEndShare.map { "\(Int(($0 * 100).rounded()))%" } ?? "—"
                    )
                }
            }

            if let timing = chapterTiming {
                Divider()
                    .overlay(theme.appTheme.cardBorder)

                if timing.canShowSkimAndPeek {
                    VStack(spacing: 0) {
                        sittingHabitRow(
                            symbol: "arrow.right.to.line",
                            title: "Skimmed",
                            detail: "left out of totals",
                            value: ReadingInsights.compactWordsLabel(timing.skimmedWords)
                        )
                        Divider()
                            .overlay(theme.appTheme.cardBorder)
                        sittingHabitRow(
                            symbol: "eye",
                            title: "Peeked at the Ending",
                            detail: nil,
                            value: InsightsBoardCopy.countLabel(timing.peekedWorks, singular: "work", plural: "works")
                        )
                    }
                } else {
                    Text("Skimmed and Peeked at the Ending appear after 20 measured chapters.")
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, SubjectMetrics.gutter)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }

    private func statColumn(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondaryInk)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func sittingHabitRow(symbol: String, title: String, detail: String?, value: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Image(systemName: symbol)
                        .font(.system(size: 16))
                        .foregroundStyle(.secondaryInk)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                }
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
        } else {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 16))
                    .foregroundStyle(.secondaryInk)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                        .lineLimit(1)
                }
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(minHeight: 30)
            .accessibilityElement(children: .combine)
        }
    }
}

struct HabitsSavedToFinishedCard: View {
    let savedToOpenedDays: Int?
    let openedToFinishedDays: Int?
    let savedToOpenedCount: Int
    let openedToFinishedCount: Int
    var showsNewChaptersUnavailable: Bool = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("From Saved to Finished")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            VStack(spacing: 6) {
                // Flow dots
                HStack(spacing: 0) {
                    Circle()
                        .strokeBorder(Color.secondary, lineWidth: 2)
                        .frame(width: 12, height: 12)
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(height: 2)
                    Circle()
                        .fill(theme.accentInk.opacity(0.55))
                        .frame(width: 12, height: 12)
                    Rectangle()
                        .fill(theme.accentInk)
                        .frame(height: 2)
                    Circle()
                        .fill(theme.accentInk)
                        .frame(width: 12, height: 12)
                }

                HStack {
                    Text("Saved")
                        .font(.caption)
                        .foregroundStyle(.secondaryInk)
                    Spacer()
                    Text("Opened")
                        .font(.caption)
                        .foregroundStyle(.secondaryInk)
                    Spacer()
                    Text("Finished")
                        .font(.caption)
                        .foregroundStyle(.secondaryInk)
                }
            }
            .accessibilityHidden(true)

            let mediansLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
            mediansLayout {
                if let days = savedToOpenedDays {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(InsightsBoardCopy.countLabel(days, singular: "day", plural: "days"))
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                        Text("saved to opened, median")
                            .font(.caption)
                            .foregroundStyle(.secondaryInk)
                        Text(InsightsBoardCopy.countLabel(savedToOpenedCount, singular: "work", plural: "works"))
                            .font(.caption)
                            .foregroundStyle(.secondaryInk)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }

                if let days = openedToFinishedDays {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(InsightsBoardCopy.countLabel(days, singular: "day", plural: "days"))
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                        Text("opened to finished, median")
                            .font(.caption)
                            .foregroundStyle(.secondaryInk)
                        Text(InsightsBoardCopy.countLabel(openedToFinishedCount, singular: "work", plural: "works"))
                            .font(.caption)
                            .foregroundStyle(.secondaryInk)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }

            if showsNewChaptersUnavailable {
                Divider()
                    .overlay(theme.appTheme.cardBorder)

                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "sun.max")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondaryInk)
                        .frame(width: 18)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("New Chapters")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Text("Chapter posting and first-read dates are not available yet.")
                            .font(.caption)
                            .foregroundStyle(.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, SubjectMetrics.gutter)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }
}

struct HabitsRereadsCard: View {
    let rereads: [ReadingHabitsInsights.RereadWork]
    let rereadTimeShare: Double?
    let discreetMode: Bool
    var discreetMasker: InsightsDiscreetMasker = .empty
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Rereads")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if let rereadTimeShare {
                    Text("\(Int((rereadTimeShare * 100).rounded()))% of reading time")
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondaryInk)
                }
            }
            .padding(.top, 14)
            .padding(.horizontal, SubjectMetrics.gutter)
            .padding(.bottom, 8)

            if rereads.isEmpty {
                Divider()
                    .overlay(theme.appTheme.cardBorder)
                Text("Works you complete multiple times will appear here as rereads.")
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                    .padding(.vertical, 12)
                    .padding(.horizontal, SubjectMetrics.gutter)
            } else {
                ForEach(Array(rereads.prefix(3).enumerated()), id: \.element.id) { _, work in
                    Divider()
                        .overlay(theme.appTheme.cardBorder)

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(discreetMode ? discreetMasker.work(id: work.id, title: work.title) : work.title)
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)

                            HStack(spacing: 5) {
                                if !work.fandom.isEmpty {
                                    Circle()
                                        .fill(fandomColor(for: work.fandom))
                                        .frame(width: 7, height: 7)
                                        .accessibilityHidden(true)
                                }
                                Text(InsightsBoardCopy.rereadDetail(
                                    fandom: work.fandom,
                                    totalWordsAcrossReads: work.totalWordsAcrossReads,
                                    discreetMode: discreetMode,
                                    discreetMasker: discreetMasker
                                ))
                                .font(.caption)
                                .foregroundStyle(.secondaryInk)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text("×\(work.finishCount)")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, SubjectMetrics.gutter)
                    .padding(.vertical, 9)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }

    private func fandomColor(for fandom: String) -> Color {
        let hue = CoverArt.workHue(fandoms: [fandom], title: "")
        return theme.appTheme.subjectPalette(hue: hue).accent
    }
}

struct HabitsFandomTimelineCard: View {
    let lanes: [ReadingHabitsInsights.FandomTimelineLane]
    var year: Int = 0
    let discreetMode: Bool
    var discreetMasker: InsightsDiscreetMasker = .empty
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var theme

    private let monthInitials = ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]

    private var yearSubtitle: String? {
        guard year > 0 else { return nil }
        let currentYear = Calendar.current.component(.year, from: Date())
        return year == currentYear ? "\(year) so far" : "\(year)"
    }

    private var visibleMonthCount: Int {
        let now = Date()
        let currentYear = Calendar.current.component(.year, from: now)
        guard year == currentYear else { return 12 }
        let currentMonth = max(1, min(12, Calendar.current.component(.month, from: now)))
        let highestActive = lanes.compactMap { lane in
            lane.monthlyActivity.lastIndex(where: { $0 > 0 }).map { $0 + 1 }
        }.max() ?? currentMonth
        return max(currentMonth, min(12, highestActive))
    }

    var body: some View {
        let monthCount = visibleMonthCount

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Fandom Timeline")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if let yearSubtitle {
                    Text(yearSubtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                }
            }

            if lanes.isEmpty {
                Text("Monthly activity by fandom will appear here as you log reading sessions.")
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(lanes.enumerated()), id: \.element.id) { _, lane in
                        let isRemainder = lane.name == ReadingInsights.remainderName
                        let label = discreetMode && !isRemainder
                            ? discreetMasker.fandom(lane.name) : lane.name

                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(label)
                                    .font(.footnote)
                                    .foregroundStyle(isRemainder ? AnyShapeStyle(.secondaryInk) : AnyShapeStyle(Color.primary))
                                monthCells(for: lane, count: monthCount)
                            }
                        } else {
                            HStack(spacing: 8) {
                                Text(label)
                                    .font(.footnote)
                                    .foregroundStyle(isRemainder ? AnyShapeStyle(.secondaryInk) : AnyShapeStyle(Color.primary))
                                    .lineLimit(1)
                                    .frame(width: 104, alignment: .leading)

                                monthCells(for: lane, count: monthCount)
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        if !dynamicTypeSize.isAccessibilitySize {
                            Spacer()
                                .frame(width: 104)
                        }
                        HStack(spacing: 3) {
                            ForEach(0..<monthCount, id: \.self) { index in
                                Text(monthInitials[index])
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondaryInk)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .accessibilityHidden(true)
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, SubjectMetrics.gutter)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }

    private func monthCells(for lane: ReadingHabitsInsights.FandomTimelineLane, count: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<count, id: \.self) { monthIdx in
                let tier = monthIdx < lane.monthlyActivity.count ? lane.monthlyActivity[monthIdx] : 0
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(timelineColor(tier: tier, fandom: lane.name))
                    .frame(height: 18)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func timelineColor(tier: Int, fandom: String) -> Color {
        if tier == 0 { return Color.primary.opacity(0.06) }
        if fandom == ReadingInsights.remainderName {
            if tier == 1 { return Color.secondary.opacity(0.22) }
            if tier == 2 { return Color.secondary.opacity(0.45) }
            return Color.secondary.opacity(0.72)
        }
        let hue = CoverArt.workHue(fandoms: [fandom], title: "")
        let base = theme.appTheme.subjectPalette(hue: hue).accent
        if tier == 1 { return base.opacity(0.3) }
        if tier == 2 { return base.opacity(0.65) }
        return base
    }
}

struct HabitsStoppedCard: View {
    let stoppedCount: Int
    let stoppedInPeriodCount: Int
    let medianProgress: Double?
    let reasons: [ReadingHabitsInsights.StopReasonCount]
    let commonTags: [(name: String, count: Int)]
    let discreetMode: Bool
    var discreetMasker: InsightsDiscreetMasker = .empty
    var isYear: Bool = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var theme

    private var maxReasonCount: Int {
        max(1, reasons.map(\.count).max() ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Stopped Reading")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(InsightsBoardCopy.stoppedHeaderSummary(
                    inPeriod: stoppedInPeriodCount,
                    total: stoppedCount,
                    isYear: isYear
                ))
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.secondaryInk)
            }

            if let medianProgress {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(Int((medianProgress * 100).rounded()))%")
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                    Text("of the way in, typically")
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                }
                .accessibilityElement(children: .combine)
            }

            VStack(spacing: 8) {
                ForEach(reasons) { reason in
                    let ratio = min(1.0, max(0.05, Double(reason.count) / Double(maxReasonCount)))
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(reason.label)
                                    .font(.subheadline)
                                Spacer()
                                Text("\(reason.count)")
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                            }
                            reasonBar(ratio: ratio)
                        }
                        .accessibilityElement(children: .combine)
                    } else {
                        HStack(spacing: 10) {
                            Text(reason.label)
                                .font(.subheadline)
                                .lineLimit(1)
                                .frame(width: 118, alignment: .leading)

                            reasonBar(ratio: ratio)

                            Text("\(reason.count)")
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .frame(minWidth: 22, alignment: .trailing)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            if !commonTags.isEmpty {
                Divider()
                    .overlay(theme.appTheme.cardBorder)

                Text("Common in Stopped Works")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)

                FlowLayout(spacing: 6, rowSpacing: 6) {
                    ForEach(Array(commonTags.enumerated()), id: \.offset) { _, tag in
                        let tagName = discreetMode ? discreetMasker.tag(tag.name) : tag.name
                        HStack(spacing: 4) {
                            Text(tagName)
                                .foregroundStyle(.primary)
                            Text("\(tag.count)")
                                .monospacedDigit()
                                .foregroundStyle(.secondaryInk)
                        }
                        .font(.footnote)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(tagName), \(InsightsBoardCopy.countLabel(tag.count, singular: "work", plural: "works"))")
                    }
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, SubjectMetrics.gutter)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }

    private func reasonBar(ratio: Double) -> some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Color.primary.opacity(0.08))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary)
                        .frame(width: proxy.size.width * ratio)
                }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

// MARK: - Library Cards

struct LibraryUnreadCard: View {
    let unreadWords: Int
    let unreadCount: Int
    let monthsToClear: Int?
    let monthsToClearRange: ClosedRange<Int>?
    let addedWords: Int
    let readWords: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var theme
    @Environment(\.secondaryInk) private var secondaryInk
    @ScaledMetric(relativeTo: .largeTitle) private var heroNumberSize: CGFloat = 38

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Unread in your library")
                .font(.footnote)
                .foregroundStyle(.secondaryInk)

            let heroLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
            heroLayout {
                Text(formatWords(unreadWords))
                    .font(.system(size: min(heroNumberSize, 52), weight: .bold))
                    .tracking(-0.5)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(InsightsBoardCopy.unreadHeroSuffix(unreadCount: unreadCount))
                    .font(.subheadline)
                    .foregroundStyle(.secondaryInk)
            }

            if let m = monthsToClear, m > 0 {
                Text("About \(InsightsBoardCopy.countLabel(m, singular: "month", plural: "months")) at this pace")
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
            } else if let range = monthsToClearRange {
                if range.lowerBound == range.upperBound {
                    Text("About \(InsightsBoardCopy.countLabel(range.lowerBound, singular: "month", plural: "months")) at this pace")
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                } else {
                    Text("About \(range.lowerBound) to \(range.upperBound) months at this pace")
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                }
            }

            Divider()
                .overlay(theme.appTheme.cardBorder)
                .padding(.top, 10)
                .padding(.bottom, 8)

            // Added vs Read
            VStack(spacing: 8) {
                let maxW = max(1, max(addedWords, readWords))
                barRow(label: "Added", words: addedWords, color: secondaryInk ?? Color.secondary, maxVal: maxW)
                barRow(label: "Read", words: readWords, color: theme.accentInk, maxVal: maxW)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Added \(addedWords.formatted()) words, read \(readWords.formatted()) words")
        }
        .padding(.vertical, 14)
        .padding(.horizontal, SubjectMetrics.gutter)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func barRow(label: String, words: Int, color: Color, maxVal: Int) -> some View {
        let ratio = min(1.0, max(words > 0 ? 0.04 : 0.0, CGFloat(words) / CGFloat(maxVal)))
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(label)
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                    Spacer()
                    Text(formatK(words))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
                unreadBar(ratio: ratio, color: color)
            }
        } else {
            HStack(spacing: 10) {
                Text(label)
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                    .frame(width: 52, alignment: .leading)

                unreadBar(ratio: ratio, color: color)

                Text(formatK(words))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .frame(minWidth: 52, alignment: .trailing)
            }
        }
    }

    private func unreadBar(ratio: CGFloat, color: Color) -> some View {
        GeometryReader { proxy in
            if ratio > 0 {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color)
                    .frame(width: max(4, proxy.size.width * ratio), height: 10)
            } else {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 4, height: 10)
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }

    private func formatWords(_ words: Int) -> String {
        if words >= 1_000_000 {
            return String(format: "%.2fM", Double(words) / 1_000_000.0)
        }
        return ReadingInsights.compactWordsLabel(words)
    }

    private func formatK(_ words: Int) -> String {
        ReadingInsights.compactWordsLabel(words)
    }
}

struct LibraryWhereEverythingStandsCard: View {
    let partition: ReadingStatusPartition
    @Environment(ThemeManager.self) private var theme
    @Environment(\.secondaryInk) private var secondaryInk

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Where Everything Stands")
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 4)
                .padding(.top, 6)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                statusRow(icon: "book.fill", color: theme.effectiveTint, label: "Reading", count: partition.readingCount)
                Divider().overlay(theme.appTheme.cardBorder)
                statusRow(icon: "clock.fill", color: Color(red: 0.17, green: 0.43, blue: 0.69), label: "Caught Up", detail: "every posted chapter read", count: partition.caughtUpCount)
                Divider().overlay(theme.appTheme.cardBorder)
                statusRow(icon: "square.stack.3d.up.fill", color: Color(red: 0.37, green: 0.36, blue: 0.90), label: "Letting Chapters Stack", detail: "back when 3 more are posted", count: partition.stackingCount)
                Divider().overlay(theme.appTheme.cardBorder)
                statusRow(icon: "pause.circle.fill", color: secondaryInk ?? Color.secondary, label: "On Hold", count: partition.onHoldCount)
                Divider().overlay(theme.appTheme.cardBorder)
                statusRow(icon: "bookmark.fill", color: Color(red: 0.69, green: 0.49, blue: 0.07), label: "Saved for Later", count: partition.savedForLaterCount)
                Divider().overlay(theme.appTheme.cardBorder)
                statusRow(icon: "checkmark.circle.fill", color: Color(red: 0.18, green: 0.48, blue: 0.29), label: "Finished", count: partition.finishedCount)
                Divider().overlay(theme.appTheme.cardBorder)
                statusRow(icon: "xmark.circle.fill", color: Color(red: 0.39, green: 0.39, blue: 0.40), label: "Stopped", count: partition.stoppedCount)
            }
            .background(theme.appTheme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
            )
        }
    }

    private func statusRow(icon: String, color: Color, label: String, detail: String? = nil, count: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(ThemeManager.label(on: color))
                .frame(width: 28, height: 28)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.callout)
                    .foregroundStyle(.primary)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondaryInk)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(count)")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondaryInk)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, SubjectMetrics.gutter)
        .padding(.vertical, 10)
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }
}

struct LibraryStillReadingCard: View {
    let candidate: ReadingLibraryInsights.StillReadingCandidate
    let work: SavedWork
    let discreetMode: Bool
    var discreetMasker: InsightsDiscreetMasker = .empty
    let onStillReading: () -> Void
    let onStoppedReading: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var theme

    private var untouchedDurationLabel: String {
        let days = max(1, candidate.daysUntouched)
        if days >= 14 || days % 7 == 0 {
            let weeks = max(1, days / 7)
            return InsightsBoardCopy.countLabel(weeks, singular: "week", plural: "weeks")
        }
        return InsightsBoardCopy.countLabel(days, singular: "day", plural: "days")
    }

    var body: some View {
        let workLabel = discreetMode
            ? discreetMasker.work(id: candidate.id, title: candidate.title) : candidate.title
        let progressText = discreetMode && !candidate.discreetChapterProgress.isEmpty
            ? candidate.discreetChapterProgress
            : candidate.chapterProgress

        VStack(alignment: .leading, spacing: 10) {
            NavigationLink(value: work) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        if !candidate.fandom.isEmpty {
                            Circle()
                                .fill(fandomColor(for: candidate.fandom))
                                .frame(width: 8, height: 8)
                                .accessibilityHidden(true)
                        }
                        let fandomPrefix = candidate.fandom.isEmpty
                            ? ""
                            : "\(discreetMode ? discreetMasker.fandom(candidate.fandom) : candidate.fandom) · "
                        Text("\(fandomPrefix)untouched for \(untouchedDurationLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondaryInk)
                    }

                    Text("Still reading \(workLabel)?")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    Text(progressText)
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens \(workLabel)")

            let actionsLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 8))
                : AnyLayout(HStackLayout(spacing: 8))
            actionsLayout {
                Button {
                    onStillReading()
                } label: {
                    Text("Still Reading")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 40)
                        .padding(.horizontal, 12)
                        .background(Color.primary.opacity(0.08))
                        .foregroundStyle(.primary)
                        .clipShape(SubjectMetrics.controlShape(dynamicTypeSize))
                }
                .buttonStyle(.plain)

                Button {
                    onStoppedReading()
                } label: {
                    Text("Stopped…")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 40)
                        .padding(.horizontal, 12)
                        .background(Color.primary.opacity(0.08))
                        .foregroundStyle(theme.accentInk)
                        .clipShape(SubjectMetrics.controlShape(dynamicTypeSize))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Record a reason or put this work on hold")
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, SubjectMetrics.gutter)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }

    private func fandomColor(for fandom: String) -> Color {
        let hue = CoverArt.workHue(fandoms: [fandom], title: "")
        return theme.appTheme.subjectPalette(hue: hue).accent
    }
}

struct LibraryWIPFreshnessCard: View {
    let freshness: WIPFreshness
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var theme

    private var activeColor: Color { Color.primary.opacity(0.78) }
    private var quietColor: Color { Color.secondary.opacity(0.75) }
    private var dormantColor: Color { Color.primary.opacity(0.22) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Works in Progress")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(freshness.total) saved")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondaryInk)
            }

            // Proportional freshness bar
            InsightsProportionalBar(
                segments: [
                    .init(id: 0, value: Double(freshness.active), color: activeColor),
                    .init(id: 1, value: Double(freshness.quiet), color: quietColor),
                    .init(id: 2, value: Double(freshness.dormant), color: dormantColor)
                ],
                height: 14
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(InsightsBoardCopy.wipFreshnessBarLabel(freshness))

            let columnsLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 6))
            columnsLayout {
                freshnessCol(label: "Active", count: freshness.active, detail: "in 6 months", color: activeColor)
                freshnessCol(label: "Quiet", count: freshness.quiet, detail: "6–12 months", color: quietColor)
                freshnessCol(label: "Dormant", count: freshness.dormant, detail: "over a year", color: dormantColor)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, SubjectMetrics.gutter)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }

    private func freshnessCol(label: String, count: Int, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondaryInk)
                    .lineLimit(1)
            }
            Text("\(count)")
                .font(.headline)
                .monospacedDigit()
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct LibraryNoLongerOnAO3Card: View {
    let count: Int
    let words: Int
    let lastCopies: Int
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "archivebox.fill")
                .font(.system(size: 18))
                .foregroundStyle(.secondaryInk)
                .frame(width: 36, height: 36)
                .background(Color.primary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("No Longer on AO3")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(InsightsBoardCopy.noLongerOnAO3Summary(count: count, words: words, lastCopies: lastCopies))
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, SubjectMetrics.gutter)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
    }
}

struct LibraryFeedbackCard: View {
    let kudosLeftPercent: Int?
    var finishedCount: Int? = nil
    var favoriteWithoutKudosCount: Int = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("On Finished Works")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    if let finishedCount {
                        Text("\(finishedCount) finished")
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(.secondaryInk)
                    }
                }

                if let kudosLeftPercent {
                    feedbackRow(label: "Kudos left", percent: kudosLeftPercent)
                }

                Text("Bookmarked and commented actions are not recorded yet.")
                    .font(.caption)
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 14)
            .padding(.horizontal, SubjectMetrics.gutter)
            .padding(.bottom, favoriteWithoutKudosCount > 0 ? 10 : 14)

            if favoriteWithoutKudosCount > 0 {
                Divider()
                    .overlay(theme.appTheme.cardBorder)
                HStack(spacing: 10) {
                    Image(systemName: "heart")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.accentInk)
                        .accessibilityHidden(true)
                    Text("Favourites Without Kudos")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(favoriteWithoutKudosCount)")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondaryInk)
                }
                .padding(.horizontal, SubjectMetrics.gutter)
                .padding(.vertical, 12)
                .frame(minHeight: 48)
                .accessibilityElement(children: .combine)
            }
        }
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func feedbackRow(label: String, percent: Int) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(label)
                        .font(.subheadline)
                    Spacer()
                    Text("\(percent)%")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
                feedbackBar(percent: percent)
            }
            .accessibilityElement(children: .combine)
        } else {
            HStack(spacing: 10) {
                Text(label)
                    .font(.subheadline)
                    .frame(width: 96, alignment: .leading)

                feedbackBar(percent: percent)

                // One line: "100%" was wider than the old fixed column and broke before the "%".
                Text("\(percent)%")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .frame(minWidth: 38, alignment: .trailing)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func feedbackBar(percent: Int) -> some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Color.primary.opacity(0.08))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(theme.accentInk)
                        .frame(width: proxy.size.width * CGFloat(percent) / 100.0)
                }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

struct LibraryPreservedStatsCard: View {
    let stats: ReadingStatistics
    let discreetMode: Bool
    var discreetMasker: InsightsDiscreetMasker = .empty
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Library Activity")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 10) {
                item(title: "Works opened", value: "\(stats.startedWorks)")
                item(title: "Words read", value: stats.wordsRead.formatted(.number.notation(.compactName)))
                item(title: "Still in progress", value: "\(stats.inProgressWorks)")
                item(title: "Finished", value: "\(stats.finishedWorks) (\(Int(stats.completionRate * 100))%)")
                item(title: "Opened in 7 days", value: "\(stats.openedLast7Days)")
                item(title: "Opened in 30 days", value: "\(stats.openedLast30Days)")
            }

            Divider()
                .overlay(theme.appTheme.cardBorder)

            Text("Most-Read Fandoms by Shelf Count")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)

            VStack(spacing: 4) {
                ForEach(Array(stats.topFandoms.prefix(4))) { f in
                    HStack {
                        Circle()
                            .fill(fandomColor(for: f.name))
                            .frame(width: 7, height: 7)
                        Text(discreetMode ? discreetMasker.fandom(f.name) : f.name)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text("\(f.count) \(f.count == 1 ? "work" : "works")")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondaryInk)
                    }
                }
            }
        }
        .padding(16)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }

    private func item(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondaryInk)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fandomColor(for fandom: String) -> Color {
        let hue = CoverArt.workHue(fandoms: [fandom], title: "")
        return theme.appTheme.subjectPalette(hue: hue).accent
    }
}
