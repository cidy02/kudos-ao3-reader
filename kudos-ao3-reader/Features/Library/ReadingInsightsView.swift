import SwiftData
import SwiftUI

/// Artboard **07** / `Insights.dc.html` — Reading Insights Redesign (T-497).
///
/// Features four tabs: Overview, Taste, Habits, and Library, with a shared
/// `InsightsTop` header controlling the period (Month/Year, ‹, ›) and ••• options.
/// Local-only calculation on `ReadingSession` and `SavedWork`.
struct ReadingInsightsDestination: Hashable {}

struct ReadingInsightsView: View {
    @Environment(\.modelContext) private var context
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
    @Environment(PrivacyGate.self) private var gate
    @AppStorage("hideMature") private var hideMature: Bool = false

    let works: [SavedWork]

    private var effectiveWorks: [SavedWork] {
        HomeReadingStats.insightsWorks(from: works, gate: gate, hideMature: hideMature)
    }

    @State private var selectedTab: Tab = .overview
    @State private var range: RangeMode = .month
    @State private var referenceDate: Date = Date()

    @State private var insights = ReadingInsights()
    @State private var tasteInsights: ReadingTasteInsights?
    @State private var habitsInsights: ReadingHabitsInsights?
    @State private var libraryInsights: ReadingLibraryInsights?
    @State private var libraryStats: ReadingStatistics?

    @State private var rankTasteByWorks: Bool = false
    @State private var showingOptionsSheet: Bool = false
    @State private var showingHowCountedSheet: Bool = false
    @State private var finishedWorksInPeriod: [SavedWork] = []

    @AppStorage("kudos.insights.discreetMode") private var discreetMode: Bool = false
    @AppStorage("kudos.insights.hideReadingTime") private var hideReadingTime: Bool = false

