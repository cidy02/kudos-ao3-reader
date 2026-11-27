import SwiftUI

/// Writing Studio's Stats section (board `Studio-Stats`): AO3's stats page as it
/// stands, plus the history AO3 doesn't keep. Each time the page is loaded from
/// AO3, Kudos saves the totals (`StudioStatsHistoryStore`), and the changes,
/// sparklines and Kudos per Week are drawn from that. The year filter is AO3's
/// own: it loads that year's page and reads that year's saved history.
///
/// A page is asked of AO3 once, then again only on pull to refresh, Try Again,
/// a sign-in or sign-out, the first look of a new local day, or after
/// `StudioStatsFreshness.window`. Opening this section again inside that window
/// shows the page already loaded, on the year filter last picked this sign-in.
/// A reload never clears numbers that are already on screen.
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
    /// Bumps when the reader picks a year, so the body reads the cache again.
    /// The year itself lives in `StudioStatsPageCache`: this view is recreated
    /// whenever Stats is shown.
    @State private var yearRevision = 0
    @State private var sort: AO3UserStats.Sort = .kudos
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var reloadToken = 0
    @State private var activeRequestID: UUID?
    /// Which account, sign-in and year the memory above belongs to. A mismatch
    /// hides it, so a year change or a new sign-in never shows the previous page.
    @State private var statsScope: Scope?
    @State private var historyScope: Scope?
    @State private var yearsScope: Scope?
    @State private var errorScope: Scope?

    private struct Scope: Equatable {
        var account: String
        var session: Int
        var year: Int?
    }

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
        .refreshable { await load(force: true) }
        .task(id: loadKey) { await load(force: false) }
        .task(id: reloadToken) {
            guard reloadToken > 0 else { return }
            await load(force: true)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var signedInContent: some View {
        periodRow
        if let visibleError { errorCard(visibleError) }
        if isLoading && visibleStats == nil {
            ProgressView("Loading stats…")
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let stats = visibleStats, stats.isEmpty {
            ContentUnavailableView(
                selectedYear == nil ? "No stats yet" : "No stats for this year",
                systemImage: "chart.bar",
                description: Text("AO3 has no posted-work statistics for this selection.")
            )
        } else if let stats = visibleStats {
            totalsGrid(stats)
        }
        if visibleStats?.isEmpty != true { weeklyPanel }
        if let stats = visibleStats, !stats.isEmpty { worksSection(stats) }
    }

    private var yearHistory: [StudioStatsSnapshot] {
        guard historyReady else { return [] }
        return StudioStatsHistory.snapshots(history, year: selectedYear)
    }

    /// This sign-in's saved history has been read. Until then the chart must not
    /// say it has nothing: the file may already hold a year of totals.
    private var historyReady: Bool { matchesAccount(historyScope) }

    private var visibleStats: AO3UserStats? {
        guard matches(statsScope) else { return nil }
        return stats
    }

    private var visibleYears: [Int] {
        guard matchesAccount(yearsScope) else { return [] }
        return years
    }

    private var visibleError: String? {
        guard matches(errorScope) else { return nil }
        return errorMessage
    }

    private func matches(_ scope: Scope?) -> Bool {
        guard matchesAccount(scope) else { return false }
        return scope?.year == selectedYear
    }

    private func matchesAccount(_ scope: Scope?) -> Bool {
        guard let scope, let account = auth.username else { return false }
        return scope.account == account && scope.session == auth.sessionGeneration
    }

    private var baseline: StudioStatsSnapshot? {
        StudioStatsHistory.baseline(yearHistory, now: Date())
    }

    // MARK: Period

    private var periodRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                periodButton("All Years", year: nil)
                ForEach(visibleYears, id: \.self) { periodButton(String($0), year: $0) }
            }
        }
        .horizontalScrollViewport()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Period")
    }

    private func periodButton(_ title: String, year: Int?) -> some View {
        let isSelected = selectedYear == year
        return Button {
            if let account = auth.username {
                StudioStatsPageCache.rememberYear(year, account: account)
            }
            yearRevision += 1
        } label: {
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
            if !historyReady {
                EmptyView()
            } else if shown.isEmpty {
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
        .accessibilityLabel(StudioStatsHistory.spokenChart(weeks, best: best))
        .accessibilityAddTraits(.isImage)
    }

    private func barFill(isLast: Bool, isBest: Bool) -> AnyShapeStyle {
        if isLast { return AnyShapeStyle(accentFill) }
        if isBest { return AnyShapeStyle(accentFill.opacity(0.6)) }
        return AnyShapeStyle(Color.primary.opacity(0.2))
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

    /// All Years until the reader picks one. Remembered for this account so a
    /// return to the section does not ask AO3 for a different page.
    private var selectedYear: Int? {
        _ = yearRevision
        guard let account = auth.username else { return nil }
        return StudioStatsPageCache.rememberedYear(account: account)
    }

    private var loadKey: String {
        "\(auth.sessionGeneration)|\(auth.username ?? "")|\(selectedYear.map(String.init) ?? "all")"
    }

    private func load(force: Bool) async {
        guard auth.isLoggedIn, let account = auth.username else {
            stats = nil
            statsScope = nil
            history = []
            historyScope = nil
            years = []
            yearsScope = nil
            errorMessage = nil
            errorScope = nil
            isLoading = false
            StudioStatsPageCache.removeAll()
            return
        }
        let year = selectedYear
        let generation = auth.sessionGeneration
        let key = StudioStatsPageCache.Key(account: account, sessionGeneration: generation, year: year)
        let requestID = UUID()
        activeRequestID = requestID
        let store = StudioStatsHistoryStore(account: account)
        // Show the page this sign-in already has before the disk read, so coming
        // back is not a blank spinner.
        if let cached = StudioStatsPageCache.entry(for: key) {
            apply(cached.stats, account: account, generation: generation, year: year)
        }
        if visibleStats == nil { isLoading = true }
        guard let savedHistory = await rememberHistory(
            store, account: account, generation: generation, requestID: requestID
        ) else { return }
        let lastLook = savedHistory.filter { $0.year == year }.map(\.date).max()

        if let cached = StudioStatsPageCache.entry(for: key),
           !StudioStatsFreshness.shouldFetch(
               fetchedAt: cached.fetchedAt, force: force, lastSnapshot: lastLook
           ) {
            apply(cached.stats, account: account, generation: generation, year: year)
            errorMessage = nil
            isLoading = false
            return
        }

        // A page this sign-in already loaded stays on screen while a newer one arrives.
        if let cached = StudioStatsPageCache.entry(for: key) {
            apply(cached.stats, account: account, generation: generation, year: year)
        }
        isLoading = true
        errorMessage = nil
        defer {
            if activeRequestID == requestID { isLoading = false }
        }
        // The moment this load was decided, not when it finished: a slower
        // earlier load must not overwrite the day's snapshot.
        let started = Date()
        if force {
            // Lifts a maintenance hold for this one probe, as every other pull to refresh does.
            await AO3Client.shared.invalidateCachedResponses()
        }
        do {
            let loaded = try await auth.loadUserStats(year: year)
            guard activeRequestID == requestID, !Task.isCancelled else { return }
            guard auth.sessionGeneration == generation,
                  auth.username == account else { return }
            apply(loaded, account: account, generation: generation, year: year)
            StudioStatsPageCache.store(loaded, for: key, at: Date())
            // A page with no posted works has no totals worth saving.
            guard !loaded.isEmpty else { return }
            let saved = await Task.detached(priority: .utility) {
                store.record(loaded, year: year, at: started)
            }.value
            guard activeRequestID == requestID, !Task.isCancelled else { return }
            history = saved
            historyScope = Scope(account: account, session: generation, year: nil)
        } catch is CancellationError {
            return
        } catch {
            guard activeRequestID == requestID, !Task.isCancelled else { return }
            errorMessage = UserFacingError.message(for: error)
            errorScope = Scope(account: account, session: generation, year: year)
        }
    }

    private func apply(_ loaded: AO3UserStats, account: String, generation: Int, year: Int?) {
        stats = loaded
        statsScope = Scope(account: account, session: generation, year: year)
        if !loaded.availableYears.isEmpty {
            years = loaded.availableYears.sorted(by: >)
            yearsScope = Scope(account: account, session: generation, year: nil)
        }
    }

    /// Saved history shows at once, and stays if AO3 can't be reached.
    /// Nil when this load has been superseded.
    private func rememberHistory(
        _ store: StudioStatsHistoryStore, account: String, generation: Int, requestID: UUID
    ) async -> [StudioStatsSnapshot]? {
        let saved = await Task.detached(priority: .utility) { store.load() }.value
        guard activeRequestID == requestID, !Task.isCancelled else { return nil }
        history = saved
        historyScope = Scope(account: account, session: generation, year: nil)
        return saved
    }
}
