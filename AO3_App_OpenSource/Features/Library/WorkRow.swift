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
                Label(work.workFandoms.joined(separator: ", "), systemImage: "books.vertical")
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .labelStyle(.titleAndIcon)
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

            // Stats wrap rather than truncate (matches AO3WorkRow).
            FlowLayout(spacing: 14, rowSpacing: 5) {
                if !work.rating.isEmpty { statLabel(work.rating, "checkmark.shield") }
                if work.wordCount > 0 { statLabel(work.wordCount.formatted(), "textformat.size") }
                if !work.chapters.isEmpty { statLabel(work.chapters, "book") }
                if work.kudos > 0 { statLabel(work.kudos.formatted(), "heart") }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.top, 1)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statLabel(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .fixedSize()
    }
}
