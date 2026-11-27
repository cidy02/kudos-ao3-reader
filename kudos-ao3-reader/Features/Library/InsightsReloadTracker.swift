import Foundation
import SwiftData

/// Per-record invalidation digest for Reading Insights.
///
/// Every input that can change a displayed figure — per-work identity and rating
/// (including soft-deleted works), queue-only / finish / completion / kudos /
/// favorite / preservation flags, word counts, metadata, derived status buckets,
/// reading-log sittings (including edits to older sittings), and tag aliases —
/// contributes its own record hash combined order-independently so swaps between
/// two works can never cancel out. Ordinary mid-chapter reading-position saves
/// (detached Read Aloud checkpoints) leave a work's signature unchanged unless
/// they cross a displayed bucket (unread → started, WIP caught-up, abandoned).
///
/// `nonisolated` so `InsightsGatherActor` can take the digest on its own context (T-537p).
nonisolated enum InsightsReloadDigest {
    private struct DeterministicHasher {
        private(set) var state: UInt64 = 0xcbf29ce484222325

        mutating func mix(_ byte: UInt8) {
            state ^= UInt64(byte)
            state = state &* 0x100000001b3
        }

        mutating func mix(_ value: UInt64) {
            var remaining = value
            for _ in 0..<8 {
                mix(UInt8(truncatingIfNeeded: remaining))
                remaining >>= 8
            }
        }

        mutating func mix(_ value: Int) {
            mix(UInt64(bitPattern: Int64(value)))
        }

        mutating func mix(_ value: Bool) {
            mix(value ? UInt8(1) : UInt8(0))
        }

        mutating func mix(_ value: Double?) {
            if let value {
                mix(true)
                mix(value.bitPattern)
            } else {
                mix(false)
            }
        }

        mutating func mix(_ value: String) {
            mix(value.utf8.count)
            for byte in value.utf8 {
                mix(byte)
            }
        }

        mutating func mix(_ values: [String]) {
            mix(values.count)
            for value in values {
                mix(value)
            }
        }

        mutating func mix(_ uuid: UUID) {
            withUnsafeBytes(of: uuid.uuid) { bytes in
                for byte in bytes {
                    mix(byte)
                }
            }
        }
    }

    /// Order-independent accumulator for per-record 64-bit hashes.
    private struct BagDigest: Equatable {
        var count = 0
        var sum: UInt64 = 0
        var xor: UInt64 = 0

        mutating func add(_ hash: UInt64) {
            count += 1
            sum &+= hash
            xor ^= hash
        }

        var token: String {
            "\(count):\(String(sum, radix: 16)):\(String(xor, radix: 16))"
        }
    }

    static func workSignature(
        _ work: SavedWork,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> UInt64 {
        var hasher = DeterministicHasher()
        hasher.mix(work.id)
        hasher.mix(work.isPendingDeletion)
        hasher.mix(work.isAdult)
        hasher.mix(work.rating.trimmingCharacters(in: .whitespacesAndNewlines))
        hasher.mix(work.isQueueOnlyWork)
        hasher.mix(work.isQueuedForLater)
        hasher.mix(work.isFinished)
        hasher.mix(work.isComplete)
        hasher.mix(work.hasGivenKudos)
        hasher.mix(work.isFavorite)
        hasher.mix(work.ao3Unavailable)
        hasher.mix(work.hasEPUB)
        hasher.mix(work.wordCount)
        hasher.mix(work.wordUnit.rawValue)
        hasher.mix(work.chapterWordCountsJSON)

        // Progress-derived status buckets (not raw mid-chapter position).
        hasher.mix(work.hasStartedReading)
        hasher.mix(work.insightsReadingStatus.rawValue)
        hasher.mix(work.keepInProgressOverride)
        hasher.mix(work.statusChangedAt?.timeIntervalSince1970)
        hasher.mix(work.stoppedAt?.timeIntervalSince1970)
        let isPartitionCaughtUp = !work.isComplete
            && !work.isFinished
            && work.hasStartedReading
            && (work.readingProgress ?? 0) >= 0.98
        hasher.mix(isPartitionCaughtUp)

        let isAbandoned = ReadingLogService.isAbandoned(work: work, now: now)
        hasher.mix(isAbandoned)
        if isAbandoned {
            hasher.mix(work.readingProgress.map { Int(($0 * 100).rounded()) } ?? -1)
            hasher.mix(work.lastSpineIndex)
            hasher.mix(work.postedChapterCount)
            hasher.mix(work.lastReadDate.map { calendar.startOfDay(for: $0).timeIntervalSince1970 })
        }

        hasher.mix(openedRecencyBucket(work.lastReadDate, now: now, calendar: calendar))
        if !work.isComplete {
            hasher.mix(wipFreshnessBucket(for: work, now: now, calendar: calendar))
        }

        // Metadata consumed by Taste, Habits, and Library insights.
        hasher.mix(work.title)
        hasher.mix(work.language.trimmingCharacters(in: .whitespacesAndNewlines))
        // The exact instant, not its day: "saved to opened" is a median over the
        // exact gap, so a same-day correction (a sync merge moving `dateAdded`
        // from 10 pm to 8 am) moves the figure while the calendar day is unchanged.
        hasher.mix(work.dateAdded.timeIntervalSince1970)
        hasher.mix(work.datePublished)
        hasher.mix(work.dateUpdated)
        hasher.mix(work.downloadedAt.map { calendar.component(.year, from: $0) } ?? -1)
        hasher.mix(work.chapters)
        hasher.mix(work.knownChapterCount)
        hasher.mix(work.workFandoms)
        hasher.mix(work.workRelationships)
        hasher.mix(work.workCharacters)
        hasher.mix(work.workFreeforms)
        hasher.mix(work.workTags)
        hasher.mix(work.workWarnings)
        hasher.mix(work.workCategories)
        hasher.mix(work.stopReasonRaw)
        hasher.mix(work.stopTag)
        hasher.mix(work.kudos)
        hasher.mix(work.kudosAtSave ?? -1)
        hasher.mix(work.statsSavedAt?.timeIntervalSince1970)
        hasher.mix(work.importSourceRaw ?? "")
        hasher.mix(work.importSourceSince?.timeIntervalSince1970)
        hasher.mix(work.ao3SeriesID ?? -1)
        hasher.mix(work.seriesPosition)
        hasher.mix(work.authorIdentitiesJSON)
        return hasher.state
    }

    private static func openedRecencyBucket(_ date: Date?, now: Date, calendar: Calendar) -> Int {
        guard let date, date <= now else { return 0 }
        let startOfToday = calendar.startOfDay(for: now)
        if let sevenDayStart = calendar.date(byAdding: .day, value: -6, to: startOfToday),
           date >= sevenDayStart {
            return 2
        }
        if let thirtyDayStart = calendar.date(byAdding: .day, value: -29, to: startOfToday),
           date >= thirtyDayStart {
            return 1
        }
        return 0
    }

    private static func wipFreshnessBucket(for work: SavedWork, now: Date, calendar: Calendar) -> Int {
        let updateDate = WorkStat.date(from: work.dateUpdated) ?? work.lastModifiedAt
        let days = calendar.dateComponents([.day], from: updateDate, to: now).day ?? 0
        if days <= 180 { return 0 }
        if days <= 365 { return 1 }
        return 2
    }

    private static func sessionSignature(_ session: ReadingSession) -> UInt64 {
        var hasher = DeterministicHasher()
        hasher.mix(session.id)
        hasher.mix(session.workID)
        hasher.mix(session.startedAt.timeIntervalSince1970)
        hasher.mix(session.endedAt.timeIntervalSince1970)
        hasher.mix(session.durationSeconds)
        hasher.mix(session.startProgress)
        hasher.mix(session.endingProgress)
        hasher.mix(session.wordCount)
        hasher.mix(session.modeRaw)
        hasher.mix(session.didFinish)
        hasher.mix(session.rating.trimmingCharacters(in: .whitespacesAndNewlines))
        hasher.mix(session.lastModifiedAt.timeIntervalSince1970)
        return hasher.state
    }

    private static func aliasSignature(_ alias: TagAlias) -> UInt64 {
        var hasher = DeterministicHasher()
        hasher.mix(alias.id)
        hasher.mix(alias.kindRaw)
        hasher.mix(alias.name)
        hasher.mix(alias.canonicalName)
        hasher.mix(alias.parentFandoms)
        return hasher.state
    }

    private static func seriesSignature(_ series: SavedSeries) -> UInt64 {
        var hasher = DeterministicHasher()
        hasher.mix(series.id)
        hasher.mix(series.ao3SeriesID)
        hasher.mix(series.title)
        hasher.mix(series.partCount)
        hasher.mix(series.isComplete)
        hasher.mix(series.wordCount)
        hasher.mix(series.partWorkIDs.count)
        for workID in series.partWorkIDs {
            hasher.mix(workID)
        }
        hasher.mix(series.lastModifiedAt.timeIntervalSince1970)
        return hasher.state
    }

    struct Snapshot: Sendable {
        let digest: String
        let liveWorkSignatures: [UUID: UInt64]
        let softDeletedAdultFlags: [UUID: Bool]
    }

    #if DEBUG
    private final class LockedCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func load() -> Int { lock.withLock { value } }
        func increment() { lock.withLock { value += 1 } }
    }

    private static let snapshotCounter = LockedCounter()

    /// Counts full library digest walks (tests prove a refresh walks once).
    static var snapshotCountForTests: Int { snapshotCounter.load() }
    #endif

    /// Streaming digest accumulator so `InsightsGatherActor` can fold bounded fetch batches
    /// into the exact same `Snapshot` without holding full tables or running duplicate queries.
    struct Builder {
        private var liveBag = BagDigest()
        private var liveSignatures: [UUID: UInt64] = [:]
        private var deletedBag = BagDigest()
        private var deletedFlags: [UUID: Bool] = [:]
        private var sessionBag = BagDigest()
        private var aliasBag = BagDigest()
        private var seriesBag = BagDigest()
        private let now: Date
        private let calendar: Calendar

        init(now: Date = Date(), calendar: Calendar = .current) {
            self.now = now
            self.calendar = calendar
        }

        mutating func addLiveWork(_ work: SavedWork) {
            let sig = InsightsReloadDigest.workSignature(work, now: now, calendar: calendar)
            liveSignatures[work.id] = sig
            liveBag.add(sig)
        }

        mutating func addSoftDeleted(_ softDeleted: (all: Set<UUID>, adult: Set<UUID>)) {
            deletedFlags.reserveCapacity(deletedFlags.count + softDeleted.all.count)
            for id in softDeleted.all {
                let isAdult = softDeleted.adult.contains(id)
                deletedFlags[id] = isAdult
                var hasher = DeterministicHasher()
                hasher.mix(id)
                hasher.mix(isAdult)
                deletedBag.add(hasher.state)
            }
        }

        mutating func addSession(_ session: ReadingSession) {
            sessionBag.add(InsightsReloadDigest.sessionSignature(session))
        }

        mutating func addAlias(_ alias: TagAlias) {
            aliasBag.add(InsightsReloadDigest.aliasSignature(alias))
        }

        mutating func addSeries(_ series: SavedSeries) {
            seriesBag.add(InsightsReloadDigest.seriesSignature(series))
        }

        func build() -> Snapshot {
            #if DEBUG
            InsightsReloadDigest.snapshotCounter.increment()
            #endif
            let digest = "\(liveBag.token)|\(deletedBag.token)|\(sessionBag.token)|\(aliasBag.token)|\(seriesBag.token)"
            return Snapshot(
                digest: digest,
                liveWorkSignatures: liveSignatures,
                softDeletedAdultFlags: deletedFlags
            )
        }
    }

    /// `preloadedSessions` is the table the gather actor already fetched in batches; nil
    /// fetches it here in one go, as the main-actor callers always did.
    static func snapshot(
        works: [SavedWork],
        context: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .current,
        preloadedSessions: [ReadingSession]? = nil
    ) -> Snapshot {
        var builder = Builder(now: now, calendar: calendar)
        for work in works {
            builder.addLiveWork(work)
        }
        builder.addSoftDeleted(HomeReadingStats.softDeletedWorkIDs(in: context))
        let sessions = preloadedSessions ?? ((try? context.fetch(FetchDescriptor<ReadingSession>())) ?? [])
        for session in sessions {
            builder.addSession(session)
        }
        let aliases = (try? context.fetch(FetchDescriptor<TagAlias>())) ?? []
        for alias in aliases {
            builder.addAlias(alias)
        }
        let seriesRows = (try? context.fetch(FetchDescriptor<SavedSeries>())) ?? []
        for series in seriesRows {
            builder.addSeries(series)
        }
        return builder.build()
    }

    static func make(
        works: [SavedWork],
        context: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        snapshot(works: works, context: context, now: now, calendar: calendar).digest
    }
}

