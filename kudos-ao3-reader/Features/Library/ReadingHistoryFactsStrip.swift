import SwiftUI

/// The three facts spec **1ah** puts under a history row: how long this work has
/// been read for, how many times it has been finished, and whether AO3 has posted
/// anything since the last visit.
///
/// These are the facts a history row has that a library row does not, which is the
/// whole reason History is its own surface rather than a filter — so they are drawn
/// as their own strip rather than folded into the shared `WorkRow` metadata line,
/// where they would appear on six other screens that have no log behind them.
struct ReadingHistoryFactsStrip: View {
    /// Which of the three facts to draw.
    ///
    /// A style rather than a second view: 1ah and 1aj draw the same footer and
    /// differ only in whether the changed-since fact appears, so the alternative
    /// is the same rules written twice.
    enum Style: Equatable {
        /// 1ah: time read, reread count, and what is new since the last visit.
        case history
        /// 1aj: time read and the reread count. Favorites drops the changed-since
        /// fact and nothing else — the two artboards draw an identical footer
        /// otherwise, down to the hairline above it.
        case favorites
    }

    let summary: WorkReadingSummary
    /// AO3's current posted-chapter count, against `summary.chapterCountAtLastVisit`.
    /// Unused by `.rereadOnly`, which draws no chapter fact.
    let postedChapterCount: Int
    let palette: SubjectPalette
    var style: Style = .history

    var body: some View {
        FlowLayout(spacing: 8, rowSpacing: 6) {
            if summary.totalSeconds > 0 {
                fact(ReadingInsights.durationLabel(summary.totalSeconds))
            }
            // "Read ×2" is the *finish* count, not the visit count: two sittings of
            // one read-through is one read, and the spec's own note ties the reread
            // count to finishing sessions.
            if summary.finishCount > 1 {
                fact("Read ×\(summary.finishCount)", tint: .subjectFavoriteGold)
            }
            if style == .history, newChapterCount > 0 {
                fact(
                    newChapterCount == 1 ? "1 new chapter" : "\(newChapterCount) new chapters",
                    tint: palette.accent
                )
            }
        }
    }

    /// Only counts up. AO3 chapter counts can fall — a chapter is deleted, or an
    /// orphaned work is re-imported — and "−2 new chapters" is not a thing. A zero
    /// baseline means the visit predates chapter-count recording, where the honest
    /// answer is to say nothing rather than to claim every chapter is new.
    private var newChapterCount: Int {
        guard summary.chapterCountAtLastVisit > 0 else { return 0 }
        return max(0, postedChapterCount - summary.chapterCountAtLastVisit)
    }

    private func fact(_ text: String, tint: Color? = nil) -> some View {
        let foreground = tint ?? Color.secondary
        let fill = tint.map { $0.opacity(0.16) } ?? Color.primary.opacity(0.06)
        return Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: SubjectMetrics.chipRadius, style: .continuous)
                    .fill(fill)
            )
    }
}
