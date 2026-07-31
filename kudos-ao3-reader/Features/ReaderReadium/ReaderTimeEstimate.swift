import Foundation

/// Turns a count of remaining Readium "positions" (~1 KB of content each) into a
/// reading-time estimate, and formats it for the position card. Pure and
/// platform-agnostic so it's directly testable without a live navigator.
nonisolated enum ReaderTimeEstimate {
    /// Readium defines a position as roughly 1 KB of publication content. At an
    /// average adult silent-reading pace (~200 wpm, ~5.5 characters per word,
    /// i.e. ~1.1 KB/min), 1 KB takes about this many seconds.
    static let secondsPerPosition: Double = 55

    /// Minutes remaining for `count` positions, rounded to the nearest minute.
    static func minutes(forPositions count: Int) -> Int {
        max(0, Int((seconds(forPositions: count) / 60).rounded()))
    }

    /// Exact second estimate for `count` positions (no rounding). Used by Now
    /// Playing duration/elapsed; the card still shows rounded minutes.
    static func seconds(forPositions count: Int) -> TimeInterval {
        Double(max(0, count)) * secondsPerPosition
    }

    /// Whole-work Now Playing timing from the same position model as the card.
    /// - Parameters:
    ///   - totalPositions: Readium positions in the publication.
    ///   - remainingPositions: positions still ahead (`total − current`).
    /// - Returns: `(duration, elapsed)` in seconds, or `nil` when total is unknown.
    static func nowPlayingTiming(
        totalPositions: Int,
        remainingPositions: Int
    ) -> (duration: TimeInterval, elapsed: TimeInterval)? {
        guard totalPositions > 0 else { return nil }
        let duration = seconds(forPositions: totalPositions)
        let remaining = seconds(forPositions: min(max(0, remainingPositions), totalPositions))
        let elapsed = max(0, duration - remaining)
        return (duration, elapsed)
    }

    /// `AVSpeechUtteranceDefaultSpeechRate` (the reader's `rate == 1.0`) reads
    /// commonly-cited English speech at roughly this pace — noticeably slower
    /// than the `secondsPerPosition` **silent**-reading estimate above, which
    /// intentionally stays untouched: it backs the position card's own labels.
    static let ttsWordsPerMinuteAtDefaultRate = 160.0

    /// Words per Readium position, backed out from the silent-reading
    /// calibration this file already documents (~200 wpm × `secondsPerPosition`
    /// seconds ≈ 1 KB of content), so the two models agree on "how much text is
    /// in a position" and differ only in how fast that text is consumed.
    private static let wordsPerPosition = 200.0 * secondsPerPosition / 60.0

    /// Seconds to *speak* one position at read-aloud `rate` (the app's 0.5–1.5
    /// multiplier on `AVSpeechUtteranceDefaultSpeechRate`, see
    /// `ReaderSpeechPreferences.rate`) — distinct from `secondsPerPosition`,
    /// which paces *silent* reading and must not be reused for TTS.
    static func ttsSecondsPerPosition(rate: Double) -> Double {
        let wordsPerMinute = max(0.01, ttsWordsPerMinuteAtDefaultRate * rate)
        return wordsPerPosition / wordsPerMinute * 60
    }

    /// Same shape as `nowPlayingTiming`, but paced by the live TTS `rate`
    /// instead of the silent-reading constant — this is the one Now Playing
    /// should actually use while a read-aloud session is active.
    static func ttsNowPlayingTiming(
        totalPositions: Int,
        remainingPositions: Int,
        rate: Double
    ) -> (duration: TimeInterval, elapsed: TimeInterval)? {
        guard totalPositions > 0 else { return nil }
        let perPosition = ttsSecondsPerPosition(rate: rate)
        let duration = Double(totalPositions) * perPosition
        let remaining = Double(min(max(0, remainingPositions), totalPositions)) * perPosition
        let elapsed = max(0, duration - remaining)
        return (duration, elapsed)
    }

    /// "12 min" / "1 hr 5 min" — the bare duration, no "left" suffix.
    static func durationLabel(minutes: Int) -> String {
        let minutes = max(0, minutes)
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = minutes / 60
        let mins = minutes % 60
        return mins == 0 ? "\(hours) hr" : "\(hours) hr \(mins) min"
    }

    /// "12 min left in chapter" — the top-line chapter estimate.
    static func chapterRemainingLabel(positions: Int) -> String {
        "\(durationLabel(minutes: minutes(forPositions: positions))) left in chapter"
    }

    /// "1 hr 5 min left" — the bottom-line whole-work estimate.
    static func workRemainingLabel(positions: Int) -> String {
        "\(durationLabel(minutes: minutes(forPositions: positions))) left"
    }
}