/// Filters `ModelContext.didSave` notifications in O(k) (where k is the number of
/// changed records in the save) so detached Read Aloud position checkpoints and
/// unrelated saves never walk the library or query `ReadingSession` while Insights
/// is visible.
@MainActor
final class InsightsReloadTracker {
    enum SaveClassification: Equatable {
        /// Save touched no Insights-relevant entity or only updated a `SavedWork`'s
        /// non-bucket position fields — skip digest & reload completely.
        case ignored
        /// Save definitely changed an Insights input (or came from another context
        /// touching a relevant entity) — schedule a coalesced reload.
        case needsReload
        /// Notification had no usable identifier payload (or an unresolved record);
        /// fall back to comparing the full per-record digest.
        case fallbackFullDigest
    }

    private var liveWorkSignatures: [UUID: UInt64] = [:]
    private var softDeletedAdultFlags: [UUID: Bool] = [:]
    private(set) var lastDigest: String = ""
    private var hasBaseline = false

    @discardableResult
    func recordBaseline(
        works: [SavedWork],
        context: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let snap = InsightsReloadDigest.snapshot(
            works: works,
            context: context,
            now: now,
            calendar: calendar
        )
        liveWorkSignatures = snap.liveWorkSignatures
        softDeletedAdultFlags = snap.softDeletedAdultFlags
        lastDigest = snap.digest
        hasBaseline = true
        return snap.digest
    }