    enum Tab: String, CaseIterable, Identifiable {
        case overview
        case taste
        case habits
        case library

        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview: "Overview"
            case .taste: "Taste"
            case .habits: "Habits"
            case .library: "Library"
            }
        }
    }

    enum RangeMode: String, CaseIterable, Identifiable {
        case month
        case year

        var id: String { rawValue }

        var title: String {
            switch self {
            case .month: "Month"
            case .year: "Year"
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
        VStack(spacing: 0) {
            // Pinned header with tabs and period controls
            headerView

            // Main scrollable content
            ScrollView {
                VStack(spacing: 14) {
                    switch selectedTab {
                    case .overview:
                        overviewContent
                    case .taste:
                        tasteContent
                    case .habits:
                        habitsContent
                    case .library:
                        libraryContent
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .appThemedScroll()
        }
        .background(theme.appTheme.cardBackdrop.ignoresSafeArea())
        .navigationTitle("Reading Insights")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingOptionsSheet = true
                    } label: {
                        Label("Insights Options…", systemImage: "gearshape")
                    }

                    Button {
                        showingHowCountedSheet = true
                    } label: {
                        Label("How Reading Insights Are Counted", systemImage: "info.circle")
                    }

                    ShareLink(
                        item: exportHistoryText(),
                        subject: Text("Reading Insights Export"),
                        message: Text("Export of Reading Insights from Kudos")
                    ) {
                        Label("Export Reading History…", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                }
                .accessibilityLabel("More: options, export, how this is counted")
            }
        }
        .task(id: "\(range.rawValue)-\(referenceDate.timeIntervalSince1970)-\(hideMature)-\(gate.revealAll)-\(gate.revealedIDs.count)") {
            reload()
        }
        .refreshable {
            reload()
        }
        .sheet(isPresented: $showingOptionsSheet) {
            InsightsOptionsSheet(
                exportText: exportHistoryText(),
                onShowHowCounted: {
                    showingOptionsSheet = false
                    showingHowCountedSheet = true
                },
                onReset: reload
            )
        }
        .sheet(isPresented: $showingHowCountedSheet) {
            HowInsightsAreCountedSheet()
        }
    }

    // MARK: - Header View (`InsightsTop`)

    private var headerView: some View {
        VStack(spacing: 10) {
            // Tab segment pill (Overview / Taste / Habits / Library)
            HStack(spacing: 0) {
                ForEach(Tab.allCases) { tab in
                    let isSelected = selectedTab == tab
                    Button {
                        selectedTab = tab
                    } label: {
                        Text(tab.title)
                            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 28)
                            .background(
                                isSelected ? theme.appTheme.cardSurface : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .shadow(
                                color: isSelected ? Color.black.opacity(0.08) : Color.clear,
                                radius: 4,
                                y: 1
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(tab.title) tab")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(2)
            .background(Color.primary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 4)

            // Period selector strip (Period title, subtitle, Range picker, ‹, ›)
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(periodTitle)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(periodSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Range picker (Month / Year)
                Menu {
                    Picker("Range", selection: $range) {
                        ForEach(RangeMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(range.title)
                            .font(.system(size: 14, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: 32)
                    .background(Color.primary.opacity(0.08))
                    .foregroundStyle(.primary)
                    .clipShape(Capsule())
                }

                // Previous period button ‹
                Button {
                    previousPeriod()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Previous period")

                // Next period button ›
                Button {
                    nextPeriod()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(canGoNext ? Color.primary : Color.secondary.opacity(0.3))
                        .frame(width: 32, height: 32)
                        .background(canGoNext ? Color.primary.opacity(0.08) : Color.primary.opacity(0.04))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canGoNext)
                .accessibilityLabel("Next period")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        }
        .background(theme.appTheme.cardBackdrop)
    }

    // MARK: - Overview Tab Content

    @ViewBuilder
    private var overviewContent: some View {
        WordsReadHeroCard(
            insights: insights,
            periodName: periodTitle,
            previousPeriodName: previousPeriodShortName,
            hideReadingTime: hideReadingTime,
            totalDaysElapsed: totalDaysElapsedInPeriod,
            palette: theme.scopePalette
        )

        WordsPerDayCard(
            days: insights.dailyWords,
            totalDays: totalDaysElapsedInPeriod
        )

        WhereTheWordsWentCard(
            fandoms: insights.fandomWordsShares,
            discreetMode: discreetMode
        )

        ReadingAndListeningCard(
            readingSeconds: insights.readingSeconds,
            hideReadingTime: hideReadingTime
        )

        RecordsGridCard(
            streakDays: insights.longestStreakDays,
            biggestDayWords: insights.biggestDay?.words ?? 0,
            medianSessionSeconds: insights.medianSessionSeconds,
            wordsPerHour: insights.wordsPerHour,
            hideReadingTime: hideReadingTime
        )

        LengthOfWhatYouReadCard(mix: insights.lengthMix)

        if !finishedWorksInPeriod.isEmpty {
            FinishedInPeriodSection(
                works: finishedWorksInPeriod,
                discreetMode: discreetMode
            )
        }

        // How Reading Insights Are Counted button
        Button {
            showingHowCountedSheet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "info.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)

                Text("How Reading Insights Are Counted")
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(theme.appTheme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Taste Tab Content

    @ViewBuilder
    private var tasteContent: some View {
        if let taste = tasteInsights {
            YourUsualFicCard(taste: taste, discreetMode: discreetMode)

            TasteFandomsCard(
                fandoms: taste.fandoms,
                rankByWorks: rankTasteByWorks,
                onToggleRank: { rankTasteByWorks.toggle() },
                discreetMode: discreetMode
            )

            TasteRelationshipsCard(
                relationships: taste.relationships,
                shipConcentrations: taste.shipConcentrations,
                discreetMode: discreetMode
            )

            if !taste.characters.isEmpty {
                TasteCharactersCard(
                    characters: taste.characters,
                    discreetMode: discreetMode
                )
            }

            if !taste.tags.isEmpty {
                TasteTagsCard(
                    tags: taste.tags,
                    oftenTogether: taste.oftenTogether,
                    discreetMode: discreetMode
                )
            }

            TasteRatingsCategoriesWarningsCard(
                ratings: taste.ratings,
                categories: taste.categories,
                warnings: taste.warnings
            )

            if !taste.yearCounts.isEmpty {
                TasteWhenPostedCard(
                    yearCounts: taste.yearCounts,
                    medianYear: taste.medianYear
                )
            }

            TasteCrossoversLanguagesGrid(
                crossoverCount: taste.crossoverCount,
                totalWorks: taste.totalWorksCount,
                languages: taste.languages
            )
        } else {
            Text("Nothing read in \(periodTitle) yet, so there is no taste to show.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        }
    }

    // MARK: - Habits Tab Content

    @ViewBuilder
    private var habitsContent: some View {
        if let habits = habitsInsights {
            HabitsTimeOfDayCard(
                hourly: habits.hourlyDuration,
                lateNightDuration: habits.lateNightDuration,
                lateNightSharePercent: habits.lateNightSharePercent
            )

            HabitsCalendarCard(
                days: habits.calendarDays,
                longestStreak: habits.longestStreak
            )

            HabitsSittingsCard(
                sittings: habits.sittingBuckets,
                typicalSeconds: habits.typicalSittingSeconds
            )

            if habits.savedToOpenedMedianDays != nil || habits.openedToFinishedMedianDays != nil {
                HabitsSavedToFinishedCard(
                    savedToOpenedDays: habits.savedToOpenedMedianDays,
                    openedToFinishedDays: habits.openedToFinishedMedianDays
                )
            }

            HabitsRereadsCard(rereads: habits.rereads, discreetMode: discreetMode)

            if !habits.fandomTimeline.isEmpty {
                HabitsFandomTimelineCard(lanes: habits.fandomTimeline, discreetMode: discreetMode)
            }

            if habits.stoppedCount > 0 {
                HabitsStoppedCard(
                    stoppedCount: habits.stoppedCount,
                    medianProgress: habits.stoppedMedianProgress,
                    commonTags: habits.commonStopTags,
                    discreetMode: discreetMode
                )
            }
        }
    }

    // MARK: - Library Tab Content

    @ViewBuilder
    private var libraryContent: some View {
        if let lib = libraryInsights, let stats = libraryStats {
            LibraryUnreadCard(
                unreadWords: lib.unreadWords,
                unreadCount: lib.unreadWorksCount,
                monthsToClear: lib.monthsToClear,
                addedWords: lib.addedWordsInPeriod,
                readWords: lib.readWordsInPeriod
            )

            LibraryWhereEverythingStandsCard(partition: lib.statuses)

            if let candidate = lib.stillReadingCandidate {
                LibraryStillReadingCard(
                    candidate: candidate,
                    discreetMode: discreetMode,
                    onStillReading: {
                        WorkLifecycle.keepInProgress(candidate.work, in: context)
                        reload()
                    }
                )
            }

            LibraryWIPFreshnessCard(freshness: lib.wipFreshness)

            if lib.noLongerOnAO3Count > 0 {
                LibraryNoLongerOnAO3Card(
                    count: lib.noLongerOnAO3Count,
                    words: lib.noLongerOnAO3Words,
                    lastCopies: lib.noLongerOnAO3LastCopies
                )
            }

            if let kudos = lib.kudosLeftPercent, let bookmarked = lib.bookmarkedPercent {
                LibraryFeedbackCard(kudosLeftPercent: kudos, bookmarkedPercent: bookmarked)
            }

            LibraryPreservedStatsCard(stats: stats, discreetMode: discreetMode)
        }
    }

    // MARK: - Period Calculation & Navigation

    private var calendar: Calendar { .current }

    private var periodTitle: String {
        switch range {
        case .month:
            return Self.monthYearFormatter.string(from: referenceDate)
        case .year:
            return Self.yearFormatter.string(from: referenceDate)
        }
    }

    private var periodSubtitle: String {
        switch range {
        case .month:
            let isCurrentMonth = calendar.isDate(referenceDate, equalTo: Date(), toGranularity: .month)
            let endDay = isCurrentMonth
                ? calendar.component(.day, from: Date())
                : (calendar.range(of: .day, in: .month, for: referenceDate)?.count ?? 30)
            let monthName = Self.shortMonthFormatter.string(from: referenceDate)
            let prevDate = calendar.date(byAdding: .month, value: -1, to: referenceDate) ?? referenceDate
            let prevMonthName = Self.shortMonthFormatter.string(from: prevDate)
            return "1–\(endDay) \(monthName) · vs \(prevMonthName)"
        case .year:
            let yr = Self.yearFormatter.string(from: referenceDate)
            let prevDate = calendar.date(byAdding: .year, value: -1, to: referenceDate) ?? referenceDate
            let prevYr = Self.yearFormatter.string(from: prevDate)
            return "\(yr) · vs \(prevYr)"
        }
    }

    private var previousPeriodShortName: String {
        let prevDate = calendar.date(byAdding: range.component, value: -1, to: referenceDate) ?? referenceDate
        switch range {
        case .month:
            return Self.shortMonthFormatter.string(from: prevDate)
        case .year:
            return Self.yearFormatter.string(from: prevDate)
        }
    }

    private var totalDaysElapsedInPeriod: Int {
        switch range {
        case .month:
            let isCurrentMonth = calendar.isDate(referenceDate, equalTo: Date(), toGranularity: .month)
            return isCurrentMonth
                ? calendar.component(.day, from: Date())
                : (calendar.range(of: .day, in: .month, for: referenceDate)?.count ?? 30)
        case .year:
            let isCurrentYear = calendar.isDate(referenceDate, equalTo: Date(), toGranularity: .year)
            return isCurrentYear
                ? calendar.ordinality(of: .day, in: .year, for: Date()) ?? 365
                : (calendar.range(of: .day, in: .year, for: referenceDate)?.count ?? 365)
        }
    }

    private var canGoNext: Bool {
        let component = range.component
        let refStart = calendar.dateInterval(of: component, for: referenceDate)?.start ?? referenceDate
        let nowStart = calendar.dateInterval(of: component, for: Date())?.start ?? Date()
        return refStart < nowStart
    }

    private func previousPeriod() {
        referenceDate = calendar.date(byAdding: range.component, value: -1, to: referenceDate) ?? referenceDate
    }

    private func nextPeriod() {
        guard canGoNext else { return }
        referenceDate = calendar.date(byAdding: range.component, value: 1, to: referenceDate) ?? referenceDate
    }

    // MARK: - Reload Data

    private func reload() {
        let component = range.component
        guard let currentInterval = calendar.dateInterval(of: component, for: referenceDate),
              let earlierDate = calendar.date(byAdding: component, value: -1, to: referenceDate),
              let previousInterval = calendar.dateInterval(of: component, for: earlierDate)
        else { return }

        let figures = ReadingLogService.insights(
            for: currentInterval,
            previousPeriod: previousInterval,
            works: effectiveWorks,
            calendar: calendar,
            context: context
        )

        insights = figures

        let allHistory = (try? context.fetch(FetchDescriptor<ReadingSession>())) ?? []
        let allFacts = ReadingLogService.facts(from: allHistory, works: effectiveWorks, history: allHistory)
        let periodFacts = allFacts.filter { currentInterval.contains($0.startedAt) }

        let readWorkIDs = Set(periodFacts.map(\.workID))
        let worksInPeriod = effectiveWorks.filter { readWorkIDs.contains($0.id) }

        // An empty period has no taste; the Taste tab shows its empty state
        // rather than all-time rankings under the period title.
        tasteInsights = worksInPeriod.isEmpty ? nil : ReadingTasteInsights.make(
            works: worksInPeriod,
            facts: periodFacts
        )

        habitsInsights = ReadingHabitsInsights.make(
            works: effectiveWorks,
            facts: periodFacts,
            allFacts: allFacts,
            calendar: calendar
        )

        libraryInsights = ReadingLibraryInsights.make(
            works: effectiveWorks,
            facts: periodFacts,
            periodInterval: currentInterval,
            periodMonths: range == .year ? 12 : 1,
            calendar: calendar
        )

        libraryStats = ReadingStatistics(works: effectiveWorks, now: Date(), calendar: calendar)

        finishedWorksInPeriod = effectiveWorks.filter { w in
            w.isFinished && periodFacts.contains { $0.workID == w.id && $0.didFinish }
        }
    }

    // MARK: - Actions

    /// The period's aggregate lines; no work is named.
    private func exportHistoryText() -> String {
        """
        Kudos Reading Insights Export
        Period: \(periodTitle) (\(periodSubtitle))
        Words read: \(insights.totalWordsRead)
        Hours read: \(ReadingInsights.hoursLabel(insights.totalSeconds))
        Works finished: \(insights.finishedWorksCount)
        Reading days: \(insights.readingDaysCount)
        """
    }

    // MARK: - Date Formatters

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("LLLL y")
        return f
    }()

    private static let shortMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("LLL")
        return f
    }()

    private static let yearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("y")
        return f
    }()
}
