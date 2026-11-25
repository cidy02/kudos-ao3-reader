import Foundation
import SwiftData

/// Figures for Insights P3 data (T-536a, D7 to D9). Each takes rows the caller has already put
/// through `InsightsScopeSelection` (works from `libraryWorks` / `readingWorks`, sittings from
/// `sessions(_:in:)`), so the Hide Mature rules of T-535b apply to every figure here without a
/// second implementation: a concealed work's sitting, source or stats never reaches a function in
/// this file. They count only what was recorded; an unrecorded value is reported as unrecorded,
/// never guessed.
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
        var chaptersEntered = 0
        var chapterSpansMeasured = 0
        var eligibleChapterEnds = 0
        var chapterEnds = 0

        var averageChaptersEach: Double? {
            chapterSpansMeasured == 0 ? nil : Double(chaptersEntered) / Double(chapterSpansMeasured)
        }

        var chapterEndShare: Double? {
            eligibleChapterEnds == 0 ? nil : Double(chapterEnds) / Double(eligibleChapterEnds)
        }
    }

    static func chapterTiming(sessions: [ReadingSession]) -> ChapterTimingFigure {
        var figure = ChapterTimingFigure()
        var peeked: Set<UUID> = []
        for session in sessions {
            if let start = session.startSpineIndex, session.lastSpineIndex >= start {
                figure.chapterSpansMeasured += 1
                figure.chaptersEntered += session.lastSpineIndex - start + 1
            }
            if let ended = session.endedAtChapterEnd {
                figure.sittingsMeasured += 1
                if ended { figure.sittingsEndedAtChapterEnd += 1 }
                if !session.didFinish && session.chapterCountAtVisit > 1 {
                    figure.eligibleChapterEnds += 1
                    if ended { figure.chapterEnds += 1 }
                }
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
}