    /// Adopts a snapshot taken for a refresh as the new baseline, so that refresh
    /// walks the library once instead of once to decide and once to record.
    @discardableResult
    func adopt(_ snapshot: InsightsReloadDigest.Snapshot) -> String {
        liveWorkSignatures = snapshot.liveWorkSignatures
        softDeletedAdultFlags = snapshot.softDeletedAdultFlags
        lastDigest = snapshot.digest
        hasBaseline = true
        return snapshot.digest
    }

    func currentDigest(
        works: [SavedWork],
        context: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        InsightsReloadDigest.make(works: works, context: context, now: now, calendar: calendar)
    }

    func classifySave(
        _ notification: Notification,
        context: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SaveClassification {
        guard hasBaseline else { return .fallbackFullDigest }
        guard let userInfo = notification.userInfo else { return .fallbackFullDigest }

        if let invalidated = identifiers(for: .invalidatedAllIdentifiers, in: userInfo), !invalidated.isEmpty {
            return .fallbackFullDigest
        }

        let inserted = identifiers(for: .insertedIdentifiers, in: userInfo)
        let updated = identifiers(for: .updatedIdentifiers, in: userInfo)
        let deleted = identifiers(for: .deletedIdentifiers, in: userInfo)
        guard inserted != nil || updated != nil || deleted != nil else {
            return .fallbackFullDigest
        }

        let workEntity = Schema.entityName(for: SavedWork.self)
        let sessionEntity = Schema.entityName(for: ReadingSession.self)
        let aliasEntity = Schema.entityName(for: TagAlias.self)
        let seriesEntity = Schema.entityName(for: SavedSeries.self)

        let insertedList = inserted ?? []
        let updatedList = updated ?? []
        let deletedList = deleted ?? []

        // Any ReadingSession, TagAlias, or SavedSeries change always affects Insights.
        if containsEntity(sessionEntity, in: insertedList, updatedList, deletedList)
            || containsEntity(aliasEntity, in: insertedList, updatedList, deletedList)
            || containsEntity(seriesEntity, in: insertedList, updatedList, deletedList) {
            return .needsReload
        }

        // Any SavedWork insert or hard-delete changes inventory or sitting classification.
        if insertedList.contains(where: { $0.entityName == workEntity })
            || deletedList.contains(where: { $0.entityName == workEntity }) {
            return .needsReload
        }

        let updatedWorks = updatedList.filter { $0.entityName == workEntity }
        guard !updatedWorks.isEmpty else {
            return .ignored
        }

        // Saves from a background context may not be merged into this context's
        // registered models yet; treat work saves from another context as relevant.
        let isSameContext = (notification.object as AnyObject?) === context
        guard isSameContext else {
            return .needsReload
        }

        for id in updatedWorks {
            guard let work: SavedWork = context.registeredModel(for: id) else {
                return .fallbackFullDigest
            }
            if workChangedInsights(work, now: now, calendar: calendar) {
                return .needsReload
            }
        }

        return .ignored
    }

    private func workChangedInsights(_ work: SavedWork, now: Date, calendar: Calendar) -> Bool {
        if work.isPendingDeletion {
            return liveWorkSignatures[work.id] != nil
                || softDeletedAdultFlags[work.id] != work.isAdult
        }
        if softDeletedAdultFlags[work.id] != nil {
            return true
        }
        guard let previous = liveWorkSignatures[work.id] else {
            return true
        }
        return InsightsReloadDigest.workSignature(work, now: now, calendar: calendar) != previous
    }

    func shouldReload(
        afterSave notification: Notification,
        works: [SavedWork],
        context: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        switch classifySave(notification, context: context, now: now, calendar: calendar) {
        case .ignored:
            return false
        case .needsReload:
            return true
        case .fallbackFullDigest:
            return currentDigest(works: works, context: context, now: now, calendar: calendar) != lastDigest
        }
    }

    private func containsEntity(_ entity: String, in lists: [PersistentIdentifier]...) -> Bool {
        lists.contains { list in list.contains { $0.entityName == entity } }
    }

    private func identifiers(
        for key: ModelContext.NotificationKey,
        in userInfo: [AnyHashable: Any]
    ) -> [PersistentIdentifier]? {
        let raw = userInfo[key] ?? userInfo[key.rawValue]
        if let array = raw as? [PersistentIdentifier] { return array }
        if let set = raw as? Set<PersistentIdentifier> { return Array(set) }
        return nil
    }
}

/// Coalesces relevant Insights refreshes with a bounded interval: once scheduled,
/// further saves do not push the deadline back, so a steady stream of saves can
/// never starve a refresh while bursts still collapse to one reload per window.
@MainActor
final class InsightsSaveCoalescer {
    private let interval: Duration
    private var pendingTask: Task<Void, Never>?

