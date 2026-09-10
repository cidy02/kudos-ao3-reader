import SwiftData
import SwiftUI

/// Artboard **1bi** — Reading Insights, reached from Library.
///
/// Three cards on the Library scope's own hue: the month's hours with a delta
/// and a seven-week bar chart, where those hours went by fandom, and four
/// figures of pace and follow-through. Every number comes from `ReadingSession`
/// rows written by `ReadingLogService`; the rules that turn them into figures
/// live in `ReadingInsights`, where they can be tested against fixtures.
///
/// **Nothing here is sent anywhere.** The header says so, because a page of
/// statistics about someone's reading is exactly the page where that question
/// occurs to them.
struct ReadingInsightsView: View {
    @Environment(\.modelContext) private var context
    @Environment(ThemeManager.self) private var theme

    /// The Library's own visible set — queue-only works excluded, and adult works
    /// excluded while the mature gate hides them. Passed in rather than queried
    /// here on purpose: a work the reader has hidden must not have its fandom
    /// named on this page. Its *hours* still count, because the session rows are
    /// read from the store unfiltered and a session with no matching work simply
    /// has no fandom to attribute — it lands in `Everything else`, which is the
    /// right answer rather than a leak or a lost hour.
    let works: [SavedWork]

    @State private var insights = ReadingInsights()
    @State private var period = Period.month

    /// The window the screen is showing. The spec draws the month, but the
    /// seven-week chart it draws with it spans more than a month, so the chart's
    /// span and the headline figure's span are deliberately separate: the
    /// headline answers "this month" and the bars give it somewhere to sit.
    enum Period: String, CaseIterable, Hashable {
        case month
        case year

        var title: String {
            switch self {
            case .month: "This month"
            case .year: "This year"
            }
        }

        var component: Calendar.Component {
            switch self {
            case .month: .month
            case .year: .year
            }
        }
    }

    var body: some View {
        List {
            Section {
                header.pageBodyRow(top: 20, gutter: 0)
            }

            // The three session cards only when there is a log to draw them
            // from. An hours card reading 0.0 over seven empty bars is not a
            // truthful nothing, it is a broken-looking something.
            if hasSessions {
                Section {
                    SectionRuleHeader(
                        title: period.title, count: insights.weeklySeconds.count
                    )
                    .pageBodyRow(top: 14, gutter: 0)
                    hoursCard.pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
                }

                Section {
                    SectionRuleHeader(
                        title: "Where the hours went", count: insights.byFandom.count
                    )
                    .pageBodyRow(top: 18, gutter: 0)
                    fandomCard.pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
                }

                Section {
                    SectionRuleHeader(title: "Pace and follow-through")
                        .pageBodyRow(top: 18, gutter: 0)
                    paceCard.pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
                }
            } else {
                Section {
                    noSessionsNote.pageBodyRow(
                        top: 14, gutter: SubjectMetrics.accountGutter
                    )
                }
            }

            Section {
                SectionRuleHeader(title: "Your library", count: works.count)
                    .pageBodyRow(top: 18, gutter: 0)
                libraryCard.pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
            }

            Section { topFandomsSection }
        }
        .cardList()
        .subjectScreenWash(palette: palette)
        .task(id: period) { reload() }
        .refreshable { reload() }
        .overlay {
            // Only when there is nothing at all to show. A reader with no
            // session log but a full shelf still has the library card, and
            // covering it with an empty state would hide real content.
            if !hasSessions, works.isEmpty {
                emptyState
            }
        }
    }

    // MARK: Header

    private var header: some View {
        SubjectHeaderBlock(
            kicker: "Library",
            title: "Reading Insights",
            subtitle: headerTallyLine,
            palette: palette,
            gutter: SubjectMetrics.accountGutter
        ) {
            SubjectSegmentedControl(
                options: Period.allCases,
                title: \.title,
                selection: $period
            )
            .frame(maxWidth: 190)
        }
    }

    /// Spec 1bi: "18.4 hours in August · measured on this device". The second
    /// half is not decoration — it is the answer to the question a statistics
    /// page raises, and it belongs where the figure is rather than in a footer.
    private var headerTallyLine: String {
        guard hasSessions else { return "Measured on this device · nothing sent anywhere" }
        let hours = ReadingInsights.hoursLabel(insights.totalSeconds)
        return "\(hours) hours in \(periodName) · measured on this device"
    }

    /// Whether the log has anything in this period. `totalSeconds` rather than a
    /// row count: rows below the log's minimum never reach the store, so a zero
    /// total and an empty log are the same state here.
    private var hasSessions: Bool { insights.totalSeconds > 0 }

    /// The Library scope's hue, matching every other Library surface.
    private var palette: SubjectPalette {
        theme.appTheme.subjectPalette(hue: theme.scopeHue)
    }

