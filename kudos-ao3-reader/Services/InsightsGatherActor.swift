import Foundation
import SwiftData

// T-537p: Reading Insights gathers off the main actor. A `@ModelActor` with its own fresh
// context fetches every table in bounded batches and hands back plain `Sendable` figures with
// no model objects; the view applies them on the main actor only if no newer reload has started.

/// What one Insights reload asks the gather actor for. Plain values only, so it can cross the
/// actor boundary: no model objects, no context.
nonisolated struct InsightsGatherRequest: Sendable {
    var period: DateInterval
    var previousPeriod: DateInterval?
    var periodMonths: Double = 1
    var calendar: Calendar = .current
    var options: InsightsOptions = InsightsOptions()
    var scope: InsightsScope = .main
    var hideMature: Bool = false
    var revealed: Bool = false
    /// Also gathers the Hidden section (the screen asks only while `hideMature && revealed`).
    var includesHiddenSection: Bool = false
    /// Also takes the library digest from the rows already fetched (one walk, not two).
    var computesDigest: Bool = true
    var now: Date = Date()
    /// Rows per fetch. Tests shrink it to count the fetches.
    var batchSize: Int = 2_000
}

/// How the rows were fetched, so tests can prove the gather paged every table instead of loading
/// a full table in one fetch. Counts batches that returned rows.
nonisolated struct InsightsGatherFetchStatistics: Equatable, Sendable {
    var workBatches = 0
    var softDeletedWorkBatches = 0
    var sessionBatches = 0
    var aliasBatches = 0
    var seriesBatches = 0
    var worksFetched = 0
    var softDeletedWorksFetched = 0
    var sessionsFetched = 0
    var aliasesFetched = 0
    var seriesFetched = 0
    var largestBatch = 0

    var totalBatches: Int {
        workBatches + softDeletedWorkBatches + sessionBatches + aliasBatches + seriesBatches
    }
}

/// One scope's figures, with no model objects: finished works and any still-reading candidate
/// travel as plain value types / ids and the view resolves live works in its own context.
nonisolated struct InsightsGatherFigures: Equatable, Sendable {
    var insights: ReadingInsights
    var taste: ReadingTasteInsights?
    var habits: ReadingHabitsInsights
    var chapterTiming: InsightsProvenance.ChapterTimingFigure
    var library: ReadingLibraryInsights
    var libraryStats: ReadingStatistics
    var finishedWorkIDs: [UUID]
    var discreetMasker: InsightsDiscreetMasker

    init(_ result: ReadingLogService.InsightsGatherResult) {
        insights = result.insights
        taste = result.taste
        habits = result.habits
        chapterTiming = result.chapterTiming
        library = result.library
        libraryStats = result.libraryStats
        finishedWorkIDs = result.finishedWorksInPeriod.map { $0.id }
        discreetMasker = result.discreetMasker
    }
}

