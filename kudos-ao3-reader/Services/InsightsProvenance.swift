import Foundation
import SwiftData

/// Figures for Insights P3 data (T-536, D7 to D11). Each takes rows the caller has already put
/// through `InsightsScopeSelection` (works from `libraryWorks` / `readingWorks`, sittings from
/// `sessions(_:in:)`, events from `events(_:in:)`), so the Hide Mature rules of T-535b apply to
/// every figure here without a second implementation: a concealed work's sitting, event, source,
/// stats or action never reaches a function in this file. They count only what was recorded;
/// an unrecorded value is reported as unrecorded, never guessed.
@MainActor
enum InsightsProvenance {
    // MARK: D7 time on each chapter

    struct ChapterTimingFigure: Equatable {
        /// Chapters judged skimmed when their sitting was saved, and their words, which
        /// leave the words-read totals.
        var skimmedChapters = 0
        var skimmedWords = 0
        /// Sittings that recorded where they stopped, and how many stopped at a chapter's end.
        var sittingsMeasured = 0
        var sittingsEndedAtChapterEnd = 0
        /// Works with a sitting that jumped to the last chapter before the halfway mark.
        var peekedWorks = 0
        /// Sittings the skim rule was applied to (read-mode sittings that stored a judgement).
        var judgedSittings = 0
    }

    static func chapterTiming(sessions: [ReadingSession]) -> ChapterTimingFigure {
        var figure = ChapterTimingFigure()
        var peeked: Set<UUID> = []
        for session in sessions {
            if let ended = session.endedAtChapterEnd {
                figure.sittingsMeasured += 1
                if ended { figure.sittingsEndedAtChapterEnd += 1 }
            }
            if session.peekedAtEnding == true { peeked.insert(session.workID) }
            guard session.skimmedChaptersJSON != nil else { continue }
            figure.judgedSittings += 1
            let words = session.chapterWords
            for spine in session.skimmedChapters {
                figure.skimmedChapters += 1
                let (sum, overflow) = figure.skimmedWords.addingReportingOverflow(words[spine] ?? 0)
                figure.skimmedWords = overflow ? Int.max : sum
            }
        }
        figure.peekedWorks = peeked.count
        return figure
    }

    // MARK: D8 where a work came from

    struct ArrivalFigure: Equatable {
        /// Works per recorded source, `.unknown` included (a path that did not know).
        var counts: [WorkImportSource: Int] = [:]
        /// Works saved before recording began.
        var unrecorded = 0
        /// The earliest date any source was recorded: the card says "since" this.
        var since: Date?

        var recorded: Int { counts.values.reduce(0, +) }
    }

    /// `works` are the finished works the card covers (the caller filters).
    static func arrival(works: [SavedWork]) -> ArrivalFigure {
        var figure = ArrivalFigure()
        for work in works {
            guard let source = work.importSource else {
                figure.unrecorded += 1
                continue
            }
            figure.counts[source, default: 0] += 1
            if let since = work.importSourceSince, figure.since.map({ since < $0 }) ?? true {
                figure.since = since
            }
        }
        return figure
    }

    // MARK: D9 kudos and hits when saved

    struct FoundEarlyEntry: Equatable, Identifiable {
        var id: UUID
        var title: String
        var kudosAtSave: Int
        var kudosNow: Int
        var hitsAtSave: Int?
        var hitsNow: Int
        var ageDaysAtSave: Int?
        var fandomWorksAtSave: Int?
        /// `kudosNow / max(kudosAtSave, 1)`: how much the work grew since it was saved.
        var growth: Double
    }

    /// Works whose kudos at save were recorded, biggest growth first. A work saved before
    /// recording began has none and is left out, not counted as zero.
    static func foundEarly(works: [SavedWork]) -> [FoundEarlyEntry] {
        works.compactMap { work -> FoundEarlyEntry? in
            guard work.statsSavedAt != nil, let atSave = work.kudosAtSave else { return nil }
            return FoundEarlyEntry(
                id: work.id,
                title: work.title,
                kudosAtSave: atSave,
                kudosNow: work.kudos,
                hitsAtSave: work.hitsAtSave,
                hitsNow: work.hits,
                ageDaysAtSave: work.ageDaysAtSave,
                fandomWorksAtSave: work.fandomWorksAtSave,
                growth: Double(work.kudos) / Double(max(atSave, 1))
            )
        }
        .sorted { ($0.growth, $0.kudosNow) > ($1.growth, $1.kudosNow) }
    }

