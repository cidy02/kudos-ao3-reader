import Foundation
import SwiftData
import Testing
@testable import Kudos

extension PersistenceGateSuites.LibraryScaleBenchmarkTests {
    // One pass per case and library size. In particular, export builds a full
    // document and What Fits evaluates smart rules again through its own path.
    func measureHighRows(
        _ fixture: LibraryScaleBenchmarkFixture, _ report: LibraryScaleBenchmarkReport
    ) async throws {
        // The log spans 30 years. Anchor inside its populated history so all
        // three History periods and both Insights periods have real activity.
        let anchor = LibraryScaleBenchmarkFixture.historyEnd.addingTimeInterval(-400 * 86_400)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt

        try autoreleasepool { try measureHome(fixture, report, anchor: anchor, calendar: calendar) }
        try await measureInsightsReloads(fixture, report, anchor: anchor, calendar: calendar)
        try autoreleasepool { try measureInsightsExclusions(fixture, report) }
        for format in InsightsExportFormat.allCases {
            try autoreleasepool { try measureInsightsExport(format, fixture, report, anchor: anchor) }
        }
        try autoreleasepool { try measureLibraryDashboard(fixture, report) }
        try autoreleasepool { try measureLibraryLists(fixture, report) }
        try autoreleasepool { try measureSmartQueues(fixture, report) }
        for scope in ReadingHistoryScope.allCases {
            try autoreleasepool { try measureHistory(scope, fixture, report, anchor: anchor, calendar: calendar) }
        }
        try await measureLaunchWork(fixture, report)
        try autoreleasepool { try seedTags(fixture, report) }
        try autoreleasepool { try measureLocalSearch(fixture, report) }
        try autoreleasepool { try measureTags(fixture, report) }
        try autoreleasepool { try measurePairing(fixture, report) }
        try autoreleasepool { try measureSessionHelpers(fixture, report, anchor: anchor) }
        // The FolderSyncObserver token and its invalidation require a mounted
        // SwiftUI view. WIP polling requires AO3. Neither runs in this benchmark.
    }

    private func measureHome(
        _ fixture: LibraryScaleBenchmarkFixture, _ report: LibraryScaleBenchmarkReport,
        anchor: Date, calendar: Calendar
    ) throws {
        let context = fixture.makeContext()
        let works = try context.fetch(Self.liveWorks)
        let sessions = try context.fetch(FetchDescriptor<ReadingSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        ))
        let started = ContinuousClock.now
        let facts = ReadingLogService.facts(from: sessions, works: works)
        let stats = HomeReadingStats.calculate(facts: facts, now: anchor, calendar: calendar)
        let seconds = benchmarkSeconds(since: started)
        try #require(stats.durationSeconds > 0)
        try report.record("home_weekly_stats", for: fixture, seconds: seconds, counts: [
            "works_fetched": works.count, "sessions_fetched": sessions.count, "facts": facts.count,
            "works_finished_this_week": stats.finishedCount
        ])

        // What Home itself runs since T-568 step 5b: the week's rows plus a bounded streak lookback.
        let boundedStarted = ContinuousClock.now
        let bounded = try HomeReadingStats.calculate(in: context, now: anchor, calendar: calendar)
        let boundedSeconds = benchmarkSeconds(since: boundedStarted)
        #expect(bounded == stats)
        try report.record("home_weekly_stats_bounded", for: fixture, seconds: boundedSeconds, counts: [
            "works_finished_this_week": bounded.finishedCount
        ])

