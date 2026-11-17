import Foundation

/// The only two surfaces allowed to trigger foreground followed-tag feed checks.
nonisolated enum FollowedTagCheckScreen: Equatable, Sendable {
    /// Checks all followed tags whose cooldown has elapsed.
    case subscriptions
    /// Checks only followed tags with `showOnHome == true`.
    case home
}

/// Pure feed-diff evaluator comparing an Atom feed fetch against what a
/// `FollowedTag` has already observed.
nonisolated enum FollowedTagFeedEvaluator {
    /// Maximum entries AO3's `/tags/:id/feed.atom` can emit (`tags_controller.rb:84`).
    static let maxFeedEntries = 25

    struct Evaluation: Equatable, Sendable {
        let unseenEntries: [AO3TagFeedEntry]
        let matchingEntries: [AO3TagFeedEntry]
        /// True when AO3's 25-entry cap was saturated by unseen entries, meaning
        /// more new works may have dropped off without a page-2 request.
        let isBusy: Bool
        let newestWorkID: Int?
        let newestPublishedAt: Date?
        let updatedSeenWorkIDs: [Int]
    }

    // swiftlint:disable:next function_parameter_count
    static func evaluate(
        feed: AO3TagFeed,
        followedAt: Date,
        priorSeenWorkIDs: [Int],
        isInitialCheck: Bool,
        completeOnly: Bool,
        hideExplicit: Bool
    ) -> Evaluation {
        let sortedEntries = feed.entries.sorted { $0.publishedAt > $1.publishedAt }
        let priorSet = Set(priorSeenWorkIDs)

        let unseen = sortedEntries.filter { entry in
            guard !priorSet.contains(entry.workID) else { return false }
            if isInitialCheck {
                return entry.publishedAt > followedAt
            }
            return true
        }

        let matching = unseen.filter {
            $0.passesFilters(completeOnly: completeOnly, hideExplicit: hideExplicit)
        }

        let isBusy = sortedEntries.count >= maxFeedEntries && unseen.count >= maxFeedEntries

        let newest = sortedEntries.first
        var mergedIDs: [Int] = []
        var seen = Set<Int>()
        for id in sortedEntries.map(\.workID) + priorSeenWorkIDs where id > 0 {
            if seen.insert(id).inserted {
                mergedIDs.append(id)
                if mergedIDs.count >= FollowedTag.seenIDRetentionLimit { break }
            }
        }

        return Evaluation(
            unseenEntries: unseen,
            matchingEntries: matching,
            isBusy: isBusy,
            newestWorkID: newest?.workID,
            newestPublishedAt: newest?.publishedAt,
            updatedSeenWorkIDs: mergedIDs
        )
    }
}

/// Pure scheduling, spacing, and failure-stop rules for followed-tag feed checks.
enum FollowedTagChecks {
    /// Six-hour per-tag cooldown, including after failure.
    nonisolated static let cooldown: TimeInterval = FollowedTag.checkInterval
    /// Minimum start-to-start spacing between consecutive feed requests.
    nonisolated static let spacing: TimeInterval = 3

    nonisolated static func isEligible(
        lastCheckedAt: Date?,
        showOnHome: Bool,
        screen: FollowedTagCheckScreen,
        now: Date,
        ignoringCooldown: Bool = false
    ) -> Bool {
        if screen == .home, !showOnHome { return false }
        if ignoringCooldown { return true }
        guard let lastCheckedAt else { return true }
        return now.timeIntervalSince(lastCheckedAt) >= cooldown
    }

    nonisolated static func eligible<Tag>(
        _ tags: [Tag],
        screen: FollowedTagCheckScreen,
        showOnHome: (Tag) -> Bool,
        checkedAt: (Tag) -> Date?,
        now: Date,
        ignoringCooldown: Bool = false
    ) -> [Tag] {
        tags.filter { tag in
            isEligible(
                lastCheckedAt: checkedAt(tag),
                showOnHome: showOnHome(tag),
                screen: screen,
                now: now,
                ignoringCooldown: ignoringCooldown
            )
        }
        .sorted { (checkedAt($0) ?? .distantPast) < (checkedAt($1) ?? .distantPast) }
    }

    /// Errors that must immediately halt the remainder of this foreground visit's pass.
    nonisolated static func shouldStopPass(on error: Error) -> Bool {
        if QueueSourceChecks.isUnreachable(error) { return true }
        guard let ao3 = error as? AO3Error else { return true }
        switch ao3 {
        case .rateLimited, .forbidden, .server, .maintenance, .network:
            return true
        case let .http(status):
            return status == 403 || status == 418 || status == 429 || (500 ... 599).contains(status)
        case .notFound, .parse, .authenticationRequired, .untrustedHost:
            return false
        }
    }

    @MainActor
    // swiftlint:disable:next function_parameter_count
    static func run<Tag>(
        tags: [Tag],
        screen: FollowedTagCheckScreen,
        showOnHome: (Tag) -> Bool,
        checkedAt: (Tag) -> Date?,
        ignoringCooldown: Bool = false,
        isScreenActive: () -> Bool,
        isRateLimitHeld: (Date) -> Bool,
        now: () -> Date,
        sleep: (TimeInterval) async throws -> Void,
        attempt: (Tag, Date) -> Bool,
        fetch: (Tag) async throws -> AO3TagFeed,
        received: (Tag, AO3TagFeed, Date) -> Void
    ) async {
        guard isScreenActive(), !isRateLimitHeld(now()) else { return }
        let selected = eligible(
            tags,
            screen: screen,
            showOnHome: showOnHome,
            checkedAt: checkedAt,
            now: now(),
            ignoringCooldown: ignoringCooldown
        )
        var previousStart: Date?

        for tag in selected {
            do {
                try Task.checkCancellation()
                guard isScreenActive(), !isRateLimitHeld(now()) else { return }

                if let previousStart {
                    let remaining = spacing - now().timeIntervalSince(previousStart)
                    if remaining > 0 {
                        try await sleep(remaining)
                    }
                }

                try Task.checkCancellation()
                guard isScreenActive(), !isRateLimitHeld(now()) else { return }

                let started = now()
                previousStart = started

                do {
                    let feed = try await fetch(tag)
                    try Task.checkCancellation()
                    guard attempt(tag, started) else { return }
                    received(tag, feed, started)
                } catch is CancellationError {
                    return
                } catch let urlError as URLError where urlError.code == .cancelled {
                    return
                } catch {
                    // Stamp attempted failures too (except cancellation/pre-flight hold)
                    // so the 6-hour gate holds even when a tag check fails.
                    _ = attempt(tag, started)
                    if shouldStopPass(on: error) {
                        return
                    }
                }
            } catch is CancellationError {
                return
            } catch let urlError as URLError where urlError.code == .cancelled {
                return
            } catch {
                return
            }
        }
    }
}
