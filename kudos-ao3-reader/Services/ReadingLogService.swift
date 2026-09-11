import Foundation
import SwiftData

/// Session lifecycle and query helpers for the local reading log.
///
/// One tracker: `startSession` / `endSession` around reader appear/disappear.
/// Mid-scroll `applyDebouncedReadiumLocator` must not write a session. Progress
/// itself still goes through `SavedWork.markProgressModified` — this type does
/// not invent a second progress writer.
@MainActor
enum ReadingLogService {
    /// Accidental opens (tap-and-back) are not history.
    static let minimumPersistableDuration: TimeInterval = 15
    /// 1ai default: mid-way and untouched for this long, and no manual override.
    static let defaultAbandonedThreshold: TimeInterval = 21 * 24 * 3600

    private struct OpenSession {
        /// The `ReadingSession.id` this visit writes to. Fixed when the session
        /// opens so a background flush and the final write land on **one** row
        /// rather than two — see `persist`.
        var recordID: UUID
        var workID: UUID
        var ao3WorkID: Int?
        var sourceURL: String
        var workTitle: String
        var startedAt: Date
        var lastResumedAt: Date
        var accumulatedSeconds: Double
        var isPaused: Bool
        /// Whether the work was already finished when this visit opened.
        ///
        /// Held here so the service can work out for itself whether *this* visit
        /// was the one that finished the work. It used to be the view's job — all
        /// three call sites wrote `work.isFinished && !finishedWhenSessionStarted`
        /// — which meant `pauseSession`, having no such flag, hard-coded `false`
        /// and silently dropped the finish on every backgrounded session.
        var wasFinishedAtStart: Bool
    }

    private static var openSessions: [UUID: OpenSession] = [:]

    /// Opens a session for `work` if one is not already open. A second call for
    /// the same work is a no-op so SwiftUI re-appear / book-reload cannot
    /// double-count.
    static func startSession(for work: SavedWork, now: Date = Date()) {
        let workID = work.id
        guard openSessions[workID] == nil else { return }
        openSessions[workID] = OpenSession(
            recordID: UUID(),
            workID: workID,
            ao3WorkID: work.ao3WorkID,
            sourceURL: work.sourceURL,
            workTitle: work.title,
            startedAt: now,
            lastResumedAt: now,
            accumulatedSeconds: 0,
            isPaused: false,
            wasFinishedAtStart: work.isFinished
        )
    }

    /// Whether this visit is the one that finished the work — the reread signal.
    ///
    /// Derived from the session's own opening state rather than passed in, so
    /// every writer agrees. A visit that opens on an already-finished work never
    /// counts as a finish however it ends, which is what stops a reread being
    /// counted twice for one read-through.
    private static func didFinish(_ session: OpenSession, for work: SavedWork) -> Bool {
        work.isFinished && !session.wasFinishedAtStart
    }

    /// Stops accumulating wall time (app backgrounded). No-op if none is open.
    ///
    /// **Writes the row as well as banking the time.** Open sessions live in
    /// memory, and `endSession` runs from the reader's `onDisappear` — which
    /// never fires when iOS reclaims a backgrounded app, so everything read
    /// before backgrounding was being lost with the process. The bias ran the
    /// wrong way, too: the longer someone reads, the likelier the app is
    /// reclaimed before they return, so the sessions most worth counting were
    /// the ones most likely to vanish. Progress already flushes here for the
    /// same reason ("force-quit safety" in `ReadiumReaderView`); the log now
    /// does too.
    static func pauseSession(for work: SavedWork, now: Date = Date()) {
        guard var session = openSessions[work.id], !session.isPaused else { return }
        session.accumulatedSeconds += max(0, now.timeIntervalSince(session.lastResumedAt))
        session.lastResumedAt = now
        session.isPaused = true
        openSessions[work.id] = session
        // The finish is carried, not deferred. Writing `false` here loses the
        // event outright: finish a work, background the app, let iOS reclaim it,
        // and the row says the visit did not finish — while reopening cannot
        // recover it, because by then the work is *already* finished and the new
        // session's transition is false too. `persist` only ever raises
        // `didFinish`, so a later pause cannot unset what this one recorded.
        persist(session, for: work, now: now, didFinish: didFinish(session, for: work))
    }

    /// Resumes after `pauseSession`. No-op if none is open or it is not paused.
    static func resumeSession(for work: SavedWork, now: Date = Date()) {
        guard var session = openSessions[work.id], session.isPaused else { return }
        session.lastResumedAt = now
        session.isPaused = false
        openSessions[work.id] = session
    }

