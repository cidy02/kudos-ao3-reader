import SwiftUI

/// One search result row: title, author, fandoms, summary, and key stats. The
/// summary is clamped to a few lines; an expand toggle reveals the full summary
/// plus the work's tags (like AO3's blurb) without opening the work.
struct AO3WorkRow: View {
    let work: AO3WorkSummary

    @State private var expanded = false

    /// Worth an expand toggle only when there's more to show than the clamped view:
    /// a long summary or any tags.
    private var isExpandable: Bool {
        work.summary.count > 120 || !work.tags.isEmpty
    }

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
                // Tight icon→text gap + bold accent glyph, matching the stats row.
                HStack(spacing: 4) {
                    Image(systemName: "books.vertical")
                        .fontWeight(.bold)
                    Text(work.fandoms.joined(separator: ", "))
                }
                .font(.caption)
                .foregroundStyle(.tint)
                .lineLimit(1)
            }

            if !work.summary.isEmpty {
                Text(work.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(expanded ? nil : 3)
                    .multilineTextAlignment(.leading)
            }

            // Tags only appear when expanded — they can be numerous on AO3.
            if expanded && !work.tags.isEmpty {
                FlowLayout(spacing: 6, rowSpacing: 6) {
                    ForEach(work.tags, id: \.self) { TagChip(text: $0) }
                }
                .padding(.top, 1)
            }

            // Thin divider separates the textual content from the metadata stats,
            // matching the Browse-by-fandom cards.
            Divider().padding(.top, 1)

            // Stats wrap to a second line rather than truncating when they don't fit
            // (long ratings like "Teen And Up Audiences" no longer clip the row).
            FlowLayout(spacing: 18, rowSpacing: 5) {
                if !work.rating.isEmpty { statLabel(work.rating, "checkmark.shield") }
                if let words = work.words { statLabel(words.formatted(), "textformat.size") }
                if !work.chapters.isEmpty { statLabel(work.chapters, "book") }
                if let kudos = work.kudos { statLabel(kudos.formatted(), "heart") }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.top, 1)

            if isExpandable {
                // Borderless so the tap toggles expansion instead of triggering the
                // row's navigation link.
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    Label(expanded ? "Show less" : "Show more",
                          systemImage: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.tint)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statLabel(_ text: String, _ symbol: String) -> some View {
        // The icon hugs its own label (tight inner spacing) and is bold + tinted in
        // the theme accent; the wider FlowLayout spacing keeps separate stats apart,
        // so each glyph reads as belonging to the value beside it.
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tint)
            Text(text)
        }
        .lineLimit(1)
        .fixedSize()
    }
}