/// The three label lines the reader's bottom position card displays. Built purely
/// from an already-resolved reading position so the formatting rules are testable
/// without a live navigator.
nonisolated struct ReaderPositionSummary: Equatable {
    /// "Page 3 of 12"
    let pageLabel: String
    /// "8 min left in chapter" — empty when no remaining-position count is known.
    let chapterTimeLabel: String
    /// "Chapter 2 of 10 · 34% of work · 1 hr 5 min left"
    let workLine: String

    /// - Parameters:
    ///   - page/pageCount: Readium positions within the current chapter.
    ///   - percent: `totalProgression` as a whole percent.
    ///   - place: where in the work the reader is — a numbered story chapter, or
    ///     AO3 front/back matter, which must never be numbered as a chapter.
    ///   - remainingInChapter/remainingInWork: Readium positions still ahead; nil
    ///     when the navigator hasn't reported a position yet, which drops the two
    ///     time estimates rather than showing a fabricated "0 min".
    init(
        page: Int, pageCount: Int, percent: Int,
        place: Place,
        remainingInChapter: Int?, remainingInWork: Int?
    ) {
        pageLabel = "Page \(page) of \(pageCount)"
        chapterTimeLabel = remainingInChapter.map(ReaderTimeEstimate.chapterRemainingLabel(positions:)) ?? ""

        // `.other` has no honest name to show, so the line starts at the percent
        // rather than carrying a dangling separator.
        var parts = place.label.isEmpty ? [] : [place.label]
        parts.append("\(percent)% of work")
        if let remainingInWork {
            parts.append(ReaderTimeEstimate.workRemainingLabel(positions: remainingInWork))
        }
        workLine = parts.joined(separator: " · ")
    }

    /// Where the reader is, for the card's bottom line. AO3 EPUBs wrap the story
    /// in a Preface/Summary/Afterword that are *not* chapters — naming them
    /// outright is honest, where the old "Chapter 1 of 66" on a Summary page was
    /// not. Mirrors `ReaderSection.pillLabel`'s contract in prose form.
    enum Place: Equatable {
        case chapter(index: Int, total: Int)
        case preface
        case summary
        case afterword
        /// A spine item that is neither story nor recognized matter — percent only.
        case other

        var label: String {
            switch self {
            // Floored at `index` so a WIP with an unknown/stale total never
            // reads the nonsense "Chapter 7 of 1".
            case let .chapter(index, total): "Chapter \(index) of \(max(total, index))"
            case .preface: "Preface"
            case .summary: "Summary"
            case .afterword: "Afterword"
            case .other: ""
            }
        }
    }
}

extension ReaderPositionSummary.Place {
    /// Maps a normalized `ReaderSection` onto a card place, preferring AO3's own
    /// posted chapter total over one counted from the section list.
    init(section: ReaderSection, storyChapterTotal: Int) {
        switch section.kind {
        case .preface: self = .preface
        case .summary: self = .summary
        case .afterword: self = .afterword
        case .other: self = .other
        case .chapter:
            self = .chapter(index: section.storyChapterIndex ?? 1, total: storyChapterTotal)
        }
    }

    /// Resolves the place for a 1-based chapter position against the normalized
    /// section list. `chapter - 1` is the spine index the position sits in.
    ///
    /// `postedChapterTotal` is AO3's own "Chapters: X/Y" total when known;
    /// otherwise the count of real story chapters in `sections` is used. Falls
    /// back to a raw spine reading when `sections` doesn't cover the index —
    /// shouldn't happen once the book is `.ready`, but a locator can in theory
    /// outrace the section build.
    static func resolve(
        chapter: Int, chapterCount: Int,
        sections: [ReaderSection], postedChapterTotal: Int?
    ) -> Self {
        guard sections.indices.contains(chapter - 1) else {
            return .chapter(index: chapter, total: chapterCount)
        }
        return Self(
            section: sections[chapter - 1],
            storyChapterTotal: postedChapterTotal ?? sections.storyChapterCount
        )
    }
}
