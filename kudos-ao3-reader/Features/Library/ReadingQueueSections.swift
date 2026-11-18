import Foundation

/// The four sections of a reading queue (`T-528`).
/// Only `new` and `inLine` are stored on `ReadingQueueMembership.stateRaw`;
/// `waiting` and `finished` are derived from `SavedWork` and never persisted.
enum ReadingQueueSectionKind: Int, CaseIterable, Identifiable, Sendable {
    case new
    case inLine
    case waiting
    case finished

    var id: RawValue { rawValue }

    var title: String {
        switch self {
        case .new: "New"
        case .inLine: "In line"
        case .waiting: "Waiting"
        case .finished: "Finished"
        }
    }

    /// Board (`Queue-Sections.dc.html`) explanatory caption under `Waiting`.
    var subtitle: String? {
        switch self {
        case .waiting: "You are caught up. A work moves back to In line when a chapter posts."
        case .new, .inLine, .finished: nil
        }
    }
}

/// One work inside a partitioned reading queue, carrying its membership,
/// resolved section, derived "New chapter" mark, and optional origin line.
struct ReadingQueueSectionEntry: Identifiable {
    let membership: ReadingQueueMembership
    let work: SavedWork
    let section: ReadingQueueSectionKind
    let hasNewChapter: Bool

    var id: UUID { work.id }

    var originDisplayLine: String? {
        membership.originDisplayLine
    }
}

/// Result of partitioning a queue's ordered memberships into its four sections,
/// splitting the lead `In line` entry out as `Up next`.
struct ReadingQueueSectionPartition {
    let new: [ReadingQueueSectionEntry]
    let upNext: ReadingQueueSectionEntry?
    let inLineRest: [ReadingQueueSectionEntry]
    let waiting: [ReadingQueueSectionEntry]
    let finished: [ReadingQueueSectionEntry]

    var inLineAll: [ReadingQueueSectionEntry] {
        (upNext.map { [$0] } ?? []) + inLineRest
    }

    var isEmpty: Bool {
        new.isEmpty && upNext == nil && inLineRest.isEmpty && waiting.isEmpty && finished.isEmpty
    }

    /// Works in reader display order across the four sections (used for manual
    /// reorder & select-all when viewing the sectioned queue).
    var orderedWorks: [SavedWork] {
        (new + inLineAll + waiting + finished).map(\.work)
    }

    func section(for workID: UUID) -> ReadingQueueSectionKind? {
        if new.contains(where: { $0.id == workID }) { return .new }
        if upNext?.id == workID || inLineRest.contains(where: { $0.id == workID }) { return .inLine }
        if waiting.contains(where: { $0.id == workID }) { return .waiting }
        if finished.contains(where: { $0.id == workID }) { return .finished }
        return nil
    }
}

extension ReadingQueueFacts {
    /// Single source of truth for deriving a queued work's section from its
    /// stored `ReadingQueueMembershipState` and live `SavedWork` progress.
    ///
    /// Precedence:
    /// 1. `Finished`: the reader finished the work AND AO3 marks it complete.
    /// 2. `Waiting`: a WIP where the reader has reached every posted chapter and
    ///    no unread update has been recorded since `knownChapterCount`.
    /// 3. `In line`: explicitly sorted into line, OR a WIP whose reader had
    ///    caught up to `knownChapterCount` before a new chapter posted.
    /// 4. `New`: bulk-added / imported items not yet sorted into line.
    static func section(
        for membershipState: ReadingQueueMembershipState,
        work: SavedWork
    ) -> ReadingQueueSectionKind {
        if work.isFinished && work.isComplete {
            return .finished
        }
        if work.isCaughtUpOnWIP {
            return .waiting
        }
        let returnedFromWaiting = membershipState == .new
            && !work.isComplete
            && work.hasStartedReading
            && work.hasUpdate
            && work.knownChapterCount > 0
            && work.lastSpineIndex + 1 >= work.knownChapterCount
        if membershipState == .inLine || returnedFromWaiting {
            return .inLine
        }
        return .new
    }

    /// Derived `"New chapter"` mark: shown on unfinished works whose posted
    /// chapter count has grown past `knownChapterCount`.
    static func hasNewChapter(for work: SavedWork) -> Bool {
        !work.isFinished && work.hasUpdate
    }

    /// Partitions a queue's ordered memberships into New, In line (with the lead
    /// unfinished work split out as `upNext`), Waiting, and Finished.
    static func partition(memberships: [ReadingQueueMembership]) -> ReadingQueueSectionPartition {
        var newEntries: [ReadingQueueSectionEntry] = []
        var inLineEntries: [ReadingQueueSectionEntry] = []
        var waitingEntries: [ReadingQueueSectionEntry] = []
        var finishedEntries: [ReadingQueueSectionEntry] = []

        for membership in memberships {
            guard !membership.isPendingDeletion,
                  let work = membership.work,
                  !work.isPendingDeletion
            else { continue }
            let kind = section(for: membership.state, work: work)
            let entry = ReadingQueueSectionEntry(
                membership: membership,
                work: work,
                section: kind,
                hasNewChapter: kind == .finished ? false : hasNewChapter(for: work)
            )
            switch kind {
            case .new: newEntries.append(entry)
            case .inLine: inLineEntries.append(entry)
            case .waiting: waitingEntries.append(entry)
            case .finished: finishedEntries.append(entry)
            }
        }

        let upNextIndex = inLineEntries.firstIndex(where: { !$0.work.isFinished })
            ?? (inLineEntries.isEmpty ? nil : 0)
        let upNext = upNextIndex.map { inLineEntries[$0] }
        let inLineRest: [ReadingQueueSectionEntry] = if let upNextIndex {
            inLineEntries.enumerated().compactMap { $0.offset == upNextIndex ? nil : $0.element }
        } else {
            []
        }

        return ReadingQueueSectionPartition(
            new: newEntries,
            upNext: upNext,
            inLineRest: inLineRest,
            waiting: waitingEntries,
            finished: finishedEntries
        )
    }
}
