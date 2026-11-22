import Foundation
import OSLog
import SwiftData

/// Local transient inbox of unread new-work batches found in followed tag Atom feeds.
///
/// Stored outside SwiftData/backups (like `SubscriptionScanService`) because it holds
/// cached feed update summaries rather than durable user library records; `FollowedTag`
/// itself carries the followed tags, switches, `lastCheckedAt`, and `lastSeen` watermarks
/// across backups and folder sync.
@MainActor
@Observable
final class FollowedTagUpdateStore {
    static let shared = FollowedTagUpdateStore()

    private(set) var updates: [SubscriptionUpdate] = []
    private(set) var isChecking = false

    @ObservationIgnored private var activeCheckToken: UUID?
    @ObservationIgnored private var activeCheckTask: Task<Void, Never>?

    private let fileURL: URL?
    private let client: AO3Client

    init(
        directory: URL? = FollowedTagUpdateStore.defaultDirectory(),
        client: AO3Client = .shared
    ) {
        self.client = client
        if let directory {
            fileURL = directory.appendingPathComponent("updates.json")
        } else {
            fileURL = nil
        }
        loadFromDisk()
    }

    nonisolated static func defaultDirectory() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("KudosFollowedTagUpdates", isDirectory: true)
    }

    // MARK: Queries & Unread Counts

    func unreadCount(forTagID tagID: Int) -> Int {
        updates.reduce(into: 0) { partial, update in
            if case let .tag(source) = update.source, source.tagID == tagID {
                partial += max(source.count, 1)
            }
        }
    }

    func latestUpdateDate(forTagID tagID: Int) -> Date? {
        updates
            .filter {
                if case let .tag(source) = $0.source { return source.tagID == tagID }
                return false
            }
            .map(\.at)
            .max()
    }

    func visibleUpdates(for tags: [FollowedTag], homeOnly: Bool) -> [SubscriptionUpdate] {
        let byTagID = Dictionary(
            tags.map { ($0.ao3TagID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return updates.compactMap { update in
            guard case let .tag(source) = update.source,
                  let tag = byTagID[source.tagID]
            else { return nil }
            if homeOnly, !tag.showOnHome { return nil }
            return update
        }
    }

    func markSeen(tagID: Int) {
        let before = updates.count
        updates.removeAll {
            if case let .tag(source) = $0.source { return source.tagID == tagID }
            return false
        }
        if updates.count != before {
            persistToDisk()
        }
    }

    func markAllSeen() {
        guard !updates.isEmpty else { return }
        updates = []
        persistToDisk()
    }

    func clearUpdates(forTagID tagID: Int) {
        markSeen(tagID: tagID)
    }

    func pruneOrphanedTags(keepingTagIDs validIDs: Set<Int>) {
        let before = updates.count
        updates.removeAll {
            if case let .tag(source) = $0.source { return !validIDs.contains(source.tagID) }
            return true
        }
        if updates.count != before {
            persistToDisk()
        }
    }

    // MARK: Foreground Check Runner

    /// Cancels any foreground pass in flight without blocking the caller.
    func cancelCheck() {
        activeCheckTask?.cancel()
    }

    /// Sequentially checks due tags while `screen` stays active.
    ///
    /// Cancels and awaits unwind of any superseded foreground check so rapid screen
    /// switches (e.g. Home -> Subscriptions) never drop the destination screen's pass.
    /// Never runs outside `Subscriptions` or `Home`, honours the 6-hour per-tag gate
    /// unless `ignoringCooldown` (pull to refresh) is true, pauses >= 3 s between
    /// requests, and stops cleanly on cancellation or AO3 rate/maintenance/403/5xx errors.
    func checkIfNeeded(
        screen: FollowedTagCheckScreen,
        in context: ModelContext,
        ignoringCooldown: Bool = false,
        isScreenActive: @escaping () -> Bool,
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = Date.init,
        sleep: ((TimeInterval) async throws -> Void)? = nil,
        fetch: ((FollowedTag) async throws -> AO3TagFeed)? = nil
    ) async {
        let token = UUID()
        let previousTask = activeCheckTask
        activeCheckToken = token
        previousTask?.cancel()

        let task = Task { @MainActor [weak self] in
            if let previousTask {
                await previousTask.value
            }
            guard let self, !Task.isCancelled, self.activeCheckToken == token else { return }
            await self.performCheck(
                screen: screen,
                in: context,
                ignoringCooldown: ignoringCooldown,
                isScreenActive: isScreenActive,
                defaults: defaults,
                now: now,
                sleep: sleep,
                fetch: fetch
            )
        }
        activeCheckTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if activeCheckToken == token {
            activeCheckTask = nil
            activeCheckToken = nil
        }
    }

    // swiftlint:disable:next function_parameter_count
    private func performCheck(
        screen: FollowedTagCheckScreen,
        in context: ModelContext,
        ignoringCooldown: Bool,
        isScreenActive: @escaping () -> Bool,
        defaults: UserDefaults,
        now: @escaping @Sendable () -> Date,
        sleep: ((TimeInterval) async throws -> Void)?,
        fetch: ((FollowedTag) async throws -> AO3TagFeed)?
    ) async {
        let tags = (try? context.fetch(FetchDescriptor<FollowedTag>())) ?? []
        pruneOrphanedTags(keepingTagIDs: Set(tags.map(\.ao3TagID)))
        guard !tags.isEmpty else { return }

        isChecking = true
        defer { isChecking = false }

        // Snapshot prior-snapshot flags BEFORE `attempt` writes `lastCheckedAt`.
        // Keying off `seenWorkIDs.isEmpty && lastSeenWorkID == nil` ensures that
        // if an earlier check failed before ever reading a feed, the first
        // successful fetch still baselines historical pre-follow entries.
        var priorStates: [UUID: (isInitial: Bool, seenIDs: [Int])] = [:]
        for tag in tags {
            let isInitial = tag.seenWorkIDs.isEmpty && tag.lastSeenWorkID == nil
            priorStates[tag.id] = (isInitial, tag.seenWorkIDs)
        }

        let paceSleep = sleep ?? { seconds in
            try await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
        }
        let client = self.client
        let feedFetcher = fetch ?? { tag in
            try await client.followedTagFeed(tagID: tag.ao3TagID, defaults: defaults, now: now)
        }

        await FollowedTagChecks.run(
            tags: tags,
            screen: screen,
            showOnHome: \.showOnHome,
            checkedAt: \.lastCheckedAt,
            ignoringCooldown: ignoringCooldown,
            isScreenActive: isScreenActive,
            isRateLimitHeld: { currentNow in
                AO3Client.isFollowedTagHeld(now: currentNow, defaults: defaults)
            },
            isMaintenanceHeld: {
                await client.isHeldForMaintenance
            },
            now: now,
            sleep: paceSleep,
            attempt: { tag, startedAt in
                guard tag.modelContext != nil else { return false }
                tag.lastCheckedAt = startedAt
                context.saveBestEffort(reason: "Saving followed-tag attempt time failed")
                return true
            },
            fetch: feedFetcher,
            received: { [weak self] tag, feed, _ in
                guard tag.modelContext != nil else { return }
                let prior = priorStates[tag.id] ?? (isInitial: false, seenIDs: tag.seenWorkIDs)
                let evaluation = FollowedTagFeedEvaluator.evaluate(
                    feed: feed,
                    followedAt: tag.followedAt,
                    priorSeenWorkIDs: prior.seenIDs,
                    isInitialCheck: prior.isInitial,
                    completeOnly: tag.completeOnly,
                    hideExplicit: tag.hideExplicit
                )
                self?.apply(evaluation: evaluation, to: tag, in: context)
            }
        )
    }

    func apply(
        evaluation: FollowedTagFeedEvaluator.Evaluation,
        to tag: FollowedTag,
        in context: ModelContext
    ) {
        tag.seenWorkIDs = evaluation.updatedSeenWorkIDs
        if let newestID = evaluation.newestWorkID,
           let newestDate = evaluation.newestPublishedAt {
            if tag.lastSeenPublishedAt == nil || newestDate >= (tag.lastSeenPublishedAt ?? .distantPast) {
                tag.lastSeenWorkID = newestID
                tag.lastSeenPublishedAt = newestDate
            }
        }
        context.saveBestEffort(reason: "Saving followed-tag feed state failed")

        guard !evaluation.matchingEntries.isEmpty else { return }
        recordMatchingEntries(evaluation.matchingEntries, for: tag, isBusy: evaluation.isBusy)
    }

    func recordMatchingEntries(
        _ entries: [AO3TagFeedEntry],
        for tag: FollowedTag,
        isBusy: Bool
    ) {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.publishedAt) }

        for (dayStart, dayEntries) in grouped {
            guard let newest = dayEntries.max(by: { $0.publishedAt < $1.publishedAt }) else { continue }
            let stableUID = Self.stableUID(tagID: tag.ao3TagID, dayStart: dayStart)
            let batchCount = dayEntries.count

            var mergedCount = batchCount
            var mergedBusy = isBusy
            var chosenNewest = newest

            if let existingIndex = updates.firstIndex(where: { update in
                if case let .tag(source) = update.source,
                   source.tagID == tag.ao3TagID,
                   calendar.startOfDay(for: update.at) == dayStart {
                    return true
                }
                return false
            }) {
                let existing = updates[existingIndex]
                if case let .tag(oldSource) = existing.source {
                    mergedCount = oldSource.count + batchCount
                    mergedBusy = oldSource.isBusy || isBusy || mergedCount >= FollowedTagFeedEvaluator.maxFeedEntries
                    if existing.at > newest.publishedAt {
                        // Keep newer metadata if the existing entry was newer.
                        chosenNewest = AO3TagFeedEntry(
                            id: existing.id,
                            workID: Int(clamping: existing.workID),
                            title: existing.workTitle,
                            authors: existing.author.isEmpty ? [] : [existing.author],
                            authorIdentities: [],
                            publishedAt: existing.at,
                            updatedAt: nil,
                            url: nil,
                            summary: existing.summary ?? "",
                            words: Int(clamping: existing.words ?? 0),
                            chapters: "",
                            isComplete: true,
                            language: "",
                            rating: existing.rating,
                            warnings: existing.warnings,
                            categories: [],
                            fandoms: existing.fandoms,
                            characters: existing.characters,
                            relationships: existing.relationships,
                            freeforms: existing.additionalTags
                        )
                    }
                }
                updates.remove(at: existingIndex)
            }

            let source = SubscriptionUpdate.FollowedTagUpdateSource(
                tagID: tag.ao3TagID,
                name: tag.name,
                category: tag.displayCategory,
                tagURLString: tag.worksURL?.absoluteString ?? tag.tagURLString,
                count: mergedCount,
                isBusy: mergedBusy,
                showOnHome: tag.showOnHome
            )

            let update = SubscriptionUpdate(
                uid: stableUID,
                workID: UInt64(max(chosenNewest.workID, 0)),
                chapterID: nil,
                chapterNumber: nil,
                isNewWork: true,
                isContested: false,
                isAnchoredToWork: false,
                workTitle: chosenNewest.title,
                author: chosenNewest.authors.joined(separator: ", "),
                at: chosenNewest.publishedAt,
                source: .tag(source),
                extraCreations: 0,
                rating: chosenNewest.rating,
                warnings: chosenNewest.warnings,
                fandoms: chosenNewest.fandoms,
                relationships: chosenNewest.relationships,
                characters: chosenNewest.characters,
                additionalTags: chosenNewest.freeforms,
                words: chosenNewest.words > 0 ? UInt64(chosenNewest.words) : nil,
                chaptersPosted: nil,
                chaptersTotal: nil,
                series: nil,
                summary: chosenNewest.summary.isEmpty ? nil : chosenNewest.summary
            )
            updates.append(update)
        }

        updates.sort { $0.at > $1.at }
        if updates.count > SubscriptionUpdateState.limit {
            updates = Array(updates.prefix(SubscriptionUpdateState.limit))
        }
        persistToDisk()
    }

    // MARK: Persistence

    private static func stableUID(tagID: Int, dayStart: Date) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        let dayBucket = Int64(dayStart.timeIntervalSince1970 / 86_400)
        for byte in "\(tagID)-\(dayBucket)".utf8 {
            hash ^= UInt32(byte)
            hash &*= 16_777_619
        }
        return hash | 0x8000_0000
    }

    private func loadFromDisk() {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            updates = try decoder.decode([SubscriptionUpdate].self, from: data)
        } catch {
            Log.library.notice("Followed tag updates store unreadable; starting fresh")
            updates = []
        }
    }

    private func persistToDisk() {
        guard let fileURL else { return }
        let dir = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(updates)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Log.library.error(
                "Failed to persist followed tag updates: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
