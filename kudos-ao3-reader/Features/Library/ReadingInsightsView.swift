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
    @State private var stoppedWork: SavedWork?
    @State private var finishedWorkIDs: [UUID] = []
    @State private var discreetMasker: InsightsDiscreetMasker = .empty
    @State private var gatherRunner = InsightsGatherRunner<InsightsGatherOutput>()
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
                    VStack(spacing: CardListMetrics.interCardSpacing) {
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
                    .padding(.horizontal, SubjectMetrics.gutter)
                    .padding(.top, 8)
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
        .wrappingInlineTitle("Reading Insights", isActive: dynamicTypeSize.isAccessibilitySize)
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
            if gatherRunner.isRunning && !hasLoadedOnce {
                lastReloadKey = ""
            }
            gatherRunner.cancel()
        }
        .onChange(of: gate.revealAll) { _, revealed in
            // Synchronously clear hidden state and recompute main figures on re-lock so
            // stale combined mature titles/figures are never painted while waiting for `.task`.
            if !revealed {
                gatherRunner.cancel()
            }
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
            let container = context.container
            reloadCoordinator.noteSave(
                notification,
                works: { [libraryMirror] in libraryMirror.works },
                context: context,
                isOnScreen: { isOnScreen },
                reload: { snapshot in reload(baseline: snapshot) },
                digest: {
                    try? await InsightsGatherActor(modelContainer: container).digest()
                }
            )
        }
        .refreshable {
            reload()
            await gatherRunner.waitForCurrent()
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
        .sheet(item: $stoppedWork) { work in
            InsightsStoppedSheet(work: work, discreetMode: discreetMode,
                                 discreetMasker: discreetMasker) {
                reload()
            }
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
        VStack(spacing: 12) {
            // Tab segment pill (Overview / Taste / Habits / Library)
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    // Two-column grid at AX sizes so four scaled tab labels never crush.
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)],
                        spacing: 2
                    ) {
                        tabButtons
                    }
                } else {
                    HStack(spacing: 0) {
                        tabButtons
                    }
                }
            }
            .padding(2)
            .background(Color.primary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
            .padding(.horizontal, SubjectMetrics.gutter)
            .padding(.top, 4)

            // Period selector strip (Period title, subtitle, Range picker, ‹, ›)
            let periodLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
            periodLayout {
                VStack(alignment: .leading, spacing: 1) {
                    Text(periodTitle)
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                        // Two lines at every size: the column shares the row with the Range menu and
                        // both arrows, and "incl. hidden" at the end of the subtitle says the figures
                        // count hidden works, so it must never be the part that truncates.
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                        .accessibilityAddTraits(.isHeader)

                    Text(periodSubtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
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
                                .font(.subheadline.weight(.medium))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .accessibilityHidden(true)
                        }
                        .padding(.leading, 12)
                        .padding(.trailing, 10)
                        .frame(minHeight: 32)
                        .background(Color.primary.opacity(0.08))
                        .foregroundStyle(.primary)
                        .clipShape(SubjectMetrics.controlShape(dynamicTypeSize))
                    }
                    .accessibilityLabel("Period: \(range.title)")

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
                            .foregroundStyle(canGoNext ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Color.secondary.opacity(0.3)))
                            .frame(width: 32, height: 32)
                            .background(canGoNext ? Color.primary.opacity(0.08) : Color.primary.opacity(0.04))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canGoNext)
                    .accessibilityLabel("Next period")
                }
            }
            .padding(.horizontal, SubjectMetrics.gutter)
            .padding(.bottom, 4)
        }
        .background(theme.appTheme.cardBackdrop)
    }

    @ViewBuilder
    private var tabButtons: some View {
        ForEach(Tab.allCases) { tab in
            let isSelected = selectedTab == tab
            Button {
                selectedTab = tab
            } label: {
                Text(tab.title)
                    .font(.footnote.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 28)
                    .padding(.horizontal, 4)
                    .background(
                        isSelected ? theme.appTheme.cardSurface : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(
                        color: isSelected ? Color.black.opacity(0.10) : Color.clear,
                        radius: 4,
                        y: 1
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tab.title)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
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
            listeningPlaybackRate: insights.listeningPlaybackRate,
            listeningWorksCount: insights.listeningWorksCount,
            hideReadingTime: hideReadingTime
        )

        RecordsGridCard(
            streakDays: insights.longestStreakDays,
            biggestDayWords: insights.biggestDay?.words ?? 0,
            medianSessionSeconds: insights.medianSessionSeconds,
            wordsPerHour: insights.wordsPerHour,
            charactersPerHour: insights.charactersPerHour,
            hideReadingTime: hideReadingTime,
            streakDateRange: InsightsBoardCopy.streakDateRangeLabel(
                days: insights.dailyWords,
                expectedLength: insights.longestStreakDays,
                calendar: calendar
            ),
            biggestDayDate: insights.biggestDay?.date,
            sittingsCount: insights.sittingBuckets.reduce(0) { $0 + $1.count }
        )

        LengthOfWhatYouReadCard(mix: insights.lengthMix)

        if !finishedWorksInPeriod.isEmpty {
            // `uniquingKeysWith`: `uniqueKeysWithValues` traps on a repeated id, and this is only a label.
            let rereadFinishCounts = Dictionary(
                (habitsInsights?.rereads ?? []).map { ($0.id, $0.finishCount) },
                uniquingKeysWith: { first, _ in first }
            )
            FinishedInPeriodSection(
                works: finishedWorksInPeriod,
                discreetMode: discreetMode,
                discreetMasker: discreetMasker,
                rereadFinishCounts: rereadFinishCounts
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
                    .font(.system(size: 19))
                    .foregroundStyle(.secondaryInk)
                    .accessibilityHidden(true)

                Text("How Reading Insights Are Counted")
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, SubjectMetrics.gutter)
            .padding(.vertical, 13)
            .frame(minHeight: 48)
            .background(theme.appTheme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("How Reading Insights Are Counted")
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
        if let taste = tasteInsights, taste.totalWorksCount > 0 {
            let rankedTaste = taste.ranked(byWorks: rankTasteByWorks)
            YourUsualFicCard(taste: rankedTaste, discreetMode: discreetMode, discreetMasker: discreetMasker)

            TasteFandomsCard(
                fandoms: rankedTaste.fandoms,
                rankByWorks: rankTasteByWorks,
                onToggleRank: { rankTasteByWorks.toggle() },
                discreetMode: discreetMode,
                discreetMasker: discreetMasker
            )

            TasteRelationshipsCard(
                relationships: rankedTaste.relationships,
                shipConcentrations: taste.shipConcentrations,
                rankByWorks: rankTasteByWorks,
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

            if !rankedTaste.tags.isEmpty || !taste.oftenTogether.isEmpty {
                TasteTagsCard(
                    tags: rankedTaste.tags,
                    oftenTogether: taste.oftenTogether,
                    rankByWorks: rankTasteByWorks,
                    discreetMode: discreetMode,
                    discreetMasker: discreetMasker
                )
            }

            TasteRatingsCategoriesWarningsCard(
                ratings: rankedTaste.ratings,
                statuses: rankedTaste.statuses,
                categories: rankedTaste.categories,
                warnings: rankedTaste.warnings,
                rankByWorks: rankTasteByWorks
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
            let isYear = range == .year
            HabitsTimeOfDayCard(
                hourly: habits.hourlyDuration,
                lateNightDuration: habits.lateNightDuration,
                lateNightSharePercent: habits.lateNightSharePercent,
                hideReadingTime: hideReadingTime,
                isYear: isYear
            )

            HabitsCalendarCard(
                days: habits.calendarDays,
                longestStreak: habits.longestStreak,
                thresholds: habits.calendarWordThresholds,
                totalDaysElapsed: totalDaysElapsedInPeriod,
                isMonthPeriod: range == .month && habits.calendarIsMonthGrid
            )

            HabitsSittingsCard(
                sittings: habits.sittingBuckets,
                typicalSeconds: habits.typicalSittingSeconds,
                hideReadingTime: hideReadingTime,
                chapterTiming: chapterTiming,
                isYear: isYear
            )

            if habits.savedToOpenedMedianDays != nil || habits.openedToFinishedMedianDays != nil {
                HabitsSavedToFinishedCard(
                    savedToOpenedDays: habits.savedToOpenedMedianDays,
                    openedToFinishedDays: habits.openedToFinishedMedianDays,
                    savedToOpenedCount: habits.savedToOpenedCount,
                    openedToFinishedCount: habits.openedToFinishedCount,
                    showsNewChaptersUnavailable: true
                )
            } else {
                InsightsUnavailableCard(
                    title: "New Chapters",
                    explanation: "Chapter posting and first-read dates are not available yet."
                )
            }

            HabitsRereadsCard(
                rereads: habits.rereads,
                rereadTimeShare: habits.rereadTimeShare,
                discreetMode: discreetMode,
                discreetMasker: discreetMasker
            )

            if !habits.fandomTimeline.isEmpty {
                HabitsFandomTimelineCard(
                    lanes: habits.fandomTimeline,
                    year: habits.fandomTimelineYear,
                    discreetMode: discreetMode,
                    discreetMasker: discreetMasker
                )
            }

            if habits.stoppedCount > 0 {
                HabitsStoppedCard(
                    stoppedCount: habits.stoppedCount,
                    stoppedInPeriodCount: habits.stoppedInPeriodCount,
                    medianProgress: habits.stoppedMedianProgress,
                    reasons: habits.stopReasons,
                    commonTags: habits.commonStopTags,
                    discreetMode: discreetMode,
                    discreetMasker: discreetMasker,
                    isYear: isYear
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
                monthsToClearRange: lib.monthsToClearRange,
                addedWords: lib.addedWordsInPeriod,
                readWords: lib.readWordsInPeriod
            )

            LibraryWhereEverythingStandsCard(partition: lib.statuses)

            if let candidate = lib.stillReadingCandidate,
               let candidateWork = libraryWorks.first(where: { $0.id == candidate.id }) {
                LibraryStillReadingCard(
                    candidate: candidate,
                    work: candidateWork,
                    discreetMode: discreetMode,
                    discreetMasker: discreetMasker,
                    onStillReading: {
                        WorkLifecycle.keepInProgress(candidateWork, in: context)
                        reload()
                    },
                    onStoppedReading: {
                        stoppedWork = candidateWork
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

            if lib.kudosLeftPercent != nil || lib.favoriteWithoutKudosCount > 0 {
                LibraryFeedbackCard(
                    kudosLeftPercent: lib.kudosLeftPercent,
                    finishedCount: stats.finishedWorks,
                    favoriteWithoutKudosCount: lib.favoriteWithoutKudosCount
                )
            } else {
                InsightsUnavailableCard(
                    title: "Bookmarked · Commented",
                    explanation: "Your AO3 bookmark and comment actions are not recorded yet."
                )
            }

            if lib.seriesStartedCount > 0 {
                LibrarySeriesCard(
                    started: lib.seriesStartedCount,
                    readToLast: lib.seriesReadToLastCount,
                    longestFinished: lib.longestFinishedSeries,
                    nextWaiting: lib.seriesNextWaitingCount,
                    discreetMode: discreetMode,
                    discreetMasker: discreetMasker
                )
            }

            if lib.authors.isEmpty {
                InsightsUnavailableCard(title: "Authors", explanation: "No read works have a recorded AO3 author account yet.")
            } else {
                LibraryAuthorsCard(authors: lib.authors, discreetMode: discreetMode, discreetMasker: discreetMasker)
            }

            if lib.arrivalRows.isEmpty {
                InsightsUnavailableCard(title: "How Finished Works Arrived", explanation: "No finished works have a recorded import source yet.")
            } else {
                LibraryArrivalCard(rows: lib.arrivalRows, since: lib.arrivalSince)
            }

            if lib.foundEarlyRecordedFinishedCount == 0 || lib.foundEarlyCount == 0 {
                InsightsUnavailableCard(title: "Found Early", explanation: "No finished work has a recorded kudos count under 500 at save yet.")
            } else {
                LibraryFoundEarlyCard(
                    recordedFinishedCount: lib.foundEarlyRecordedFinishedCount,
                    count: lib.foundEarlyCount,
                    foundEarlyShare: lib.foundEarlyShare,
                    grownCount: lib.foundEarlyGrownCount,
                    grownShare: lib.foundEarlyGrowthShare,
                    since: lib.foundEarlySince,
                    example: lib.foundEarlyExampleItem,
                    discreetMode: discreetMode,
                    discreetMasker: discreetMasker
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
        InsightsBoardCopy.periodSubtitle(
            isYear: range == .year,
            referenceDate: referenceDate,
            now: Date(),
            scopeSuffix: scopeSuffix,
            calendar: calendar
        )
    }

    /// Says on screen when the figures include hidden works.
    private var scopeSuffix: String {
        scopeState.scopeSuffix(hideMature: hideMature, revealed: gate.revealAll)
    }

    private var previousPeriodShortName: String {
        InsightsBoardCopy.previousComparisonLabel(
            isYear: range == .year,
            referenceDate: referenceDate,
            now: Date(),
            calendar: calendar
        )
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

    private var finishedWorksInPeriod: [SavedWork] {
        guard !finishedWorkIDs.isEmpty else { return [] }
        let byID = Dictionary(libraryWorks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return finishedWorkIDs.compactMap { byID[$0] }
    }

    private func clearMainDisplayState() {
        insights = ReadingInsights()
        tasteInsights = nil
        habitsInsights = nil
        chapterTiming = InsightsProvenance.ChapterTimingFigure()
        libraryInsights = nil
        libraryStats = nil
        finishedWorkIDs = []
        discreetMasker = .empty
    }

    /// - Parameter baseline: the digest snapshot a coalesced save refresh already took;
    ///   adopted as-is so that refresh walks the library once.
    private func reload(baseline: InsightsReloadDigest.Snapshot? = nil) {
        if let digest = baseline.map({ reloadCoordinator.tracker.adopt($0) }) {
            libraryDigest = digest
        }
        let component = range.component
        guard let currentInterval = calendar.dateInterval(of: component, for: referenceDate),
              let earlierDate = calendar.date(byAdding: component, value: -1, to: referenceDate),
              let previousInterval = calendar.dateInterval(of: component, for: earlierDate)
        else { return }

        let periodMonths: Double = range == .year ? 12 : 1
        let options = InsightsOptions.load()
        let activeScope = screenScope
        let hideMatureAtStart = hideMature
        let revealedAtStart = gate.revealAll
        let request = InsightsGatherRequest(
            period: currentInterval,
            previousPeriod: previousInterval,
            periodMonths: periodMonths,
            calendar: calendar,
            options: options,
            scope: activeScope,
            hideMature: hideMatureAtStart,
            revealed: revealedAtStart,
            includesHiddenSection: hideMatureAtStart && revealedAtStart,
            computesDigest: baseline == nil,
            now: Date()
        )
        let container = context.container
        lastReloadKey = reloadKey
        gatherRunner.start(
            gather: {
                try await InsightsGatherActor(modelContainer: container).gather(request)
            },
            apply: { output in
                // Drop stale scope results if Hide Mature or PrivacyGate changed while gathering.
                guard request.scope == screenScope,
                      request.hideMature == hideMature,
                      request.revealed == gate.revealAll
                else { return }

                if let digestSnapshot = output.digest {
                    libraryDigest = reloadCoordinator.tracker.adopt(digestSnapshot)
                }
                if hideMature && gate.revealAll, let hidden = output.hidden {
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
                insights = output.main.insights
                tasteInsights = output.main.taste
                habitsInsights = output.main.habits
                chapterTiming = output.main.chapterTiming
                libraryInsights = output.main.library
                libraryStats = output.main.libraryStats
                finishedWorkIDs = output.main.finishedWorkIDs
                discreetMasker = output.main.discreetMasker
                lastReloadKey = reloadKey
                hasLoadedOnce = true
            }
        )
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

    private static let yearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("y")
        return f
    }()
}
