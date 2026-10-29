import Charts
import SwiftData
import SwiftUI

/// Reading History as a timeline (T-462; board 02, with the older History-Month
/// and History-Year boards for the other two scopes).
///
/// Week / Month / Year, the period's time with its works, finishes and streak,
/// the scope's chart, then each day's sittings on a rail. Every figure comes
/// from `ReadingSession` through `ReadingHistoryTimeline`; nothing new is
/// recorded.
///
/// Each sitting keeps the History row it replaces — the ledger `WorkRow`, with
/// its author line and four-symbol tray — and adds the sitting under it, so no
/// AO3 metadata leaves the page (AGENTS.md "UI Consistency"). Selection, the
/// swipes and their asks are the section page's own, passed in, so they behave
/// exactly as they did on the grouped list.
struct ReadingHistoryTimelineList<Header: View, OffTimelineRow: View>: View {
    /// The History shelf after the page's filters and privacy gate: the only
    /// works this page may name.
    let works: [SavedWork]
    let isSelecting: Bool
    @Binding var selection: Set<UUID>
    @Binding var pendingDelete: SavedWork?
    @Binding var pendingRemoval: PendingLibraryRemoval?
    /// A row's "Select" menu item: enter select mode with that work picked.
    let onSelect: (SavedWork) -> Void
    /// The section page's header rows (kicker, title, tally, filter chips).
    let header: () -> Header
    /// The page's ordinary row, for works the timeline cannot place.
    let offTimelineRow: (SavedWork) -> OffTimelineRow

    @Environment(ThemeManager.self) private var themeManager
    @Environment(PrivacyGate.self) private var gate
    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("library.history.scope") private var scope: ReadingHistoryScope = .week
    /// Any moment in the period on screen; the arrows step it a period at a time.
    @State private var anchor = Date()
    @Query private var sessions: [ReadingSession]

    @ScaledMetric(relativeTo: .caption) private var timeColumnWidth: CGFloat = 54

    /// Written out so the two builders take `@ViewBuilder` closures and the three
    /// bindings arrive as bindings.
    init(
        works: [SavedWork],
        isSelecting: Bool,
        selection: Binding<Set<UUID>>,
        pendingDelete: Binding<SavedWork?>,
        pendingRemoval: Binding<PendingLibraryRemoval?>,
        onSelect: @escaping (SavedWork) -> Void,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder offTimelineRow: @escaping (SavedWork) -> OffTimelineRow
    ) {
        self.works = works
        self.isSelecting = isSelecting
        _selection = selection
        _pendingDelete = pendingDelete
        _pendingRemoval = pendingRemoval
        self.onSelect = onSelect
        self.header = header
        self.offTimelineRow = offTimelineRow
    }

