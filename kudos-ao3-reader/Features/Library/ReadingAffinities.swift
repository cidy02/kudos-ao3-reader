import Foundation
import SwiftData

/// The aggregate rows behind Favorites' Authors, Fandoms and Tags scopes —
/// artboards **1ak**, **1bc** and **1bd**.
///
/// **These are derived, not starred.** The spec's rows read "6 works read · 31h
/// 12m · last read 4 Sep 2026" and "41 works read carry this tag" — facts the app
/// computes from the reading log, not a list someone curated. A star list would be
/// empty for every reader who has not curated one, which is every reader; an
/// affinity list is full the moment you have read anything.
///
/// `ReadingFavorite`'s `.author` / `.fandom` / `.tag` kinds are the *explicit* star
/// and are a separate axis. Nothing in the app writes them yet — `setFavorite` has no
/// callers — so nothing here reads them.
///
/// `@MainActor` because every function walks `SavedWork`, which is a SwiftData
/// `@Model`. The rules are still pure: same inputs, same rows, no fetching.
@MainActor
enum ReadingAffinities {

    /// One creator, fandom or tag, with what the log knows about it.
    nonisolated struct Row: Identifiable, Equatable {
        /// The creator's byline, the fandom tag, or the tag — also the display name.
        var name: String
        /// Distinct works read that carry this name.
        var worksRead: Int
        /// Time spent in those works.
        var totalSeconds: Double
        var lastRead: Date?
        /// Works in the library carrying this name that have never been opened.
        var unreadInLibrary: Int
        /// Of those, how many have their file on disk.
        var downloadedInLibrary: Int
        /// Of those, how many sit in the permanent Saved for Later queue.
        var savedForLater: Int

        var id: String { name }
    }

    /// Which field a scope's rows are ranked by. Spec 1ak and 1bd both offer
    /// "Most read" beside "All", so the order is a control rather than a constant.
    nonisolated enum Order: String, CaseIterable, Hashable, Sendable {
        /// Most recently read first — the default, because a favourites list is
        /// mostly re-entered to get back to something.
        case recent
        /// Most works read.
        case mostRead
        /// Most time spent. Distinct from `mostRead`: six short works and one
        /// enormous one are different kinds of favourite.
        case mostTime

        var title: String {
            switch self {
            case .recent: "Recent"
            case .mostRead: "Most read"
            case .mostTime: "Most time"
            }
        }
    }

    /// Creators, one row each.
    static func authors(
        works: [SavedWork],
        summaries: [UUID: WorkReadingSummary],
        order: Order = .recent
    ) -> [Row] {
        rows(works: works, summaries: summaries, order: order) { work in
            let byline = work.author.trimmingCharacters(in: .whitespacesAndNewlines)
            return byline.isEmpty ? [] : [byline]
        }
    }

    static func fandoms(
        works: [SavedWork],
        summaries: [UUID: WorkReadingSummary],
        order: Order = .recent
    ) -> [Row] {
        rows(works: works, summaries: summaries, order: order) { $0.workFandoms }
    }

    /// Freeform and additional tags — not fandoms, which have their own scope, and
    /// not characters or relationships, which are about *who* rather than what the
    /// work is like.
    static func tags(
        works: [SavedWork],
        summaries: [UUID: WorkReadingSummary],
        order: Order = .recent
    ) -> [Row] {
        rows(works: works, summaries: summaries, order: order) { work in
            work.workFreeforms.isEmpty ? work.workTags : work.workFreeforms
        }
    }

    /// The shared pass. `keys` says which names a work contributes to; everything
    /// else is the same arithmetic for all three scopes.
    ///
    /// A work contributes to **every** key it carries, which means the totals here
    /// deliberately over-count against a grand total — unlike `ReadingInsights`'
    /// fandom shares, which partition. The difference is what the number means: a
    /// share of a fixed pie has to sum to the pie, while "41 works read carry this
    /// tag" is a count about that tag alone and a work with two tags is honestly
    /// counted by both.
    private static func rows(
        works: [SavedWork],
        summaries: [UUID: WorkReadingSummary],
        order: Order,
        keys: (SavedWork) -> [String]
    ) -> [Row] {
        var byName: [String: Row] = [:]
        for work in works {
            let summary = summaries[work.id]
            let wasRead = (summary?.visitCount ?? 0) > 0 || work.hasStartedReading
            let isUnread = !work.hasStartedReading && summary == nil
            for rawKey in keys(work) {
                let name = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                var row = byName[name] ?? Row(
                    name: name, worksRead: 0, totalSeconds: 0, lastRead: nil,
                    unreadInLibrary: 0, downloadedInLibrary: 0, savedForLater: 0
                )
                if wasRead {
                    row.worksRead += 1
                    row.totalSeconds += summary?.totalSeconds ?? 0
                    let candidate = summary?.lastEndedAt ?? work.lastReadDate
                    if let candidate, candidate > (row.lastRead ?? .distantPast) {
                        row.lastRead = candidate
                    }
                }
                if isUnread {
                    row.unreadInLibrary += 1
                    if work.hasEPUB { row.downloadedInLibrary += 1 }
                    // The shelf's own rule, not just queue membership — see
                    // `SavedWork.isOnSavedForLaterShelf`.
                    if work.isOnSavedForLaterShelf { row.savedForLater += 1 }
                }
                byName[name] = row
            }
        }
        // Only names with something read behind them. A tag carried solely by works
        // still sitting unopened is not an affinity, it is a shelf.
        return byName.values
            .filter { $0.worksRead > 0 }
            .sorted { sortsBefore($0, $1, order: order) }
    }

    /// Every order falls back to the name so the list is stable when two rows tie —
    /// a favourites list that reshuffles between renders looks broken.
    private static func sortsBefore(_ lhs: Row, _ rhs: Row, order: Order) -> Bool {
        switch order {
        case .recent:
            let left = lhs.lastRead ?? .distantPast
            let right = rhs.lastRead ?? .distantPast
            if left != right { return left > right }
        case .mostRead:
            if lhs.worksRead != rhs.worksRead { return lhs.worksRead > rhs.worksRead }
        case .mostTime:
            if lhs.totalSeconds != rhs.totalSeconds { return lhs.totalSeconds > rhs.totalSeconds }
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}
