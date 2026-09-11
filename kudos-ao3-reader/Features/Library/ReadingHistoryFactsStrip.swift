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
    let summary: WorkReadingSummary
    /// AO3's current posted-chapter count, against `summary.chapterCountAtLastVisit`.
    let postedChapterCount: Int
    let palette: SubjectPalette

    var body: some View {
        FlowLayout(spacing: 8, rowSpacing: 6) {
            if summary.totalSeconds > 0 {
                fact(ReadingInsights.durationLabel(summary.totalSeconds), isTinted: false)
            }
            // "Read ×2" is the *finish* count, not the visit count: two sittings of
            // one read-through is one read, and the spec's own note ties the reread
            // count to finishing sessions.
            if summary.finishCount > 1 {
                fact("Read ×\(summary.finishCount)", isTinted: false)
            }
            if newChapterCount > 0 {
                fact(
                    newChapterCount == 1 ? "1 new chapter" : "\(newChapterCount) new chapters",
                    isTinted: true
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

    private func fact(_ text: String, isTinted: Bool) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(isTinted ? palette.accent : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: SubjectMetrics.chipRadius, style: .continuous)
                    .fill(isTinted ? palette.chipFill : Color.primary.opacity(0.06))
            )
    }
}
