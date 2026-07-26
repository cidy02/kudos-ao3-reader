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
        max(0, Int((Double(max(0, count)) * secondsPerPosition / 60).rounded()))
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
