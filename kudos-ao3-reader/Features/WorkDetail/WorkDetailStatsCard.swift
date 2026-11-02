import SwiftUI

// Board 19's stats card: nine labelled figures in a 3×3 grid on one panel. It
// replaces the old Kudos/Comments/Bookmarks/Hits strip, the "English · words ·
// upd" headline row, the Published row and the Chapters cell of the figure strip.

/// What the stats card prints, as plain data so the order, the formatting and
/// the empty states are testable without a view.
enum WorkDetailStats {
    struct Cell: Equatable, Identifiable {
        let label: String
        let value: String
        /// The Kudos cell of a work the reader has given kudos to: a filled
        /// heart before the figure (a state about the reader, so the app colour).
        var showsGivenHeart = false
        /// What VoiceOver reads instead of "label value".
        let accessibilityText: String

        var id: String { label }
    }

    /// What a cell prints when the field is genuinely unknown, rather than
    /// leaving a blank ninth of the card that reads as a layout gap.
    static let emptyFigure = "—"

    /// The nine cells in the board's order, row by row. Every cell is always
    /// present: a work with no hits figure shows a dash, so the card keeps its
    /// 3×3 shape instead of reflowing from one work to the next.
    static func cells(
        words: Int?, chapters: String, kudos: Int?, kudosGiven: Bool, hits: Int?,
        comments: Int?, bookmarks: Int?, published: String, updated: String, language: String
    ) -> [Cell] {
        let chapterText = chapters.trimmingCharacters(in: .whitespacesAndNewlines)
        let heart = kudosGiven
        return [
            Cell(
                label: "Words", value: words?.formatted() ?? emptyFigure,
                accessibilityText: words.map { $0.formatted() + " words" } ?? "Words unknown"
            ),
            Cell(
                label: "Chapters", value: chapterText.isEmpty ? emptyFigure : chapterText,
                accessibilityText: chapterText.isEmpty ? "Chapters unknown" : chapterText + " chapters"
            ),
            Cell(
                label: "Kudos", value: kudos?.formatted() ?? emptyFigure, showsGivenHeart: heart,
                accessibilityText: (kudos.map { $0.formatted() + " kudos" } ?? "Kudos unknown")
                    + (heart ? ", given by you" : "")
            ),
            Cell(
                label: "Hits", value: hits?.compactCount ?? emptyFigure,
                accessibilityText: hits.map { $0.formatted() + " hits" } ?? "Hits unknown"
            ),
            Cell(
                label: "Comments", value: comments?.compactCount ?? emptyFigure,
                accessibilityText: comments.map { $0.formatted() + " comments" } ?? "Comments unknown"
            ),
            Cell(
                label: "Bookmarks", value: bookmarks?.compactCount ?? emptyFigure,
                accessibilityText: bookmarks.map { $0.formatted() + " bookmarks" } ?? "Bookmarks unknown"
            ),
            dateCell("Published", published),
            dateCell("Updated", updated),
            Cell(
                label: "Language", value: language.isEmpty ? emptyFigure : language,
                accessibilityText: language.isEmpty ? "Language unknown" : "Language: " + language
            )
        ]
    }

    /// The board's short date: "Mar 3", with the year added when it is not the
    /// current one. An unparseable string prints as AO3 wrote it.
    static func shortDate(_ raw: String, now: Date = Date()) -> String {
        guard let date = WorkStat.date(from: raw) else { return raw }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let sameYear = utc.component(.year, from: date) == utc.component(.year, from: now)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = utc.timeZone
        formatter.dateFormat = sameYear ? "MMM d" : "MMM d, yyyy"
        return formatter.string(from: date)
    }

    private static func dateCell(_ label: String, _ raw: String) -> Cell {
        guard !raw.isEmpty else {
            return Cell(label: label, value: emptyFigure, accessibilityText: label + " date unknown")
        }
        let printed = shortDate(raw)
        return Cell(label: label, value: printed, accessibilityText: label + " " + printed)
    }
}

/// The 3×3 card. Three columns share the width with hairlines between them;
/// the accessibility sizes switch to one labelled row per figure, since three
/// across cannot hold a scaled figure and its caption.
struct WorkDetailStatsCard: View {
    let cells: [WorkDetailStats.Cell]

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                listLayout
            } else {
                gridLayout
            }
        }
        .subjectPanel()
    }

    private var gridLayout: some View {
        VStack(spacing: 14) {
            ForEach(Array(stride(from: 0, to: cells.count, by: 3)), id: \.self) { start in
                let row = Array(cells[start ..< min(start + 3, cells.count)])
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.element.id) { index, cell in
                        if index > 0 {
                            Rectangle()
                                .fill(themeManager.appTheme.glassStroke(0.13))
                                .frame(width: 0.5)
                        }
                        cellView(cell)
                    }
                }
            }
        }
        .padding(.vertical, 14)
    }

    private var listLayout: some View {
        VStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.element.id) { index, cell in
                if index > 0 { SubjectRowSeparator() }
                SubjectFormRow(label: cell.label) {
                    HStack(spacing: 4) {
                        if cell.showsGivenHeart {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.accentInk)
                                .accessibilityHidden(true)
                        }
                        SubjectFormValue(text: cell.value)
                    }
                }
                .combinedAccessibilityRow(cell.accessibilityText)
            }
        }
    }

    private func cellView(_ cell: WorkDetailStats.Cell) -> some View {
        VStack(spacing: 2) {
            Text(cell.label.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.4)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: 3) {
                if cell.showsGivenHeart {
                    Image(systemName: "heart.fill")
                        .font(.footnote)
                        .foregroundStyle(.accentInk)
                }
                Text(cell.value)
                    .font(.system(.headline, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
        .combinedAccessibilityRow(cell.accessibilityText)
    }
}
