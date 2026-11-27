import Foundation
import SwiftData

// T-537p: Reading Insights gathers off the main actor. A `@ModelActor` with its own context
// fetches in bounded batches and hands back plain `Sendable` figures; the view applies them on
// the main actor, and only if no newer reload has started since (`InsightsGatherRunner`).

/// What one Insights reload asks the gather actor for. Plain values only, so it can cross the
/// actor boundary: no model objects, no context.
nonisolated struct InsightsGatherRequest: Sendable {
    var period: DateInterval
    var previousPeriod: DateInterval
    var periodMonths: Double
    var calendar: Calendar
    var options: InsightsOptions
    var scope: InsightsScope
    var hideMature: Bool
    var revealed: Bool
    /// Also gathers the Hidden section (the screen asks only while `hideMature && revealed`).
    var includesHiddenSection: Bool
    /// Also takes the library digest from the rows already fetched (one walk, not two).
    var computesDigest: Bool
    var now: Date
    /// Rows per fetch. Tests shrink it to count the fetches.
    var batchSize: Int = 2_000
}

/// How the rows were fetched, so a test can prove the gather paged instead of loading a table
/// in one fetch. Counts batches that returned rows.
nonisolated struct InsightsGatherFetchStatistics: Equatable, Sendable {
    var workBatches = 0
    var sessionBatches = 0
    var worksFetched = 0
    var sessionsFetched = 0
    var largestBatch = 0
}

/// One scope's figures, with no model objects: finished works travel as ids and the view looks
/// them up in its own context.
nonisolated struct InsightsGatherFigures: Sendable {
    var insights: ReadingInsights
    var taste: ReadingTasteInsights?
    var habits: ReadingHabitsInsights
    var chapterTiming: InsightsProvenance.ChapterTimingFigure
    /// `library.stillReadingCandidate.work` is a model object of the gather actor's own context:
    /// never read it. `InsightsGatherFigures.libraryInsights(resolving:)` swaps in the view's.
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
    /// The library figures with the "still reading" card pointing at the caller's own model
    /// object (the card opens it); dropped when that work is no longer in `works`.
    func libraryInsights(resolving works: [SavedWork]) -> ReadingLibraryInsights {
        var resolved = library
        guard var candidate = resolved.stillReadingCandidate else { return resolved }
        if let work = works.first(where: { $0.id == candidate.id }) {
            candidate.work = work
            resolved.stillReadingCandidate = candidate
        } else {
            resolved.stillReadingCandidate = nil
        }
        return resolved
    }

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

/// Fetches and computes every Reading Insights figure on its own `ModelContext`. Reads only:
/// nothing here inserts, deletes or saves.
///
/// shortcut: the figure functions take whole arrays, so every fetched row is still held in this
/// actor's memory at once (off the main thread); the batches bound each fetch and give
/// cancellation a point to stop at. Upgrade to streaming aggregates if memory, not latency,
/// becomes the limit. Sessions are paged by offset in store order (a sort would re-sort the
/// whole table per batch); a delete by another context mid-gather can shift a row out of the
/// window, and the save that caused it schedules the next reload anyway.
@ModelActor
actor InsightsGatherActor {
    private var fetches = InsightsGatherFetchStatistics()

    /// Fetch counts of the latest `gather` / `digest`.
    var fetchStatistics: InsightsGatherFetchStatistics { fetches }

    var hasUnsavedChanges: Bool { modelContext.hasChanges }

    func gather(_ request: InsightsGatherRequest) throws -> InsightsGatherOutput {
        fetches = InsightsGatherFetchStatistics()
        let batchSize = max(1, request.batchSize)
        let works = try fetchLiveWorks(batchSize: batchSize)
        let sessions = try fetchSessions(batchSize: batchSize)
        try Task.checkCancellation()
        let main = figures(for: request.scope, works: works, sessions: sessions, request: request)
        var hidden: InsightsGatherFigures?
        if request.includesHiddenSection {
            try Task.checkCancellation()
            hidden = figures(for: .hidden, works: works, sessions: sessions, request: request)
        }
        var digest: InsightsReloadDigest.Snapshot?
        if request.computesDigest {
            try Task.checkCancellation()
            digest = InsightsReloadDigest.snapshot(
                works: works,
                context: modelContext,
                now: request.now,
                calendar: request.calendar,
                preloadedSessions: sessions
            )
        }
        return InsightsGatherOutput(main: main, hidden: hidden, digest: digest, fetches: fetches)
    }

    /// Only the invalidation digest, for a save that may or may not have moved a figure.
    func digest(
        batchSize: Int = 2_000,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> InsightsReloadDigest.Snapshot {
        fetches = InsightsGatherFetchStatistics()
        let size = max(1, batchSize)
        let works = try fetchLiveWorks(batchSize: size)
        let sessions = try fetchSessions(batchSize: size)
        try Task.checkCancellation()
        return InsightsReloadDigest.snapshot(
            works: works,
            context: modelContext,
            now: now,
            calendar: calendar,
            preloadedSessions: sessions
        )
    }

    private func figures(
        for scope: InsightsScope,
        works: [SavedWork],
        sessions: [ReadingSession],
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
            rawSessions: sessions,
            now: request.now
        )
        return InsightsGatherFigures(result)
    }

    /// Every live (not in Recently Deleted) work, newest saved first like the screen's own query.
    private func fetchLiveWorks(batchSize: Int) throws -> [SavedWork] {
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
            works.append(contentsOf: batch)
            offset += batch.count
            if batch.count < batchSize { break }
        }
        return works
    }

    private func fetchSessions(batchSize: Int) throws -> [ReadingSession] {
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
            sessions.append(contentsOf: batch)
            offset += batch.count
            if batch.count < batchSize { break }
        }
        return sessions
    }
}

/// Runs the latest reload and nothing older: starting a run cancels the one in flight, and a
/// result is applied only if its run is still the newest and was not cancelled, even when the
/// gather itself ignores cancellation.
@MainActor
final class InsightsGatherRunner<Output: Sendable> {
    private var generation = 0
    private var task: Task<Void, Never>?

    @discardableResult
    func start(
        gather: @escaping @Sendable () async throws -> Output,
        apply: @escaping @MainActor (Output) -> Void
    ) -> Task<Void, Never> {
        generation += 1
        let mine = generation
        task?.cancel()
        let run = Task { [weak self] in
            let output = try? await gather()
            guard !Task.isCancelled, let self, self.generation == mine, let output else { return }
            apply(output)
        }
        task = run
        return run
    }

    /// Stops the run in flight and keeps its result from being applied.
    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
    }

    /// Returns when the current run has finished (a pull to refresh waits on this).
    func waitForCurrent() async {
        await task?.value
    }
}