        let visible = Self.libraryVisibility()
        let shelfStarted = ContinuousClock.now
        let readingNow = HomeSectionKind.readingNow.works(from: works, visible: visible)
        let updates = HomeSectionKind.recentlyUpdated.works(from: works, visible: visible)
        let shelf = HomeReadingNowCount.shelfCounts(total: readingNow.count)
        let shelfSeconds = benchmarkSeconds(since: shelfStarted)
        try #require(!readingNow.isEmpty && !updates.isEmpty)
        try report.record("home_shelf_summaries", for: fixture, seconds: shelfSeconds, counts: [
            "works_fetched": works.count, "reading_now": readingNow.count, "recently_updated": updates.count,
            "reading_now_under_header": shelf.sectionCount, "reading_now_preview": shelf.visibleCount
        ])
    }

    private func measureInsightsReloads(
        _ fixture: LibraryScaleBenchmarkFixture, _ report: LibraryScaleBenchmarkReport,
        anchor: Date, calendar: Calendar
    ) async throws {
        let container = fixture.makeContext().container
        let periods: [(Calendar.Component, String, Double)] = [(.month, "month", 1), (.year, "year", 12)]
        for (component, label, months) in periods {
            let period = try #require(calendar.dateInterval(of: component, for: anchor))
            let previousAnchor = try #require(calendar.date(byAdding: component, value: -1, to: anchor))
            let previousPeriod = try #require(calendar.dateInterval(of: component, for: previousAnchor))
            let request = InsightsGatherRequest(
                period: period, previousPeriod: previousPeriod, periodMonths: months,
                calendar: calendar, hideMature: true, now: anchor
            )
            let started = ContinuousClock.now
            let result = try await InsightsGatherActor(modelContainer: container).gather(request)
            let seconds = benchmarkSeconds(since: started)
            let fetched = result.fetches
            try #require(result.digest != nil && result.main.insights.readingSeconds > 0)
            try #require(fetched.sessionsFetched == fixture.library * 6)
            try report.record("insights_reload_\(label)", for: fixture, seconds: seconds, counts: [
                "works_fetched": fetched.worksFetched, "deleted_works_fetched": fetched.softDeletedWorksFetched,
                "sessions_fetched": fetched.sessionsFetched, "aliases_fetched": fetched.aliasesFetched,
                "series_fetched": fetched.seriesFetched, "fetch_batches": fetched.totalBatches,
                "largest_batch": fetched.largestBatch, "finished_works": result.main.finishedWorkIDs.count
            ])
        }
    }

    // The drilldown measured here is the "Left Out of Insights" sheet's scoped
    // session load. Its option arrays and rendering live in the sheet itself.
    private func measureInsightsExclusions(
        _ fixture: LibraryScaleBenchmarkFixture, _ report: LibraryScaleBenchmarkReport
    ) throws {
        let context = fixture.makeContext()
        let works = try context.fetch(Self.liveWorks)
        let scope = HomeReadingStats.insightsScope(.main, from: works, hideMature: true, revealed: false)
        let started = ContinuousClock.now
        let sessions = try context.fetch(FetchDescriptor<ReadingSession>())
        let scoped = scope.sessions(sessions, in: context)
        let seconds = benchmarkSeconds(since: started)
        try #require(scoped.count == fixture.library * 6)
        try report.record("insights_exclusions_drilldown", for: fixture, seconds: seconds, counts: [
            "live_works": works.count, "sessions_fetched": sessions.count, "scoped_sessions": scoped.count
        ])
    }

    private func measureInsightsExport(
        _ format: InsightsExportFormat, _ fixture: LibraryScaleBenchmarkFixture, _ report: LibraryScaleBenchmarkReport,
        anchor: Date
    ) throws {
        let context = fixture.makeContext()
        let works = try context.fetch(Self.liveWorks)
        let started = ContinuousClock.now
        let scope = HomeReadingStats.insightsScope(.main, from: works, hideMature: true, revealed: false)
        let rawSessions = try context.fetch(FetchDescriptor<ReadingSession>())
        let sessions = scope.sessions(rawSessions, in: context)
        let aliases = TagAliasStore.resolver(in: context)
        let output = try InsightsExportService.writeTemporaryExportFile(
            format: format, works: scope.libraryWorks, readingWorks: scope.readingWorks,
            sessions: sessions, aliases: aliases, now: anchor
        )
        let seconds = benchmarkSeconds(since: started)
        defer { InsightsShareItem.cleanUp(output) }
        let bytes = try #require(try output.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        try #require(bytes > 0 && sessions.count == fixture.library * 6)
        try report.record("insights_export_\(format.rawValue)", for: fixture, seconds: seconds, counts: [
            "library_works": scope.libraryWorks.count, "sessions_fetched": rawSessions.count,
            "scoped_sessions": sessions.count, "output_bytes": bytes
        ])
    }

    private func measureLibraryDashboard(
        _ fixture: LibraryScaleBenchmarkFixture, _ report: LibraryScaleBenchmarkReport
    ) throws {
        let context = fixture.makeContext()
        let works = try context.fetch(Self.liveWorks)
        let visible = Self.libraryVisibility()
        let kinds: [LibrarySectionKind] = [.readingNow, .savedForLater, .finished, .downloaded, .history, .favorites]
        let isImported: (SavedWork) -> Bool = {
            LibraryShelfID.isImported(origin: $0.origin, isQueueOnly: $0.isQueueOnlyWork) && visible($0)
        }
        let dashboardStarted = ContinuousClock.now
        let filters = LibraryFilters()
        let counts = kinds.map { (kind: $0, count: filters.apply(to: $0.works(from: works, visible: visible)).count) }
        let imported = filters.apply(to: works.filter(isImported))
        let libraryCount = works.filter { !$0.isQueueOnlyWork && visible($0) }.count
        let seconds = benchmarkSeconds(since: dashboardStarted)
        var shelfCounts = Dictionary(uniqueKeysWithValues: counts.map { ($0.kind.rawValue, $0.count) })
        shelfCounts["works_fetched"] = works.count
        shelfCounts["library_works"] = libraryCount
        shelfCounts["imported"] = imported.count
        try report.record("library_dashboard_counts", for: fixture, seconds: seconds, counts: shelfCounts)

        var changedFilters = filters
        changedFilters.wordsTo = "50000"
        let filterStarted = ContinuousClock.now
        let filtered = kinds.map { changedFilters.apply(to: $0.works(from: works, visible: visible)).count }
        let filteredImported = changedFilters.apply(to: works.filter(isImported)).count
        let filterSeconds = benchmarkSeconds(since: filterStarted)
        let narrowedShelf = zip(filtered, counts).contains { $0.0 < $0.1.count }
        try #require(narrowedShelf)
        try report.record("library_dashboard_filter_change", for: fixture, seconds: filterSeconds, counts: [
            "input_works": works.count, "shelves": kinds.count, "total_shelf_entries": filtered.reduce(0, +),
            "imported": filteredImported
        ])

        let storageStarted = ContinuousClock.now
        let downloads = LibrarySectionKind.downloaded.works(from: works, visible: visible)
        let filteredDownloads = changedFilters.apply(to: downloads)
        let totalBytes = downloads.reduce(Int64(0)) { $0 + queueWorkFileSize($1.fileURL) }
        let filteredBytes = filteredDownloads.reduce(Int64(0)) { $0 + queueWorkFileSize($1.fileURL) }
        let storageSeconds = benchmarkSeconds(since: storageStarted)
        try #require(filteredBytes > 0 && totalBytes > filteredBytes)
        try report.record("library_dashboard_storage", for: fixture, seconds: storageSeconds, counts: [
            "downloads": downloads.count, "filtered_downloads": filteredDownloads.count,
            "file_size_lookups": downloads.count + filteredDownloads.count,
            "download_bytes": Int(totalBytes), "filtered_bytes": Int(filteredBytes)
        ])
    }

    private func measureLibraryLists(
        _ fixture: LibraryScaleBenchmarkFixture, _ report: LibraryScaleBenchmarkReport
    ) throws {
        let context = fixture.makeContext()
        let works = try context.fetch(Self.liveWorks)
        let visible = Self.libraryVisibility()
        var filters = LibraryFilters()
        filters.wordsFrom = "5000"
        filters.sort = .title
        let listStarted = ContinuousClock.now
        let history = LibrarySectionKind.history.works(from: works, visible: visible)
        let sorted = filters.apply(to: history)
        let listSeconds = benchmarkSeconds(since: listStarted)
        try #require(!sorted.isEmpty && sorted.count < history.count)
        try report.record("library_full_list_sort_filter", for: fixture, seconds: listSeconds, counts: [
            "works_fetched": works.count, "section_works": history.count, "matching_works": sorted.count
        ])

        let collectionID = fixture.id(for: fixture.library + fixture.queueCount)
        let descriptor = FetchDescriptor<WorkCollection>(predicate: #Predicate { $0.id == collectionID })
        let collection = try #require(try context.fetch(descriptor).first)
        let pickerStarted = ContinuousClock.now
        let candidates = CollectionWorkPicker.candidates(from: works, notIn: collection)
        let pickerSeconds = benchmarkSeconds(since: pickerStarted)
        try #require(candidates.count < works.count && !candidates.isEmpty)
        try report.record("library_collection_picker", for: fixture, seconds: pickerSeconds, counts: [
            "input_works": works.count, "candidate_works": candidates.count
        ])
    }

    private func measureSmartQueues(
        _ fixture: LibraryScaleBenchmarkFixture, _ report: LibraryScaleBenchmarkReport
    ) throws {
        let context = fixture.makeContext()
        let works = try context.fetch(Self.liveWorks)
        let visible = Self.libraryVisibility()
        let aliases = TagAliasStore.resolver(in: context)
        // Even with 100 displayed matches, each broad rule matches and sorts
        // almost every eligible work before applying the limit.
        let smartQueues = try (0..<100).map { index in
            let rule = SmartQueueDocument.Rule(
                id: fixture.id(for: 9_000_000 + index), kind: .length, lengthComparison: .atLeast, words: 1_000 + index
            )
            let document = SmartQueueDocument(match: .all, rules: [rule], sort: .shortestFirst, limit: 100)
            let queue = ReadingQueue(
                id: fixture.id(for: 9_001_000 + index), name: "Smart archive \(index)", kind: .smart,
                sortOrder: fixture.queueCount + index, dateCreated: LibraryScaleBenchmarkFixture.historyEnd,
                dateUpdated: LibraryScaleBenchmarkFixture.historyEnd
            )
            queue.smartRulesJSON = try #require(SmartQueueRules.encode(document))
            return queue
        }
        let started = ContinuousClock.now
        let snapshot = ReadingQueueService.SmartLibrarySnapshot(works: works, aliases: aliases)
        let matches = smartQueues.map { ReadingQueueService.orderedWorks(in: $0, snapshot: snapshot, where: visible) }
        let seconds = benchmarkSeconds(since: started)
        try #require(matches.allSatisfy { $0.count == 100 })
        try report.record("smart_queues_100_broad", for: fixture, seconds: seconds, counts: [
            "works_fetched": works.count, "eligible_works": snapshot.eligible.count, "queues": smartQueues.count,
            "returned_matches": matches.reduce(0) { $0 + $1.count }
        ])

        let manualQueues = try context.fetch(FetchDescriptor<ReadingQueue>(
            predicate: #Predicate { !$0.isPendingDeletion }
        ))
        let fitStarted = ContinuousClock.now
        let plan = WhatFitsPlanner.plan(
            queues: manualQueues + smartQueues, bucket: .defaultSelection, isVisible: visible,
            libraryWorks: works, tagAliases: aliases
        )
        let fitSeconds = benchmarkSeconds(since: fitStarted)
        try #require(plan.hasAnyUnfinishedWorks && !plan.allEntries.isEmpty)
        try report.record("what_fits", for: fixture, seconds: fitSeconds, counts: [
            "input_works": works.count, "manual_queues_fetched": manualQueues.count,
            "smart_queues": smartQueues.count, "queues_planned": plan.queueCount, "entries": plan.allEntries.count
        ])
    }

    private func measureHistory(
        _ scope: ReadingHistoryScope, _ fixture: LibraryScaleBenchmarkFixture, _ report: LibraryScaleBenchmarkReport,
        anchor: Date, calendar: Calendar
    ) throws {
        let context = fixture.makeContext()
        let works = LibrarySectionKind.history.works(from: try context.fetch(Self.liveWorks),
                                                     visible: Self.libraryVisibility())
        let started = ContinuousClock.now
        let sessions = try context.fetch(FetchDescriptor<ReadingSession>())
        let workIDs = Set(works.map(\.id))
        let shown = sessions.filter { workIDs.contains($0.workID) }
        let facts = ReadingLogService.facts(from: shown, works: works)
        let timeline = ReadingHistoryTimeline.make(scope: scope, containing: anchor, facts: facts,
                                                   now: anchor, calendar: calendar)
        let seconds = benchmarkSeconds(since: started)
        try #require(timeline.totalSeconds > 0)
        try report.record("reading_history_\(scope.rawValue)", for: fixture, seconds: seconds, counts: [
            "input_works": works.count, "sessions_fetched": sessions.count, "facts": facts.count,
            "sittings_in_period": timeline.days.reduce(0) { $0 + $1.sittings.count }
        ])
    }

    private func measureLaunchWork(
        _ fixture: LibraryScaleBenchmarkFixture, _ report: LibraryScaleBenchmarkReport
    ) async throws {
        try autoreleasepool {
            let context = fixture.makeContext()
            let work = try fixture.work(at: 0, in: context)
            try #require(!work.queueMemberships.isEmpty)
            work.isQueuedForLater = false
            try context.save()
            let memberships = try context.fetchCount(FetchDescriptor<ReadingQueueMembership>())
            let flaggedDescriptor = FetchDescriptor<SavedWork>(predicate: #Predicate { $0.isQueuedForLater })
            let flagged = try context.fetchCount(flaggedDescriptor)
            let started = ContinuousClock.now
            ReadingQueueService.normalizeAllQueuedWorks(in: context)
            let seconds = benchmarkSeconds(since: started)
            try #require(work.isQueuedForLater && !context.hasChanges)
            try report.record("launch_queue_normalization", for: fixture, seconds: seconds, counts: [
                "memberships_before": memberships, "flagged_works_before": flagged
            ])
        }

        let context = fixture.makeContext()
        let version = WorkSearchIndex.currentVersion
        let stale = FetchDescriptor<SavedWork>(predicate: #Predicate { $0.searchIndexVersion != version })
        // The rare term occurs in one record and is set before its index is built.
        let rareWork = try fixture.work(at: fixture.library - 10, in: context)
        rareWork.title += " \(Self.rareSearchTerm)"
        rareWork.searchIndexVersion = 0
        try context.save()
        let staleCount = try context.fetchCount(stale)
        try #require(staleCount > 0)
        let started = ContinuousClock.now
        let rebuilt = await WorkSearchIndex.rebuildIfNeeded(in: context)
        let seconds = benchmarkSeconds(since: started)
        let remaining = try fixture.makeContext().fetchCount(stale)
        try #require(rebuilt == staleCount && remaining == 0)
        try report.record("launch_search_index_rebuild", for: fixture, seconds: seconds, counts: [
            "stale_works_fetched": rebuilt
        ])
    }

    private func seedTags(
        _ fixture: LibraryScaleBenchmarkFixture, _ report: LibraryScaleBenchmarkReport
    ) throws {
        // The original fixture's trope pool lives in SavedWork metadata. These
        // cases need distinct persisted user tags, like the screens' @Query.
        let started = ContinuousClock.now
        for start in stride(from: 0, to: fixture.tagPoolSize, by: 2_000) {
            try autoreleasepool {
                let context = fixture.makeContext()
                context.autosaveEnabled = false
                for index in start..<min(start + 2_000, fixture.tagPoolSize) {
                    let name = index == fixture.tagPoolSize - 1 ? Self.rareTag : "Archive label \(index)"
                    context.insert(Kudos.Tag(name: name))
                }
                try context.save()
            }
        }
        try report.record("seed_user_tags", for: fixture, seconds: benchmarkSeconds(since: started), counts: [
            "tag_rows": fixture.tagPoolSize
        ])
    }

    private func measureLocalSearch(
        _ fixture: LibraryScaleBenchmarkFixture, _ report: LibraryScaleBenchmarkReport
    ) throws {
        let context = fixture.makeContext()
        let works = try context.fetch(Self.liveWorks)
        let visible = Self.libraryVisibility()
        for (label, query, expected) in [
            ("absent", "NoSuchArchivePalimpsest", 0), ("rare", Self.rareSearchTerm, 1), ("broad", "archivist", 20)
        ] {
            let started = ContinuousClock.now
            let terms = WorkSearchIndex.terms(from: query)
            let shown = works.filter(visible)
            let matches = Array(shown.lazy.filter { WorkSearchIndex.matches($0, terms: terms) }.prefix(20))
            let seconds = benchmarkSeconds(since: started)
            try #require(matches.count == expected)
            try report.record("local_search_\(label)", for: fixture, seconds: seconds, counts: [
                "works_fetched": works.count, "visible_works": shown.count, "returned_matches": matches.count
            ])
        }

        let tags = try context.fetch(FetchDescriptor<Kudos.Tag>(sortBy: [SortDescriptor(\.name)]))
        let fandoms = (0..<Self.fandomCount).map { AO3Fandom(name: "Fandom \($0)", workCount: $0) }
        let catalog = FandomCatalog.searchIndex(over: [fandoms])
        let started = ContinuousClock.now
        let fandomSuggestions = FandomCatalog.rankedMatches(
            in: catalog, normalizedQuery: WorkSearchIndex.normalize("Fandom 11"), limit: 12
        )
        let tagQuery = WorkSearchIndex.normalize(Self.rareTag)
        let tagSuggestions = Array(
            tags.lazy.filter { WorkSearchIndex.normalize($0.name).contains(tagQuery) }.prefix(12)
        )
        let seconds = benchmarkSeconds(since: started)
        try #require(!fandomSuggestions.isEmpty && tagSuggestions.count == 1)
        try report.record("local_search_suggestions", for: fixture, seconds: seconds, counts: [
            "catalog_entries": catalog.count, "tag_rows_fetched": tags.count,
            "fandom_suggestions": fandomSuggestions.count, "tag_suggestions": tagSuggestions.count
        ])
    }

    private func measureTags(
        _ fixture: LibraryScaleBenchmarkFixture, _ report: LibraryScaleBenchmarkReport
    ) throws {
        let context = fixture.makeContext()
        let descriptor = FetchDescriptor<Kudos.Tag>(sortBy: [SortDescriptor(\.name)])
        let started = ContinuousClock.now
        let tags = try context.fetch(descriptor)
        let names = tags.map(\.name)
        let listSeconds = benchmarkSeconds(since: started)
        try #require(names.count == fixture.tagPoolSize)
        try report.record("library_tag_list", for: fixture, seconds: listSeconds, counts: ["tags_fetched": tags.count])

        // The suggestion UI is view-local. Exercise the app's store-wide,
        // case-insensitive typed-name resolution on accepting a tag.
        let typedName = Self.rareTag.lowercased()
        let queueID = fixture.id(for: fixture.library + 3)
        let queueDescriptor = FetchDescriptor<ReadingQueue>(predicate: #Predicate { $0.id == queueID })
        let queue = try #require(try context.fetch(queueDescriptor).first)
        let resolutionStarted = ContinuousClock.now
        let resolved = queue.addTag(named: typedName, in: context)
        let resolutionSeconds = benchmarkSeconds(since: resolutionStarted)
        let tag = try #require(resolved)
        try #require(tag.name == Self.rareTag)
        try context.save()
        try report.record("library_tag_typed_lookup", for: fixture, seconds: resolutionSeconds, counts: [
            "tag_rows_before": tags.count
        ])

        let nextName = "Refiled \(Self.rareTag)"
        let renameStarted = ContinuousClock.now
        let conflict = Kudos.Tag.renameConflict(for: tag, proposedName: nextName, among: tags)
        try #require(conflict == nil)
        tag.name = nextName
        let saved = context.saveBestEffort(reason: "Saving benchmark tag rename failed")
        let renameSeconds = benchmarkSeconds(since: renameStarted)
        let renamed = FetchDescriptor<Kudos.Tag>(predicate: #Predicate { $0.name == nextName })
        let renameCount = try fixture.makeContext().fetchCount(renamed)
        try #require(saved && renameCount == 1)
        try report.record("library_tag_rename", for: fixture, seconds: renameSeconds, counts: [
            "candidate_tags": tags.count, "renamed_tags": renameCount
        ])
    }

    private func measurePairing(
        _ fixture: LibraryScaleBenchmarkFixture, _ report: LibraryScaleBenchmarkReport
    ) throws {
        let context = fixture.makeContext()
        let works = try context.fetch(Self.liveWorks)
        let page = (0..<20).map { index in
            // Even entries already exist and are live. Odd entries are new.
            let ordinal = index.isMultiple(of: 2) ? index * 10 : fixture.library + index
            return AO3WorkSummary.subscription(id: fixture.ao3ID(for: ordinal),
                                               title: "Archive work \(ordinal)", authors: ["Archivist"])
        }
        let started = ContinuousClock.now
        let paired = CanonicalWorkMerge.remoteLed(remote: page, localLibrary: works)
        let seconds = benchmarkSeconds(since: started)
        let localMatches = paired.compactMap(\.local).count
        try #require(paired.count == page.count && localMatches == 10)
        try report.record("remote_local_pairing_page_20", for: fixture, seconds: seconds, counts: [
            "works_fetched": works.count, "remote_results": page.count, "local_matches": localMatches
        ])
    }

    private func measureSessionHelpers(
        _ fixture: LibraryScaleBenchmarkFixture, _ report: LibraryScaleBenchmarkReport, anchor: Date
    ) throws {
        let defaultsName = "LibraryScaleBenchmark.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        let dirtyKey = "hasPendingFolderSyncChanges"
        let priorDirty = UserDefaults.standard.object(forKey: dirtyKey)
        defer {
            defaults.removePersistentDomain(forName: defaultsName)
            UserDefaults.standard.set(priorDirty, forKey: dirtyKey)
        }
        try autoreleasepool { try measureSittingFinish(fixture, report, anchor: anchor, defaults: defaults) }
        try autoreleasepool { try measureSittingCheckpoint(fixture, report, anchor: anchor, defaults: defaults) }
        try autoreleasepool { try measureWatermarks(fixture, report, anchor: anchor) }
    }

    private func measureSittingFinish(
        _ fixture: LibraryScaleBenchmarkFixture, _ report: LibraryScaleBenchmarkReport,
        anchor: Date, defaults: UserDefaults
    ) throws {
        let context = fixture.makeContext()
        let work = try fixture.work(at: 30, in: context)
        let chapterWords = try #require(work.chapterWordCounts.dropFirst().first)
        try #require(chapterWords >= ChapterTiming.skimMinimumWords && !work.isFinished)
        let readRows = FetchDescriptor<ReadingSession>(predicate: #Predicate { $0.modeRaw == "read" })
        let before = try context.fetchCount(readRows)
        let opened = anchor.addingTimeInterval(123)
        ReadingLogService.startSession(for: work, now: opened, defaults: defaults)
        ReadingLogService.noteActivity(for: work, chapter: .init(spineIndex: 0, storyChapter: 1), now: opened)
        ReadingLogService.noteActivity(
            for: work, chapter: .init(spineIndex: 1, storyChapter: 2), now: opened.addingTimeInterval(60)
        )
        ReadingLogService.noteActivity(
            for: work, chapter: .init(spineIndex: 2, storyChapter: 3), now: opened.addingTimeInterval(120)
        )
        work.isFinished = true
        work.legacyReaderProgress = 1
        let started = ContinuousClock.now
        ReadingLogService.endSession(for: work, now: opened.addingTimeInterval(180))
        let seconds = benchmarkSeconds(since: started)
        let verification = fixture.makeContext()
        let sitting = try Self.sitting(for: work.id, opened: opened, in: verification)
        try #require(sitting.didFinish && sitting.chapterWords[1] == chapterWords)
        try report.record("reading_session_finish", for: fixture, seconds: seconds, counts: [
            "other_read_sittings_before": before, "whole_chapters": sitting.chapterWords.count
        ])
    }

    private func measureSittingCheckpoint(
        _ fixture: LibraryScaleBenchmarkFixture, _ report: LibraryScaleBenchmarkReport,
        anchor: Date, defaults: UserDefaults
    ) throws {
        let context = fixture.makeContext()
        let work = try fixture.work(at: 45, in: context)
        let chapterWords = try #require(work.chapterWordCounts.dropFirst().first)
        try #require(chapterWords >= ChapterTiming.skimMinimumWords)
        let readRows = FetchDescriptor<ReadingSession>(predicate: #Predicate { $0.modeRaw == "read" })
        let before = try context.fetchCount(readRows)
        let opened = anchor.addingTimeInterval(321)
        ReadingLogService.startSession(for: work, now: opened, defaults: defaults)
        defer { ReadingLogService.endSession(for: work, now: opened.addingTimeInterval(181)) }
        ReadingLogService.noteActivity(for: work, chapter: .init(spineIndex: 0, storyChapter: 1), now: opened)
        ReadingLogService.noteActivity(
            for: work, chapter: .init(spineIndex: 1, storyChapter: 2), now: opened.addingTimeInterval(60)
        )
        ReadingLogService.pauseSession(for: work, now: opened.addingTimeInterval(90))
        let checkpointContext = fixture.makeContext()
        let checkpoint = try Self.sitting(for: work.id, opened: opened, in: checkpointContext)
        let checkpointID = checkpoint.id
        try #require(checkpoint.chapterWords.isEmpty)
        ReadingLogService.resumeSession(for: work, now: opened.addingTimeInterval(91))
        ReadingLogService.noteActivity(
            for: work, chapter: .init(spineIndex: 2, storyChapter: 3), now: opened.addingTimeInterval(120)
        )
        let started = ContinuousClock.now
        ReadingLogService.endSession(for: work, now: opened.addingTimeInterval(180))
        let seconds = benchmarkSeconds(since: started)
        let verification = fixture.makeContext()
        let corrected = try Self.sitting(for: work.id, opened: opened, in: verification)
        try #require(corrected.id == checkpointID && corrected.chapterWords[1] == chapterWords)
        try report.record("reading_session_checkpoint_update", for: fixture, seconds: seconds, counts: [
            "other_read_sittings_before": before, "whole_chapters": corrected.chapterWords.count
        ])
    }

    private static func sitting(for workID: UUID, opened: Date, in context: ModelContext) throws -> ReadingSession {
        let descriptor = FetchDescriptor<ReadingSession>(
            predicate: #Predicate { $0.workID == workID && $0.startedAt == opened }
        )
        let matches = try context.fetch(descriptor)
        try #require(matches.count == 1)
        return try #require(matches.first)
    }

    private func measureWatermarks(
        _ fixture: LibraryScaleBenchmarkFixture, _ report: LibraryScaleBenchmarkReport, anchor: Date
    ) throws {
        let context = fixture.makeContext()
        let previous = anchor.addingTimeInterval(-86_400)
        for index in 0..<Self.fandomCount {
            context.insert(FandomReadWatermark(
                id: fixture.id(for: 9_002_000 + index), fandomName: "Fandom \(index)", lastVisitedAt: previous
            ))
        }
        try context.save()

        let visitContext = fixture.makeContext()
        let work = try fixture.work(at: Self.fandomCount - 1, in: visitContext)
        let fandom = try #require(work.workFandoms.first)
        let started = ContinuousClock.now
        let lastVisit = ReadingLogService.lastVisit(fandom: fandom, in: visitContext)
        ReadingLogService.markVisited(fandom: fandom, newestWork: work, in: visitContext, now: anchor)
        let seconds = benchmarkSeconds(since: started)
        let descriptor = FetchDescriptor<FandomReadWatermark>(predicate: #Predicate { $0.fandomName == fandom })
        let verification = fixture.makeContext()
        let updated = try #require(try verification.fetch(descriptor).first)
        try #require(lastVisit == previous && updated.lastVisitedAt == anchor)
        try #require(updated.newestWorkIDSeen == work.ao3WorkID)
        try report.record("fandom_watermarks", for: fixture, seconds: seconds, counts: [
            "watermark_rows_before": Self.fandomCount, "watermarks_updated": 1
        ])
    }

    private static var liveWorks: FetchDescriptor<SavedWork> {
        FetchDescriptor<SavedWork>(
            predicate: #Predicate { !$0.isPendingDeletion },
            sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
        )
    }

    private static var rareSearchTerm: String { "UncataloguedPalimpsest" }
    private static var rareTag: String { "Ziggurat transcription" }
    private static var fandomCount: Int { 1_200 }

    private static func libraryVisibility() -> (SavedWork) -> Bool {
        let gate = PrivacyGate()
        return { !gate.isHidden($0, enabled: true, mode: .hide) }
    }
}
