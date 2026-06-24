import SwiftUI

/// One row representing a saved work, reused across Library and Bookmarks. Mirrors
/// the Search result card (`AO3WorkRow`) — title, author, fandoms, summary, and a
/// stats line — so the two lists read consistently, plus a Library-specific
/// favorite marker. The richer fields (fandoms, word count, chapters, kudos) fill
/// in once the work has been refreshed from AO3 in the background.
struct WorkRow: View {
    let work: SavedWork

    private var summaryText: String { work.summary.strippingHTML() }

    /// Real content warnings only — AO3's "No Archive Warnings Apply" / "Creator
    /// Chose Not To Use Archive Warnings" aren't warnings worth flagging.
    private var warnings: [String] {
        work.workWarnings.filter {
            !$0.localizedCaseInsensitiveContains("No Archive Warnings")
                && !$0.localizedCaseInsensitiveContains("Chose Not To Use")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title + author, with the favorite star pinned top-trailing.
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(work.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    if work.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }
                if !work.author.isEmpty {
                    Text("by \(work.author)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if !work.workFandoms.isEmpty {
                // Tight icon→text gap + bold accent glyph, matching the stats row.
                HStack(spacing: 4) {
                    Image(systemName: "books.vertical")
                        .fontWeight(.bold)
                    Text(work.workFandoms.joined(separator: ", "))
                }
                .font(.caption)
                .foregroundStyle(.tint)
                .lineLimit(1)
            }

            if !summaryText.isEmpty {
                Text(summaryText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }

            if !warnings.isEmpty {
                Label(warnings.joined(separator: ", "), systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
            }

            // Thin divider separates the textual content from the metadata stats,
            // matching the Search and Browse-by-fandom cards.
            Divider().padding(.top, 1)

            // Stats wrap rather than truncate (matches AO3WorkRow).
            FlowLayout(spacing: 18, rowSpacing: 5) {
                if !work.rating.isEmpty { WorkStatLabel(text: work.rating, symbol: "checkmark.shield") }
                if work.wordCount > 0 { WorkStatLabel(text: work.wordCount.formatted(), symbol: "textformat.size") }
                if !work.chapters.isEmpty { WorkStatLabel(text: work.chapters, symbol: "book") }
                if work.kudos > 0 { WorkStatLabel(text: work.kudos.formatted(), symbol: "heart") }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.top, 1)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
