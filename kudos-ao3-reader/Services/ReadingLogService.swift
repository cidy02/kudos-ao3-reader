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
    static let currentRulesVersion = 1
    private static let deviceIDKey = "readingLogDeviceID"

    static func deviceID(defaults: UserDefaults = .standard) -> String {
        if let value = defaults.string(forKey: deviceIDKey), !value.isEmpty { return value }
        let value = UUID().uuidString
        defaults.set(value, forKey: deviceIDKey)
        return value
    }

    nonisolated static func activeGap(from previous: Date, to now: Date) -> Double {
        let seconds = now.timeIntervalSince(previous)
        return min(300, max(0, seconds))
    }

    /// 1ai default: mid-way and untouched for this long, and no manual override.
    nonisolated static let defaultAbandonedThreshold: TimeInterval = 21 * 24 * 3600

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
        var tzOffsetSeconds: Int
        var startProgress: Double?
        var startSpineIndex: Int
        var mode: ReadingSession.Mode
        var playbackRate: Double?
        var activeSeconds: Double
        var lastActivityAt: Date
        var deviceID: String
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
    static func startSession(
        for work: SavedWork,
        mode: ReadingSession.Mode = .read,
        playbackRate: Double? = nil,
        now: Date = Date(),
        timeZone: TimeZone = .current,
        defaults: UserDefaults = .standard
    ) {
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
            tzOffsetSeconds: timeZone.secondsFromGMT(for: now),
            // A stored overall fraction is trustworthy; chapter-count fallbacks are not.
            startProgress: work.publicationProgress ?? (
                work.readiumLocator.isEmpty && work.lastSpineIndex == 0
                    && work.lastScrollFraction == 0 ? 0 : nil
            ),
            startSpineIndex: work.lastSpineIndex,
            mode: mode,
            playbackRate: mode == .listen ? playbackRate : nil,
            activeSeconds: 0,
            lastActivityAt: now,
            deviceID: deviceID(defaults: defaults),
            wasFinishedAtStart: work.isFinished
        )
    }

    static func noteActivity(for work: SavedWork, now: Date = Date()) {
        guard var session = openSessions[work.id], !session.isPaused,
              now >= session.lastActivityAt else { return }
        session.activeSeconds += activeGap(from: session.lastActivityAt, to: now)
        session.lastActivityAt = now
        openSessions[work.id] = session
    }

    static func openSessionMode(for workID: UUID) -> ReadingSession.Mode? {
        openSessions[workID]?.mode
    }

    /// Switches the open session's mode (`.read` vs `.listen`).
    ///
    /// D4 rule: a sitting that changes mode mid-sitting splits into two
    /// `ReadingSession` rows (finalizing the outgoing segment when it reached
    /// `minimumPersistableDuration`, then opening a fresh segment at `now`). Rate
    /// changes within `.listen` update the open row in place.
    static func setMode(
        _ mode: ReadingSession.Mode,
        for work: SavedWork,
        playbackRate: Double? = nil,
        now: Date = Date()
    ) {
        guard var session = openSessions[work.id] else { return }
        if session.mode == mode {
            session.playbackRate = mode == .listen ? playbackRate : nil
            openSessions[work.id] = session
            return
        }

        noteActivity(for: work, now: now)
        session = openSessions[work.id] ?? session

        let splitAt: Date
        if !session.isPaused {
            session.accumulatedSeconds += max(0, now.timeIntervalSince(session.lastResumedAt))
            session.lastResumedAt = now
            splitAt = now
        } else {
            splitAt = session.lastResumedAt
        }

        // Switching at open (0s active, same instant) keeps original start facts
        // (location/spine) on the same row.
        if session.accumulatedSeconds == 0 && !session.isPaused && now == session.startedAt {
            session.mode = mode
            session.playbackRate = mode == .listen ? playbackRate : nil
            openSessions[work.id] = session
            return
        }

        let persistedOutgoing = session.accumulatedSeconds >= minimumPersistableDuration
        if persistedOutgoing {
            persist(session, for: work, now: splitAt, didFinish: didFinish(session, for: work))
        }

        openSessions[work.id] = OpenSession(
            recordID: UUID(),
            workID: work.id,
            ao3WorkID: work.ao3WorkID,
            sourceURL: work.sourceURL,
            workTitle: work.title,
            startedAt: now,
            lastResumedAt: now,
            accumulatedSeconds: 0,
            isPaused: session.isPaused,
            tzOffsetSeconds: session.tzOffsetSeconds,
            startProgress: work.publicationProgress ?? (
                work.readiumLocator.isEmpty && work.lastSpineIndex == 0
                    && work.lastScrollFraction == 0 ? 0 : nil
            ),
            startSpineIndex: work.lastSpineIndex,
            mode: mode,
            playbackRate: mode == .listen ? playbackRate : nil,
            activeSeconds: 0,
            lastActivityAt: now,
            deviceID: session.deviceID,
            wasFinishedAtStart: persistedOutgoing ? work.isFinished : session.wasFinishedAtStart
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
        noteActivity(for: work, now: now)
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
        session.lastActivityAt = max(session.lastActivityAt, now)
        session.isPaused = false
        openSessions[work.id] = session
    }

    /// Persists the open session, or drops it when shorter than 15 seconds.
    ///
    /// The reread signal is computed here rather than supplied: see
    /// `didFinish(_:for:)`. Callers used to pass it and all three wrote the same
    /// expression, which is how `pauseSession` came to write a fourth, wrong one.
    static func endSession(for work: SavedWork, now: Date = Date()) {
        noteActivity(for: work, now: now)
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
            if !existing.hasMetadataSnapshot { existing.snapshot(from: work) }
            existing.endedAt = now
            existing.durationSeconds = durationSeconds
            existing.activeSeconds = session.activeSeconds
            existing.modeRaw = session.mode.rawValue
            existing.playbackRate = session.playbackRate
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
            let newSession = ReadingSession(
                id: recordID,
                workID: session.workID,
                ao3WorkID: work.ao3WorkID ?? session.ao3WorkID,
                sourceURL: work.sourceURL.isEmpty ? session.sourceURL : work.sourceURL,
                workTitle: work.title.isEmpty ? session.workTitle : work.title,
                startedAt: session.startedAt,
                endedAt: now,
                durationSeconds: durationSeconds,
                tzOffsetSeconds: session.tzOffsetSeconds,
                startProgress: session.startProgress,
                startSpineIndex: session.startSpineIndex,
                modeRaw: session.mode.rawValue,
                playbackRate: session.playbackRate,
                activeSeconds: session.activeSeconds,
                deviceID: session.deviceID,
                rulesVersion: currentRulesVersion,
                lastSpineIndex: work.lastSpineIndex,
                chapterTitle: chapterTitle,
                endingProgress: endingProgress,
                wordCount: work.wordCount,
                chapterCountAtVisit: work.postedChapterCount,
                didFinish: didFinish,
                lastModifiedAt: now
            )
            newSession.snapshot(from: work)
            context.insert(newSession)
        }
        FolderSyncService.markDirty()
        context.saveBestEffort(reason: "Saving reading session failed")
    }

    /// Closes or keeps the open sitting when the reader disappears.
    ///
    /// D4: Active Read Aloud detaches instead of closing the sitting so
    /// background/out-of-reader listening stays tracked as `.listen`.
    static func handleReaderClose(
        for work: SavedWork,
        detachListening: Bool,
        isSpeechPlaying: Bool,
        playbackRate: Double,
        now: Date = Date()
    ) {
        guard detachListening else {
            endSession(for: work, now: now)
            return
        }
        if isSpeechPlaying {
            setMode(.listen, for: work, playbackRate: playbackRate, now: now)
            noteActivity(for: work, now: now)
        } else {
            pauseSession(for: work, now: now)
        }
    }

    enum DetachedSpeechState {
        case playing
        case paused
        case stopped
    }

    /// Updates the reading log for Read Aloud transport changes while the
    /// reader view is detached.
    static func handleDetachedSpeech(
        _ state: DetachedSpeechState,
        for work: SavedWork,
        playbackRate: Double,
        now: Date = Date()
    ) {
        switch state {
        case .playing:
            if hasOpenSession(for: work.id) {
                resumeSession(for: work, now: now)
                setMode(.listen, for: work, playbackRate: playbackRate, now: now)
            } else {
                startSession(for: work, mode: .listen, playbackRate: playbackRate, now: now)
            }
        case .paused:
            pauseSession(for: work, now: now)
        case .stopped:
            endSession(for: work, now: now)
        }
    }

    /// Opens or resumes the reading session when a reader view appears.
    static func handleReaderOpen(
        for work: SavedWork,
        isSpeechPlaying: Bool,
        isSpeechStopped: Bool,
        playbackRate: Double,
        now: Date = Date()
    ) {
        if hasOpenSession(for: work.id) {
            resumeSession(for: work, now: now)
            if isSpeechPlaying {
                setMode(.listen, for: work, playbackRate: playbackRate, now: now)
            } else if isSpeechStopped {
                setMode(.read, for: work, now: now)
            }
        } else {
            startSession(
                for: work,
                mode: isSpeechPlaying ? .listen : .read,
                playbackRate: isSpeechPlaying ? playbackRate : nil,
                now: now
            )
        }
    }

    /// Updates the open reading log for Read Aloud status transitions while the
    /// reader is mounted (including backgrounded Lock Screen / Control Center
    /// pause or stop events delivered directly from the speech controller).
    static func handleSpeechStatusChange(
        _ state: DetachedSpeechState,
        isReaderOpen: Bool,
        isBackgrounded: Bool,
        for work: SavedWork,
        playbackRate: Double,
        now: Date = Date()
    ) {
        guard isReaderOpen else {
            handleDetachedSpeech(state, for: work, playbackRate: playbackRate, now: now)
            return
        }
        switch state {
        case .playing:
            resumeSession(for: work, now: now)
            setMode(.listen, for: work, playbackRate: playbackRate, now: now)
        case .paused:
            if isBackgrounded {
                pauseSession(for: work, now: now)
            }
        case .stopped:
            setMode(.read, for: work, now: now)
            if isBackgrounded {
                pauseSession(for: work, now: now)
            }
        }
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

    /// Total duration including any in-flight session.
    ///
    /// The open session's own row is left out of the persisted sum: `pauseSession`
    /// writes it while keeping the session open, so adding the row *and*
    /// `accumulatedSeconds` would count the same time twice.
    static func currentTotalDuration(of workID: UUID, in context: ModelContext, now: Date = Date()) -> Double {
        let open = openSessions[workID]
        let all = (try? context.fetch(FetchDescriptor<ReadingSession>())) ?? []
        var duration = all
            .filter { $0.workID == workID && $0.id != open?.recordID }
            .reduce(0) { $0 + $1.durationSeconds }
        if let open {
            let currentStretch = open.isPaused ? 0 : max(0, now.timeIntervalSince(open.lastResumedAt))
            duration += open.accumulatedSeconds + currentStretch
        }
        return duration
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

    /// Uses the words each session read (`wordsRead(sessions:)`, from its stored
    /// `wordCount` and `endingProgress`) and its `durationSeconds`. Sessions
    /// with `durationSeconds <= 0` are ignored so a zero-length row cannot
    /// divide-by-zero or dilute the rate.
    ///
    /// Delegates to `ReadingInsights` so the Insights screen and this helper
    /// cannot report two different rates for the same rows.
    static func wordsPerHour(sessions: [ReadingSession], works: [SavedWork]) -> Double {
        ReadingInsights.wordsPerHour(of: facts(from: sessions, works: works))
    }

    /// Flattens log rows into the plain values the statistics work on, resolving
    /// each session's fandom from the live work.
    ///
    /// A session whose work is gone keeps an empty fandom rather than being
    /// dropped: the log is deliberately keyed by UUID with a denormalised title
    /// so deleting a work does not rewrite your history, and the hours are still
    /// hours you read. They land in `Everything else`.
    ///
    /// `history` is every session the words read are measured against (each
    /// sitting is measured from the one before it, which may lie outside a
    /// period); it defaults to `sessions`.
    static func facts(
        from sessions: [ReadingSession],
        works: [SavedWork],
        history: [ReadingSession]? = nil,
        aliases: TagAliasResolver = .empty
    ) -> [ReadingSessionFacts] {
        let worksByID = Dictionary(
            works.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        let read = wordsRead(sessions: history ?? sessions, works: works)
        return sessions.map { session in
            let work = worksByID[session.workID]
            let rawFandom = session.fandoms.first(where: { !$0.isEmpty })
                ?? work?.workFandoms.first(where: { !$0.isEmpty }) ?? ""
            return ReadingSessionFacts(
                workID: session.workID,
                startedAt: session.startedAt,
                durationSeconds: session.durationSeconds,
                wordCount: session.wordCount,
                didFinish: session.didFinish,
                fandom: aliases.resolve(rawFandom, kind: .fandom),
                wordsRead: read[session.id] ?? 0,
                sessionID: session.id,
                title: session.workTitle.isEmpty ? work?.title ?? "" : session.workTitle,
                endingProgress: session.endingProgress,
                // Rows written before the count was recorded fall back to the
                // work's count now, which is the best the log can do for them.
                chapterCount: session.chapterCountAtVisit > 0
                    ? session.chapterCountAtVisit : work?.postedChapterCount ?? 0,
                startProgress: session.startProgress,
                mode: session.mode,
                wordUnit: work?.wordUnit ?? .words
            )
        }
    }

    /// Words (or characters, per `SavedWork.wordUnit`) each sitting read.
    ///
    /// D3: Uses per-chapter EPUB counts when available on the work and within
    /// 10% of AO3's reported word count, never double-counting a revised chapter
    /// already read in the current read-through. Falls back to the legacy
    /// `progress × wordCount` rule otherwise.
    static func wordsRead(
        sessions: [ReadingSession],
        works: [SavedWork]
    ) -> [UUID: Int] {
        let worksByID = Dictionary(
            works.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        var read: [UUID: Int] = [:]
        for (workID, group) in Dictionary(grouping: sessions, by: \.workID) {
            let sorted = group.sorted {
                ($0.startedAt, $0.id.uuidString) < ($1.startedAt, $1.id.uuidString)
            }
            let work = worksByID[workID]
            if let work, canUseChapterWordCounts(work.chapterWordCounts, for: work, sessions: sorted) {
                chapterWordsRead(
                    sortedSessions: sorted,
                    chapterCounts: work.chapterWordCounts,
                    into: &read
                )
            } else {
                legacyWordsRead(sortedSessions: sorted, into: &read)
            }
        }
        return read
    }

    private static func canUseChapterWordCounts(
        _ counts: [Int],
        for work: SavedWork,
        sessions: [ReadingSession]
    ) -> Bool {
        guard !counts.isEmpty else { return false }
        let chapterSum = counts.reduce(0, +)
        guard chapterSum > 0 else { return false }
        let ao3Count = work.wordCount
        if work.postedChapterCount > 0 && counts.count < work.postedChapterCount {
            // Local EPUB has fewer chapters than AO3 reports: only use chapter counts
            // when a sitting explicitly stayed within `counts.count` and matched its
            // own AO3 word count within 10% (or had no AO3 count). Otherwise a
            // collapsed TOC (e.g. [500] vs 50_000) falls back to `progress * wordCount`.
            return sessions.contains { session in
                guard session.chapterCountAtVisit > 0,
                      session.chapterCountAtVisit <= counts.count else { return false }
                guard session.wordCount > 0 else { return true }
                let prefixSum = counts.prefix(session.chapterCountAtVisit).reduce(0, +)
                return abs(Double(prefixSum - session.wordCount)) <= Double(session.wordCount) * 0.10
            }
        }
        if ao3Count > 0 {
            return abs(Double(chapterSum - ao3Count)) <= Double(ao3Count) * 0.10
        }
        return true
    }

    private static func inferredChapterCount(
        forWordCount wordCount: Int,
        in chapterCounts: [Int]
    ) -> Int {
        let totalSum = chapterCounts.reduce(0, +)
        guard wordCount > 0, Double(wordCount) < Double(totalSum) * 0.90 else {
            return chapterCounts.count
        }
        var cumulative = 0
        var bestCount = chapterCounts.count
        var bestDiff = Int.max
        for (index, count) in chapterCounts.enumerated() {
            cumulative += count
            let diff = abs(cumulative - wordCount)
            if diff < bestDiff {
                bestDiff = diff
                bestCount = index + 1
            }
        }
        return bestCount
    }

    private static func chapterWordsRead(
        sortedSessions: [ReadingSession],
        chapterCounts: [Int],
        into read: inout [UUID: Int]
    ) {
        var chapterHighWater = Array(repeating: 0.0, count: chapterCounts.count)
        var previousEndFraction = 0.0
        var previousWords = 0
        var previousChapterCount = 0
        var previousFinished = false
        // A finish was seen and no later sitting has read forward yet. It survives
        // sittings that read nothing (open a finished work at its end, scroll back),
        // so the first forward read after a finish decides "reread or revision".
        struct FinishMark { let endFraction: Double, words: Int, chapterCount: Int }
        var pendingFinish: FinishMark?

        for session in sortedSessions {
            let hasChapterMismatch = session.chapterCountAtVisit > chapterCounts.count
            let activeCount: Int
            if session.chapterCountAtVisit > 0 {
                activeCount = min(session.chapterCountAtVisit, chapterCounts.count)
            } else {
                activeCount = inferredChapterCount(forWordCount: session.wordCount, in: chapterCounts)
            }
            let activeCounts = Array(chapterCounts.prefix(activeCount))
            let prefixSum = activeCounts.reduce(0, +)

            let workGrew = (previousChapterCount > 0 && activeCount > previousChapterCount)
                || (previousWords > 0 && session.wordCount > previousWords)
            let clampedStart = session.startProgress.map { min(1, max(0, $0)) }
            let endFraction = min(1, max(0, session.endingProgress))

            // Same rule as `legacyWordsRead`: no recorded start right after a finish
            // means a reread from 0 unless the work grew.
            let startFraction: Double
            if let clampedStart {
                startFraction = clampedStart
            } else if previousFinished && !workGrew {
                startFraction = 0
            } else {
                startFraction = previousEndFraction
            }

            if let finish = pendingFinish, endFraction > startFraction {
                // Starting from 0 is always a reread (even after an AO3 recount). A start
                // part-way in is a reread unless the work changed since the finish: grew
                // (catching up on new chapters) or shrank by more than 10% (a revised,
                // already-read chapter), where the read-through continues instead.
                let grewSinceFinish = (finish.chapterCount > 0 && activeCount > finish.chapterCount)
                    || (finish.words > 0 && session.wordCount > finish.words)
                let shrankSinceFinish = finish.words > 0 && session.wordCount > 0
                    && Double(session.wordCount) < Double(finish.words) * 0.90
                let isGenuineNewReread = startFraction == 0
                    || (!grewSinceFinish && !shrankSinceFinish && startFraction < finish.endFraction)
                if isGenuineNewReread {
                    chapterHighWater = Array(repeating: 0.0, count: chapterCounts.count)
                }
                pendingFinish = nil
            }
            if session.didFinish {
                pendingFinish = FinishMark(
                    endFraction: endFraction, words: session.wordCount, chapterCount: activeCount
                )
            }

            guard prefixSum > 0, endFraction > startFraction else {
                read[session.id] = 0
                previousEndFraction = endFraction
                previousWords = session.wordCount
                previousChapterCount = activeCount
                previousFinished = session.didFinish
                continue
            }

            let differsBeyondTenPercent = session.wordCount > 0
                && abs(Double(prefixSum - session.wordCount)) > Double(session.wordCount) * 0.10
            // Never scale up across a chapter mismatch (counts.count < session.chapterCountAtVisit),
            // and do not project a partial fraction across shifted chapter boundaries when >10% off.
            if !hasChapterMismatch && differsBeyondTenPercent && endFraction < 1.0 {
                read[session.id] = Int(max(0, (endFraction - startFraction) * Double(session.wordCount)).rounded())
                let completedWholeChapters = min(
                    activeCounts.count,
                    max(0, Int(floor(endFraction * Double(activeCounts.count))))
                )
                for index in 0..<completedWholeChapters {
                    chapterHighWater[index] = 1.0
                }
                previousEndFraction = endFraction
                previousWords = session.wordCount
                previousChapterCount = activeCount
                previousFinished = session.didFinish
                continue
            }

            let startPos = startFraction * Double(prefixSum)
            let endPos = endFraction * Double(prefixSum)
            var cumulative = 0.0
            var rawWords = 0.0

            for index in 0..<activeCounts.count {
                let count = Double(max(0, activeCounts[index]))
                let chapterStart = cumulative
                let chapterEnd = cumulative + count
                cumulative = chapterEnd
                guard count > 0, endPos > chapterStart, startPos < chapterEnd else { continue }

                let coveredStart = max(0.0, min(1.0, (startPos - chapterStart) / count))
                let coveredEnd = max(0.0, min(1.0, (endPos - chapterStart) / count))
                let effectiveStart = max(coveredStart, chapterHighWater[index])
                if coveredEnd > effectiveStart {
                    rawWords += (coveredEnd - effectiveStart) * count
                }
                chapterHighWater[index] = max(chapterHighWater[index], coveredEnd)
            }

            let scale: Double = (!hasChapterMismatch && differsBeyondTenPercent)
                ? Double(session.wordCount) / Double(prefixSum)
                : 1.0

            read[session.id] = Int(max(0, rawWords * scale).rounded())
            previousEndFraction = endFraction
            previousWords = session.wordCount
            previousChapterCount = activeCount
            previousFinished = session.didFinish
        }
    }

    private static func legacyWordsRead(
        sortedSessions: [ReadingSession],
        into read: inout [UUID: Int]
    ) {
        var previousEndFraction = 0.0
        var previousEndWords = 0.0
        var previousWords = 0
        var previousFinished = false

        for session in sortedSessions {
            let words = max(0, session.wordCount)
            let endFraction = min(1, max(0, session.endingProgress))
            let endWords = endFraction * Double(words)
            let startWords: Double
            if let explicit = session.startProgress {
                let clamped = min(1, max(0, explicit))
                if previousWords > 0 && words > previousWords && clamped == previousEndFraction {
                    startWords = previousEndWords
                } else {
                    startWords = clamped * Double(words)
                }
            } else if previousFinished && words <= previousWords {
                startWords = 0
            } else {
                startWords = previousEndWords
            }
            read[session.id] = Int(max(0, endWords - startWords).rounded())
            previousEndFraction = endFraction
            previousEndWords = endWords
            previousWords = words
            previousFinished = session.didFinish
        }
    }

    /// Everything artboard 1bi prints, for one period and the one before it.
    ///
    /// `period` is the window on screen; `previousPeriod` is what the delta is
    /// measured against. Both are fetched here rather than in the view so the
    /// screen cannot accidentally compare a month against a week.
    /// Gathered and option-filtered Insights snapshot for a period.
    struct InsightsGatherResult {
        var insights: ReadingInsights
        var taste: ReadingTasteInsights?
        var habits: ReadingHabitsInsights
        var library: ReadingLibraryInsights
        var libraryStats: ReadingStatistics
        var finishedWorksInPeriod: [SavedWork]
        var filteredWorks: [SavedWork]
        var filteredSessions: [ReadingSession]
        var discreetMasker: InsightsDiscreetMasker
    }

    /// Gathers every Reading Insights figure through the single `options.filter` pass.
    static func gatherInsights(
        for period: DateInterval,
        previousPeriod: DateInterval?,
        works: [SavedWork],
        hiddenWorkIDs: Set<UUID> = [],
        periodMonths: Double = 1,
        calendar: Calendar = .current,
        context: ModelContext,
        options: InsightsOptions = InsightsOptions(),
        aliases: TagAliasResolver? = nil,
        now: Date = Date()
    ) -> InsightsGatherResult {
        let resolvedAliases = aliases ?? TagAliasStore.resolver(in: context)
        let rawHistory = (try? context.fetch(FetchDescriptor<ReadingSession>())) ?? []
        // Hidden (mature, not revealed) works' sessions leave every figure, not just their rows.
        let history = hiddenWorkIDs.isEmpty
            ? rawHistory
            : rawHistory.filter { !hiddenWorkIDs.contains($0.workID) }
        let filtered = options.filter(sessions: history, works: works, aliases: resolvedAliases)

        let allFacts = facts(
            from: filtered.sessions,
            works: filtered.works,
            history: filtered.sessions,
            aliases: resolvedAliases
        )
        let periodFacts = allFacts.filter { period.contains($0.startedAt) }
        let previousFacts = previousPeriod.map { interval in
            allFacts.filter { interval.contains($0.startedAt) }
        } ?? []

        let figures = ReadingInsights.make(
            facts: periodFacts,
            previousPeriodFacts: previousFacts,
            dayRange: ReadingInsights.chartDays(for: period, now: now, calendar: calendar),
            calendar: calendar,
            aliases: resolvedAliases
        )
        let readWorkIDs = Set(periodFacts.map(\.workID))
        let worksInPeriod = filtered.works.filter { readWorkIDs.contains($0.id) }
        let taste = worksInPeriod.isEmpty
            ? nil
            : ReadingTasteInsights.make(works: worksInPeriod, facts: periodFacts, aliases: resolvedAliases)
        let habits = ReadingHabitsInsights.make(
            works: filtered.works,
            facts: periodFacts,
            allFacts: allFacts,
            calendar: calendar,
            aliases: resolvedAliases
        )
        let library = ReadingLibraryInsights.make(
            works: filtered.works,
            facts: periodFacts,
            periodInterval: period,
            periodMonths: periodMonths,
            calendar: calendar,
            aliases: resolvedAliases,
            askAboutUntouched: options.askAboutUntouched,
            untouchedDays: options.clampedUntouchedDays,
            now: now
        )
        let libraryStats = ReadingStatistics(
            works: filtered.works,
            now: now,
            calendar: calendar,
            aliases: resolvedAliases
        )
        let finishedWorksInPeriod = filtered.works.filter { w in
            w.isFinished && periodFacts.contains { $0.workID == w.id && $0.didFinish }
        }
        let masker = InsightsDiscreetMasker.forScreen(
            InsightsDiscreetMasker.ScreenSeed(
                insights: figures,
                taste: taste,
                habits: habits,
                library: library,
                stats: libraryStats,
                finishedWorks: finishedWorksInPeriod,
                works: filtered.works,
                sessions: filtered.sessions
            ),
            aliases: resolvedAliases
        )
        return InsightsGatherResult(
            insights: figures,
            taste: taste,
            habits: habits,
            library: library,
            libraryStats: libraryStats,
            finishedWorksInPeriod: finishedWorksInPeriod,
            filteredWorks: filtered.works,
            filteredSessions: filtered.sessions,
            discreetMasker: masker
        )
    }

    static func insights(
        for period: DateInterval,
        previousPeriod: DateInterval?,
        works: [SavedWork],
        hiddenWorkIDs: Set<UUID> = [],
        calendar: Calendar = .current,
        context: ModelContext,
        aliases: TagAliasResolver? = nil,
        options: InsightsOptions = InsightsOptions()
    ) -> ReadingInsights {
        let resolvedAliases = aliases ?? TagAliasStore.resolver(in: context)
        let rawHistory = (try? context.fetch(FetchDescriptor<ReadingSession>())) ?? []
        let history = hiddenWorkIDs.isEmpty
            ? rawHistory
            : rawHistory.filter { !hiddenWorkIDs.contains($0.workID) }
        let filtered = options.filter(sessions: history, works: works, aliases: resolvedAliases)
        let allFacts = facts(
            from: filtered.sessions,
            works: filtered.works,
            history: filtered.sessions,
            aliases: resolvedAliases
        )
        let current = allFacts.filter { period.contains($0.startedAt) }
        let previous = previousPeriod.map { interval in
            allFacts.filter { interval.contains($0.startedAt) }
        } ?? []
        return ReadingInsights.make(
            facts: current, previousPeriodFacts: previous,
            dayRange: ReadingInsights.chartDays(for: period, calendar: calendar),
            calendar: calendar,
            aliases: resolvedAliases
        )
    }

    /// Tag counts on works that have at least one session. Each tag is counted
    /// once per work, keyed by the work UUID (two works with the same title
    /// do not collapse), resolving learned `TagAlias` names at query time.
    static func tagCounts(
        from sessions: [ReadingSession],
        works: [SavedWork],
        aliases: TagAliasResolver = .empty
    ) -> [(tag: String, count: Int)] {
        let workIDs = Set(sessions.map(\.workID))
        let worksByID = Dictionary(works.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var counts: [String: Int] = [:]
        for workID in workIDs {
            guard let work = worksByID[workID] else { continue }
            let tags: [String]
            if !work.workTags.isEmpty {
                tags = aliases.resolvedUnique(work.workTags, kind: .freeform)
            } else {
                tags = aliases.resolvedUnique(work.workFandoms, kind: .fandom)
                    + aliases.resolvedUnique(work.workCharacters, kind: .character)
                    + aliases.resolvedUnique(work.workRelationships, kind: .relationship)
                    + aliases.resolvedUnique(work.workFreeforms, kind: .freeform)
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
    nonisolated static func isAbandoned(
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

    /// When the reader last opened `fandom`'s works — read before `markVisited`
    /// overwrites it, so a screen can mark what is new since then.
    static func lastVisit(fandom: String, in context: ModelContext) -> Date? {
        let name = fandom.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = (try? context.fetch(FetchDescriptor<FandomReadWatermark>())) ?? []
        return all.first { $0.fandomName == name }?.lastVisitedAt
    }

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
