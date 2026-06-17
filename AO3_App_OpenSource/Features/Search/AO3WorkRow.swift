import SwiftUI

/// One search result row: title, author, fandoms, summary, and key stats.
struct AO3WorkRow: View {
    let work: AO3WorkSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title + author share a tight block so the hierarchy reads as one unit.
            VStack(alignment: .leading, spacing: 2) {
                Text(work.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text("by \(work.authorText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !work.fandoms.isEmpty {
                Label(work.fandoms.joined(separator: ", "), systemImage: "books.vertical")
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
            }

            if !work.summary.isEmpty {
                Text(work.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }

            // Stats wrap to a second line rather than truncating when they don't fit
            // (long ratings like "Teen And Up Audiences" no longer clip the row).
            FlowLayout(spacing: 14, rowSpacing: 5) {
                if !work.rating.isEmpty { statLabel(work.rating, "checkmark.shield") }
                if let words = work.words { statLabel(words.formatted(), "textformat.size") }
                if !work.chapters.isEmpty { statLabel(work.chapters, "book") }
                if let kudos = work.kudos { statLabel(kudos.formatted(), "heart") }
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