    /// Persists the open session, or drops it when shorter than 15 seconds.
    ///
    /// The reread signal is computed here rather than supplied: see
    /// `didFinish(_:for:)`. Callers used to pass it and all three wrote the same
    /// expression, which is how `pauseSession` came to write a fourth, wrong one.
    static func endSession(for work: SavedWork, now: Date = Date()) {
        guard var session = openSessions.removeValue(forKey: work.id) else { return }
        if !session.isPaused {
            session.accumulatedSeconds += max(0, now.timeIntervalSince(session.lastResumedAt))
        }
        persist(session, for: work, now: now, didFinish: didFinish(session, for: work))
    }

    /// Writes this visit's row, creating it on the first call and updating it on
    /// every later one. Keyed by `OpenSession.recordID`, so a visit that is
    /// backgrounded and resumed several times is one row with a growing
    /// duration rather than one row per stretch — which matters because
    /// `didFinish` drives the reread count, and three rows for one finish would
    /// count it three times.
    ///
    /// Still refuses anything under `minimumPersistableDuration`: a tap-and-back
    /// is not history, and a session that never reaches 15 seconds never gets a
    /// row to update.
    private static func persist(
        _ session: OpenSession,
        for work: SavedWork,
        now: Date,
        didFinish: Bool
    ) {
        let durationSeconds = max(0, session.accumulatedSeconds)
        guard durationSeconds >= minimumPersistableDuration else { return }
        guard let context = work.modelContext else { return }

        let chapterTitle = WorkReadingPosition.title(from: work.readiumLocator) ?? ""
        let endingProgress = min(1, max(0, work.readingProgress ?? 0))
        let recordID = session.recordID
        let existing = try? context.fetch(
            FetchDescriptor<ReadingSession>(predicate: #Predicate { $0.id == recordID })
        ).first

        if let existing {
            existing.endedAt = now
            existing.durationSeconds = durationSeconds
            existing.lastSpineIndex = work.lastSpineIndex
            existing.chapterTitle = chapterTitle
            existing.endingProgress = endingProgress
            existing.wordCount = work.wordCount
            existing.chapterCountAtVisit = work.postedChapterCount
            // Never clears a finish already recorded if a later checkpoint or
            // close reports false for the same visit.
            existing.didFinish = existing.didFinish || didFinish
            existing.lastModifiedAt = now
        } else {
            context.insert(ReadingSession(
                id: recordID,
                workID: session.workID,
                ao3WorkID: work.ao3WorkID ?? session.ao3WorkID,
                sourceURL: work.sourceURL.isEmpty ? session.sourceURL : work.sourceURL,
                workTitle: work.title.isEmpty ? session.workTitle : work.title,
                startedAt: session.startedAt,
                endedAt: now,
                durationSeconds: durationSeconds,
                lastSpineIndex: work.lastSpineIndex,
                chapterTitle: chapterTitle,
                endingProgress: endingProgress,
                wordCount: work.wordCount,
                chapterCountAtVisit: work.postedChapterCount,
                didFinish: didFinish,
                lastModifiedAt: now
            ))
        }
        FolderSyncService.markDirty()
        context.saveBestEffort(reason: "Saving reading session failed")
    }

    static func hasOpenSession(for workID: UUID) -> Bool {
        openSessions[workID] != nil
    }

    /// Test seam: in-memory open sessions otherwise leak across tests.
    static func resetOpenSessionsForTests() {
        openSessions.removeAll()
    }

    // MARK: Queries

    static func sessions(in context: ModelContext, interval: DateInterval) -> [ReadingSession] {
        let all = (try? context.fetch(FetchDescriptor<ReadingSession>())) ?? []
        return all.filter { interval.contains($0.startedAt) }
            .sorted { $0.startedAt > $1.startedAt }
    }

    /// Every work's log summary, in **one** fetch.
    ///
    /// The per-work helpers below each fetch the whole session table, which is fine
    /// for a detail screen asking about one work and quadratic for a history list
    /// asking about three hundred. Any screen rendering a list of works wants this
    /// one instead.
    static func summaries(in context: ModelContext) -> [UUID: WorkReadingSummary] {
        let all = (try? context.fetch(FetchDescriptor<ReadingSession>())) ?? []
        var summaries: [UUID: WorkReadingSummary] = [:]
        for session in all {
            var summary = summaries[session.workID] ?? WorkReadingSummary()
            summary.totalSeconds += session.durationSeconds
            summary.visitCount += 1
            if session.didFinish { summary.finishCount += 1 }
            if let last = summary.lastEndedAt {
                if session.endedAt > last {
                    summary.lastEndedAt = session.endedAt
                    summary.chapterCountAtLastVisit = session.chapterCountAtVisit
                }
            } else {
                summary.lastEndedAt = session.endedAt
                summary.chapterCountAtLastVisit = session.chapterCountAtVisit
            }
            summaries[session.workID] = summary
        }
        return summaries
    }

    static func totalDuration(of workID: UUID, in context: ModelContext) -> Double {
        let all = (try? context.fetch(FetchDescriptor<ReadingSession>())) ?? []
        return all.filter { $0.workID == workID }.reduce(0) { $0 + $1.durationSeconds }
    }

    /// Reread count: finishing sessions for this work UUID, not the title.
    static func finishCount(of workID: UUID, in context: ModelContext) -> Int {
        let all = (try? context.fetch(FetchDescriptor<ReadingSession>())) ?? []
        return all.filter { $0.workID == workID && $0.didFinish }.count
    }

    static func lastSession(of workID: UUID, in context: ModelContext) -> ReadingSession? {
        let all = (try? context.fetch(FetchDescriptor<ReadingSession>())) ?? []
        return all.filter { $0.workID == workID }.max { $0.endedAt < $1.endedAt }
    }

    /// Weekly bars for 1bi. Duration is attributed to the week the session
    /// started, using `calendar`'s week-of-year.
    static func hoursByWeek(
        in interval: DateInterval,
        calendar: Calendar,
        context: ModelContext
    ) -> [(weekStart: Date, seconds: Double)] {
        let inInterval = sessions(in: context, interval: interval)
        var buckets: [Date: Double] = [:]
        for session in inInterval {
            guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: session.startedAt)?.start
            else { continue }
            buckets[weekStart, default: 0] += session.durationSeconds
        }
        return buckets.keys.sorted().map { (weekStart: $0, seconds: buckets[$0] ?? 0) }
    }