    // MARK: D10 chapter update events

    /// What is known about one new chapter and the reader.
    enum NewChapterReadState: Equatable {
        /// A sitting that recorded its highest chapter reached this one.
        case read(firstReadAt: Date, delay: TimeInterval)
        /// No sitting since it posted got this far, and every one had a chapter signal.
        case unread
        /// A sitting since it posted recorded no chapter signal (older rows, macOS), so
        /// whether it was read cannot be said. Counted apart, never as read or unread.
        case unknown
    }

    struct NewChapterEntry: Equatable, Identifiable {
        var id: String { "\(eventID.uuidString)#\(chapter)" }
        var eventID: UUID
        var workID: UUID
        /// The AO3 story chapter (1-based).
        var chapter: Int
        var postedAt: Date
        var state: NewChapterReadState

        var delay: TimeInterval? {
            if case let .read(_, delay) = state { delay } else { nil }
        }
    }

    struct NewChaptersFigure: Equatable {
        /// One entry per new chapter, never two for the same chapter of a work.
        var entries: [NewChapterEntry] = []
        var unreadChapters = 0
        var unknownChapters = 0
        var medianDelay: TimeInterval?
    }

    /// Resolves each new chapter on its own. Events from different devices can overlap (3 to 5
    /// seen here, 3 to 6 there): a chapter is claimed by the earliest sighting that covers it, so
    /// it is counted once. A chapter counts as read only when a sitting after it posted
    /// recorded a highest chapter at or past it; one reaching chapter 4 leaves 5 and 6 unread.
    static func newChapters(events: [ChapterUpdateEvent], sessions: [ReadingSession]) -> NewChaptersFigure {
        var figure = NewChaptersFigure()
        let byWork = Dictionary(grouping: sessions.filter { $0.mode == .read }, by: \.workID)
        let valid = events.filter {
            $0.previousChapterCount >= 0 && $0.chapterCount > $0.previousChapterCount
                && $0.chapterCount <= ChapterUpdateRecorder.maximumChapterCount
        }
        for (workID, workEvents) in Dictionary(grouping: valid, by: \.workID) {
            var claim: [Int: ChapterUpdateEvent] = [:]
            // Ties break on the observation's own values, never its UUID (which depends on which
            // archive was imported first): same detection time, earlier posting day, narrower
            // start, then the end.
            let ordered = workEvents.sorted {
                ($0.detectedAt, $0.postedAt, $0.previousChapterCount, $0.chapterCount)
                    < ($1.detectedAt, $1.postedAt, $1.previousChapterCount, $1.chapterCount)
            }
            for event in ordered {
                for chapter in (event.previousChapterCount + 1) ... event.chapterCount where claim[chapter] == nil {
                    claim[chapter] = event
                }
            }
            let workSessions = byWork[workID] ?? []
            for chapter in claim.keys.sorted() {
                guard let event = claim[chapter] else { continue }
                let posted = event.postedAt
                let later = workSessions.filter { $0.endedAt >= posted }
                let reaching = later
                    .filter { ($0.highestStoryChapter ?? 0) >= chapter && $0.chapterCountAtVisit >= chapter }
                    .min { $0.startedAt < $1.startedAt }
                let state: NewChapterReadState
                if let reaching {
                    let firstReadAt = max(reaching.startedAt, posted)
                    state = .read(firstReadAt: firstReadAt, delay: max(0, firstReadAt.timeIntervalSince(posted)))
                } else if later.contains(where: {
                    // A sitting with no chapter signal leaves it unknown, unless the chapter
                    // count it recorded shows the copy it read did not have this chapter yet.
                    $0.highestStoryChapter == nil && ($0.chapterCountAtVisit == 0 || $0.chapterCountAtVisit >= chapter)
                }) {
                    state = .unknown
                    figure.unknownChapters += 1
                } else {
                    state = .unread
                    figure.unreadChapters += 1
                }
                figure.entries.append(NewChapterEntry(
                    eventID: event.id, workID: workID, chapter: chapter, postedAt: posted, state: state
                ))
            }
        }
        figure.entries.sort { ($0.postedAt, $0.workID.uuidString, $0.chapter) < ($1.postedAt, $1.workID.uuidString, $1.chapter) }
        let delays = figure.entries.compactMap(\.delay).sorted()
        if !delays.isEmpty {
            let middle = delays.count / 2
            figure.medianDelay = delays.count.isMultiple(of: 2)
                ? (delays[middle - 1] + delays[middle]) / 2 : delays[middle]
        }
        return figure
    }