    init(interval: Duration = .milliseconds(500)) {
        self.interval = interval
    }

    var hasPendingRefresh: Bool { pendingTask != nil }

    func schedule(_ action: @escaping @MainActor () -> Void) {
        guard pendingTask == nil else { return }
        pendingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.interval)
            // A cancelled task must not touch `pendingTask`: `cancel()` already
            // cleared it, and by the time this wakes a *newer* refresh may own the
            // slot. Clearing it here would orphan that one (it could no longer be
            // cancelled, and the next save would schedule a duplicate).
            guard !Task.isCancelled else { return }
            self.pendingTask = nil
            action()
        }
    }

    func cancel() {
        pendingTask?.cancel()
        pendingTask = nil
    }
}

/// Wires `ModelContext.didSave` to a coalesced Insights refresh, in one place the
/// screen and its tests share: classify the save cheaply, schedule at most one
/// refresh per window, and when it fires take **one** digest snapshot of the library
/// and hand it to the reload (as its baseline) only if it differs from the last one.
@MainActor
final class InsightsReloadCoordinator {
    let tracker: InsightsReloadTracker
    private let coalescer: InsightsSaveCoalescer
    /// The off-main digest of the latest coalesced save, cancelled when a newer one starts.
    private var digestTask: Task<Void, Never>?
    private var digestGeneration = 0

