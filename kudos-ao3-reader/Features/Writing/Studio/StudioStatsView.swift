import SwiftUI

/// Writing Studio's Stats section (board `Studio-Stats`): AO3's stats page as it
/// stands, plus the history AO3 doesn't keep. Each time the page loads, Kudos saves
/// the totals (`StudioStatsHistoryStore`), and the changes, sparklines and Kudos per
/// Week are drawn from that. The year filter is AO3's own: it loads that year's page
/// and reads that year's saved history.
///
/// Pads its own sides with `SubjectMetrics.gutter`; the shell should not pad again.
struct StudioStatsView: View {
    @Environment(AO3AuthService.self) private var auth
    @Environment(AppRouter.self) private var router
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accentFill) private var accentFill

    @State private var stats: AO3UserStats?
    @State private var history: [StudioStatsSnapshot] = []
    @State private var years: [Int] = []
    @State private var selectedYear: Int?
    @State private var sort: AO3UserStats.Sort = .kudos
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var reloadToken = 0
    @State private var activeRequestID: UUID?

    private static let chartHeight: CGFloat = 104
    private static let shownWeeks = 12

    init() {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if auth.isLoggedIn {
                    signedInContent
                } else {
                    ContentUnavailableView(
                        "Stats need an AO3 account",
                        systemImage: "chart.bar",
                        description: Text("Documents, drafts and word counts work without one.")
                    )
                }
            }
            .padding(.horizontal, SubjectMetrics.gutter)
            .padding(.bottom, 24)
        }
        .refreshable { await load(clearing: false) }
        .task(id: loadKey) { await load(clearing: true) }
    }

    // MARK: Content

    @ViewBuilder
    private var signedInContent: some View {
        periodRow
        if let errorMessage { errorCard(errorMessage) }
        if isLoading && stats == nil {
            ProgressView("Loading stats…")
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let stats, stats.isEmpty {
            ContentUnavailableView(
                selectedYear == nil ? "No stats yet" : "No stats for this year",
                systemImage: "chart.bar",
                description: Text("AO3 has no posted-work statistics for this selection.")
            )
        } else if let stats {
            totalsGrid(stats)
        }
        if stats?.isEmpty != true { weeklyPanel }
        if let stats, !stats.isEmpty { worksSection(stats) }
    }

    private var yearHistory: [StudioStatsSnapshot] {
        StudioStatsHistory.snapshots(history, year: selectedYear)
    }

    private var baseline: StudioStatsSnapshot? {
        StudioStatsHistory.baseline(yearHistory, now: Date())
    }

    // MARK: Period

    private var periodRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                periodButton("All Years", year: nil)
                ForEach(years, id: \.self) { periodButton(String($0), year: $0) }
            }
        }
        .horizontalScrollViewport()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Period")
    }

    private func periodButton(_ title: String, year: Int?) -> some View {
        let isSelected = selectedYear == year
        return Button { selectedYear = year } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .frame(minHeight: 44)
                .background {
                    if isSelected {
                        Capsule().fill(.accentFill)
                    } else {
                        Capsule().fill(theme.appTheme.glassFill(0.09))
                            .overlay(Capsule().stroke(theme.appTheme.glassStroke(0.13), lineWidth: 0.5))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Totals

    private func totalsGrid(_ stats: AO3UserStats) -> some View {
        let base = baseline
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 10, alignment: .top),
            count: dynamicTypeSize.isAccessibilitySize ? 1 : 2
        )
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(StudioStatsMetric.allCases, id: \.self) { metric in
                if let value = metric.total(in: stats) {
                    StudioStatsTotalCard(
                        metric: metric,
                        value: value,
                        change: StudioStatsHistory.change(value, since: base?.total(metric)),
                        since: base?.date,
                        sparkline: StudioStatsHistory.sparkline(yearHistory, metric: metric)
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Totals")
    }

    // MARK: Kudos per Week

    private var weeklyPanel: some View {
        let all = StudioStatsHistory.weeks(yearHistory, metric: .kudos)
        let shown = Array(all.suffix(Self.shownWeeks))
        let best = StudioStatsHistory.best(all)
        return VStack(alignment: .leading, spacing: 10) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) { weeklyTitle; bestLabel(best) }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    weeklyTitle
                    Spacer(minLength: 8)
                    bestLabel(best)
                }
            }
            if shown.isEmpty {
                Text(StudioStatsHistory.emptyChartMessage(yearHistory))
                    .font(.subheadline)
            } else {
                bars(shown, best: best)
            }
            Text("AO3 keeps no history: Kudos saves your totals each time you look, so charts start the week you began.")
                .font(.caption)
                .foregroundStyle(.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .subjectPanel(cornerRadius: 18)
    }

    private var weeklyTitle: some View {
        Text("Kudos per Week")
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func bestLabel(_ best: StudioStatsWeek?) -> some View {
        if let best {
            Text("Best: \(best.gain.formatted()), week of \(best.start.studioStatsShort)")
                .font(.footnote)
                .foregroundStyle(.secondaryInk)
        }
    }

    private func bars(_ weeks: [StudioStatsWeek], best: StudioStatsWeek?) -> some View {
        let top = max(1, weeks.map { $0.gain }.max() ?? 1)
        let last = weeks.count - 1
        return VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barFill(isLast: index == last, isBest: week.start == best?.start))
                        .opacity(week.isEstimate ? 0.5 : 1)
                        .frame(height: max(3, CGFloat(week.gain) / CGFloat(top) * Self.chartHeight))
                }
            }
            .frame(height: Self.chartHeight + 6, alignment: .bottom)
            HStack {
                Text(weeks[0].start.studioStatsShort)
                Spacer()
                Text(Calendar.current.isDate(weeks[last].start, equalTo: Date(), toGranularity: .weekOfYear)
                    ? "This week" : weeks[last].start.studioStatsShort)
            }
            .font(.caption2)
            .foregroundStyle(.secondaryInk)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chartLabel(weeks, best: best))
        .accessibilityAddTraits(.isImage)
    }

    private func barFill(isLast: Bool, isBest: Bool) -> AnyShapeStyle {
        if isLast { return AnyShapeStyle(accentFill) }
        if isBest { return AnyShapeStyle(accentFill.opacity(0.6)) }
        return AnyShapeStyle(Color.primary.opacity(0.2))
    }

    private func chartLabel(_ weeks: [StudioStatsWeek], best: StudioStatsWeek?) -> String {
        var text = "Kudos per week for \(weeks.count) \(weeks.count == 1 ? "week" : "weeks"), "
            + "latest \(weeks[weeks.count - 1].gain.formatted())"
        if let best { text += ", best \(best.gain.formatted()) the week of \(best.start.studioStatsShort)" }
        if weeks.contains(where: \.isEstimate) { text += ". Weeks you didn't open Kudos are estimated." }
        return text
    }

    // MARK: Your Works

    private func worksSection(_ stats: AO3UserStats) -> some View {
        let works = stats.sections(grouping: .flat, sortedBy: sort).first?.works ?? []
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Your Works")
                    .font(.title3.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Text(works.count.formatted())
                    .font(.subheadline)
                    .foregroundStyle(.secondaryInk)
            }
            StudioStatsWorksTable(works: works, baseline: baseline, sort: $sort) { work in
                router.open(AO3Client.workURL(workID: work.id))
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondaryInk)
            Button("Try Again") { reloadToken += 1 }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .subjectPanel()
    }

    // MARK: Loading

    private var loadKey: String {
        "\(auth.sessionGeneration)|\(auth.username ?? "")|\(selectedYear.map(String.init) ?? "all")|\(reloadToken)"
    }

    private func load(clearing: Bool) async {
        guard auth.isLoggedIn, let account = auth.username else { return }
        let store = StudioStatsHistoryStore(account: account)
        let year = selectedYear
        let requestID = UUID()
        activeRequestID = requestID
        isLoading = true
        errorMessage = nil
        if clearing { stats = nil }
        defer {
            if activeRequestID == requestID { isLoading = false }
        }
        // Saved history shows at once, and stays if AO3 can't be reached.
        let saved = await Task.detached(priority: .utility) { store.load() }.value
        guard activeRequestID == requestID, !Task.isCancelled else { return }
        history = saved
        do {
            let loaded = try await auth.loadUserStats(year: year)
            guard activeRequestID == requestID, !Task.isCancelled else { return }
            stats = loaded
            if !loaded.availableYears.isEmpty { years = loaded.availableYears.sorted(by: >) }
            // A page with no posted works has no totals worth saving.
            if !loaded.isEmpty {
                history = await Task.detached(priority: .utility) {
                    store.record(loaded, year: year)
                }.value
            }
        } catch is CancellationError {
            return
        } catch {
            guard activeRequestID == requestID, !Task.isCancelled else { return }
            errorMessage = UserFacingError.message(for: error)
        }
    }
}