    var body: some View {
        // Bound once: the log fetch, the facts and the timeline are the whole
        // page, and reading them through properties would rebuild them per row.
        let byID = Dictionary(works.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let shown = sessions.filter { byID[$0.workID] != nil }
        let timeline = ReadingHistoryTimeline.make(
            scope: scope,
            containing: anchor,
            facts: ReadingLogService.facts(from: shown, works: works),
            calendar: calendar
        )
        let logged = Set(shown.map(\.workID))
        let abandoned = works.filter { ReadingLogService.isAbandoned(work: $0) }
        let abandonedIDs = Set(abandoned.map(\.id))
        let unlogged = works.filter { !logged.contains($0.id) && !abandonedIDs.contains($0.id) }

        return List {
            header()

            Section {
                periodSummary(timeline)
                    .pageBodyRow(top: 4, gutter: SubjectMetrics.gutter)
                ReadingHistoryChart(
                    timeline: timeline,
                    summary: timeline.chartSummary(periodName: spokenPeriodName(timeline), calendar: calendar)
                )
                .pageBodyRow(top: 14, gutter: SubjectMetrics.gutter)
                if scope == .month {
                    mostRead(timeline, byID: byID)
                }
                if scope == .year, timeline.totalSeconds > 0 {
                    yearFacts(timeline)
                        .pageBodyRow(top: 18, gutter: SubjectMetrics.gutter)
                }
            }

            if timeline.days.isEmpty {
                Section {
                    Text("Nothing read \(periodNoun(timeline)).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .pageBodyRow(top: 22, gutter: SubjectMetrics.gutter)
                }
            }

            ForEach(timeline.days) { day in
                Section {
                    SectionRuleHeader(
                        title: dayTitle(day.start), countText: ReadingInsights.durationLabel(day.totalSeconds)
                    )
                    .pageBodyRow(top: 22, gutter: 0)
                    ForEach(day.sittings) { sitting in
                        if let work = byID[sitting.workID] {
                            sittingRow(sitting, work: work, isLast: sitting.id == day.sittings.last?.id)
                        }
                    }
                }
            }

            // Not period-bound, so after every period's days. These are works the
            // grouped list showed and the rail cannot place, kept rather than lost.
            offTimelineSection(
                "Abandoned", works: abandoned,
                note: "In progress, untouched for \(Int(ReadingLogService.defaultAbandonedThreshold / 86_400)) days"
            )
            offTimelineSection(
                "No reading time recorded", works: unlogged,
                note: "Read before Kudos kept time"
            )
        }
        .cardList()
    }

    // MARK: Summary

    private func periodSummary(_ timeline: ReadingHistoryTimeline) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SubjectSegmentedControl(
                options: ReadingHistoryScope.allCases,
                title: \.title,
                selection: $scope
            )
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(periodName(timeline))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(ReadingInsights.durationLabel(timeline.totalSeconds))
                        .font(.title.bold())
                        .monospacedDigit()
                    Text(summaryLine(timeline))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    stepButton(-1, systemImage: "chevron.left", label: "Previous \(scope.title.lowercased())")
                    stepButton(1, systemImage: "chevron.right", label: "Next \(scope.title.lowercased())")
                        .disabled(timeline.isCurrent)
                }
            }
        }
    }

    /// Board 02's "11 works · 2 finished · 9-day streak". Month adds how many of
    /// its days had reading and Year how many words, as their boards do; a zero
    /// streak or word count is left out rather than printed.
    private func summaryLine(_ timeline: ReadingHistoryTimeline) -> String {
        var parts = [
            "\(timeline.workCount) \(timeline.workCount == 1 ? "work" : "works")",
            "\(timeline.finishedCount) finished"
        ]
        if scope == .month {
            parts.append("read on \(timeline.daysRead) of \(timeline.daysElapsed) days")
        }
        if scope == .year, timeline.wordsRead > 0 {
            parts.append("\(timeline.wordsRead.formatted(.number.notation(.compactName))) words")
        }
        if timeline.streakDays > 0 {
            parts.append("\(timeline.streakDays)-day streak")
        }
        return parts.joined(separator: " · ")
    }

    private func stepButton(_ delta: Int, systemImage: String, label: String) -> some View {
        Button {
            anchor = calendar.date(byAdding: scope.component, value: delta, to: anchor) ?? anchor
        } label: {
            Image(systemName: systemImage)
                .font(.footnote.weight(.bold))
                .frame(width: 32, height: 32)
                .background(Circle().fill(themeManager.appTheme.glassFill(0.12)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(themeManager.accentInk)
        .minimumHitTarget()
        .accessibilityLabel(label)
    }

    // MARK: Month and Year extras

    /// History-Month's "Most Read": the month's three works by time, a list row
    /// each so each opens its own work.
    @ViewBuilder
    private func mostRead(_ timeline: ReadingHistoryTimeline, byID: [UUID: SavedWork]) -> some View {
        // A blurred mature work cannot be named here; the rail below draws it blurred.
        let entries = Array(timeline.mostRead
            .filter { entry in byID[entry.workID].map { !gate.isConcealed($0, enabled: hideMature) } ?? false }
            .prefix(3))
        if !entries.isEmpty {
            SectionRuleHeader(title: "Most read", count: entries.count)
                .pageBodyRow(top: 22, gutter: 0)
            ForEach(Array(entries.enumerated()), id: \.element.id) { rank, entry in
                if let work = byID[entry.workID] {
                    mostReadRow(entry, rank: rank + 1, work: work)
                        .pageBodyRow(top: 10, gutter: SubjectMetrics.gutter)
                }
            }
        }
    }

    private func mostReadRow(
        _ entry: ReadingHistoryTimeline.WorkTime, rank: Int, work: SavedWork
    ) -> some View {
        let time = ReadingInsights.durationLabel(entry.seconds)
        return HStack(spacing: 12) {
            Text("\(rank)")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                if !entry.fandom.isEmpty {
                    SubjectKicker(text: FandomDisplayName.bareTitle(entry.fandom), palette: fandomPalette(work))
                }
                Text(entry.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(time)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .subjectRowNavigation(
            to: LocalWorkDestination.reader(work),
            accessibilityLabel: "\(rank). \(entry.title), \(time)"
        )
    }

    /// History-Year's four facts about the year.
    private func yearFacts(_ timeline: ReadingHistoryTimeline) -> some View {
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 10, alignment: .leading),
            count: dynamicTypeSize.isAccessibilitySize ? 1 : 2
        )
        let streak = timeline.longestStreakDays
        let words = timeline.longestFinishedWordCount
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            factCell("Longest streak", streak > 0 ? "\(streak) day\(streak == 1 ? "" : "s")" : "—")
            factCell("Most-read fandom", timeline.topFandom.map(FandomDisplayName.bareTitle) ?? "—")
            factCell(
                "Longest work finished",
                words > 0 ? "\(words.formatted(.number.notation(.compactName))) words" : "—"
            )
            factCell("Favourite time", timeline.favouriteTime?.title ?? "—")
        }
    }

    private func factCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .subjectCard(palette: themeManager.scopePalette)
        .accessibilityElement(children: .combine)
    }

    // MARK: The rail

    @ViewBuilder
    private func sittingRow(
        _ sitting: ReadingHistoryTimeline.Sitting, work: SavedWork, isLast: Bool
    ) -> some View {
        // Flat on the wash and flush top to bottom, so one row's rail meets the next.
        let row = railRow(sitting, work: work, isLast: isLast)
            .pageBodyRow(top: 0, gutter: SubjectMetrics.gutter)
        // As on the grouped list: swipes give way to a plain selectable row.
        if isSelecting {
            row
        } else {
            row.libraryWorkSwipeActions(
                work,
                kind: .history,
                isFavoritesList: false,
                pendingDelete: $pendingDelete,
                pendingRemoval: $pendingRemoval
            )
        }
    }

    private func railRow(
        _ sitting: ReadingHistoryTimeline.Sitting, work: SavedWork, isLast: Bool
    ) -> some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let time = sitting.startedAt.formatted(date: .omitted, time: .shortened)
        return HStack(alignment: .top, spacing: 10) {
            if !stacked {
                Text(time)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: timeColumnWidth, alignment: .trailing)
                    .padding(.top, 14)
                    .accessibilityHidden(true)
            }
            railDot(finished: sitting.didFinish)
                .frame(width: 14)
                .padding(.top, 15)
            VStack(alignment: .leading, spacing: 8) {
                if stacked {
                    Text(time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                SensitiveWorkRow(
                    work: work,
                    openMode: .reader,
                    onSelect: { onSelect(work) },
                    isSelecting: isSelecting,
                    isSelected: selection.contains(work.id),
                    onToggleSelection: { toggle(work) },
                    presentation: .ledger
                )
                sittingFacts(sitting, time: time)
                if !isLast {
                    SubjectRowSeparator(inset: 0)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, isLast ? 4 : 0)
        }
        .background(alignment: .topLeading) {
            // The rail runs the row's height, stopping at the day's last dot.
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 2, height: isLast ? 21 : nil)
                .padding(.leading, (stacked ? 0 : timeColumnWidth + 10) + 6)
                .accessibilityHidden(true)
        }
    }

    /// Filled for a sitting that finished the work, a ring otherwise.
    private func railDot(finished: Bool) -> some View {
        let tint = themeManager.effectiveTint
        return Circle()
            .fill(finished ? tint : themeManager.appTheme.cardSurface)
            .overlay(Circle().strokeBorder(tint, lineWidth: 2))
            .frame(width: 12, height: 12)
            .accessibilityHidden(true)
    }

    /// The sitting itself: chapter cells, "Chapters 3–4 · 35 min", and its badge,
    /// read by VoiceOver as one stop.
    private func sittingFacts(_ sitting: ReadingHistoryTimeline.Sitting, time: String) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        let spoken = [
            "Read at \(time)",
            sitting.chapters?.accessibilityLabel,
            sitting.detailLine,
            sitting.badge?.title
        ]
        return VStack(alignment: .leading, spacing: 6) {
            if let chapters = sitting.chapters {
                ChapterCells(span: chapters, current: themeManager.effectiveTint)
            }
            layout {
                Text(sitting.detailLine)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let badge = sitting.badge {
                    SubjectStateBadge(title: badge.title, color: themeManager.accentInk)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken.compactMap { $0 }.joined(separator: ", "))
    }

    // MARK: Off the timeline

    @ViewBuilder
    private func offTimelineSection(_ title: String, works: [SavedWork], note: String) -> some View {
        if !works.isEmpty {
            Section {
                ForEach(works) { work in
                    offTimelineRow(work)
                }
            } header: {
                SectionRuleHeader(title: title, count: works.count, note: note)
                    .textCase(nil)
                    .listRowInsets(EdgeInsets())
                    .padding(.top, 22)
                    .padding(.bottom, 10)
            }
        }
    }

    // MARK: Labels

    private func toggle(_ work: SavedWork) {
        if selection.contains(work.id) {
            selection.remove(work.id)
        } else {
            selection.insert(work.id)
        }
    }

    private func fandomPalette(_ work: SavedWork) -> SubjectPalette {
        themeManager.appTheme.subjectPalette(hue: CoverArt.workHue(fandoms: work.workFandoms, title: work.title))
    }

    /// "Oct 20 – 26", "October 2026", "2026 so far".
    private func periodName(_ timeline: ReadingHistoryTimeline) -> String {
        let period = timeline.period
        switch scope {
        case .week:
            let lastDay = period.end.addingTimeInterval(-1)
            return (period.start..<lastDay).formatted(.interval.month(.abbreviated).day())
        case .month:
            return period.start.formatted(.dateTime.month(.wide).year())
        case .year:
            let year = period.start.formatted(.dateTime.year())
            return timeline.isCurrent ? "\(year) so far" : year
        }
    }

    private func spokenPeriodName(_ timeline: ReadingHistoryTimeline) -> String {
        guard timeline.isCurrent else { return periodName(timeline) }
        return "This \(scope.title.lowercased())"
    }

    /// "this week", "in October 2026", for the empty period's line.
    private func periodNoun(_ timeline: ReadingHistoryTimeline) -> String {
        timeline.isCurrent ? "this \(scope.title.lowercased())" : "in \(periodName(timeline))"
    }

    /// Board 02's "Today" and "Yesterday", then the weekday and date.
    private func dayTitle(_ day: Date) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

/// The scope's chart: board 02's week of bars with its average, History-Month's
/// calendar, History-Year's months. VoiceOver reads it as `summary`, one
/// sentence, rather than a stop per bar or day.
private struct ReadingHistoryChart: View {
    let timeline: ReadingHistoryTimeline
    let summary: String

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 112
    @ScaledMetric(relativeTo: .footnote) private var monthCellHeight: CGFloat = 42

    var body: some View {
        Group {
            switch timeline.scope {
            case .week: weekChart
            case .month: monthCalendar
            case .year: yearChart
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    /// Board 02: a bar a day, the latest day solid, and the average as a dashed rule.
    private var weekChart: some View {
        let tint = themeManager.effectiveTint
        let latest = timeline.buckets.last { !$0.isFuture }?.start
        let average = timeline.averageBucketSeconds
        return Chart {
            ForEach(timeline.buckets) { bucket in
                BarMark(
                    x: .value("Day", bucket.start, unit: .day),
                    y: .value("Minutes", bucket.seconds / 60)
                )
                .foregroundStyle(bucket.start == latest ? tint : tint.opacity(0.35))
                .cornerRadius(4)
            }
            RuleMark(y: .value("Baseline", 0.0))
                .foregroundStyle(Color.primary.opacity(0.15))
                .lineStyle(StrokeStyle(lineWidth: 0.5))
            if average > 0 {
                RuleMark(y: .value("Average", average / 60))
                    .foregroundStyle(Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .trailing, spacing: 2) {
                        Text("avg \(ReadingInsights.durationLabel(average))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
            }
        }
        .frame(height: chartHeight)
    }

    /// History-Month: the month as a calendar, each day shaded by time read.
    private var monthCalendar: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        let firstWeekday = calendar.firstWeekday
        let initials = calendar.veryShortWeekdaySymbols
        let leading = timeline.buckets.first.map {
            (calendar.component(.weekday, from: $0.start) - firstWeekday + 7) % 7
        } ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(0..<7, id: \.self) { offset in
                    let symbol = (firstWeekday - 1 + offset) % 7
                    Text(initials.indices.contains(symbol) ? initials[symbol] : "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                ForEach(0..<leading, id: \.self) { _ in
                    Color.clear.frame(height: 1)
                }
                ForEach(timeline.buckets) { bucket in
                    monthCell(bucket)
                }
            }
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                Text("Less")
                ForEach([0.0, 15, 45, 75], id: \.self) { minutes in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(dayShade(minutes * 60))
                        .frame(width: 12, height: 12)
                }
                Text("More")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func monthCell(_ bucket: ReadingHistoryTimeline.Bucket) -> some View {
        let strong = bucket.seconds >= 3_600
        let isToday = calendar.isDateInToday(bucket.start)
        return VStack(spacing: 1) {
            Text("\(calendar.component(.day, from: bucket.start))")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(bucket.isFuture ? AnyShapeStyle(.tertiary) : AnyShapeStyle(strong
                    ? themeManager.onEffectiveTint : Color.primary))
            if bucket.seconds > 0, !dynamicTypeSize.isAccessibilitySize {
                Text("\(Int((bucket.seconds / 60).rounded()))m")
                    .font(.caption2)
                    .foregroundStyle(strong ? themeManager.onEffectiveTint.opacity(0.85) : Color.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .frame(maxWidth: .infinity, minHeight: monthCellHeight)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(bucket.isFuture ? Color.clear : dayShade(bucket.seconds))
        )
        .overlay {
            if isToday {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(themeManager.effectiveTint, lineWidth: 2)
            }
        }
    }

    /// History-Month's four steps: none, under half an hour, under an hour, more.
    private func dayShade(_ seconds: Double) -> Color {
        let tint = themeManager.effectiveTint
        switch seconds {
        case ..<1: return themeManager.appTheme.glassFill(0.08)
        case ..<1_800: return tint.opacity(0.18)
        case ..<3_600: return tint.opacity(0.42)
        default: return tint.opacity(0.75)
        }
    }

    /// History-Year: hours a month, the works finished in it over each bar.
    ///
    /// The board stacks finished works *inside* the hours bar, two units on one
    /// scale; here the bar is hours alone and the finish count is its label.
    private var yearChart: some View {
        let tint = themeManager.effectiveTint
        let latest = timeline.buckets.last { !$0.isFuture }?.start
        return VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(timeline.buckets) { bucket in
                    BarMark(
                        x: .value("Month", bucket.start, unit: .month),
                        y: .value("Hours", bucket.seconds / 3_600)
                    )
                    .foregroundStyle(bucket.start == latest ? tint : tint.opacity(0.35))
                    .cornerRadius(3)
                    .annotation(position: .top, spacing: 2) {
                        if bucket.finishedCount > 0 {
                            Text("\(bucket.finishedCount)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(themeManager.accentInk)
                        }
                    }
                }
                RuleMark(y: .value("Baseline", 0.0))
                    .foregroundStyle(Color.primary.opacity(0.15))
                    .lineStyle(StrokeStyle(lineWidth: 0.5))
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
                }
            }
            .frame(height: chartHeight)

            HStack(spacing: 14) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(tint.opacity(0.35))
                        .frame(width: 10, height: 10)
                    Text("Hours read")
                }
                HStack(spacing: 4) {
                    Text("3").fontWeight(.semibold).foregroundStyle(themeManager.accentInk)
                    Text("Works finished")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}

/// A sitting's chapters as board 02's cells: read before in grey, this sitting
/// in the app colour, still to come pale. Past thirty chapters the gaps close
/// and the cells read as three runs, which is what they are at that size.
private struct ChapterCells: View {
    let span: ReadingHistoryTimeline.ChapterSpan
    let current: Color

    @ScaledMetric(relativeTo: .caption) private var height: CGFloat = 6

    var body: some View {
        Canvas { context, size in
            let total = CGFloat(span.total)
            let gap: CGFloat = span.total > 30 ? 0 : 2
            let cell = min(28, max(0, (size.width - gap * (total - 1)) / total))
            for index in 0..<span.total {
                let chapter = index + 1
                let colour: Color = chapter < span.first
                    ? Color.secondary.opacity(0.55)
                    : chapter <= span.last ? current : Color.primary.opacity(0.1)
                let rect = CGRect(x: CGFloat(index) * (cell + gap), y: 0, width: cell, height: size.height)
                context.fill(Path(roundedRect: rect, cornerRadius: min(2, cell / 2)), with: .color(colour))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