    init(
        interval: Duration = .milliseconds(500),
        tracker: InsightsReloadTracker? = nil
    ) {
        self.tracker = tracker ?? InsightsReloadTracker()
        self.coalescer = InsightsSaveCoalescer(interval: interval)
    }

    var hasPendingRefresh: Bool { coalescer.hasPendingRefresh }

    /// Call for every `didSave` while the screen is up. `works` is read when the
    /// refresh fires, not when the save arrives. With `digest`, the library walk runs
    /// there (off the main actor) instead of here; a newer refresh cancels an older one.
    func noteSave(
        _ notification: Notification,
        works: @escaping @MainActor () -> [SavedWork],
        context: ModelContext,
        isOnScreen: @escaping @MainActor () -> Bool,
        reload: @escaping @MainActor (InsightsReloadDigest.Snapshot) -> Void,
        digest: (@MainActor () async -> InsightsReloadDigest.Snapshot?)? = nil
    ) {
        guard tracker.classifySave(notification, context: context) != .ignored else { return }
        coalescer.schedule { [tracker, weak self] in
            guard isOnScreen() else { return }
            if let digest {
                guard let self else { return }
                self.digestGeneration += 1
                let gen = self.digestGeneration
                self.digestTask?.cancel()
                self.digestTask = Task { @MainActor [weak self] in
                    guard let snapshot = await digest(),
                          !Task.isCancelled,
                          let self,
                          self.digestGeneration == gen,
                          isOnScreen()
                    else { return }
                    guard snapshot.digest != tracker.lastDigest else { return }
                    reload(snapshot)
                }
                return
            }
            let snapshot = InsightsReloadDigest.snapshot(works: works(), context: context)
            guard snapshot.digest != tracker.lastDigest else { return }
            reload(snapshot)
        }
    }

    func cancel() {
        coalescer.cancel()
        digestGeneration += 1
        digestTask?.cancel()
        digestTask = nil
    }
}

/// What makes the Insights screen reload. Every input that changes a displayed
/// figure is a component, including the library digest: a same-count edit (a rating
/// swap, a corrected save time) moves only that component.
enum InsightsReloadKey {
    static func make(
        range: String,
        referenceDate: Date,
        hideMature: Bool,
        revealAll: Bool,
        includeHidden: Bool,
        countRereads: Bool,
        countReadAloud: Bool,
        askAboutUntouched: Bool,
        untouchedDays: Int,
        optionsRevision: Int,
        libraryCount: Int,
        libraryDigest: String
    ) -> String {
        [
            range,
            "\(referenceDate.timeIntervalSince1970)",
            "\(hideMature)-\(revealAll)-\(includeHidden)",
            "\(countRereads)-\(countReadAloud)-\(askAboutUntouched)-\(untouchedDays)",
            "\(optionsRevision)",
            "\(libraryCount)-\(libraryDigest)"
        ].joined(separator: "|")
    }
}