    // MARK: The hours card

    private var hoursCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ReadingInsights.hoursLabel(insights.totalSeconds))
                        .font(.system(size: heroSize, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("hours in \(periodName)")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                deltaPill
            }

            Divider().overlay(Color.primary.opacity(0.12))

            weeklyChart
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .subjectCard(palette: palette)
    }

    /// Spec 1bi's `↑ +3.1 vs Jul`. Absent when there is no earlier period to
    /// compare against, rather than showing `+18.4` against a month that does
    /// not exist.
    @ViewBuilder
    private var deltaPill: some View {
        if let previous = insights.previousPeriodSeconds {
            let delta = insights.totalSeconds - previous
            HStack(spacing: 6) {
                Image(systemName: delta < 0 ? "arrow.down.right" : "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(delta < 0 ? Color.secondary : Color.green)
                Text(ReadingInsights.signedHoursLabel(delta))
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                Text("vs \(previousPeriodName)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(theme.appTheme.glassFill(0.08))
                    .overlay(Capsule().strokeBorder(theme.appTheme.glassStroke(0.12),
                                                    lineWidth: 0.5))
            )
            .combinedAccessibilityRow(
                "\(ReadingInsights.signedHoursLabel(delta)) hours versus \(previousPeriodName)"
            )
        }
    }

    /// The spec's bars: value above, 72pt column, week label below, the most
    /// recent week in the accent.
    ///
    /// Heights are a share of the tallest bar rather than of a fixed ceiling, so
    /// a quiet month still reads as a shape instead of seven stubs. A week with
    /// no reading keeps a 2pt sliver so the row stays legible as seven weeks.
    private var weeklyChart: some View {
        let peak = insights.weeklySeconds.map(\.seconds).max() ?? 0
        return HStack(alignment: .bottom, spacing: 7) {
            ForEach(Array(insights.weeklySeconds.enumerated()), id: \.offset) { index, bucket in
                let isLatest = index == insights.weeklySeconds.count - 1
                VStack(spacing: 6) {
                    Text(ReadingInsights.hoursLabel(bucket.seconds))
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(isLatest ? palette.accent : Color.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    GeometryReader { proxy in
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            UnevenRoundedRectangle(
                                topLeadingRadius: 5,
                                bottomLeadingRadius: 2,
                                bottomTrailingRadius: 2,
                                topTrailingRadius: 5,
                                style: .continuous
                            )
                            .fill(palette.accent.opacity(isLatest ? 0.72 : 0.34))
                            .frame(height: max(2, proxy.size.height * share(bucket.seconds,
                                                                           of: peak)))
                        }
                    }
                    .frame(height: chartHeight)
                    Text(weekLabel(bucket.weekStart))
                        .font(.system(size: 8.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                .combinedAccessibilityRow(
                    "Week of \(weekLabel(bucket.weekStart)): "
                        + "\(ReadingInsights.hoursLabel(bucket.seconds)) hours"
                )
            }
        }
    }

    // MARK: Where the hours went

    private var fandomCard: some View {
        let peak = insights.byFandom.map(\.seconds).max() ?? 0
        return VStack(alignment: .leading, spacing: 13) {
            ForEach(Array(insights.byFandom.enumerated()), id: \.offset) { index, share in
                fandomRow(share, rank: index, peak: peak)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .subjectCard(palette: palette)
    }

    private func fandomRow(
        _ entry: ReadingInsights.FandomShare,
        rank: Int,
        peak: Double,
        valueLabel: String? = nil
    ) -> some View {
        let width = share(entry.seconds, of: peak)
        let tint = barTint(rank: rank, isRemainder: entry.isRemainder)
        let value = valueLabel ?? "\(ReadingInsights.hoursLabel(entry.seconds)) h"
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.name)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(value)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tint)
            }
            Capsule()
                .fill(Color.primary.opacity(0.09))
                .frame(height: 5)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(tint)
                            .frame(width: proxy.size.width * width)
                    }
                }
        }
        .combinedAccessibilityRow("\(entry.name): \(value)")
    }

    /// The spec gives the three named fandoms three distinct tints and the
    /// remainder a neutral one. Derived by rotating the subject hue rather than
    /// hard-coding `#8FE0C4`/`#A8D69B`/`#8FB4E0`, so the card still separates its
    /// rows when the app accent is anything other than the spec's green.
    private func barTint(rank: Int, isRemainder: Bool) -> Color {
        guard !isRemainder else { return Color.secondary.opacity(0.55) }
        let rotated = (palette.hue + Double(rank) * 0.06).truncatingRemainder(dividingBy: 1)
        return theme.appTheme.subjectPalette(hue: rotated).accent
    }

    // MARK: Pace and follow-through

    private var paceCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            paceGrid
            Divider().overlay(Color.primary.opacity(0.12))
            Text(paceFootnote)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .subjectCard(palette: palette)
    }

    private var paceGrid: some View {
        // A two-column grid that collapses to one at accessibility sizes: the
        // spec's `22pt` figures beside an eleven-point caption do not survive
        // being halved in width.
        let columns = [
            GridItem(.flexible(), spacing: 12, alignment: .leading),
            GridItem(.flexible(), spacing: 12, alignment: .leading)
        ]
        return LazyVGrid(
            columns: dynamicTypeSize.isAccessibilitySize ? [columns[0]] : columns,
            alignment: .leading,
            spacing: 15
        ) {
            paceCell(ReadingInsights.durationLabel(insights.medianSessionSeconds),
                     "median session")
            paceCell(wordsPerHourLabel, "words per hour")
            paceCell(finishRateLabel, "of started works finished")
            paceCell(streakLabel, "longest streak")
        }
    }

    private func paceCell(_ figure: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(figure)
                .font(.system(size: figureSize, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .combinedAccessibilityRow("\(figure) \(caption)")
    }

    private var wordsPerHourLabel: String {
        let rate = Int(insights.wordsPerHour.rounded())
        guard rate > 0 else { return "—" }
        return rate.formatted(.number.grouping(.automatic))
    }

    /// `nil` finish rate is "no works started", which is not 0%.
    private var finishRateLabel: String {
        guard let rate = insights.finishRate else { return "—" }
        return "\(Int((rate * 100).rounded()))%"
    }

    private var streakLabel: String {
        let days = insights.longestStreakDays
        return "\(days) day\(days == 1 ? "" : "s")"
    }

    /// The spec's footnote says "shorter than a minute". The log's actual
    /// threshold is `ReadingLogService.minimumPersistableDuration`, so the
    /// sentence is built from it: a footnote that states a rule the code does
    /// not follow is worse than no footnote, and the two would drift the first
    /// time anyone tuned the constant.
    private var paceFootnote: String {
        let seconds = Int(ReadingLogService.minimumPersistableDuration.rounded())
        return "Sessions shorter than \(seconds) seconds are not counted, so a work opened "
            + "and closed does not read as reading."
    }

    private var noSessionsNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No reading logged this \(period == .month ? "month" : "year")")
                .font(.system(size: 15, weight: .semibold))
            Text("Sessions are recorded while a work is open in the reader, on this device "
                + "only. Your library is summarised below.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .subjectCard(palette: palette)
    }

    // MARK: Your library

    /// Artboard 1bi draws three cards and stops. This is a fourth, and it is
    /// here because the screen it replaces showed these figures and `AGENTS.md`
    /// counts a cleaner screen that drops metadata as a regression.
    ///
    /// They are also a different *kind* of fact from the three cards above.
    /// Those measure reading — time, pace, follow-through, all of it from the
    /// session log. These describe the shelf: how much is on it, how much has
    /// been opened, when it was last touched. A reader with an empty log still
    /// has a library, and this card is what that reader sees.
    private var libraryCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            libraryGrid
            Divider().overlay(Color.primary.opacity(0.12))
            Text("Words read counts finished works with a known AO3 word count. "
                + "Recent activity counts distinct works opened. Finished counts works "
                + "marked finished, including any you read before the session log existed.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .subjectCard(palette: palette)
    }

    /// Most-read fandoms by **number of works**, all time — the figure the
    /// retired screen showed.
    ///
    /// Deliberately kept alongside the spec's hours card rather than replaced by
    /// it, because the two answer different questions and only this one answers
    /// anything for a reader whose session log is empty. `topFandoms` counts
    /// works started; `byFandom` measures hours spent in a period.
    ///
    /// Header and card are one builder so the ranking is computed once:
    /// `ReadingStatistics.init` walks every work, and a heading that needed its
    /// own count would walk them twice per render.
    @ViewBuilder
    private var topFandomsSection: some View {
        let ranked = Array(library.topFandoms.prefix(6))
        if !ranked.isEmpty {
            let peak = ranked.first?.count ?? 0
            SectionRuleHeader(title: "Most-read fandoms", count: ranked.count)
                .pageBodyRow(top: 18, gutter: 0)
            VStack(alignment: .leading, spacing: 13) {
                ForEach(Array(ranked.enumerated()), id: \.element.id) { index, fandom in
                    fandomRow(
                        ReadingInsights.FandomShare(
                            name: fandom.name, seconds: Double(fandom.count)
                        ),
                        rank: index,
                        peak: Double(peak),
                        valueLabel: fandom.count.formatted()
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .subjectCard(palette: palette)
            .pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
        }
    }

    private var libraryGrid: some View {
        // Bound once. `ReadingStatistics.init` walks every work, and reading it
        // through a computed property six times in this builder would walk the
        // library six times per render.
        let stats = library
        let columns = [
            GridItem(.flexible(), spacing: 12, alignment: .leading),
            GridItem(.flexible(), spacing: 12, alignment: .leading)
        ]
        return LazyVGrid(
            columns: dynamicTypeSize.isAccessibilitySize ? [columns[0]] : columns,
            alignment: .leading,
            spacing: 15
        ) {
            paceCell(stats.startedWorks.formatted(), "works opened")
            paceCell(
                stats.wordsRead.formatted(.number.notation(.compactName)), "words read"
            )
            paceCell(stats.inProgressWorks.formatted(), "still in progress")
            paceCell(
                stats.finishedWorks.formatted(),
                "finished (\(completionPercent(stats)))"
            )
            paceCell(stats.openedLast7Days.formatted(), "opened in 7 days")
            paceCell(stats.openedLast30Days.formatted(), "opened in 30 days")
            paceCell(lastReadLabel(stats.latestReadDate), "last read")
        }
    }

    private var library: ReadingStatistics {
        ReadingStatistics(works: works)
    }

    private func lastReadLabel(_ date: Date?) -> String {
        guard let date else { return "Not yet" }
        return date.formatted(.relative(presentation: .named))
    }

    private func completionPercent(_ stats: ReadingStatistics) -> String {
        stats.completionRate.formatted(.percent.precision(.fractionLength(0)))
    }

    // MARK: Empty

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No reading logged yet", systemImage: "chart.bar.xaxis")
        } description: {
            Text("Open a work and read for a minute or two. Sessions are recorded on this "
                + "device only, and nothing here is ever sent anywhere.")
        }
    }

    // MARK: Shared bits

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 44
    @ScaledMetric(relativeTo: .title2) private var figureSize: CGFloat = 22
    @ScaledMetric(relativeTo: .caption) private var chartHeight: CGFloat = 72

    private var calendar: Calendar { .current }

    private var periodName: String {
        switch period {
        case .month: monthFormatter.string(from: Date())
        case .year: yearFormatter.string(from: Date())
        }
    }

    private var previousPeriodName: String {
        let earlier = calendar.date(
            byAdding: period.component, value: -1, to: Date()
        ) ?? Date()
        switch period {
        case .month: return shortMonthFormatter.string(from: earlier)
        case .year: return yearFormatter.string(from: earlier)
        }
    }

    // Held rather than rebuilt: `weekLabel` runs once per bar per render, and a
    // DateFormatter is not cheap to construct. Templates rather than literal
    // formats so the order and separators follow the reader's locale.
    private static let monthFormatter = formatter("LLLL")
    private static let shortMonthFormatter = formatter("LLL")
    private static let yearFormatter = formatter("y")
    private static let weekFormatter = formatter("MMMd")

    private var monthFormatter: DateFormatter { Self.monthFormatter }
    private var shortMonthFormatter: DateFormatter { Self.shortMonthFormatter }
    private var yearFormatter: DateFormatter { Self.yearFormatter }

    private static func formatter(_ template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }

    private func weekLabel(_ weekStart: Date) -> String {
        Self.weekFormatter.string(from: weekStart)
    }

    /// A bar's share of the tallest, guarding the empty case so a month with no
    /// reading does not divide by zero.
    private func share(_ value: Double, of peak: Double) -> Double {
        guard peak > 0 else { return 0 }
        return min(1, max(0, value / peak))
    }

    // MARK: Loading

    /// The seven-week chart spans more than the headline period on purpose (see
    /// `Period`), so the chart window and the figure window are computed
    /// separately and the chart's is the wider of the two.
    private func reload() {
        let now = Date()
        guard let current = calendar.dateInterval(of: period.component, for: now),
              let earlier = calendar.date(byAdding: period.component, value: -1, to: now),
              let previous = calendar.dateInterval(of: period.component, for: earlier)
        else { return }

        let figures = ReadingLogService.insights(
            for: current,
            previousPeriod: previous,
            works: works,
            calendar: calendar,
            context: context
        )

        // The bars come from a wider window than the headline: spec 1bi draws
        // seven weeks under a month's total.
        let chartStart = calendar.date(byAdding: .weekOfYear, value: -6, to: now) ?? current.start
        let chartWindow = DateInterval(
            start: min(chartStart, current.start), end: max(now, current.end)
        )
        let chartFacts = ReadingLogService.facts(
            from: ReadingLogService.sessions(in: context, interval: chartWindow), works: works
        )

        var combined = figures
        combined.weeklySeconds = ReadingInsights.weeklyBuckets(
            from: chartFacts, calendar: calendar
        )
        insights = combined
    }
}
