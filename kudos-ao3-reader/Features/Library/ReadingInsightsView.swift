import Combine
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
    // The app-wide key (Settings, Home, Library); "hideMature" was never written, so the
    // gate here was always off.
    @AppStorage("hideMatureContent") private var hideMature = true

    /// The UNFILTERED library (every non-deleted work). The view applies the
    /// queue-only / Hide Mature gate itself: given an already-filtered list it
    /// could not tell which sessions belong to hidden works.
    let libraryWorks: [SavedWork]

    /// View-level scope, re-lock, subtitle and Hidden cache state.
    @State private var scopeState = ReadingInsightsScopeState()
    @State private var lastReloadKey = ""
    @State private var hasLoadedOnce = false

    /// What the figures and exports on screen count: everything but hidden works, or
    /// (revealed, Include Hidden on) everything.
    private var screenScope: InsightsScope {
        scopeState.screenScope(hideMature: hideMature, revealed: gate.revealAll)
    }

    private func selection(_ scope: InsightsScope) -> InsightsScopeSelection {
        HomeReadingStats.insightsScope(scope, from: libraryMirror.works, hideMature: hideMature, revealed: gate.revealAll)
    }

    @State private var selectedTab: Tab = .overview
    @State private var range: RangeMode = .month
    @State private var referenceDate: Date = Date()

    @State private var insights = ReadingInsights()
    @State private var tasteInsights: ReadingTasteInsights?
    @State private var habitsInsights: ReadingHabitsInsights?
    @State private var chapterTiming = InsightsProvenance.ChapterTimingFigure()
    @State private var libraryInsights: ReadingLibraryInsights?
    @State private var libraryStats: ReadingStatistics?

    @State private var rankTasteByWorks: Bool = false
    @State private var showingOptionsSheet: Bool = false
    @State private var showingHowCountedSheet: Bool = false
    @State private var finishedWorksInPeriod: [SavedWork] = []
    @State private var discreetMasker: InsightsDiscreetMasker = .empty
    @State private var optionsRevision: Int = 0
    @State private var exportedShareItem: InsightsShareItem?
    @State private var exportFailure: String?
    #if os(macOS)
    @State private var macExportDocument: InsightsExportFileDocument?
    @State private var macExportFormat: InsightsExportFormat = .csv
    @State private var showingMacExporter = false
    #endif

    @AppStorage(InsightsOptions.Keys.discreetMode) private var discreetMode: Bool = false
    @AppStorage(InsightsOptions.Keys.hideReadingTime) private var hideReadingTime: Bool = false
    @AppStorage(InsightsOptions.Keys.countRereads) private var countRereads: Bool = true
    @AppStorage(InsightsOptions.Keys.countReadAloud) private var countReadAloud: Bool = true
    @AppStorage(InsightsOptions.Keys.askAboutUntouched) private var askAboutUntouched: Bool = true
    @AppStorage(InsightsOptions.Keys.untouchedDays)
    private var untouchedDays: Int = InsightsOptions.defaultUntouchedDays

    /// `InsightsReloadDigest` of the library as of the last reload (or the last
    /// relevant save seen while on screen). Part of `reloadKey`, so a change that
    /// moves the figures (an AO3 refresh marking a work Explicit, finishing a work,
    /// a sitting written) reloads them once; a reading-position save does not.
    @State private var libraryDigest = ""
    @State private var reloadCoordinator = InsightsReloadCoordinator()
    /// Always the library the parent last handed over, so a refresh that waited out
    /// its window reads the *current* works, never the array its save arrived with.
    @State private var libraryMirror = LibraryMirror()
    private final class LibraryMirror { var works: [SavedWork] = [] }
    /// Saves arriving while another screen covers this one are ignored; `onAppear`
    /// reloads on return.
    @State private var isOnScreen = false

    private var reloadKey: String {
        InsightsReloadKey.make(
            range: range.rawValue,
            referenceDate: referenceDate,
            hideMature: hideMature,
            revealAll: gate.revealAll,
            includeHidden: scopeState.includeHidden,
            countRereads: countRereads,
            countReadAloud: countReadAloud,
            askAboutUntouched: askAboutUntouched,
            untouchedDays: untouchedDays,
            optionsRevision: optionsRevision,
            libraryCount: libraryWorks.count,
            libraryDigest: libraryDigest
        )
    }

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
        let _ = libraryMirror.works = libraryWorks // refreshed on every body pass
        VStack(spacing: 0) {
            // Pinned header with tabs and period controls
            headerView

            // Main scrollable content
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 14) {
                        if scopeState.mayDisplayLoadedData(hideMature: hideMature, revealed: gate.revealAll) {
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
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
                .appThemedScroll()
                #if DEBUG
                .task {
                    guard DebugLaunchRoute.opensInsightsHidden else { return }
                    try? await Task.sleep(for: .seconds(2))
                    proxy.scrollTo(Self.hiddenSectionID, anchor: .center)
                }
                #endif
            }
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

                    Menu {
                        Button {
                            exportReadingHistory(format: .csv)
                        } label: {
                            Label("Export as CSV", systemImage: "tablecells")
                        }

                        Button {
                            exportReadingHistory(format: .json)
                        } label: {
                            Label("Export as JSON", systemImage: "curlybraces")
                        }
                    } label: {
                        Label("Export Reading History…", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    // Bare glyph: the toolbar draws the glass circle; a custom
                    // filled circle here read as a stuck pressed state.
                    Image(systemName: "ellipsis")
                }
                // Neutral dots like every other toolbar "…" (WorkListMoreMenu).
                .tint(Color.primary)
                .accessibilityLabel("More: options, export, how this is counted")
            }
        }
        .task(id: reloadKey) {
            guard lastReloadKey != reloadKey else { return }
            reload()
        }
        .onAppear {
            isOnScreen = true
            if hasLoadedOnce { reload() }
        }
        .onDisappear {
            isOnScreen = false
            reloadCoordinator.cancel()
        }
        .onChange(of: gate.revealAll) { _, revealed in
            // Synchronously clear hidden state and recompute main figures on re-lock so
            // stale combined mature titles/figures are never painted while waiting for `.task`.
            if scopeState.handleRevealChange(revealed: revealed, hideMature: hideMature) {
                if !revealed { clearMainDisplayState() }
                reload()
            }
        }
        .onChange(of: hideMature) { _, isHiding in
            scopeState.handleHideMatureChange(hideMature: isHiding, revealed: gate.revealAll)
            if isHiding && !gate.revealAll { clearMainDisplayState() }
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .kudosSyncRelevantSettingChanged)) { _ in
            optionsRevision += 1
        }
        // Filter ordinary reading-position checkpoints and unrelated models in O(k)
        // before scheduling a bounded-interval coalesced reload, so detached Read
        // Aloud never walks the library and a continuous save stream cannot starve.
        .onReceive(
            NotificationCenter.default.publisher(for: ModelContext.didSave)
                .receive(on: DispatchQueue.main)
        ) { notification in
            guard isOnScreen else { return }
            reloadCoordinator.noteSave(
                notification,
                works: { [libraryMirror] in libraryMirror.works },
                context: context,
                isOnScreen: { isOnScreen },
                reload: { snapshot in reload(baseline: snapshot) }
            )
        }
        .refreshable {
            reload()
        }
        .sheet(isPresented: $showingOptionsSheet) {
            InsightsOptionsSheet(
                // Exclusion choices never list hidden works' names: what is chosen is
                // stored, and would still show after the gate re-locks.
                exclusionsScope: selection(.main),
                exportScope: selection(screenScope),
                includeHidden: $scopeState.includeHidden,
                canIncludeHidden: scopeState.canIncludeHidden(hideMature: hideMature, revealed: gate.revealAll),
                onShowHowCounted: {
                    showingOptionsSheet = false
                    showingHowCountedSheet = true
                },
                onOptionsChanged: {
                    optionsRevision += 1
                }
            )
        }
        .sheet(isPresented: $showingHowCountedSheet) {
            HowInsightsAreCountedSheet()
        }
        .alert("Couldn’t Export Reading History", isPresented: Binding(
            get: { exportFailure != nil },
            set: { if !$0 { exportFailure = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportFailure ?? "")
        }
        #if os(iOS)
        .sheet(item: $exportedShareItem) { item in
            InsightsExportActivitySheet(url: item.url) {
                InsightsShareItem.cleanUp(item.url)
                exportedShareItem = nil
            }
        }
        #else
        .fileExporter(
            isPresented: $showingMacExporter,
            document: macExportDocument,
            contentType: macExportFormat.contentType,
            defaultFilename: "Kudos-Reading-History.\(macExportFormat.fileExtension)"
        ) { result in
            if case .failure(let error) = result {
                exportFailure = error.localizedDescription
            }
            macExportDocument = nil
        }
        #endif
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
                            .foregroundStyle(isSelected ? AnyShapeStyle(Color.primary) : AnyShapeStyle(.secondaryInk))
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
                        .foregroundStyle(.secondaryInk)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
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
            discreetMode: discreetMode,
            discreetMasker: discreetMasker
        )

        ReadingAndListeningCard(
            readingSeconds: insights.readingSeconds,
            silentReadingSeconds: insights.silentReadingSeconds,
            listeningSeconds: insights.listeningSeconds,
            hideReadingTime: hideReadingTime
        )

        RecordsGridCard(
            streakDays: insights.longestStreakDays,
            biggestDayWords: insights.biggestDay?.words ?? 0,
            medianSessionSeconds: insights.medianSessionSeconds,
            wordsPerHour: insights.wordsPerHour,
            charactersPerHour: insights.charactersPerHour,
            hideReadingTime: hideReadingTime
        )

        LengthOfWhatYouReadCard(mix: insights.lengthMix)

        if !finishedWorksInPeriod.isEmpty {
            FinishedInPeriodSection(
                works: finishedWorksInPeriod,
                discreetMode: discreetMode,
                discreetMasker: discreetMasker
            )
        } else {
            InsightsUnavailableCard(title: "Finished", explanation: "No works finished in this period.")
        }

        if hideMature {
            hiddenSection
        }

        // How Reading Insights Are Counted button
        Button {
            showingHowCountedSheet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "info.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondaryInk)

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

    // MARK: - Hidden Section

    /// Only the hidden (mature, Hide Mature) works' reading, with the Overview's own cards.
    /// Locked, it is one row offering the reveal control and shows nothing about them.
    private static let hiddenSectionID = "insightsHiddenSection"

    @ViewBuilder
    private var hiddenSection: some View {
        if gate.revealAll, let hidden = scopeState.hiddenInsights {
            InsightsHiddenHeader(isRevealed: true, includesHidden: screenScope == .combined)
                .id(Self.hiddenSectionID)

            WordsReadHeroCard(
                insights: hidden,
                periodName: periodTitle,
                previousPeriodName: previousPeriodShortName,
                hideReadingTime: hideReadingTime,
                totalDaysElapsed: totalDaysElapsedInPeriod,
                palette: theme.scopePalette
            )

            WhereTheWordsWentCard(
                fandoms: hidden.fandomWordsShares,
                discreetMode: discreetMode,
                discreetMasker: scopeState.hiddenSectionMasker(
                    mainMasker: discreetMasker,
                    hideMature: hideMature,
                    revealed: gate.revealAll
                )
            )
        } else {
            InsightsHiddenHeader(isRevealed: false, includesHidden: false)
                .id(Self.hiddenSectionID)
        }
    }

    // MARK: - Taste Tab Content

    @ViewBuilder
    private var tasteContent: some View {
        if let taste = tasteInsights {
            YourUsualFicCard(taste: taste, discreetMode: discreetMode, discreetMasker: discreetMasker)

            TasteFandomsCard(
                fandoms: taste.fandoms,
                rankByWorks: rankTasteByWorks,
                onToggleRank: { rankTasteByWorks.toggle() },
                discreetMode: discreetMode,
                discreetMasker: discreetMasker
            )

            TasteRelationshipsCard(
                relationships: taste.relationships,
                shipConcentrations: taste.shipConcentrations,
                discreetMode: discreetMode,
                discreetMasker: discreetMasker
            )

            if !taste.characters.isEmpty {
                TasteCharactersCard(
                    characters: taste.characters,
                    discreetMode: discreetMode,
                    discreetMasker: discreetMasker
                )
            }

            if !taste.tags.isEmpty {
                TasteTagsCard(
                    tags: taste.tags,
                    oftenTogether: taste.oftenTogether,
                    discreetMode: discreetMode,
                    discreetMasker: discreetMasker
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
                .foregroundStyle(.secondaryInk)
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
                lateNightSharePercent: habits.lateNightSharePercent,
                hideReadingTime: hideReadingTime
            )

            HabitsCalendarCard(
                days: habits.calendarDays,
                longestStreak: habits.longestStreak
            )

            HabitsSittingsCard(
                sittings: habits.sittingBuckets,
                typicalSeconds: habits.typicalSittingSeconds,
                hideReadingTime: hideReadingTime
            )

            HabitsChapterTimingCard(figure: chapterTiming)

            InsightsUnavailableCard(title: "New Chapters", explanation: "Chapter posting and first-read dates are not available yet.")

            if habits.savedToOpenedMedianDays != nil || habits.openedToFinishedMedianDays != nil {
                HabitsSavedToFinishedCard(
                    savedToOpenedDays: habits.savedToOpenedMedianDays,
                    openedToFinishedDays: habits.openedToFinishedMedianDays
                )
            }

            HabitsRereadsCard(rereads: habits.rereads, discreetMode: discreetMode, discreetMasker: discreetMasker)

            if !habits.fandomTimeline.isEmpty {
                HabitsFandomTimelineCard(lanes: habits.fandomTimeline, discreetMode: discreetMode, discreetMasker: discreetMasker)
            }

            if habits.stoppedCount > 0 {
                HabitsStoppedCard(
                    stoppedCount: habits.stoppedCount,
                    medianProgress: habits.stoppedMedianProgress,
                    commonTags: habits.commonStopTags,
                    discreetMode: discreetMode,
                    discreetMasker: discreetMasker
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
                    discreetMasker: discreetMasker,
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

            if let kudos = lib.kudosLeftPercent {
                LibraryFeedbackCard(kudosLeftPercent: kudos)
            }

            InsightsUnavailableCard(title: "Bookmarked · Commented", explanation: "Your AO3 bookmark and comment actions are not recorded yet.")

            LibraryFavouritesAndSeriesCard(
                favoritesWithoutKudos: lib.favoriteWithoutKudosCount,
                seriesStarted: lib.seriesStartedCount,
                seriesReadToLast: lib.seriesReadToLastCount,
                nextWaiting: lib.seriesNextWaitingCount
            )

            if lib.authors.isEmpty {
                InsightsUnavailableCard(title: "Authors", explanation: "No read works have a recorded AO3 author account yet.")
            } else {
                LibraryAuthorsCard(authors: lib.authors, discreetMode: discreetMode)
            }

            if lib.arrivalRows.isEmpty {
                InsightsUnavailableCard(title: "How Finished Works Arrived", explanation: "Import source recording has not begun for these works.")
            } else {
                LibraryArrivalCard(rows: lib.arrivalRows)
            }

            if lib.foundEarlyCount == 0 {
                InsightsUnavailableCard(title: "Found Early", explanation: "No finished work has a recorded kudos count under 500 at save yet.")
            } else {
                LibraryFoundEarlyCard(
                    count: lib.foundEarlyCount,
                    grownCount: lib.foundEarlyGrownCount,
                    example: lib.foundEarlyExample,
                    discreetMode: discreetMode
                )
            }

            LibraryPreservedStatsCard(stats: stats, discreetMode: discreetMode, discreetMasker: discreetMasker)
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
            return "1–\(endDay) \(monthName) · vs \(prevMonthName)\(scopeSuffix)"
        case .year:
            let yr = Self.yearFormatter.string(from: referenceDate)
            let prevDate = calendar.date(byAdding: .year, value: -1, to: referenceDate) ?? referenceDate
            let prevYr = Self.yearFormatter.string(from: prevDate)
            return "\(yr) · vs \(prevYr)\(scopeSuffix)"
        }
    }

    /// Says on screen when the figures include hidden works.
    private var scopeSuffix: String {
        scopeState.scopeSuffix(hideMature: hideMature, revealed: gate.revealAll)
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

    private func clearMainDisplayState() {
        insights = ReadingInsights()
        tasteInsights = nil
        habitsInsights = nil
        chapterTiming = InsightsProvenance.ChapterTimingFigure()
        libraryInsights = nil
        libraryStats = nil
        finishedWorksInPeriod = []
        discreetMasker = .empty
    }

    /// - Parameter baseline: the digest snapshot a coalesced save refresh already took;
    ///   adopted as-is so that refresh walks the library once.
    private func reload(baseline: InsightsReloadDigest.Snapshot? = nil) {
        // Taken first, so `reloadKey` already holds it when `lastReloadKey` is
        // written below and a save this reload follows triggers no second one.
        libraryDigest = baseline.map { reloadCoordinator.tracker.adopt($0) }
            ?? reloadCoordinator.tracker.recordBaseline(works: libraryMirror.works, context: context)
        let component = range.component
        guard let currentInterval = calendar.dateInterval(of: component, for: referenceDate),
              let earlierDate = calendar.date(byAdding: component, value: -1, to: referenceDate),
              let previousInterval = calendar.dateInterval(of: component, for: earlierDate)
        else { return }

        let periodMonths: Double = range == .year ? 12 : 1
        let options = InsightsOptions.load()
        let activeScope = screenScope
        let gathered = ReadingLogService.gatherInsights(
            for: currentInterval,
            previousPeriod: previousInterval,
            scope: selection(activeScope),
            periodMonths: periodMonths,
            calendar: calendar,
            context: context,
            options: options
        )
        if hideMature && gate.revealAll {
            let hidden = ReadingLogService.gatherInsights(
                for: currentInterval,
                previousPeriod: previousInterval,
                scope: selection(.hidden),
                periodMonths: periodMonths,
                calendar: calendar,
                context: context,
                options: options
            )
            scopeState.recordGather(
                scope: activeScope,
                hiddenInsights: hidden.insights,
                hiddenMasker: hidden.discreetMasker
            )
        } else {
            scopeState.recordGather(
                scope: activeScope,
                hiddenInsights: nil,
                hiddenMasker: .empty
            )
        }
        insights = gathered.insights
        tasteInsights = gathered.taste
        habitsInsights = gathered.habits
        chapterTiming = gathered.chapterTiming
        libraryInsights = gathered.library
        libraryStats = gathered.libraryStats
        finishedWorksInPeriod = gathered.finishedWorksInPeriod
        discreetMasker = gathered.discreetMasker
        lastReloadKey = reloadKey
        hasLoadedOnce = true
    }

    // MARK: - Actions

    private func exportReadingHistory(format: InsightsExportFormat) {
        // Follows what is on screen; while locked that is never the hidden works.
        let scope = selection(screenScope)
        let exportWorks = scope.libraryWorks
        let exportReadingWorks = scope.readingWorks
        let sessions = scope.sessions(
            (try? context.fetch(FetchDescriptor<ReadingSession>())) ?? [],
            in: context
        )
        let options = InsightsOptions.load()
        let aliases = TagAliasStore.resolver(in: context)
        do {
            #if os(iOS)
            let url = try InsightsExportService.writeTemporaryExportFile(
                format: format,
                works: exportWorks,
                readingWorks: exportReadingWorks,
                sessions: sessions,
                options: options,
                aliases: aliases
            )
            exportedShareItem = InsightsShareItem(url: url)
            #else
            let data: Data
            switch format {
            case .csv:
                data = Data(InsightsExportService.csvString(
                    works: exportWorks,
                    readingWorks: exportReadingWorks,
                    sessions: sessions,
                    options: options,
                    aliases: aliases
                ).utf8)
            case .json:
                data = try InsightsExportService.jsonData(
                    works: exportWorks,
                    readingWorks: exportReadingWorks,
                    sessions: sessions,
                    options: options,
                    aliases: aliases
                )
            }
            macExportFormat = format
            macExportDocument = InsightsExportFileDocument(data: data, contentType: format.contentType)
            showingMacExporter = true
            #endif
        } catch {
            exportFailure = error.localizedDescription
        }
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