    // MARK: D11 your own AO3 actions

    struct OwnActionsFigure: Equatable {
        var works = 0
        var bookmarked = 0
        var bookmarkedPublic = 0
        var bookmarkedPrivate = 0
        var commented = 0
        var gaveKudos = 0
    }

    /// Lower bounds: an action taken in a browser stays invisible until a fetched work page
    /// shows it, so these never claim "none".
    static func ownActions(works: [SavedWork]) -> OwnActionsFigure {
        var figure = OwnActionsFigure(works: works.count)
        for work in works {
            if work.bookmarkedAt != nil {
                figure.bookmarked += 1
                if work.bookmarkIsPrivate { figure.bookmarkedPrivate += 1 } else { figure.bookmarkedPublic += 1 }
            }
            if work.lastCommentedAt != nil { figure.commented += 1 }
            if work.kudosGivenAt != nil || work.hasGivenKudos { figure.gaveKudos += 1 }
        }
        return figure
    }
}

extension InsightsScopeSelection {
    /// Whether a chapter update event belongs in this scope: the same rule a sitting follows
    /// (`includes(_:extraHiddenWorkIDs:)`), using the rating the event itself recorded, so an
    /// event of a deleted mature work still stays out of locked views and lands in Hidden.
    func includes(_ event: ChapterUpdateEvent, extraHiddenWorkIDs: Set<UUID> = []) -> Bool {
        if scope == .hidden && !revealed { return false }
        if hideMature {
            if scope == .combined && revealed { return true }
            let isHidden = hiddenWorkIDs.contains(event.workID)
                || extraHiddenWorkIDs.contains(event.workID)
                || MatureContentRating.isAdult(event.rating)
            return scope == .hidden ? isHidden : !isHidden
        }
        if excludedWorkIDs.contains(event.workID) { return false }
        if let onlyWorkIDs { return onlyWorkIDs.contains(event.workID) }
        return true
    }

    /// Events in this scope. Like `sessions(_:in:)`, a work in Recently Deleted that is adult
    /// rated is hidden too when a context is supplied.
    @MainActor
    func events(_ everything: [ChapterUpdateEvent], in context: ModelContext? = nil) -> [ChapterUpdateEvent] {
        // Events of a work that is gone here and covered by a signed tombstone are hidden first.
        let all = context.map { ChapterUpdateRecorder.visible(everything, in: $0) } ?? everything
        guard hideMature, !(scope == .combined && revealed), !(scope == .hidden && !revealed) else {
            return all.filter { includes($0) }
        }
        var hidden = hiddenWorkIDs
        if let context { hidden.formUnion(HomeReadingStats.softDeletedAdultWorkIDs(in: context)) }
        // One adult snapshot makes the whole work hidden: an earlier, unrated event of a work
        // that later became Mature must not stay visible once the work record is gone. The evidence
        // counts even when its own event is hidden by a tombstone.
        for event in everything where MatureContentRating.isAdult(event.rating) { hidden.insert(event.workID) }
        return all.filter { includes($0, extraHiddenWorkIDs: hidden) }
    }
}