@MainActor
extension InsightsGatherFigures {
    /// The works finished in the period, as the caller's own model objects, in gather order.
    func finishedWorks(in works: [SavedWork]) -> [SavedWork] {
        let byID = Dictionary(works.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return finishedWorkIDs.compactMap { byID[$0] }
    }
}

nonisolated struct InsightsGatherOutput: Sendable {
    var main: InsightsGatherFigures
    var hidden: InsightsGatherFigures?
    var digest: InsightsReloadDigest.Snapshot?
    var fetches: InsightsGatherFetchStatistics
}

/// Fetches and computes every Reading Insights figure on its own fresh `ModelContext`.
/// Reads only: nothing here inserts, updates, deletes, or saves.
///
/// shortcut: the figure functions take whole `[SavedWork]` / `[ReadingSession]` arrays, so live
/// works and sessions are still held in this actor's memory while `gather` runs (off the main
/// thread); bounded batches cap each SQLite fetch and check cancellation between pages, while
/// soft-deleted works, tag aliases, series snapshots, and standalone `digest` walks stream
/// without retaining whole model tables. Upgrade the figure functions to streaming aggregates if
/// background memory, not main-thread latency, becomes the limit. Sessions are paged by offset in
/// store order (a sort would re-sort the whole table per batch); a delete by another context
/// mid-gather can shift a row out of the window, and the save that caused it schedules the next
/// reload anyway.
@ModelActor
actor InsightsGatherActor {
    private var fetches = InsightsGatherFetchStatistics()

    /// Fetch counts of the latest `gather` / `digest` (updated even when cancelled mid-flight).
    var fetchStatistics: InsightsGatherFetchStatistics { fetches }

    var hasUnsavedChanges: Bool { modelContext.hasChanges }

    func gather(
        _ request: InsightsGatherRequest,
        afterBatch: (@Sendable () async -> Void)? = nil
    ) async throws -> InsightsGatherOutput {
        var localFetches = InsightsGatherFetchStatistics()
        defer { fetches = localFetches }

        let batchSize = max(1, request.batchSize)
        var digestBuilder = request.computesDigest
            ? InsightsReloadDigest.Builder(now: request.now, calendar: request.calendar)
            : nil

        let works = try await fetchLiveWorks(
            batchSize: batchSize,
            fetches: &localFetches,
            digestBuilder: &digestBuilder,
            afterBatch: afterBatch
        )
        let softDeleted = try await fetchSoftDeletedWorkIDs(
            batchSize: batchSize,
            fetches: &localFetches,
            afterBatch: afterBatch
        )
        digestBuilder?.addSoftDeleted(softDeleted)

        let sessions = try await fetchSessions(
            batchSize: batchSize,
            fetches: &localFetches,
            digestBuilder: &digestBuilder,
            afterBatch: afterBatch
        )
        let aliases = try await fetchAliases(
            batchSize: batchSize,
            fetches: &localFetches,
            digestBuilder: &digestBuilder,
            afterBatch: afterBatch
        )
        let seriesSnapshots = try await fetchSeries(
            batchSize: batchSize,
            fetches: &localFetches,
            digestBuilder: &digestBuilder,
            afterBatch: afterBatch
        )

        try Task.checkCancellation()
        let main = figures(
            for: request.scope,
            works: works,
            sessions: sessions,
            aliases: aliases,
            seriesSnapshots: seriesSnapshots,
            softDeleted: softDeleted,
            request: request
        )
        var hidden: InsightsGatherFigures?
        if request.includesHiddenSection {
            try Task.checkCancellation()
            hidden = figures(
                for: .hidden,
                works: works,
                sessions: sessions,
                aliases: aliases,
                seriesSnapshots: seriesSnapshots,
                softDeleted: softDeleted,
                request: request
            )
        }
        let digest: InsightsReloadDigest.Snapshot?
        if let digestBuilder {
            try Task.checkCancellation()
            digest = digestBuilder.build()
        } else {
            digest = nil
        }
        return InsightsGatherOutput(main: main, hidden: hidden, digest: digest, fetches: localFetches)
    }

    /// Only the invalidation digest, for a save that may or may not have moved a figure.
    /// Streams every table batch-by-batch without retaining full model arrays across batches.
    func digest(
        batchSize: Int = 2_000,
        now: Date = Date(),
        calendar: Calendar = .current,
        afterBatch: (@Sendable () async -> Void)? = nil
    ) async throws -> InsightsReloadDigest.Snapshot {
        var localFetches = InsightsGatherFetchStatistics()
        defer { fetches = localFetches }

        let size = max(1, batchSize)
        var builder = InsightsReloadDigest.Builder(now: now, calendar: calendar)

        try await streamLiveWorks(batchSize: size, fetches: &localFetches, into: &builder, afterBatch: afterBatch)
        let softDeleted = try await fetchSoftDeletedWorkIDs(
            batchSize: size,
            fetches: &localFetches,
            afterBatch: afterBatch
        )
        builder.addSoftDeleted(softDeleted)
        try await streamSessions(batchSize: size, fetches: &localFetches, into: &builder, afterBatch: afterBatch)
        var optionalBuilder: InsightsReloadDigest.Builder? = builder
        _ = try await fetchAliases(
            batchSize: size,
            fetches: &localFetches,
            digestBuilder: &optionalBuilder,
            afterBatch: afterBatch
        )
        _ = try await fetchSeries(
            batchSize: size,
            fetches: &localFetches,
            digestBuilder: &optionalBuilder,
            afterBatch: afterBatch
        )
        try Task.checkCancellation()
        return (optionalBuilder ?? builder).build()
    }

    private func figures(
        for scope: InsightsScope,
        works: [SavedWork],
        sessions: [ReadingSession],
        aliases: TagAliasResolver,
        seriesSnapshots: [SavedSeriesSnapshot],
        softDeleted: (all: Set<UUID>, adult: Set<UUID>),
        request: InsightsGatherRequest
    ) -> InsightsGatherFigures {
        let selection = HomeReadingStats.insightsScope(
            scope,
            from: works,
            hideMature: request.hideMature,
            revealed: request.revealed
        )
        let result = ReadingLogService.gatherInsights(
            for: request.period,
            previousPeriod: request.previousPeriod,
            scope: selection,
            periodMonths: request.periodMonths,
            calendar: request.calendar,
            context: modelContext,
            options: request.options,
            aliases: aliases,
            rawSessions: sessions,
            seriesSnapshots: seriesSnapshots,
            softDeleted: softDeleted,
            now: request.now
        )
        return InsightsGatherFigures(result)
    }

    /// Every live (not in Recently Deleted) work, newest saved first like the screen's own query.
    private func fetchLiveWorks(
        batchSize: Int,
        fetches: inout InsightsGatherFetchStatistics,
        digestBuilder: inout InsightsReloadDigest.Builder?,
        afterBatch: (@Sendable () async -> Void)?
    ) async throws -> [SavedWork] {
        var works: [SavedWork] = []
        var offset = 0
        while true {
            try Task.checkCancellation()
            var descriptor = FetchDescriptor<SavedWork>(
                predicate: #Predicate { !$0.isPendingDeletion },
                sortBy: [SortDescriptor(\.dateAdded, order: .reverse), SortDescriptor(\.id)]
            )
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = offset
            let batch = try modelContext.fetch(descriptor)
            guard !batch.isEmpty else { break }
            fetches.workBatches += 1
            fetches.worksFetched += batch.count
            fetches.largestBatch = max(fetches.largestBatch, batch.count)
            if digestBuilder != nil {
                for work in batch {
                    digestBuilder?.addLiveWork(work)
                }
            }
            works.append(contentsOf: batch)
            offset += batch.count
            if batch.count < batchSize { break }
            if let afterBatch { await afterBatch() }
            await Task.yield()
        }
        return works
    }

    private func streamLiveWorks(
        batchSize: Int,
        fetches: inout InsightsGatherFetchStatistics,
        into builder: inout InsightsReloadDigest.Builder,
        afterBatch: (@Sendable () async -> Void)?
    ) async throws {
        var offset = 0
        while true {
            try Task.checkCancellation()
            var descriptor = FetchDescriptor<SavedWork>(
                predicate: #Predicate { !$0.isPendingDeletion },
                sortBy: [SortDescriptor(\.dateAdded, order: .reverse), SortDescriptor(\.id)]
            )
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = offset
            let batch = try modelContext.fetch(descriptor)
            guard !batch.isEmpty else { break }
            fetches.workBatches += 1
            fetches.worksFetched += batch.count
            fetches.largestBatch = max(fetches.largestBatch, batch.count)
            for work in batch {
                builder.addLiveWork(work)
            }
            offset += batch.count
            if batch.count < batchSize { break }
            if let afterBatch { await afterBatch() }
            await Task.yield()
        }
    }

    private func fetchSoftDeletedWorkIDs(
        batchSize: Int,
        fetches: inout InsightsGatherFetchStatistics,
        afterBatch: (@Sendable () async -> Void)?
    ) async throws -> (all: Set<UUID>, adult: Set<UUID>) {
        var all: Set<UUID> = []
        var adult: Set<UUID> = []
        var offset = 0
        while true {
            try Task.checkCancellation()
            var descriptor = FetchDescriptor<SavedWork>(
                predicate: #Predicate { $0.isPendingDeletion }
            )
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = offset
            let batch = try modelContext.fetch(descriptor)
            guard !batch.isEmpty else { break }
            fetches.softDeletedWorkBatches += 1
            fetches.softDeletedWorksFetched += batch.count
            fetches.largestBatch = max(fetches.largestBatch, batch.count)
            for work in batch {
                all.insert(work.id)
                if work.isAdult { adult.insert(work.id) }
            }
            offset += batch.count
            if batch.count < batchSize { break }
            if let afterBatch { await afterBatch() }
            await Task.yield()
        }
        return (all, adult)
    }

    private func fetchSessions(
        batchSize: Int,
        fetches: inout InsightsGatherFetchStatistics,
        digestBuilder: inout InsightsReloadDigest.Builder?,
        afterBatch: (@Sendable () async -> Void)?
    ) async throws -> [ReadingSession] {
        var sessions: [ReadingSession] = []
        var offset = 0
        while true {
            try Task.checkCancellation()
            var descriptor = FetchDescriptor<ReadingSession>()
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = offset
            let batch = try modelContext.fetch(descriptor)
            guard !batch.isEmpty else { break }
            fetches.sessionBatches += 1
            fetches.sessionsFetched += batch.count
            fetches.largestBatch = max(fetches.largestBatch, batch.count)
            if digestBuilder != nil {
                for session in batch {
                    digestBuilder?.addSession(session)
                }
            }
            sessions.append(contentsOf: batch)
            offset += batch.count
            if batch.count < batchSize { break }
            if let afterBatch { await afterBatch() }
            await Task.yield()
        }
        return sessions
    }

    private func streamSessions(
        batchSize: Int,
        fetches: inout InsightsGatherFetchStatistics,
        into builder: inout InsightsReloadDigest.Builder,
        afterBatch: (@Sendable () async -> Void)?
    ) async throws {
        var offset = 0
        while true {
            try Task.checkCancellation()
            var descriptor = FetchDescriptor<ReadingSession>()
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = offset
            let batch = try modelContext.fetch(descriptor)
            guard !batch.isEmpty else { break }
            fetches.sessionBatches += 1
            fetches.sessionsFetched += batch.count
            fetches.largestBatch = max(fetches.largestBatch, batch.count)
            for session in batch {
                builder.addSession(session)
            }
            offset += batch.count
            if batch.count < batchSize { break }
            if let afterBatch { await afterBatch() }
            await Task.yield()
        }
    }

    private func fetchAliases(
        batchSize: Int,
        fetches: inout InsightsGatherFetchStatistics,
        digestBuilder: inout InsightsReloadDigest.Builder?,
        afterBatch: (@Sendable () async -> Void)?
    ) async throws -> TagAliasResolver {
        var entries: [TagAliasResolver.Entry] = []
        var offset = 0
        while true {
            try Task.checkCancellation()
            var descriptor = FetchDescriptor<TagAlias>()
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = offset
            let batch = try modelContext.fetch(descriptor)
            guard !batch.isEmpty else { break }
            fetches.aliasBatches += 1
            fetches.aliasesFetched += batch.count
            fetches.largestBatch = max(fetches.largestBatch, batch.count)
            for alias in batch {
                digestBuilder?.addAlias(alias)
                guard !alias.isDeleted else { continue }
                entries.append(TagAliasResolver.Entry(
                    name: alias.name,
                    canonicalName: alias.canonicalName,
                    kind: alias.kind,
                    parentFandoms: alias.parentFandoms
                ))
            }
            offset += batch.count
            if batch.count < batchSize { break }
            if let afterBatch { await afterBatch() }
            await Task.yield()
        }
        return TagAliasResolver(entries: entries)
    }

    private func fetchSeries(
        batchSize: Int,
        fetches: inout InsightsGatherFetchStatistics,
        digestBuilder: inout InsightsReloadDigest.Builder?,
        afterBatch: (@Sendable () async -> Void)?
    ) async throws -> [SavedSeriesSnapshot] {
        var snapshots: [SavedSeriesSnapshot] = []
        var offset = 0
        while true {
            try Task.checkCancellation()
            var descriptor = FetchDescriptor<SavedSeries>()
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = offset
            let batch = try modelContext.fetch(descriptor)
            guard !batch.isEmpty else { break }
            fetches.seriesBatches += 1
            fetches.seriesFetched += batch.count
            fetches.largestBatch = max(fetches.largestBatch, batch.count)
            for series in batch {
                digestBuilder?.addSeries(series)
                snapshots.append(series.snapshot)
            }
            offset += batch.count
            if batch.count < batchSize { break }
            if let afterBatch { await afterBatch() }
            await Task.yield()
        }
        return snapshots
    }
}

/// Runs the latest reload and nothing older: starting a run cancels the one in flight, and a
/// result is applied only if its run is still the newest and was not cancelled, even when the
/// gather itself ignores cancellation.
@MainActor
final class InsightsGatherRunner<Output: Sendable> {
    private var generation = 0
    private var task: Task<Void, Never>?
    private(set) var isRunning = false

    var currentGeneration: Int { generation }

    @discardableResult
    func start(
        gather: @escaping @Sendable () async throws -> Output,
        apply: @escaping @MainActor (Output) -> Void
    ) -> Task<Void, Never> {
        generation += 1
        let mine = generation
        task?.cancel()
        isRunning = true
        let run = Task { [weak self] in
            let output = try? await gather()
            guard let self, self.generation == mine else { return }
            self.isRunning = false
            guard !Task.isCancelled, let output else { return }
            apply(output)
        }
        task = run
        return run
    }

    /// Stops the run in flight and keeps its result from being applied.
    func cancel() {
        generation += 1
        isRunning = false
        task?.cancel()
        task = nil
    }

    /// Returns when the latest run has finished (a pull to refresh waits on this).
    func waitForCurrent() async {
        while let current = task {
            let gen = generation
            await current.value
            if generation == gen { break }
        }
    }
}