    /// Uses each session's stored `wordCount` and `durationSeconds`. Sessions
    /// with `durationSeconds <= 0` are ignored so a zero-length row cannot
    /// divide-by-zero or dilute the rate.
    ///
    /// Delegates to `ReadingInsights` so the Insights screen and this helper
    /// cannot report two different rates for the same rows.
    static func wordsPerHour(sessions: [ReadingSession]) -> Double {
        ReadingInsights.wordsPerHour(of: facts(from: sessions, works: []))
    }

    /// Flattens log rows into the plain values the statistics work on, resolving
    /// each session's fandom from the live work.
    ///
    /// A session whose work is gone keeps an empty fandom rather than being
    /// dropped: the log is deliberately keyed by UUID with a denormalised title
    /// so deleting a work does not rewrite your history, and the hours are still
    /// hours you read. They land in `Everything else`.
    static func facts(
        from sessions: [ReadingSession],
        works: [SavedWork]
    ) -> [ReadingSessionFacts] {
        let worksByID = Dictionary(
            works.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        return sessions.map { session in
            ReadingSessionFacts(
                workID: session.workID,
                startedAt: session.startedAt,
                durationSeconds: session.durationSeconds,
                wordCount: session.wordCount,
                didFinish: session.didFinish,
                fandom: worksByID[session.workID]?
                    .workFandoms.first(where: { !$0.isEmpty }) ?? ""
            )
        }
    }

    /// Everything artboard 1bi prints, for one period and the one before it.
    ///
    /// `period` is the window on screen; `previousPeriod` is what the delta is
    /// measured against. Both are fetched here rather than in the view so the
    /// screen cannot accidentally compare a month against a week.
    static func insights(
        for period: DateInterval,
        previousPeriod: DateInterval?,
        works: [SavedWork],
        calendar: Calendar = .current,
        context: ModelContext
    ) -> ReadingInsights {
        let current = facts(from: sessions(in: context, interval: period), works: works)
        let previous = previousPeriod.map {
            facts(from: sessions(in: context, interval: $0), works: works)
        } ?? []
        return ReadingInsights.make(
            facts: current, previousPeriodFacts: previous, calendar: calendar
        )
    }

    /// Tag counts on works that have at least one session. Each tag is counted
    /// once per work, keyed by the work UUID (two works with the same title
    /// do not collapse).
    static func tagCounts(
        from sessions: [ReadingSession],
        works: [SavedWork]
    ) -> [(tag: String, count: Int)] {
        let workIDs = Set(sessions.map(\.workID))
        let worksByID = Dictionary(works.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var counts: [String: Int] = [:]
        for workID in workIDs {
            guard let work = worksByID[workID] else { continue }
            var tags = work.workTags
            if tags.isEmpty {
                tags = work.workFandoms + work.workCharacters
                    + work.workRelationships + work.workFreeforms
            }
            for tag in Set(tags) where !tag.isEmpty {
                counts[tag, default: 0] += 1
            }
        }
        return counts.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key < rhs.key
        }.map { (tag: $0.key, count: $0.value) }
    }

    /// Derived Abandoned (1ai): in-progress, progress in (0.05, 0.95), last
    /// read older than `threshold`, and no manual keep-in-progress override.
    static func isAbandoned(
        work: SavedWork,
        now: Date = Date(),
        threshold: TimeInterval = defaultAbandonedThreshold
    ) -> Bool {
        guard !work.keepInProgressOverride else { return false }
        guard work.isInProgress else { return false }
        let progress = work.readingProgress ?? 0
        guard progress > 0.05, progress < 0.95 else { return false }
        guard let lastRead = work.lastReadDate else { return false }
        return now.timeIntervalSince(lastRead) > threshold
    }

    // MARK: Favorites

    static func isFavorite(
        kind: ReadingFavoriteKind,
        targetKey: String,
        in context: ModelContext
    ) -> Bool {
        favorite(kind: kind, targetKey: targetKey, in: context) != nil
    }

    static func favorite(
        kind: ReadingFavoriteKind,
        targetKey: String,
        in context: ModelContext
    ) -> ReadingFavorite? {
        let all = (try? context.fetch(FetchDescriptor<ReadingFavorite>())) ?? []
        return all.first { $0.kind == kind && $0.targetKey == targetKey }
    }

    @discardableResult
    static func setFavorite(
        _ shouldFavorite: Bool,
        kind: ReadingFavoriteKind,
        targetKey: String,
        displayName: String,
        in context: ModelContext,
        now: Date = Date()
    ) -> ReadingFavorite? {
        if shouldFavorite {
            if let existing = favorite(kind: kind, targetKey: targetKey, in: context) {
                if existing.displayName != displayName, !displayName.isEmpty {
                    existing.displayName = displayName
                    existing.lastModifiedAt = now
                    FolderSyncService.markDirty()
                    context.saveBestEffort(reason: "Updating reading favorite failed")
                }
                return existing
            }
            let record = ReadingFavorite(
                kind: kind,
                targetKey: targetKey,
                displayName: displayName,
                createdAt: now
            )
            context.insert(record)
            FolderSyncService.markDirty()
            context.saveBestEffort(reason: "Saving reading favorite failed")
            return record
        }
        if let existing = favorite(kind: kind, targetKey: targetKey, in: context) {
            delete(existing, in: context)
        }
        return nil
    }

    static func delete(_ session: ReadingSession, in context: ModelContext) {
        SyncTombstones.recordDeletion(of: session, in: context)
        context.delete(session)
        FolderSyncService.markDirty()
        context.saveBestEffort(reason: "Deleting reading session failed")
    }

    static func delete(_ favorite: ReadingFavorite, in context: ModelContext) {
        SyncTombstones.recordDeletion(of: favorite, in: context)
        context.delete(favorite)
        FolderSyncService.markDirty()
        context.saveBestEffort(reason: "Deleting reading favorite failed")
    }

    static func delete(_ watermark: FandomReadWatermark, in context: ModelContext) {
        SyncTombstones.recordDeletion(of: watermark, in: context)
        context.delete(watermark)
        FolderSyncService.markDirty()
        context.saveBestEffort(reason: "Deleting fandom watermark failed")
    }

    // MARK: Fandom watermarks

    /// Records that the reader visited `fandom` (raw AO3 tag name). Updates the
    /// existing row for that name rather than inserting a second watermark.
    static func markVisited(
        fandom: String,
        newestWork: SavedWork?,
        in context: ModelContext,
        now: Date = Date()
    ) {
        let name = fandom.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let all = (try? context.fetch(FetchDescriptor<FandomReadWatermark>())) ?? []
        let watermark: FandomReadWatermark
        if let existing = all.first(where: { $0.fandomName == name }) {
            watermark = existing
        } else {
            watermark = FandomReadWatermark(fandomName: name, lastVisitedAt: now)
            context.insert(watermark)
        }
        watermark.lastVisitedAt = now
        watermark.lastModifiedAt = now
        if let newestWork {
            watermark.newestWorkIDSeen = newestWork.ao3WorkID
            watermark.newestWorkTitleSeen = newestWork.title
        }
        FolderSyncService.markDirty()
        context.saveBestEffort(reason: "Saving fandom watermark failed")
    }
}
