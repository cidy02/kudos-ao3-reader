import SwiftUI
import SwiftData

/// A generated "cover" placeholder — EPUBs carry no cover art, so each work gets a
/// stable gradient (hued from its title) with a book glyph, giving the dashboard a
/// Books-like, cover-forward feel without real artwork.
struct CoverArt: View {
    let title: String

    var body: some View {
        let hue = Self.hue(for: title)
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(LinearGradient(
                colors: [
                    Color(hue: hue, saturation: 0.42, brightness: 0.74),
                    Color(hue: hue, saturation: 0.58, brightness: 0.46)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
            .overlay {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
    }

    /// A stable hue in 0...1 derived from the title (djb2-ish hash).
    static func hue(for string: String) -> Double {
        let hash = string.unicodeScalars.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1.value) }
        return Double(hash % 360) / 360
    }
}

/// Standard carousel card: cover + title + author + an optional footer (e.g. "Ch 3").
struct WorkCoverCard: View {
    let work: SavedWork
    var footer: String?

    var progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverArt(title: work.title)
                .frame(width: 120, height: 172)
                .overlay(alignment: .bottom) { progressBar }
            Text(work.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(.primary)
            if !work.author.isEmpty {
                Text(work.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            CoverStatsLine(rating: work.rating, chapters: work.chapters)
            if let footer {
                Text(footer)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 120, alignment: .leading)
    }

    /// A thin reading-progress bar overlaid on the cover (Reading Now).
    @ViewBuilder
    private var progressBar: some View {
        if let progress {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.black.opacity(0.3)).frame(height: 4)
                    Capsule().fill(.white)
                        .frame(width: geo.size.width * max(0.03, min(1, progress)), height: 4)
                }
            }
            .frame(height: 4)
            .padding(8)
        }
    }
}

/// Carousel card for a remote AO3 work (Subscriptions / Recently Updated): cover +
/// title + author + fandom. Tapping opens the native AO3 work page (download + read).
struct AO3WorkCoverCard: View {
    let work: AO3WorkSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverArt(title: work.title)
                .frame(width: 120, height: 172)
            Text(work.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(.primary)
            if let author = work.authors.first, !author.isEmpty {
                Text(author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let fandom = work.fandoms.first {
                Text(fandom)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            CoverStatsLine(rating: work.rating, chapters: work.chapters)
        }
        .frame(width: 120, alignment: .leading)
    }
}

/// A compact rating + chapter-count line for the cover-card shelves, using the same
/// `WorkStatLabel` glyphs as the dense rows so every surface's metadata matches.
struct CoverStatsLine: View {
    let rating: String
    let chapters: String

    var body: some View {
        let ratingShort = WorkStat.ratingShort(rating)
        if ratingShort != nil || !chapters.isEmpty {
            HStack(spacing: 10) {
                if let ratingShort {
                    WorkStatLabel(text: ratingShort, symbol: "checkmark.shield")
                }
                if !chapters.isEmpty {
                    WorkStatLabel(text: chapters, symbol: "book")
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }
}

/// How the dashboard opens a tapped work: straight into the reader when the EPUB is
/// on disk, otherwise its detail page (which can re-download a freed file).
struct HomeWorkDestination: View {
    let work: SavedWork
    @Environment(\.modelContext) private var context

    var body: some View {
        Group {
            if work.hasEPUB {
                ReaderView(work: work)
            } else {
                WorkDetailView(work: work)
            }
        }
        .onAppear {
            // Opening an updated work marks its current chapters as seen — clears it
            // from Recently Updated.
            if work.hasUpdate {
                work.knownChapterCount = work.postedChapterCount
                try? context.save()
            }
        }
    }
}
